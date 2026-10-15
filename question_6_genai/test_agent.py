"""Test script for the GenAI Clinical Data Assistant (Question 6).

Runs three example questions and prints the results.

    python test_agent.py

Uses OpenAI via LangChain if OPENAI_API_KEY is set; otherwise the offline
MockLLM (same Prompt -> Parse -> Execute flow).
"""

from clinical_agent import ClinicalTrialDataAgent

QUESTIONS = [
    "Give me the subjects who had Adverse events of Moderate severity",
    "Which patients reported a headache?",
    "Show me everyone with a cardiac problem",
]


def main() -> None:
    agent = ClinicalTrialDataAgent.from_csv()
    print(f"LLM back-end: {agent.backend}\n")

    for question in QUESTIONS:
        result = agent.ask(question)
        preview = ", ".join(result["subjects"][:10])
        more = " ..." if result["n_subjects"] > 10 else ""
        print(f"Q: {question}")
        print(f"   -> filter {result['target_column']} ~ '{result['filter_value']}'")
        print(f"   -> {result['n_subjects']} subjects ({result['n_records']} AE records)")
        print(f"   -> {preview}{more}\n")


if __name__ == "__main__":
    main()
