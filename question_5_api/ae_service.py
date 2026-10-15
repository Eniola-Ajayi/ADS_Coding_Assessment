"""Business logic for the Clinical Trial Data API.

Kept separate from the FastAPI layer (``main.py``) so the filtering and
risk-score rules are plain pandas functions that can be unit tested without
running a web server.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Iterable

import pandas as pd

# Default location of the exported ADAE data (see data/export_adae.R).
# Can be overridden with the ADAE_PATH environment variable.
DEFAULT_ADAE_PATH = Path(__file__).resolve().parent.parent / "data" / "adae.csv"

REQUIRED_COLUMNS = {"USUBJID", "AESEV", "ACTARM"}

# Points per adverse event, by severity (AESEV)
SEVERITY_WEIGHTS = {"MILD": 1, "MODERATE": 3, "SEVERE": 5}


def load_adae(path: str | os.PathLike | None = None) -> pd.DataFrame:
    """Read the AE data and normalise the columns used for filtering.

    Text columns are read as strings and stripped of surrounding whitespace so
    that comparisons are reliable.
    """
    path = Path(path or os.environ.get("ADAE_PATH", DEFAULT_ADAE_PATH))
    if not path.exists():
        raise FileNotFoundError(
            f"AE data not found at {path}. Run data/export_adae.R first "
            "or set the ADAE_PATH environment variable."
        )

    df = pd.read_csv(path, dtype=str, keep_default_na=False, na_values=[""])
    missing = REQUIRED_COLUMNS - set(df.columns)
    if missing:
        raise ValueError(f"AE data is missing required columns: {sorted(missing)}")

    for col in df.select_dtypes(include=["object", "string"]).columns:
        df[col] = df[col].str.strip()
    return df


def _normalise(values: Iterable[str]) -> list[str]:
    """Upper-case and strip user-supplied filter values."""
    return [str(v).strip().upper() for v in values if v is not None and str(v).strip()]


def query_adverse_events(
    df: pd.DataFrame,
    severity: list[str] | None = None,
    treatment_arm: str | None = None,
) -> dict:
    """Filter AE records on optional criteria (combined with AND).

    Parameters
    ----------
    severity:
        List of AESEV values to keep, e.g. ``["MILD", "MODERATE"]``.
        ``None`` or an empty list means "do not filter on severity".
    treatment_arm:
        Actual treatment arm (ACTARM) to keep, e.g. ``"Placebo"``.
        ``None`` or an empty string means "do not filter on treatment".

    Matching is case-insensitive, so ``"moderate"`` matches ``"MODERATE"``.

    Returns
    -------
    dict with the number of matching records, the number of unique subjects
    and the sorted list of unique USUBJIDs.
    """
    mask = pd.Series(True, index=df.index)

    severities = _normalise(severity or [])
    if severities:
        mask &= df["AESEV"].str.upper().isin(severities)

    if treatment_arm is not None and str(treatment_arm).strip():
        mask &= df["ACTARM"].str.upper() == str(treatment_arm).strip().upper()

    matched = df.loc[mask]
    subjects = sorted(matched["USUBJID"].dropna().unique().tolist())
    return {
        "count": int(len(matched)),
        "n_subjects": len(subjects),
        "subjects": subjects,
    }


def categorise_risk(score: int) -> str:
    """Map a risk score to Low (< 5), Medium (5 to < 15) or High (>= 15)."""
    if score < 5:
        return "Low"
    if score < 15:
        return "Medium"
    return "High"


def subject_risk(df: pd.DataFrame, subject_id: str) -> dict | None:
    """Calculate the weighted safety risk score for one subject.

    Each AE scores MILD = 1, MODERATE = 3, SEVERE = 5 points; missing or
    unrecognised severities score 0. Returns ``None`` if the subject has no
    records in the data (the API turns this into a 404).
    """
    records = df.loc[df["USUBJID"] == str(subject_id).strip()]
    if records.empty:
        return None

    points = records["AESEV"].str.upper().map(SEVERITY_WEIGHTS).fillna(0)
    score = int(points.sum())
    return {
        "subject_id": str(subject_id).strip(),
        "risk_score": score,
        "risk_category": categorise_risk(score),
    }
