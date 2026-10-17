# Investigator app: AE Safety Explorer (extension)

A Streamlit web app on top of the Question 5 API and the Question 6 agent, for
investigators and medical monitors who want answers without writing code or
calling an API.

> **Beyond the brief.** This is not one of the six assessment answers. It
> imports the Question 5 and Question 6 code without changing it; this folder
> only builds on them.

## What it does

| Tab | Question it answers | API calls |
|---|---|---|
| **Ask a question** | Anything in plain English, including combined conditions, e.g. "Moderate or severe skin problems on placebo" | `POST /ask` (agent built on Question 6, behind the API) |
| **Cohort finder** | Which subjects had AEs of this severity, in this arm? | `POST /ae-query` (Question 5) |
| **Risk overview** | Which subjects need attention first, and how does each arm compare? | `GET /risk-summary` |
| **Subject profile** | What is this subject's score, and what AEs make it up? | `GET /subject-risk/{id}` (Question 5), `GET /subjects/{id}/events` |

Results can be downloaded as CSV, and the sidebar shows whether the API is
connected and how the risk score works. The "Ask a question" tab always shows
how the question was understood, for example

> Searched for adverse events where **Severity** (AESEV) is "MODERATE" or
> "SEVERE" and **Body system** (AESOC) contains "SKIN AND SUBCUTANEOUS TISSUE
> DISORDERS" and **Treatment arm** (ACTARM) is "Placebo"

so the answer can be checked rather than taken on trust.

## From one filter to several

Question 6, as the brief asks, turns a question into **one** filter
(`target_column` + `filter_value`), so "severe headaches on placebo" could
only be answered on one of its three conditions. `multi_agent.py` extends it
without changing it: the language model returns a list of filters,

```json
{"filters": [{"column": "AESEV",  "values": ["SEVERE"]},
             {"column": "AETERM", "values": ["HEADACHE"]},
             {"column": "ACTARM", "values": ["Placebo"]}]}
```

* **AND between filters, OR within one.** Every filter must hold for the same
  AE record; "mild or moderate" is one filter with two values.
* **Reused from Question 6:** the schema shown to the model (column meanings
  plus real values from the data), the choice of model (OpenAI if
  `OPENAI_API_KEY` is set, otherwise an offline stand-in), and the
  Prompt -> Parse -> Execute pipeline with pydantic checking the reply.
* **Extra checks on the model's reply**, because a wrong filter would
  otherwise look like a real answer:
  * a column that is not in the data is rejected (as in Question 6);
  * for columns matched exactly (severity, seriousness, causality, outcome,
    treatment arm), a value
    that is not in the data, such as ACTARM "High Dose", is rejected with the
    list of real values, instead of quietly matching nobody;
  * the same column used twice ("AETERM is HEADACHE and AETERM is NAUSEA",
    which no single record can meet) is rejected with an explanation.
* **The offline stand-in (`MultiMockLLM`)** extends the Question 6 MockLLM: it
  keeps every column that matches instead of the first, recognises a body
  system by a word only it has ("cardiac"), an arm without its drug name
  ("high dose"), and "serious" / "non-serious". It has no synonym list, so
  "itching" will not find PRURITUS; OpenAI will.

## How it fits together

```
Browser ──> app.py (Streamlit) ──HTTP──> api.py ──> question_5_api/main.py        original endpoints, unchanged
                                            └─────> extended_service.py ──┬──> question_5_api/ae_service.py
                                                    (new endpoints)       │     (scoring rules, reused not copied)
                                                                          └──> multi_agent.py ──> question_6_genai/clinical_agent.py
                                                                               (used by /ask)     (schema, model choice, reused)
```

* **Questions 5 and 6 are reused, not copied.** `api.py` imports the
  Question 5 app and adds four endpoints to it. The scoring rules
  (`SEVERITY_WEIGHTS`, `categorise_risk`) are imported from `ae_service.py`,
  so there is one definition of the rules. A test checks that the new bulk
  endpoint gives the same score as `/subject-risk` for every subject.
* **The app never touches the data.** Every number comes from the API, so
  another front end (Shiny, Power BI, a scheduled report) would show exactly
  the same results.
