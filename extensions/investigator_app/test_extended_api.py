"""Tests for the extended API used by the investigator app.

Run from this folder with:  python -m pytest -v

Uses a small, hand-made dataset so every expected value can be checked by eye:

    S-1  Placebo  MILD, MODERATE, SEVERE   1 + 3 + 5 =  9  Medium
    S-2  Drug A   SEVERE x 3               5 + 5 + 5 = 15  High
    S-3  Placebo  MILD                                 1   Low
    S-4  Drug A   (severity missing)                   0   Low
"""

import pandas as pd
import pytest
from fastapi.testclient import TestClient

import api

SAMPLE = pd.DataFrame(
    {
        "USUBJID": ["S-1", "S-1", "S-1", "S-2", "S-2", "S-2", "S-3", "S-4"],
        "ACTARM": ["Placebo"] * 3 + ["Drug A"] * 3 + ["Placebo", "Drug A"],
        "AESEQ": ["2", "1", "10", "1", "2", "3", "1", "1"],
        "AETERM": ["HEADACHE", "RASH", "SYNCOPE", "NAUSEA", "NAUSEA", "VOMITING",
                   "COUGH", "FATIGUE"],
        "AESOC": ["NERVOUS SYSTEM DISORDERS", "SKIN AND SUBCUTANEOUS TISSUE DISORDERS",
                  "NERVOUS SYSTEM DISORDERS", "GASTROINTESTINAL DISORDERS",
                  "GASTROINTESTINAL DISORDERS", "GASTROINTESTINAL DISORDERS",
                  "RESPIRATORY, THORACIC AND MEDIASTINAL DISORDERS",
                  "GENERAL DISORDERS AND ADMINISTRATION SITE CONDITIONS"],
        "AESEV": ["MILD", "MODERATE", "SEVERE", "SEVERE", "SEVERE", "SEVERE", "MILD", None],
        "AESTDTC": ["2014-01-03", "2014-01-02", "2014-02-01", "2014-01-05",
                    "2014-01-06", "2014-01-07", "2014-03-01", None],
    }
)


@pytest.fixture
def client(tmp_path, monkeypatch):
    csv = tmp_path / "adae.csv"
    SAMPLE.to_csv(csv, index=False)
    monkeypatch.setenv("ADAE_PATH", str(csv))
    with TestClient(api.app) as c:  # runs the Question 5 start-up (loads data)
        yield c


# --- The original Question 5 endpoints are still there and unchanged --------
def test_original_endpoints_still_work(client):
    assert client.get("/").json() == {"message": "Clinical Trial Data API is running"}
    body = client.post("/ae-query", json={"treatment_arm": "Placebo"}).json()
    assert body == {"count": 4, "n_subjects": 2, "subjects": ["S-1", "S-3"]}
    assert client.get("/subject-risk/S-2").json()["risk_category"] == "High"


# --- GET /options -----------------------------------------------------------
def test_options_in_clinical_order(client):
    body = client.get("/options").json()
    assert body == {
        "severities": ["MILD", "MODERATE", "SEVERE"],
        "treatment_arms": ["Drug A", "Placebo"],
    }


# --- GET /risk-summary ------------------------------------------------------
def test_risk_summary_values_and_order(client):
    rows = client.get("/risk-summary").json()
    assert [(r["subject_id"], r["risk_score"], r["risk_category"]) for r in rows] == [
        ("S-2", 15, "High"),
        ("S-1", 9, "Medium"),
        ("S-3", 1, "Low"),
        ("S-4", 0, "Low"),
    ]
    assert rows[0]["treatment_arm"] == "Drug A"
    assert rows[0]["n_events"] == 3


def test_risk_summary_agrees_with_subject_risk(client):
    """The bulk endpoint must give the same answer as /subject-risk for everyone."""
    for row in client.get("/risk-summary").json():
        single = client.get(f"/subject-risk/{row['subject_id']}").json()
        assert single["risk_score"] == row["risk_score"]
        assert single["risk_category"] == row["risk_category"]


# --- GET /subjects/{subject_id}/events -------------------------------------
def test_subject_events_in_date_order(client):
    body = client.get("/subjects/S-1/events").json()
    assert body["subject_id"] == "S-1"
    assert body["treatment_arm"] == "Placebo"
    assert body["n_events"] == 3
    assert [e["AESTDTC"] for e in body["events"]] == ["2014-01-02", "2014-01-03", "2014-02-01"]


def test_subject_events_missing_values_are_null(client):
    event = client.get("/subjects/S-4/events").json()["events"][0]
    assert event["AESEV"] is None
    assert event["AESTDTC"] is None


def test_subject_events_404(client):
    assert client.get("/subjects/NOT-A-SUBJECT/events").status_code == 404


# --- /docs lists both the original and the new endpoints --------------------
def test_openapi_lists_all_endpoints(client):
    paths = client.get("/openapi.json").json()["paths"]
    for path in ["/", "/ae-query", "/subject-risk/{subject_id}",
                 "/options", "/risk-summary", "/subjects/{subject_id}/events"]:
        assert path in paths
