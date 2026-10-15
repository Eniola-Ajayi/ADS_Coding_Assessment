# Question 6: GenAI Clinical Data Assistant

Translates free-text safety questions into a structured pandas filter on the
AE data, without hard-coded keyword rules.

| File | Purpose |
|---|---|
| `clinical_agent.py` | Schema definition, prompt, output parser, `ClinicalTrialDataAgent` |
| `test_agent.py` | Runs three example questions and prints the results |
| `requirements.txt` | Dependencies (LangChain/OpenAI only needed for a real LLM) |

## How it works: Prompt -> Parse -> Execute

```
"Give me the subjects who had AEs of Moderate severity"
      |
  (1) PROMPT   schema (column meanings + real example values from the data)
      |        + the question  ->  LLM
      v
  (2) PARSE    LLM reply  {"target_column": "AESEV", "filter_value": "MODERATE"}
      |        -> extracted, validated with pydantic, column checked against schema
      v
  (3) EXECUTE  df[df["AESEV"].str.upper() == "MODERATE"]
               -> unique USUBJIDs + count
```

* **Schema**: `COLUMN_DESCRIPTIONS` explains each column in plain language
  (AESEV = severity/intensity, AETERM = specific condition, AESOC = body
  system, ...). `build_schema()` adds real values from the data so the LLM
  sees how they are written.
* **Mapping is done by the LLM**, not by rules: "intensity" -> AESEV,
  "Headache" -> AETERM, "Cardiac" -> AESOC.
* **Execution** uses exact matching for coded columns (AESEV, AESER, ...) and
  case-insensitive "contains" matching for terms and body systems, so
  "CARDIAC" finds "CARDIAC DISORDERS".
* **Guardrails**: replies without valid JSON, unknown columns or empty values
  raise clear errors; questions that do not fit the data return a helpful
  message rather than a wrong answer.

## LLM back-ends

| Situation | Back-end |
|---|---|
| `OPENAI_API_KEY` set and `langchain-openai` installed | `ChatOpenAI(model="gpt-4o-mini", temperature=0)` via LangChain |
| Otherwise | `MockLLM`: offline stand-in, same Prompt -> Parse -> Execute flow |
| Any other LangChain chat model | `ClinicalTrialDataAgent(df, llm=my_model)` |

`MockLLM` has no synonym table: it answers by matching the question against
the values that actually occur in each column of the schema, and returns the
same JSON a real model would. It exists so that the full pipeline can be run
and tested without an API key.

## Run

```bash
cd question_6_genai
pip install -r requirements.txt
python test_agent.py                 # uses MockLLM

set OPENAI_API_KEY=sk-...            # Windows (macOS/Linux: export OPENAI_API_KEY=...)
python test_agent.py                 # uses OpenAI via LangChain
```

Example output:

```
Q: Give me the subjects who had Adverse events of Moderate severity
   -> filter AESEV ~ 'MODERATE'
   -> ... subjects (... AE records)
```

Input: `../data/adae.csv` (created by `data/export_adae.R`; override with
`ADAE_PATH`). It contains the SDTM AE variables (USUBJID, AETERM, AEDECOD,
AESOC, AESEV, ...) from `pharmaverseadam::adae`.
