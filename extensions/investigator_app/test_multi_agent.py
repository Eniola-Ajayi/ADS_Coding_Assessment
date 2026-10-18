"""Tests for multi_agent.py, the multi-condition question answering.

Run from this folder with:  python -m pytest -v

A real language model can return anything, so most of these tests give the
agent a scripted reply (ScriptedLLM) and check that bad replies are caught
with a clear message before they reach the data. The rest check the offline
stand-in (MultiMockLLM).
"""

import json

import pandas as pd
import pytest

from multi_agent import MockMessage, MultiFilterAgent, MultiMockLLM, build_multi_messages

DATA = pd.DataFrame(
    {
        "USUBJID": ["S-1", "S-1", "S-2", "S-3", "S-3"],
        "ACTARM": ["Placebo", "Placebo", "Xanomeline High Dose", "Xanomeline Low Dose",
                   "Xanomeline Low Dose"],
        "AETERM": ["APPLICATION SITE PRURITUS", "UPPER RESPIRATORY TRACT INFECTION",
                   "SINUS BRADYCARDIA", "PRURITUS", "HEADACHE"],
        "AESOC": ["GENERAL DISORDERS AND ADMINISTRATION SITE CONDITIONS",
                  "INFECTIONS AND INFESTATIONS", "CARDIAC DISORDERS",
                  "SKIN AND SUBCUTANEOUS TISSUE DISORDERS", "NERVOUS SYSTEM DISORDERS"],
        "AESEV": ["MILD", "MODERATE", "SEVERE", "MILD", None],
        "AESER": ["N", "N", "Y", "N", "N"],
    }
)


@pytest.fixture(autouse=True)
def no_openai_key(monkeypatch):
    """Never call OpenAI from the tests, even if the key is set in the terminal."""
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)


class ScriptedLLM:
    """Stands in for a language model that always gives the same reply."""

    def __init__(self, reply: str):
        self.reply = reply

    def invoke(self, messages):
        return MockMessage(content=self.reply)


def ask_with_reply(reply, question="any question"):
    agent = MultiFilterAgent(DATA, llm=ScriptedLLM(reply))
    return agent.ask(question)


def filters_json(*filters):
    return json.dumps({"filters": [{"column": c, "values": v} for c, v in filters]})


# --- A good reply is used as given ------------------------------------------
def test_reply_in_code_fences_and_lower_case_is_accepted():
    reply = '```json\n{"filters": [{"column": "actarm", "values": "placebo"}]}\n```'
    result = ask_with_reply(reply)
    # the column is upper-cased and the value takes the data's spelling
    assert result["filters"] == [{"column": "ACTARM", "values": ["Placebo"], "match": "exact"}]
    assert result["subjects"] == ["S-1"]


def test_and_between_filters_or_within_a_filter():
    reply = filters_json(("AESEV", ["MILD", "SEVERE"]), ("AESER", ["N"]))
    result = ask_with_reply(reply)
    assert result["n_records"] == 2  # the two mild, non-serious events
    assert result["subjects"] == ["S-1", "S-3"]


def test_contains_match_for_terms():
    result = ask_with_reply(filters_json(("AETERM", ["pruritus"])))
    assert result["n_records"] == 2  # PRURITUS and APPLICATION SITE PRURITUS


def test_repeated_values_are_dropped():
    result = ask_with_reply(filters_json(("AESEV", ["SEVERE", "severe", " "])))
    assert result["filters"][0]["values"] == ["SEVERE"]


# --- A bad reply is stopped with an explanation -----------------------------
@pytest.mark.parametrize(
    "reply, message",
    [
        ("Sorry, I can't help with that.", "did not contain JSON"),
        ('{"filters": []}', "could not be mapped"),
        (filters_json(("AGE", ["65"])), "not in the schema"),
        (filters_json(("AESEV", []),), "Could not parse"),
        # a value the model made up would otherwise quietly match nothing
        (filters_json(("ACTARM", ["High Dose"])), "has no value 'High Dose'"),
        # each record has one AETERM, so AETERM = A and AETERM = B can never both hold
        (filters_json(("AETERM", ["HEADACHE"]), ("AETERM", ["PRURITUS"])), "two conditions on AETERM"),
        (filters_json(*[("AESEV", ["MILD"])] * 6), "Could not parse"),  # more than 5 filters
    ],
)
def test_bad_replies_are_rejected(reply, message):
    with pytest.raises(ValueError, match=message):
        ask_with_reply(reply)


def test_prompt_contains_the_schema_and_the_question():
    agent = MultiFilterAgent(DATA, llm=ScriptedLLM("{}"))
    (_, system), (_, human) = build_multi_messages(agent.schema_text, "Severe events?")
    assert "AESEV" in system and "Xanomeline High Dose" in system  # real values shown
    assert '{"filters": [' in system  # the JSON format asked for
    assert human == "Severe events?"


# --- The offline stand-in ---------------------------------------------------
def mock_conditions(question):
    agent = MultiFilterAgent(DATA)  # no llm given and no API key: MultiMockLLM
    assert isinstance(agent.llm, MultiMockLLM)
    return [(f["column"], f["values"]) for f in agent.ask(question)["filters"]]


@pytest.mark.parametrize(
    "question, expected",
    [
        ("Which subjects had a headache?", [("AETERM", ["HEADACHE"])]),
        # values in the order they appear in the question
        ("severe or mild events", [("AESEV", ["SEVERE", "MILD"])]),
        # a body system by its key word, an arm without its drug name
        ("cardiac events in the high-dose arm",
         [("AESOC", ["CARDIAC DISORDERS"]), ("ACTARM", ["Xanomeline High Dose"])]),
        # "non-serious" is not also counted as "serious"
        ("non-serious skin problems", [("AESER", ["N"]), ("AESOC", ["SKIN AND SUBCUTANEOUS TISSUE DISORDERS"])]),
        ("serious events", [("AESER", ["Y"])]),
        # the words of a reported term are not reused as body systems
        ("upper respiratory tract infections", [("AETERM", ["UPPER RESPIRATORY TRACT INFECTION"])]),
        # the longer term is found first, the shorter one is not added again
        ("application site pruritus", [("AETERM", ["APPLICATION SITE PRURITUS"])]),
    ],
)
def test_mock_finds_every_condition(question, expected):
    assert mock_conditions(question) == expected
