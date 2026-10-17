"""Tests for the extended API used by the investigator app.

Run from this folder with:  python -m pytest -v

Uses a small, hand-made dataset so every expected value can be checked by eye:

    S-1  Placebo  MILD, MODERATE, SEVERE   1 + 3 + 5 =  9  Medium
    S-2  Drug A   SEVERE x 3               5 + 5 + 5 = 15  High
    S-3  Placebo  MILD                                 1   Low
    S-4  Drug A   (severity missing)                   0   Low

The /ask tests use the offline stand-in for the language model, so their
answers are fixed. test_multi_agent.py tests how a language model's reply is
checked.
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
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)  # /ask uses the offline MockLLM
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


# --- POST /ask (question answering, built on the Question 6 agent) ----------
def ask(client, question):
    return client.post("/ask", json={"question": question}).json()


def conditions(body):
    """The filters in a /ask reply, as (column, values) pairs."""
    return [(f["column"], f["values"]) for f in body["filters"]]


def test_ask_maps_the_question_and_returns_subjects(client):
    body = ask(client, "Which subjects had a headache?")
    assert body["filters"] == [{"column": "AETERM", "values": ["HEADACHE"], "match": "contains"}]
    assert body["subjects"] == ["S-1"]
    assert body["n_records"] == 1
    assert body["backend"] == "MultiMockLLM"


@pytest.mark.parametrize(
    "question, expected_filters, query",
    [
        # one condition
        ("Show me severe adverse events",
         [("AESEV", ["SEVERE"])],
         {"severity": ["SEVERE"]}),
        # two conditions on different variables: AND
        ("Which placebo patients had severe events?",
         [("AESEV", ["SEVERE"]), ("ACTARM", ["Placebo"])],
         {"severity": ["SEVERE"], "treatment_arm": "Placebo"}),
        # two values of one variable: OR
        ("mild or moderate events",
         [("AESEV", ["MILD", "MODERATE"])],
         {"severity": ["MILD", "MODERATE"]}),
        # both together
        ("Moderate or severe events on placebo",
         [("AESEV", ["MODERATE", "SEVERE"]), ("ACTARM", ["Placebo"])],
         {"severity": ["MODERATE", "SEVERE"], "treatment_arm": "Placebo"}),
    ],
)
def test_ask_agrees_with_ae_query(client, question, expected_filters, query):
    """Questions the Question 5 filters can also express give the same answer."""
    asked = ask(client, question)
    queried = client.post("/ae-query", json=query).json()
    assert conditions(asked) == expected_filters
    assert asked["subjects"] == queried["subjects"]
    assert asked["n_records"] == queried["count"]


def test_ask_three_conditions(client):
    """Severity, body system and arm must all hold for the same AE record."""
    body = ask(client, "Severe nervous system events on placebo")
    assert conditions(body) == [
        ("AESEV", ["SEVERE"]),
        ("AESOC", ["NERVOUS SYSTEM DISORDERS"]),
        ("ACTARM", ["Placebo"]),
    ]
    assert body["subjects"] == ["S-1"]  # S-1's severe syncope
    assert body["n_records"] == 1


def test_ask_conditions_apply_to_the_same_record(client):
    """S-1 had a headache and a severe event, but the headache was mild."""
    body = ask(client, "Severe headaches")
    assert conditions(body) == [("AESEV", ["SEVERE"]), ("AETERM", ["HEADACHE"])]
    assert body["n_subjects"] == 0
    assert body["subjects"] == []


def test_ask_matches_the_question_6_agent_on_one_condition(client):
    """For a one-condition question, the answer is the same as Question 6's."""
    from clinical_agent import ClinicalTrialDataAgent

    q6 = ClinicalTrialDataAgent(SAMPLE)  # offline MockLLM
    for question in ["Which subjects had a headache?", "Show me severe adverse events",
                     "Anyone with skin problems?", "Which patients were on placebo?"]:
        assert ask(client, question)["subjects"] == q6.ask(question)["subjects"], question


def test_ask_unanswerable_question_gives_422_with_explanation(client):
    r = client.post("/ask", json={"question": "What is the weather like?"})
    assert r.status_code == 422
    assert "could not be mapped" in r.json()["detail"]


def test_ask_rejects_an_empty_question(client):
    assert client.post("/ask", json={"question": ""}).status_code == 422


# --- /docs lists both the original and the new endpoints --------------------
def test_openapi_lists_all_endpoints(client):
    paths = client.get("/openapi.json").json()["paths"]
    for path in ["/", "/ae-query", "/subject-risk/{subject_id}",
                 "/options", "/risk-summary", "/subjects/{subject_id}/events", "/ask"]:
        assert path in paths
