"""Clinical Trial Data API, extended for the investigator app.

This is the Question 5 API itself (imported from ``question_5_api/main.py``,
unchanged) plus three read-only endpoints that the Streamlit app needs:

GET /options                         severities and treatment arms in the data
GET /risk-summary                    risk score and category for every subject
GET /subjects/{subject_id}/events    one subject's adverse events

The original endpoints (/, /ae-query, /subject-risk/{subject_id}) behave
exactly as in Question 5.

Run from this folder::

    uvicorn api:app --reload

then open http://127.0.0.1:8000/docs to see all endpoints.
"""

from __future__ import annotations

from typing import Optional

from fastapi import HTTPException
from pydantic import BaseModel, Field

import extended_service  # imported first: it makes the question_5_api modules importable
import main as q5_api  # the original Question 5 app (question_5_api/main.py)

app = q5_api.app
app.title = "Clinical Trial Data API (with investigator app extension)"
app.description = (
    "The Question 5 endpoints, unchanged, plus read-only endpoints used by the "
    "Streamlit investigator app (tagged 'Investigator app')."
)

TAG = "Investigator app"


# ---------------------------------------------------------------------------
# Response models (they also document the new endpoints on /docs)
# ---------------------------------------------------------------------------
class FilterOptions(BaseModel):
    severities: list[str] = Field(description="AESEV values in the data, in clinical order.")
    treatment_arms: list[str] = Field(description="ACTARM values in the data.")


class SubjectRiskRow(BaseModel):
    subject_id: str
    treatment_arm: Optional[str] = None
    n_events: int = Field(description="Number of AE records for the subject.")
    risk_score: int
    risk_category: str


class SubjectEvents(BaseModel):
    subject_id: str
    treatment_arm: Optional[str] = None
    n_events: int
    events: list[dict[str, Optional[str]]] = Field(
        description="The subject's AE records (SDTM AE variable names), in start-date order."
    )


# ---------------------------------------------------------------------------
# New endpoints. They read the data the Question 5 app loads at start-up.
# ---------------------------------------------------------------------------
@app.get("/options", response_model=FilterOptions, tags=[TAG])
def options() -> dict:
    """Values available for the cohort filters."""
    return extended_service.filter_options(q5_api.DATA["adae"])


@app.get("/risk-summary", response_model=list[SubjectRiskRow], tags=[TAG])
def risk_summary() -> list[dict]:
    """Risk score and category for every subject, highest score first.

    Same rule as /subject-risk, but for all subjects in one request.
    """
    return extended_service.risk_summary(q5_api.DATA["adae"])


@app.get("/subjects/{subject_id}/events", response_model=SubjectEvents, tags=[TAG])
def subject_events(subject_id: str) -> dict:
    """All adverse events recorded for one subject."""
    result = extended_service.subject_events(q5_api.DATA["adae"], subject_id)
    if result is None:
        raise HTTPException(status_code=404, detail=f"Subject '{subject_id}' not found")
    return result
