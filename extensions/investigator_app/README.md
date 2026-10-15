# Investigator app: AE Safety Explorer (extension)

A Streamlit web app on top of the Question 5 API, for investigators and
medical monitors who want answers without writing code or calling an API.

> **Beyond the brief.** This is not one of the six assessment answers.
> `question_5_api` and `question_6_genai` are unchanged; this folder only
> builds on them.

## What it does

| Tab | Question it answers | API calls |
|---|---|---|
| **Cohort finder** | Which subjects had AEs of this severity, in this arm? | `POST /ae-query` (Question 5) |
| **Risk overview** | Which subjects need attention first, and how does each arm compare? | `GET /risk-summary` |
| **Subject profile** | What is this subject's score, and what AEs make it up? | `GET /subject-risk/{id}` (Question 5), `GET /subjects/{id}/events` |

The cohort can be downloaded as CSV, and the sidebar shows whether the API is
connected and how the risk score works.

## How it fits together

```
Browser ──> app.py (Streamlit) ──HTTP──> api.py ──> question_5_api/main.py   original endpoints, unchanged
                                            └─────> extended_service.py ──> question_5_api/ae_service.py
                                                    (3 new read-only          (scoring rules, reused
                                                     endpoints)                not copied)
```

* **Question 5 is reused, not copied.** `api.py` imports the Question 5 app
  and adds three read-only endpoints to it. The scoring rules
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
* **Colours carry meaning.** Red, amber and green are used only for the risk
  categories, always with an icon and a text label, never colour alone. The
  controls use a neutral teal (`.streamlit/config.toml`), so a button never
  looks like a risk signal.
* **Missing values are sent as JSON `null`**, which pandas' `NaN` is not.

## Run it

From this folder, with the Python environment active:

```bash
pip install -r requirements.txt      # Question 5 packages + streamlit, requests
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
* To point the app at an API somewhere else, set `AE_API_URL`
  (default `http://127.0.0.1:8000`).

Stop either process with Ctrl+C.

## Tests

```bash
python -m pytest -v
```

The tests cover the new endpoints on a hand-made dataset with known answers,
check that the original Question 5 endpoints still behave the same, and check
that `/risk-summary` agrees with `/subject-risk` for every subject.

## Files

| File | Purpose |
|---|---|
| `app.py` | The Streamlit app |
| `api.py` | Question 5 app + the three new endpoints and their response models |
| `extended_service.py` | Logic for the new endpoints (plain pandas, reuses `ae_service`) |
| `test_extended_api.py` | `pytest` tests |
| `.streamlit/config.toml` | App theme |
| `requirements.txt` | Dependencies (includes the Question 5 requirements) |

## Limitations and next steps

* **Population.** Only subjects with at least one AE are in the AE data, so
  subjects with no AEs are not listed (they would score 0, Low). A
  production version would join to ADSL for the full safety population.
* **Prototype, not production.** It runs locally over HTTP, with no login and
  no audit trail. A GxP deployment would add authentication, HTTPS, logging of
  who viewed what, and a validated data source in place of a CSV.
* **Next:** an "Ask a question" tab that sends plain-English questions to the
  Question 6 agent through an `/ask` endpoint.
