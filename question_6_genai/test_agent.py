"""Test script for the GenAI Clinical Data Assistant (Question 6).

Runs three example questions and prints the results:

    python test_agent.py

Or ask your own questions, one after another (chat mode):

    python test_agent.py --chat

Uses OpenAI via LangChain if OPENAI_API_KEY is set; otherwise the offline
MockLLM (same Prompt -> Parse -> Execute flow).
"""

import argparse

from clinical_agent import ClinicalTrialDataAgent

QUESTIONS = [
    "Give me the subjects who had Adverse events of Moderate severity",
    "Which patients reported a headache?",
    "Show me everyone with a cardiac problem",
]

STOP_WORDS = {"", "q", "quit", "exit"}


def print_result(result: dict, show_question: bool = True) -> None:
    preview = ", ".join(result["subjects"][:10])
    more = " ..." if result["n_subjects"] > 10 else ""
    if show_question:
        print(f"Q: {result['question']}")
    print(f"   -> filter {result['target_column']} ~ '{result['filter_value']}'")
    print(f"   -> {result['n_subjects']} subjects ({result['n_records']} AE records)")
    print(f"   -> {preview}{more}\n")


def run_examples(agent: ClinicalTrialDataAgent) -> None:
    for question in QUESTIONS:
        print_result(agent.ask(question))


def chat(agent: ClinicalTrialDataAgent) -> None:
    """Ask questions until the user types quit (or a blank line, or Ctrl+C)."""
    print("Ask a question about the adverse events. Type quit, or press Enter on a blank line, to stop.")
    while True:
        try:
            question = input("\nYour question: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if question.lower() in STOP_WORDS:
            break
        try:
            print_result(agent.ask(question), show_question=False)
        except ValueError as err:  # the question could not be turned into a filter
            print(f"   -> {err}")
        except Exception as err:  # e.g. the LLM service could not be reached
            print(f"   -> The language model call failed ({type(err).__name__}): {err}")


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(description="Ask questions about the AE data in plain English.")
    parser.add_argument("--chat", action="store_true", help="ask your own questions interactively")
    args = parser.parse_args(argv)

    agent = ClinicalTrialDataAgent.from_csv()
    print(f"LLM back-end: {agent.backend}\n")
    if args.chat:
        chat(agent)
    else:
        run_examples(agent)


if __name__ == "__main__":
    main()
