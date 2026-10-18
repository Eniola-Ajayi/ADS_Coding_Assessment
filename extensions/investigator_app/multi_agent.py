"""Multi-condition questions for the investigator app (extends Question 6).

Question 6, as the brief specifies, turns a question into ONE filter
(``target_column`` + ``filter_value``). Here the language model returns a
LIST of filters instead, so

    "Which placebo patients had severe headaches?"

is answered as

    AESEV is SEVERE  and  AETERM contains HEADACHE  and  ACTARM is Placebo

* Different filters must all hold for the same AE record (AND).
* One filter can list several values, any of which may match (OR):
  "mild or moderate" -> AESEV is MILD or MODERATE.

The rest is reused from ``question_6_genai/clinical_agent.py``, which is not
changed: the schema shown to the model (column meanings plus real values),
the choice of model (OpenAI if OPENAI_API_KEY is set, otherwise an offline
mock) and the Prompt -> Parse -> Execute pipeline, with pydantic checking the
model's reply before it touches the data.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any, Optional

import pandas as pd
from pydantic import BaseModel, Field, ValidationError, field_validator

# Make the Question 6 module importable from this folder.
Q6_DIR = Path(__file__).resolve().parents[2] / "question_6_genai"
if str(Q6_DIR) not in sys.path:
    sys.path.insert(0, str(Q6_DIR))

from clinical_agent import (  # noqa: E402  (needs the path set up above)
    MockLLM,
    MockMessage,
    build_schema,
    default_llm,
    schema_to_text,
)

MAX_FILTERS = 5


# ---------------------------------------------------------------------------
# 1. Structured output expected from the language model
# ---------------------------------------------------------------------------
class Filter(BaseModel):
    column: str = Field(description="AE variable to filter on.")
    values: list[str] = Field(min_length=1, description="Values to look for; any of them may match.")

    @field_validator("column")
    @classmethod
    def upper_case(cls, column: str) -> str:
        return column.strip().upper()

    @field_validator("values", mode="before")
    @classmethod
    def one_value_is_a_list(cls, values: Any) -> Any:
        return [values] if isinstance(values, str) else values

    @field_validator("values")
    @classmethod
    def drop_blanks_and_repeats(cls, values: list[str]) -> list[str]:
        cleaned: list[str] = []
        for value in (str(v).strip() for v in values):
            if value and value.upper() not in {c.upper() for c in cleaned}:
                cleaned.append(value)
        if not cleaned:
            raise ValueError("a filter needs at least one value")
        return cleaned


class MultiQueryPlan(BaseModel):
    filters: list[Filter] = Field(max_length=MAX_FILTERS)


# ---------------------------------------------------------------------------
# 2. Prompt and parsing (same pattern as Question 6)
# ---------------------------------------------------------------------------
MULTI_SYSTEM_PROMPT = """You are a clinical data assistant. You translate a safety reviewer's \
question about an adverse events (AE) dataset into filters on its columns.

Dataset columns:
{schema}

Each row of the dataset is one adverse event record. Rules:
- Make one filter for each condition in the question, on the column whose meaning best
  matches it. Severity / intensity words -> AESEV. A specific condition or symptom -> AETERM
  (not AEDECOD). A body system or organ (e.g. cardiac, skin) -> AESOC. A treatment group -> ACTARM.
- A record must meet every filter (they are combined with AND), so use each column at most
  once. Several acceptable values for one column (e.g. "mild or moderate") go in that
  filter's "values" list; any of them may match.
- Only add filters for conditions the question actually states, at most {max_filters}.
- Write values the way they appear in the dataset (e.g. "MODERATE", "HEADACHE", "Placebo").
  For a body system, use the key word (e.g. "CARDIAC").
