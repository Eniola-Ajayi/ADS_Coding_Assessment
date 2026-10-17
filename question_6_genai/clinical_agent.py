"""GenAI Clinical Data Assistant (Question 6).

Translates a free-text safety question into a structured query on the AE data
and runs it with pandas.

    question --(1) Prompt--> LLM --(2) Parse--> QueryPlan --(3) Execute--> result

1. **Prompt**: the LLM receives a schema description of the dataset (column
   meanings plus real example values taken from the data) and the question.
2. **Parse**: the LLM must answer with JSON ``{"target_column", "filter_value"}``,
   which is validated against the schema with pydantic.
3. **Execute**: the plan is applied to the DataFrame and the unique subjects
   are returned.

The column mapping is NOT hard-coded: the LLM infers it from the schema (e.g.
"intensity" -> AESEV, "Headache" -> AETERM, "Cardiac" -> AESOC).

LLM back-ends
-------------
* If ``OPENAI_API_KEY`` is set and ``langchain-openai`` is installed, an
  OpenAI chat model is used through LangChain.
* Otherwise a ``MockLLM`` stands in. It follows exactly the same
  prompt -> JSON -> parse -> execute flow, but chooses the column by matching
  the question against the *values found in the data* (from the schema), so
  the pipeline can be demonstrated offline without an API key.
* Any LangChain chat model can be passed in instead (``llm=...``).
"""

from __future__ import annotations

import json
import os
import re
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

import pandas as pd
from pydantic import BaseModel, Field, ValidationError, field_validator

DEFAULT_ADAE_PATH = Path(__file__).resolve().parent.parent / "data" / "adae.csv"

# ---------------------------------------------------------------------------
# 1. Schema definition: what each column means, in plain language.
#    `match` controls how the filter is applied when the column is queried.
# ---------------------------------------------------------------------------
COLUMN_DESCRIPTIONS: dict[str, dict[str, str]] = {
    "AESEV": {
        "description": "Severity or intensity of the adverse event (how bad it was).",
        "match": "exact",
    },
    "AETERM": {
        "description": (
            "Reported term for the adverse event: the specific condition or "
            "symptom as reported, e.g. a headache, rash or nausea."
        ),
        "match": "contains",
    },
    "AEDECOD": {
        "description": "Dictionary-coded (MedDRA preferred term) version of the adverse event.",
        "match": "contains",
    },
    "AESOC": {
        "description": (
            "Primary system organ class: the body system affected, e.g. cardiac, "
            "skin, nervous system, gastrointestinal."
        ),
        "match": "contains",
    },
    "AESER": {
        "description": "Whether the adverse event was serious (Y = serious, N = not serious).",
        "match": "exact",
    },
    "AEREL": {
        "description": "Causality: the relationship of the event to the study drug.",
        "match": "exact",
    },
    "AEOUT": {
        "description": "Outcome of the adverse event, e.g. recovered/resolved, fatal.",
        "match": "exact",
    },
    "ACTARM": {
        "description": "Actual treatment arm / group the subject received.",
        "match": "exact",
    },
}

MAX_EXAMPLES = 25  # example values shown to the LLM per column


def build_schema(df: pd.DataFrame) -> dict[str, dict[str, Any]]:
    """Combine the column descriptions with real values from the data.

    Low-cardinality columns list all their values; others list the most
    frequent ones, so the LLM sees how values are actually written.
    """
    schema = {}
    for col, meta in COLUMN_DESCRIPTIONS.items():
        if col not in df.columns:
            continue
        counts = df[col].dropna().astype(str).value_counts()
        schema[col] = {
            **meta,
            "n_distinct": int(counts.size),
            "values": counts.index[:MAX_EXAMPLES].tolist(),
        }
    return schema


