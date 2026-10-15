"""Clinical Trial Data API (Question 5).

A small FastAPI service over the adverse events data exported from R
(``data/adae.csv``).

Endpoints
---------
GET  /                         health check / welcome message
POST /ae-query                 dynamic filtering by severity and/or treatment arm
GET  /subject-risk/{subject_id} weighted safety risk score for one subject

Run locally (from the question_5_api folder)::

    uvicorn main:app --reload

then open http://127.0.0.1:8000/docs for the interactive Swagger UI.
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

import ae_service

# The data is loaded once at start-up and shared by all requests.
DATA: dict = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    DATA["adae"] = ae_service.load_adae()
    yield
    DATA.clear()


app = FastAPI(
    title="Clinical Trial Data API",
    description="Serves adverse event data, dynamic cohort queries and subject risk scores.",
    version="1.0.0",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Request / response models (these also drive the /docs page)
# ---------------------------------------------------------------------------
class AEQuery(BaseModel):
    """Optional filters. Omitted or null fields are not applied."""

    severity: Optional[list[str]] = Field(
        default=None, examples=[["MILD", "MODERATE"]],
        description="AESEV values to include (case-insensitive).",
    )
    treatment_arm: Optional[str] = Field(
        default=None, examples=["Placebo"],
        description="Actual treatment arm (ACTARM) to include (case-insensitive).",
    )


class AEQueryResult(BaseModel):
    count: int = Field(description="Number of matching AE records.")
    n_subjects: int = Field(description="Number of unique subjects in the cohort.")
    subjects: list[str] = Field(description="Unique USUBJIDs in the cohort.")


class SubjectRisk(BaseModel):
    subject_id: str
    risk_score: int
    risk_category: str


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/")
def root() -> dict:
    """Welcome message confirming the API is running."""
    return {"message": "Clinical Trial Data API is running"}


@app.post("/ae-query", response_model=AEQueryResult)
def ae_query(query: AEQuery) -> dict:
    """Filter AE records by any combination of severity and treatment arm."""
    return ae_service.query_adverse_events(
        DATA["adae"], severity=query.severity, treatment_arm=query.treatment_arm
    )


@app.get("/subject-risk/{subject_id}", response_model=SubjectRisk)
def subject_risk(subject_id: str) -> dict:
    """Weighted safety risk score: MILD = 1, MODERATE = 3, SEVERE = 5 points per AE.

    Category: Low (< 5), Medium (5 to < 15), High (>= 15).
    """
    result = ae_service.subject_risk(DATA["adae"], subject_id)
    if result is None:
        raise HTTPException(status_code=404, detail=f"Subject '{subject_id}' not found")
    return result