- If the question cannot be answered by filtering these columns, return {{"filters": []}}.
- Respond with ONLY a JSON object, no other text, in exactly this form:
  {{"filters": [{{"column": "<column name>", "values": ["<value>", ...]}}]}}"""


def build_multi_messages(schema_text: str, question: str) -> list[tuple[str, str]]:
    """Prompt as (role, content) pairs, the input format LangChain chat models accept."""
    system = MULTI_SYSTEM_PROMPT.format(schema=schema_text, max_filters=MAX_FILTERS)
    return [("system", system), ("human", question)]


def parse_multi_output(text: str, schema: dict[str, Any]) -> MultiQueryPlan:
    """Extract and validate the JSON plan from the model's reply.

    Raises ValueError (shown to the user) if the reply is not usable.
    """
    match = re.search(r"\{.*\}", text, flags=re.DOTALL)  # tolerate ```json fences
    if not match:
        raise ValueError(f"LLM response did not contain JSON: {text!r}")
    try:
        plan = MultiQueryPlan.model_validate(json.loads(match.group(0)))
    except (json.JSONDecodeError, ValidationError) as err:
        raise ValueError(f"Could not parse LLM response {text!r}: {err}") from err

    if not plan.filters:
        raise ValueError(
            "The question could not be mapped to the AE dataset. Try mentioning a "
            "severity, a specific condition, a body system or a treatment arm."
        )
    used: set[str] = set()
    for f in plan.filters:
        if f.column not in schema:
            raise ValueError(
                f"LLM chose column {f.column!r}, which is not in the schema ({', '.join(schema)})."
            )
        if f.column in used:
            raise ValueError(
                f"The question was read as two conditions on {f.column}, but each AE record "
                f"has only one {f.column}. To find either value, ask with 'or' (for example "
                "'headache or nausea'); to find subjects who had both, ask about each one separately."
            )
        used.add(f.column)
    return plan


# ---------------------------------------------------------------------------
# Offline stand-in for the language model
# ---------------------------------------------------------------------------
def _phrase_pattern(text: str) -> str:
    """Regex for a value written in a question: any case, an optional plural 's',
    and spaces or hyphens between words ("high dose" or "high-dose")."""
    body = re.escape(text.upper()).replace(r"\ ", r"[\s-]+")
    return rf"(?<!\w){body}S?(?!\w)"


def _word_pattern(word: str) -> str:
    """Regex for one key word, singular or plural ("infection" for INFECTIONS)."""
    stem = word[:-1] if word.endswith("S") and len(word) > 4 else word
    return rf"(?<!\w){re.escape(stem)}(?:S|ES)?(?!\w)"


class MultiMockLLM(MockLLM):
    """Offline stand-in for the language model, for multi-condition questions.

    Like the Question 6 MockLLM (whose word lists it inherits) it has no synonym
    table: it looks for values from the data in the question. It differs in
    three ways:

    * it keeps every column that matches, instead of stopping at the first;
    * it recognises a body system by a word only that body system has
      ("cardiac", "skin") and a treatment arm without its drug name
      ("high dose" for Xanomeline High Dose);
    * "serious" / "non-serious" map to AESER Y / N, because a Y/N flag
      cannot be found from its values.
    """

    COLUMNS = ["AESEV", "AESER", "AETERM", "AEDECOD", "AESOC", "AEOUT", "ACTARM"]
    # (pattern, AESER value); "non-serious" is checked first and used up, so
    # its "serious" is not counted again
    SERIOUS_WORDS = [(r"\bNON[\s-]?SERIOUS\b|\bNOT\s+SERIOUS\b", "N"), (r"\bSERIOUS\b", "Y")]

    def __init__(self, schema: dict[str, dict[str, Any]], df: pd.DataFrame):
        super().__init__(schema, df)  # self.vocab: every value of each column, longest first
        self.aliases = {
            "AESOC": self._key_words(self.vocab.get("AESOC", [])),
            "ACTARM": self._short_arm_names(self.vocab.get("ACTARM", [])),
        }

    def _key_words(self, values: list[str]) -> list[tuple[str, str]]:
        """(pattern, value) for each word that occurs in only one of the values."""
        owners: dict[str, set[str]] = {}
        for value in values:
            for word in re.findall(r"[A-Z]{3,}", value.upper()):
                if word not in self.STOPWORDS:
                    owners.setdefault(word, set()).add(value)
        return [(_word_pattern(w), vals.pop()) for w, vals in owners.items() if len(vals) == 1]

    @staticmethod
    def _short_arm_names(arms: list[str]) -> list[tuple[str, str]]:
        """(pattern, arm) for each arm named without its first word, if that is unique."""
        short = {arm: arm.split(" ", 1)[1] for arm in arms if " " in arm}
        return [
            (_phrase_pattern(name), arm)
            for arm, name in short.items()
            if len(name) >= 4 and list(short.values()).count(name) == 1
        ]

    def invoke(self, messages: list[tuple[str, str]]) -> MockMessage:
        question = messages[-1][1].upper()
        rest = question  # the question with the words already used blanked out
        filters = []
        for col in self.COLUMNS:
            if col not in self.vocab:
                continue
            if col == "AEDECOD" and any(f["column"] == "AETERM" for f in filters):
                continue  # the same condition, already found as a reported term
            if col == "AESER":
                candidates = self.SERIOUS_WORDS
            else:  # whole values (longest first), then key words / short names
                candidates = [(_phrase_pattern(v), v) for v in self.vocab[col]]
                candidates += self.aliases.get(col, [])

            hits: list[tuple[int, str]] = []  # (position in question, value)
            for pattern, value in candidates:
                m = re.search(pattern, rest)
                if m and value not in (v for _, v in hits):
                    hits.append((m.start(), value))
                if m:
                    # each word is used once, so "upper respiratory tract infection"
                    # is a reported term, not also a respiratory and an infection SOC
                    rest = rest[: m.start()] + " " * (m.end() - m.start()) + rest[m.end():]
            if hits:
                filters.append({"column": col, "values": [v for _, v in sorted(hits)]})
        return MockMessage(content=json.dumps({"filters": filters}))


# ---------------------------------------------------------------------------
# 3. The agent: Prompt -> Parse -> Execute
# ---------------------------------------------------------------------------
class MultiFilterAgent:
    """Answer free-text questions with one or more combined filters."""

    def __init__(self, df: pd.DataFrame, llm: Optional[Any] = None, model: str = "gpt-4o-mini"):
        if "USUBJID" not in df.columns:
            raise ValueError("The AE data must contain USUBJID.")
        self.df = df
        self.schema = build_schema(df)
        self.schema_text = schema_to_text(self.schema)
        # Every value of the exact-match columns, keyed in upper case, so the
        # model's values can be checked and given the data's spelling.
        self.levels = {
            col: {v.upper(): v for v in df[col].dropna().astype(str).unique()}
            for col, meta in self.schema.items()
            if meta["match"] == "exact"
        }
        self.llm = llm or self._default_llm(model)

    def _default_llm(self, model: str):
        """Question 6's choice of model, with this module's mock in place of its MockLLM."""
        llm = default_llm(self.schema, self.df, model)
        return MultiMockLLM(self.schema, self.df) if isinstance(llm, MockLLM) else llm

    @property
    def backend(self) -> str:
        return type(self.llm).__name__

    # (1) + (2)
    def parse_question(self, question: str) -> MultiQueryPlan:
        reply = self.llm.invoke(build_multi_messages(self.schema_text, question))
        text = reply.content if hasattr(reply, "content") else str(reply)
        return self._check_values(parse_multi_output(text, self.schema))

    def _check_values(self, plan: MultiQueryPlan) -> MultiQueryPlan:
        """For exact-match columns, every value must occur in the data.

        Otherwise a value the model made up (e.g. ACTARM "High Dose") would
        quietly match nothing and look like "no patients".
        """
        checked = []
        for f in plan.filters:
            levels = self.levels.get(f.column)
            if levels is not None:
                unknown = [v for v in f.values if v.upper() not in levels]
                if unknown:
                    raise ValueError(
                        f"{f.column} has no value {unknown[0]!r} in the data. "
                        f"Its values are: {', '.join(sorted(levels.values()))}."
                    )
                f = Filter(column=f.column, values=[levels[v.upper()] for v in f.values])
            checked.append(f)
        return MultiQueryPlan(filters=checked)

    # (3)
    def execute(self, plan: MultiQueryPlan) -> dict:
        mask = pd.Series(True, index=self.df.index)
        applied = []
        for f in plan.filters:
            column = self.df[f.column].fillna("").astype(str).str.upper()
            values = [v.upper() for v in f.values]
            match_type = self.schema[f.column]["match"]
            if match_type == "exact":
                hit = column.isin(values)
            else:
                hit = pd.Series(False, index=self.df.index)
                for value in values:  # any of the values (OR)
                    hit |= column.str.contains(value, regex=False)
            mask &= hit  # every filter (AND)
            applied.append({"column": f.column, "values": f.values, "match": match_type})

        subjects = sorted(self.df.loc[mask, "USUBJID"].dropna().unique().tolist())
        return {
            "filters": applied,
            "n_records": int(mask.sum()),
            "n_subjects": len(subjects),
            "subjects": subjects,
        }

    def ask(self, question: str) -> dict:
        """Full pipeline for one question."""
        plan = self.parse_question(question)
        return {"question": question, **self.execute(plan)}