def schema_to_text(schema: dict[str, dict[str, Any]]) -> str:
    lines = []
    for col, meta in schema.items():
        shown = ", ".join(meta["values"])
        more = "" if meta["n_distinct"] <= MAX_EXAMPLES else f" (and {meta['n_distinct'] - MAX_EXAMPLES} more)"
        lines.append(f"- {col}: {meta['description']}\n  Example values: {shown}{more}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 2. Structured output expected from the LLM
# ---------------------------------------------------------------------------
class QueryPlan(BaseModel):
    target_column: str = Field(description="Dataset column to filter on.")
    filter_value: str = Field(description="Value to search for, taken from the question.")

    @field_validator("filter_value")
    @classmethod
    def not_blank(cls, v: str) -> str:
        if not str(v).strip():
            raise ValueError("filter_value must not be empty")
        return str(v).strip()


SYSTEM_PROMPT = """You are a clinical data assistant. You translate a safety reviewer's \
question about an adverse events (AE) dataset into a single filter on ONE column.

Dataset columns:
{schema}

Rules:
- Choose the ONE column whose meaning best matches what the question asks about.
  Severity / intensity words -> AESEV. A specific condition or symptom -> AETERM.
  A body system or organ (e.g. cardiac, skin) -> AESOC.
- filter_value must be the value to search for, written the way values appear in the
  dataset where possible (e.g. "MODERATE", "HEADACHE"). For a body system, use the key
  word (e.g. "CARDIAC").
- If the question cannot be answered by filtering one of these columns, use
  {{"target_column": "NONE", "filter_value": "NONE"}}.
- Respond with ONLY a JSON object, no other text, in exactly this form:
  {{"target_column": "<column name>", "filter_value": "<value>"}}"""


def build_messages(schema_text: str, question: str) -> list[tuple[str, str]]:
    """Prompt as (role, content) pairs, the input format LangChain chat models accept."""
    return [
        ("system", SYSTEM_PROMPT.format(schema=schema_text)),
        ("human", question),
    ]


def parse_llm_output(text: str, schema: dict[str, Any]) -> QueryPlan:
    """Extract and validate the JSON plan from the LLM's reply."""
    match = re.search(r"\{.*\}", text, flags=re.DOTALL)  # tolerate ```json fences
    if not match:
        raise ValueError(f"LLM response did not contain JSON: {text!r}")
    try:
        plan = QueryPlan.model_validate(json.loads(match.group(0)))
    except (json.JSONDecodeError, ValidationError) as err:
        raise ValueError(f"Could not parse LLM response {text!r}: {err}") from err

    column = plan.target_column.strip().upper()
    if column == "NONE":
        raise ValueError(
            "The question could not be mapped to a column in the AE dataset. "
            "Try mentioning a severity, a specific condition or a body system."
        )
    if column not in schema:
        raise ValueError(
            f"LLM chose column {plan.target_column!r}, which is not in the schema "
            f"({', '.join(schema)})."
        )
    return QueryPlan(target_column=column, filter_value=plan.filter_value)


# ---------------------------------------------------------------------------
# Offline stand-in for the LLM
# ---------------------------------------------------------------------------
@dataclass
class MockMessage:
    content: str


class MockLLM:
    """Offline stand-in with the same ``invoke(messages) -> .content`` interface.

    It has no hand-written synonym table: it looks for values (or key words of
    values) that actually occur in each schema column, in priority order, and
    returns the same JSON a real LLM would.
    """

    # Columns checked in order; earlier columns win when several match.
    PRIORITY = ["AESEV", "AETERM", "AEDECOD", "AESOC", "AEOUT", "ACTARM"]
    STOPWORDS = {"AND", "OF", "THE", "DISORDERS", "CONDITIONS", "GENERAL", "SITE", "TISSUE","SYSTEM"}

    def __init__(self, schema: dict[str, dict[str, Any]], df: pd.DataFrame):
        # The mock may see every distinct value (not just the examples).
        self.vocab = {
            col: sorted(df[col].dropna().astype(str).unique(), key=len, reverse=True)
            for col in schema
        }

    def invoke(self, messages: list[tuple[str, str]]) -> MockMessage:
        question = messages[-1][1].upper()
        for col in self.PRIORITY:
            for value in self.vocab.get(col, []):
                v = value.upper()
                # whole value appears in the question (e.g. "HEADACHE")
                if re.search(rf"\b{re.escape(v)}\b", question):
                    return self._reply(col, v)
                # body systems: a key word of the value appears (e.g. "CARDIAC")
                if col == "AESOC":
                    for word in re.findall(r"[A-Z]{4,}", v):
                        if word not in self.STOPWORDS and re.search(rf"\b{word}", question):
                            return self._reply(col, word)
        return MockMessage(content='{"target_column": "NONE", "filter_value": "NONE"}')

    @staticmethod
    def _reply(column: str, value: str) -> MockMessage:
        return MockMessage(content=json.dumps({"target_column": column, "filter_value": value}))


def default_llm(schema, df, model: str = "gpt-4o-mini"):
    """Use OpenAI via LangChain if configured, otherwise the offline mock."""
    if os.environ.get("OPENAI_API_KEY"):
        try:
            from langchain_openai import ChatOpenAI
        except ImportError:
            warnings.warn("OPENAI_API_KEY is set but langchain-openai is not installed; using MockLLM.")
        else:
            return ChatOpenAI(model=model, temperature=0)
    return MockLLM(schema, df)


# ---------------------------------------------------------------------------
# 3. The agent: Prompt -> Parse -> Execute
# ---------------------------------------------------------------------------
class ClinicalTrialDataAgent:
    """Answer free-text questions about the AE dataset."""

    def __init__(self, df: pd.DataFrame, llm: Optional[Any] = None, model: str = "gpt-4o-mini"):
        if "USUBJID" not in df.columns:
            raise ValueError("The AE data must contain USUBJID.")
        self.df = df
        self.schema = build_schema(df)
        self.schema_text = schema_to_text(self.schema)
        self.llm = llm or default_llm(self.schema, df, model)

    @classmethod
    def from_csv(cls, path: str | os.PathLike | None = None, **kwargs) -> "ClinicalTrialDataAgent":
        path = Path(path or os.environ.get("ADAE_PATH", DEFAULT_ADAE_PATH))
        df = pd.read_csv(path, dtype=str, keep_default_na=False, na_values=[""])
        return cls(df, **kwargs)

    @property
    def backend(self) -> str:
        return type(self.llm).__name__

    # (1) + (2)
    def parse_question(self, question: str) -> QueryPlan:
        messages = build_messages(self.schema_text, question)
        reply = self.llm.invoke(messages)
        text = reply.content if hasattr(reply, "content") else str(reply)
        return parse_llm_output(text, self.schema)

    # (3)
    def execute(self, plan: QueryPlan) -> dict:
        column = self.df[plan.target_column].astype(str).str.upper()
        value = plan.filter_value.upper()
        if self.schema[plan.target_column]["match"] == "exact":
            mask = column == value
        else:
            mask = column.str.contains(value, regex=False, na=False)

        subjects = sorted(self.df.loc[mask, "USUBJID"].dropna().unique().tolist())
        return {
            "target_column": plan.target_column,
            "filter_value": plan.filter_value,
            "n_records": int(mask.sum()),
            "n_subjects": len(subjects),
            "subjects": subjects,
        }

    def ask(self, question: str) -> dict:
        """Full pipeline for one question."""
        plan = self.parse_question(question)
        return {"question": question, **self.execute(plan)}
