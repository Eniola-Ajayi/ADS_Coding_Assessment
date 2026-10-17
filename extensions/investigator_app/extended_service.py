"""Extra business logic for the investigator app (extends Questions 5 and 6).

The Question 5 and 6 code is reused unchanged:

* the scoring rules (``SEVERITY_WEIGHTS``, ``categorise_risk``) are imported
  from ``question_5_api/ae_service.py`` rather than copied, so the API and
  the app can never disagree about how a subject is scored;
* plain-English questions are answered by ``multi_agent.py``, which builds
  on the Question 6 agent (``question_6_genai/clinical_agent.py``) so that
  one question can combine several conditions.

Like ``ae_service``, these are plain pandas functions with no web framework
dependency, so they can be tested on their own.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

# Make the Question 5 (ae_service, main) and Question 6 (clinical_agent)
# modules importable from this folder.
REPO_ROOT = Path(__file__).resolve().parents[2]
for folder in (REPO_ROOT / "question_5_api", REPO_ROOT / "question_6_genai"):
    if str(folder) not in sys.path:
        sys.path.insert(0, str(folder))

import ae_service  # noqa: E402  (needs the path set up above)
from multi_agent import MultiFilterAgent  # noqa: E402

# AE variables shown in a subject's profile, in display order.
EVENT_COLUMNS = [
    "AESEQ", "AETERM", "AEDECOD", "AESOC", "AESEV", "AESER",
    "AEREL", "AEOUT", "AESTDTC", "AEENDTC", "TRTEMFL",
]


def _records(frame: pd.DataFrame) -> list[dict]:
    """Convert a DataFrame to a list of row dictionaries that are safe as JSON.

    pandas marks missing values as NaN, which is not valid JSON, so they are
    replaced by None (sent as ``null``).
    """
    clean = frame.astype(object).where(frame.notna(), None)
    return clean.to_dict(orient="records")


def filter_options(df: pd.DataFrame) -> dict:
    """Severities and treatment arms present in the data, for the app's dropdowns.

    Severities are listed in clinical order (MILD, MODERATE, SEVERE) rather
    than alphabetically; any unexpected values follow at the end.
    """
    found = set(df["AESEV"].dropna().str.upper())
    known = [sev for sev in ae_service.SEVERITY_WEIGHTS if sev in found]
    other = sorted(found - set(ae_service.SEVERITY_WEIGHTS))
    arms = sorted(df["ACTARM"].dropna().unique().tolist())
    return {"severities": known + other, "treatment_arms": arms}


def risk_summary(df: pd.DataFrame) -> list[dict]:
    """Risk score and category for every subject in one table.

    Uses the same rule as GET /subject-risk (MILD = 1, MODERATE = 3,
    SEVERE = 5 points per AE), so the app can show all subjects with one
    request instead of one request per subject. Sorted from highest score.
    """
    data = df.dropna(subset=["USUBJID"])
    if data.empty:
        return []

    points = data["AESEV"].str.upper().map(ae_service.SEVERITY_WEIGHTS).fillna(0)
    by_subject = data.assign(points=points).groupby("USUBJID")

    summary = pd.DataFrame(
        {
            "treatment_arm": by_subject["ACTARM"].first(),
            "n_events": by_subject.size(),
            "risk_score": by_subject["points"].sum().astype(int),
        }
    )
    summary = summary.rename_axis("subject_id").reset_index()
    summary["risk_category"] = summary["risk_score"].map(ae_service.categorise_risk)
    summary = summary.sort_values(["risk_score", "subject_id"], ascending=[False, True])
    return _records(summary)


def subject_events(df: pd.DataFrame, subject_id: str) -> dict | None:
    """All AE records for one subject, in start-date order.

    Returns None if the subject has no records (the API turns this into a 404).
    """
    sid = str(subject_id).strip()
    records = df.loc[df["USUBJID"] == sid]
    if records.empty:
        return None

    columns = [col for col in EVENT_COLUMNS if col in records.columns]
    events = records[columns]
    sort_by = [col for col in ("AESTDTC", "AESEQ") if col in columns]
    if sort_by:
        # AESEQ is read as text, so sort it as a number ("2" before "10").
        events = events.sort_values(
            sort_by,
            key=lambda s: pd.to_numeric(s, errors="coerce") if s.name == "AESEQ" else s,
            na_position="last",
        )

    arms = records["ACTARM"].dropna()
    return {
        "subject_id": sid,
        "treatment_arm": arms.iloc[0] if not arms.empty else None,
        "n_events": int(len(records)),
        "events": _records(events),
    }


# ---------------------------------------------------------------------------
# Plain-English questions (multi-condition agent, built on Question 6)
# ---------------------------------------------------------------------------
_AGENT: dict = {}


def get_agent(df: pd.DataFrame) -> MultiFilterAgent:
    """The question-answering agent for this data, created once and then reused.

    Building the agent reads the data's schema and chooses the language model
    (OpenAI if OPENAI_API_KEY is set when it is first needed, otherwise the
    offline mock), so it is done once rather than for every question.
    """
    agent = _AGENT.get("agent")
    if agent is None or agent.df is not df:  # new data (e.g. in tests): new agent
        agent = MultiFilterAgent(df)
        _AGENT["agent"] = agent
    return agent


def ask_question(df: pd.DataFrame, question: str) -> dict:
    """Answer one question, which may combine several conditions.

    Returns the filters the question was turned into (AND between filters,
    OR between the values of one filter), the number of matching AE records,
    the subjects, and the language model used. Raises ValueError if the
    question cannot be turned into filters.
    """
    agent = get_agent(df)
    result = agent.ask(question.strip())
    return {**result, "backend": agent.backend}
