"""Tests for the Clinical Trial Data API.

Run from the question_5_api folder with:  pytest -v

Uses a small, hand-made dataset (not the real export) so expected results
can be checked by eye.
"""

import pandas as pd
import pytest
from fastapi.testclient import TestClient

import ae_service
import main

SAMPLE = pd.DataFrame(
    {
        "USUBJID": ["S-1", "S-1", "S-1", "S-2", "S-2", "S-3", "S-4"],
        "ACTARM": ["Placebo", "Placebo", "Placebo", "Drug A", "Drug A", "Placebo", "Drug A"],
        "AESEV": ["MILD", "MODERATE", "SEVERE", "SEVERE", "SEVERE", "MILD", None],
    }
)


@pytest.fixture
def client(tmp_path, monkeypatch):
    csv = tmp_path / "adae.csv"
    SAMPLE.to_csv(csv, index=False)
    monkeypatch.setenv("ADAE_PATH", str(csv))
    with TestClient(main.app) as c:  # runs the lifespan start-up (loads data)
        yield c


def test_root(client):
    r = client.get("/")
    assert r.status_code == 200
    assert r.json() == {"message": "Clinical Trial Data API is running"}


def test_query_no_filters_returns_everything(client):
    body = client.post("/ae-query", json={}).json()
    assert body["count"] == 7
    assert body["subjects"] == ["S-1", "S-2", "S-3", "S-4"]


def test_query_severity_and_arm(client):
    body = client.post(
        "/ae-query", json={"severity": ["MILD", "MODERATE"], "treatment_arm": "Placebo"}
    ).json()
    assert body == {"count": 3, "n_subjects": 2, "subjects": ["S-1", "S-3"]}


def test_query_null_fields_are_ignored(client):
    body = client.post("/ae-query", json={"severity": None, "treatment_arm": "Drug A"}).json()
    assert body["count"] == 3
    assert body["subjects"] == ["S-2", "S-4"]


def test_query_is_case_insensitive(client):
    body = client.post("/ae-query", json={"severity": ["severe"], "treatment_arm": "drug a"}).json()
    assert body["count"] == 2
    assert body["subjects"] == ["S-2"]


def test_query_no_matches(client):
    body = client.post("/ae-query", json={"treatment_arm": "Unknown"}).json()
    assert body == {"count": 0, "n_subjects": 0, "subjects": []}


def test_query_rejects_wrong_types(client):
    r = client.post("/ae-query", json={"severity": "MILD"})  # must be a list
    assert r.status_code == 422


def test_subject_risk_medium(client):
    # 1 + 3 + 5 = 9 -> Medium
    assert client.get("/subject-risk/S-1").json() == {
        "subject_id": "S-1", "risk_score": 9, "risk_category": "Medium"
    }


def test_subject_risk_low_and_missing_severity(client):
    assert client.get("/subject-risk/S-3").json()["risk_category"] == "Low"
    assert client.get("/subject-risk/S-4").json()["risk_score"] == 0


def test_subject_risk_404(client):
    r = client.get("/subject-risk/NOT-A-SUBJECT")
    assert r.status_code == 404


@pytest.mark.parametrize(
    "score, expected",
    [(0, "Low"), (4, "Low"), (5, "Medium"), (14, "Medium"), (15, "High"), (40, "High")],
)
def test_risk_category_boundaries(score, expected):
    assert ae_service.categorise_risk(score) == expected
