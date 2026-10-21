# Question 5: Clinical Data API (FastAPI)

A REST API over the adverse events data that supports dynamic cohort queries
and a per-subject safety risk score.

| File | Purpose |
|---|---|
| `main.py` | FastAPI app: endpoints, request/response models |
| `ae_service.py` | Business logic (filtering, risk score) as plain pandas functions |
| `test_api.py` | `pytest` tests on a small hand-made dataset |
| `requirements.txt` | Python dependencies |

Input: `../data/adae.csv`, created by `data/export_adae.R` (override with the
`ADAE_PATH` environment variable).

## Run locally

```bash
cd question_5_api
python -m venv .venv
# Activate the environment (pick your shell):
#   Windows CMD:         .venv\Scripts\activate
#   Windows PowerShell:  .venv\Scripts\Activate.ps1
#   macOS / Linux:       source .venv/bin/activate
pip install -r requirements.txt

uvicorn main:app --reload
```

Open <http://127.0.0.1:8000/docs> for the interactive Swagger UI.

#pytest detects files named with the prefix "test_" and-
#runs all the tests within similar to devtools:: test() as seen in R

Run the tests with `python -m pytest -v`. 

## Endpoints

### `GET /`
```json
{"message": "Clinical Trial Data API is running"}
```

### `POST /ae-query`
Optional filters, combined with AND. A missing or `null` field is not applied.
Matching is case-insensitive.
```bash
curl -X POST http://127.0.0.1:8000/ae-query \
     -H "Content-Type: application/json" \
     -d '{"severity": ["MILD", "MODERATE"], "treatment_arm": "Placebo"}'
```
```json
{"count": <matching AE records>, "n_subjects": <unique subjects>, "subjects": ["01-701-...", "..."]}
```
`count` is the number of matching AE records; `subjects` the unique USUBJIDs.

### `GET /subject-risk/{subject_id}`
Sums MILD = 1, MODERATE = 3, SEVERE = 5 points over the subject's AEs, then
categorises the total: Low (< 5), Medium (5 to < 15), High (>= 15).
Response format (example from the brief):
```json
{"subject_id": "01-701-1015", "risk_score": 8, "risk_category": "Medium"}
```
Returns **404** if the subject has no records.

## Design notes
* **Logic separated from the web layer**: `ae_service.py` has no FastAPI
  dependency, so the rules can be tested and reused directly.
* **Pydantic models** validate input (e.g. `severity` must be a list) and
  document the API automatically in `/docs`.
* **Data loaded once** at start-up (FastAPI lifespan), not on every request.
* Records with a missing or unrecognised severity score 0 points.
* **Data source**: the brief mentions `pharmaversesdtm::ae`, but the
  treatment-arm filter needs `ACTARM`, which is not in SDTM AE. The export
  therefore uses `pharmaverseadam::adae`, which is built from SDTM AE and
  carries `ACTARM`.