* **The new endpoints exist because a real front end needs them:**
  * `/risk-summary` returns every subject in one request, instead of one
    `/subject-risk` call per subject.
  * `/options` fills the dropdowns from the data, so they are never typed in
    by hand.
  * `/subjects/{id}/events` returns one subject's AEs, for the drill-down.
  * `/ask` puts question answering behind the API, on the same data the
    other endpoints use (see [From one filter to several](#from-one-filter-to-several)).
    Tests check that questions `/ae-query` can also express (severity and
    arm) return the same subjects, and that one-condition questions get the
    same answer as the Question 6 agent. Questions that cannot be answered
    get a 422 with an explanation; a failed LLM call gets a 502.
* **Colours carry meaning.** Red, amber and green are used only for the risk
  categories, always with an icon and a text label, never colour alone. The
  controls use a neutral teal (`.streamlit/config.toml`), so a button never
  looks like a risk signal.
* **Missing values are sent as JSON `null`**, which pandas' `NaN` is not.

## Run it

From this folder, with the Python environment active:

```bash
pip install -r requirements.txt      # Question 5 + Question 6 packages, streamlit, requests
```

Then start two processes, each in its own terminal:

```bash
uvicorn api:app --reload             # terminal 1: the extended API on port 8000
streamlit run app.py                 # terminal 2: the app, opens in your browser
```

* If the Question 5 API (`question_5_api`, `uvicorn main:app`) is already
  running, stop it first. Both use port 8000.
* The first time Streamlit runs, it may ask for an email address in the
  terminal. Press Enter to skip.
* All endpoints, old and new, are listed at <http://127.0.0.1:8000/docs>.
  The new ones are under "Investigator app".
* **"Ask a question" with a real LLM:** set `OPENAI_API_KEY` in terminal 1
  *before* starting the API, because the API (not the app) calls the model.
  Without a key it uses the offline stand-in, and the tab says so under each
  answer.
* To point the app at an API somewhere else, set `AE_API_URL`
  (default `http://127.0.0.1:8000`).

Stop either process with Ctrl+C.

## Tests

```bash
python -m pytest -v
```

37 tests, on hand-made datasets with known answers. They never call OpenAI,
even if `OPENAI_API_KEY` is set.

* `test_extended_api.py`: the new endpoints; the original Question 5
  endpoints still behave the same; `/risk-summary` agrees with
  `/subject-risk` for every subject; `/ask` agrees with `/ae-query` and with
  the Question 6 agent, and applies combined conditions to the same record.
* `test_multi_agent.py`: bad replies from a language model (no JSON, unknown
  column, made-up value, same column twice, too many filters) are stopped
  with a clear message, and the offline stand-in finds every condition.

## Files

| File | Purpose |
|---|---|
| `app.py` | The Streamlit app |
| `api.py` | Question 5 app + the four new endpoints and their request/response models |
| `extended_service.py` | Logic for the new endpoints (plain pandas; reuses `ae_service`) |
| `multi_agent.py` | Multi-condition question answering, built on the Question 6 agent |
| `test_extended_api.py`, `test_multi_agent.py` | `pytest` tests |
| `.streamlit/config.toml` | App theme |
| `requirements.txt` | Dependencies (includes the Question 5 and 6 requirements) |

## Limitations and next steps

* **Population.** Only subjects with at least one AE are in the AE data, so
  subjects with no AEs are not listed (they would score 0, Low). A
  production version would join to ADSL for the full safety population.
* **Prototype, not production.** It runs locally over HTTP, with no login and
  no audit trail. A GxP deployment would add authentication, HTTPS, logging of
  who viewed what, and a validated data source in place of a CSV.
* **Conditions apply to one AE record at a time.** "Severe headaches" means
  records that are both severe and a headache. A question about subjects who
  had two *different* events ("patients with a headache and nausea") is
  answered as "headache or nausea", and the tab shows this. Finding subjects
  who had both would need a subject-level step (one search per event, then
  the subjects in both), a natural next step.
* **Questions only filter the AE variables in the schema**: no counts by
  group, dates or lab values. Questions are limited to 500 characters.
