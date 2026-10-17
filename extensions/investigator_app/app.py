"""AE Safety Explorer: a Streamlit front end for the Clinical Trial Data API.

Lets an investigator or medical monitor ask questions in plain English, find
cohorts, see which subjects carry the most safety risk and open a subject's
adverse event history, without writing any code.

The app never reads the data or applies the rules itself. Every number on
screen comes from the API, so the rules stay defined in one place: the risk
score in question_5_api/ae_service.py, the question answering in
multi_agent.py (built on question_6_genai/clinical_agent.py).

Run from this folder, in two terminals:

    uvicorn api:app --reload      # 1. the API
    streamlit run app.py          # 2. this app (opens in your browser)
"""

from __future__ import annotations

import os
from urllib.parse import quote

import altair as alt
import pandas as pd
import requests
import streamlit as st

API_URL = os.environ.get("AE_API_URL", "http://127.0.0.1:8000").rstrip("/")
TIMEOUT_SECONDS = 10
ASK_TIMEOUT_SECONDS = 60  # a language model can take a few seconds to answer
CACHE_SECONDS = 300  # results are reused for 5 minutes, or until "Reload data"

ALL_ARMS = "All treatment arms"

# Risk categories use status colours (good / warning / critical) and are always
# shown with an icon and a text label as well, never colour alone.
RISK_ORDER = ["Low", "Medium", "High"]
RISK_COLOURS = {"Low": "#0ca30c", "Medium": "#fab219", "High": "#d03b3b"}
RISK_ICONS = {"Low": "🟢", "Medium": "🟡", "High": "🔴"}
INK = "#1d2733"  # text colour, matches .streamlit/config.toml

# Plain-language column names for a subject's AE table
EVENT_LABELS = {
    "AESEQ": "Seq",
    "AETERM": "Reported term",
    "AEDECOD": "Preferred term",
    "AESOC": "Body system",
    "AESEV": "Severity",
    "AESER": "Serious",
    "AEREL": "Related to drug",
    "AEOUT": "Outcome",
    "AESTDTC": "Start date",
    "AEENDTC": "End date",
    "TRTEMFL": "Treatment-emergent",
}
# How the variables the question was turned into are described to the user
SEARCH_LABELS = {**EVENT_LABELS, "ACTARM": "Treatment arm"}

EXAMPLE_QUESTIONS = [
    "Which patients reported a headache?",
    "Moderate or severe skin problems on placebo",
    "Serious cardiac events in the high dose arm",
]


# ---------------------------------------------------------------------------
# Talking to the API
# ---------------------------------------------------------------------------
class ApiUnavailable(Exception):
    """The API could not be reached."""


def call_api(method: str, path: str, **kwargs):
    """Send one request to the API and return its JSON reply (None for a 404)."""
    try:
        response = requests.request(
            method, f"{API_URL}{path}", timeout=TIMEOUT_SECONDS, **kwargs
        )
    except requests.exceptions.RequestException as err:
        raise ApiUnavailable(str(err)) from err
    if response.status_code == 404:
        return None
    response.raise_for_status()
    return response.json()


def api_is_running() -> bool:
    try:
        return call_api("GET", "/") is not None
    except Exception:
        return False


@st.cache_data(ttl=CACHE_SECONDS, show_spinner=False)
def get_options() -> dict | None:
    return call_api("GET", "/options")


@st.cache_data(ttl=CACHE_SECONDS, show_spinner=False)
def get_risk_summary() -> pd.DataFrame:
    rows = call_api("GET", "/risk-summary") or []
    columns = ["subject_id", "treatment_arm", "n_events", "risk_score", "risk_category"]
    return pd.DataFrame(rows, columns=columns)


@st.cache_data(ttl=CACHE_SECONDS, show_spinner="Finding subjects...")
def find_cohort(severities: tuple[str, ...], treatment_arm: str | None) -> dict:
    """The Question 5 cohort query (POST /ae-query)."""
    body = {"severity": list(severities) or None, "treatment_arm": treatment_arm}
    return call_api("POST", "/ae-query", json=body)


def error_detail(response: requests.Response) -> str:
    """The API's explanation of an error, as one readable sentence."""
    try:
        detail = response.json().get("detail")
    except ValueError:
        return response.text
    if isinstance(detail, list):  # validation errors are a list of problems
        return "; ".join(str(d.get("msg", d)) for d in detail)
    return str(detail)


@st.cache_data(ttl=CACHE_SECONDS, show_spinner="Thinking about your question...")
def ask(question: str) -> dict:
    """POST /ask: the question-answering agent, behind the API.

    Returns the agent's answer, or {"error": "..."} with the API's explanation
    when the question can't be answered.
    """
    try:
        response = requests.post(
            f"{API_URL}/ask", json={"question": question}, timeout=ASK_TIMEOUT_SECONDS
        )
    except requests.exceptions.RequestException as err:
        raise ApiUnavailable(str(err)) from err
    if response.status_code == 404:
        return {"error": "This API has no /ask endpoint. Start the extended API (uvicorn api:app)."}
    if response.status_code in (422, 502):
        return {"error": error_detail(response)}
    response.raise_for_status()
    return response.json()


@st.cache_data(ttl=CACHE_SECONDS, show_spinner=False)
def get_subject(subject_id: str) -> tuple[dict | None, dict | None]:
    """A subject's risk score (Question 5 endpoint) and AE history."""
    sid = quote(subject_id, safe="")
    return (
        call_api("GET", f"/subject-risk/{sid}"),
        call_api("GET", f"/subjects/{sid}/events"),
    )


# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------
def risk_label(category: str) -> str:
    return f"{RISK_ICONS.get(category, '')} {category}".strip()


def subject_table(frame: pd.DataFrame) -> pd.DataFrame:
    """Subjects with their risk, using column names an investigator would use."""
    return pd.DataFrame(
        {
            "Subject": frame["subject_id"],
            "Treatment arm": frame["treatment_arm"],
            "Adverse events": frame["n_events"],
            "Risk score": frame["risk_score"],
            "Risk category": frame["risk_category"].map(risk_label),
        }
    )


def subject_columns(max_score: int) -> dict:
    """Column settings for subject_table(): the score is drawn as a bar."""
    return {
        "Risk score": st.column_config.ProgressColumn(
            "Risk score",
            help="Points over all of the subject's adverse events",
            min_value=0,
            max_value=max(int(max_score), 1),
            format="%d",
        ),
    }


def risk_by_arm_chart(summary: pd.DataFrame) -> alt.LayerChart:
    """Stacked bars: how many subjects in each arm are Low, Medium and High risk."""
    data = (
        summary.groupby(["treatment_arm", "risk_category"])
        .size()
        .reset_index(name="subjects")
    )
    data["share"] = data["subjects"] / data.groupby("treatment_arm")["subjects"].transform("sum")
    data["order"] = data["risk_category"].map({cat: i for i, cat in enumerate(RISK_ORDER)})

    base = alt.Chart(data)
    y = alt.Y("treatment_arm:N", title=None)
    tooltip = [
        alt.Tooltip("treatment_arm:N", title="Treatment arm"),
        alt.Tooltip("risk_category:N", title="Risk category"),
        alt.Tooltip("subjects:Q", title="Subjects"),
        alt.Tooltip("share:Q", title="Share of arm", format=".0%"),
    ]

    bars = base.mark_bar(stroke="#ffffff", strokeWidth=2).encode(
        y=y,
        x=alt.X("subjects:Q", title="Subjects", stack="zero"),
        color=alt.Color(
            "risk_category:N",
            title="Risk category",
            scale=alt.Scale(domain=RISK_ORDER, range=[RISK_COLOURS[c] for c in RISK_ORDER]),
            legend=alt.Legend(orient="top"),
        ),
        order=alt.Order("order:Q"),
        tooltip=tooltip,
    )

    # Subject counts written inside each segment (skipped if too small to fit).
    # The stack transform works out where each segment starts (x0) and ends (x1).
    labels = (
        base.transform_stack(
            stack="subjects",
            groupby=["treatment_arm"],
            sort=[alt.SortField("order")],
            as_=["x0", "x1"],
        )
        .transform_calculate(mid="(datum.x0 + datum.x1) / 2")
        .transform_filter("datum.subjects >= 3")
        .mark_text(color=INK, fontSize=12)
        .encode(y=y, x=alt.X("mid:Q", title="Subjects"), text=alt.Text("subjects:Q"), tooltip=tooltip)
    )

    return alt.layer(bars, labels).properties(
        title="Subjects by risk category and treatment arm", height=alt.Step(48)
    )


def describe_filters(filters: list[dict]) -> str:
    """How a question was understood, e.g.
    'Severity (AESEV) is "SEVERE" and Treatment arm (ACTARM) is "Placebo"'."""
    parts = []
    for f in filters:
        label = SEARCH_LABELS.get(f["column"], f["column"])
        verb = "is" if f["match"] == "exact" else "contains"
        values = " or ".join(f'"{value}"' for value in f["values"])
        parts.append(f"**{label}** ({f['column']}) {verb} {values}")
    return " and ".join(parts)


def severity_breakdown(events: list[dict], severities: list[str]) -> str:
    """e.g. '3 mild, 1 severe' for a subject's events."""
    counts = pd.Series([e.get("AESEV") for e in events], dtype=object).value_counts()
    parts = [f"{int(counts[s])} {s.lower()}" for s in severities if s in counts]
    missing = sum(1 for e in events if not e.get("AESEV"))
    if missing:
        parts.append(f"{missing} with no severity recorded")
    return ", ".join(parts)


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------
def ask_a_question(summary: pd.DataFrame) -> None:
    st.markdown(
        "Ask about the adverse events in plain English. A question can combine "
        "conditions, such as a severity, a type of event and a treatment arm. It is "
        "turned into a search on the AE variables, shown below so you can check how "
        "it was understood, and the matching subjects are listed."
    )
    with st.form("ask_form"):
        question = st.text_input("Your question", placeholder=EXAMPLE_QUESTIONS[0])
        submitted = st.form_submit_button("Ask")
    st.caption("For example: " + " / ".join(f"\"{q}\"" for q in EXAMPLE_QUESTIONS))

    if submitted and question.strip():
        # Kept between reruns, so the answer stays when you use the other tabs
        st.session_state["last_answer"] = ask(question.strip())
    answer = st.session_state.get("last_answer")
    if not answer:
        return
    if "error" in answer:
        st.warning(answer["error"])
        return

    st.success(f"Searched for adverse events where {describe_filters(answer['filters'])}")
    first, second = st.columns(2)
    first.metric("Subjects", answer["n_subjects"])
    second.metric("Matching adverse events", answer["n_records"])

    if answer["n_subjects"] == 0:
        st.info("No subjects match. Try different wording, or check the search above.")
    else:
        members = summary[summary["subject_id"].isin(answer["subjects"])]
        st.dataframe(
            subject_table(members),
            hide_index=True,
            column_config=subject_columns(summary["risk_score"].max()),
        )
        st.download_button(
            "Download these subjects (CSV)",
            data=members.to_csv(index=False),
            file_name="ae_question_subjects.csv",
            mime="text/csv",
        )

    model = (
        "OpenAI (via LangChain)" if answer["backend"] == "ChatOpenAI"
        else "the offline stand-in model (start the API with OPENAI_API_KEY set to use OpenAI)"
    )
    st.caption(f"Question: \"{answer['question']}\". Answered by {model}.")


def cohort_finder(options: dict, summary: pd.DataFrame) -> None:
    st.markdown(
        "Find the subjects who had adverse events of a given severity, in a given "
        "treatment arm. Leave a filter empty to include everything."
    )
    left, right = st.columns(2)
    severities = left.multiselect(
        "Severity", options["severities"], format_func=str.title, placeholder="All severities"
    )
    arm_choice = right.selectbox("Treatment arm", [ALL_ARMS] + options["treatment_arms"])
    treatment_arm = None if arm_choice == ALL_ARMS else arm_choice

    cohort = find_cohort(tuple(severities), treatment_arm)
    first, second = st.columns(2)
    first.metric("Subjects", cohort["n_subjects"])
    second.metric("Matching adverse events", cohort["count"])

    if cohort["n_subjects"] == 0:
        st.info("No subjects match these filters. Try another severity or treatment arm.")
        return

    members = summary[summary["subject_id"].isin(cohort["subjects"])]
    st.dataframe(
        subject_table(members),
        hide_index=True,
        column_config=subject_columns(summary["risk_score"].max()),
    )
    st.caption(
        "Risk scores count all of each subject's adverse events, not only the ones "
        "matching the filters."
    )
    st.download_button(
        "Download this cohort (CSV)",
        data=members.to_csv(index=False),
        file_name="ae_cohort.csv",
        mime="text/csv",
    )


def risk_overview(summary: pd.DataFrame) -> None:
    st.markdown(
        "Every subject with at least one adverse event, scored over all of their events. "
        "Start with the high-risk subjects."
    )
    counts = summary["risk_category"].value_counts()
    for column, category in zip(st.columns(3), reversed(RISK_ORDER)):
        column.metric(f"{risk_label(category)} risk", int(counts.get(category, 0)))

    st.altair_chart(risk_by_arm_chart(summary))
    st.caption(
        "Subjects with no adverse events are not in the AE data, so they are not shown "
        "(they would score 0, Low)."
    )

    shown = st.multiselect(
        "Show subjects with risk",
        list(reversed(RISK_ORDER)),
        default=list(reversed(RISK_ORDER)),
        format_func=risk_label,
    )
    st.dataframe(
        subject_table(summary[summary["risk_category"].isin(shown)]),
        hide_index=True,
        column_config=subject_columns(summary["risk_score"].max()),
    )


def subject_profile(options: dict, summary: pd.DataFrame) -> None:
    st.markdown(
        "Look up one subject's risk score and full adverse event history. "
        "Subjects are listed from highest risk."
    )
    lookup = summary.set_index("subject_id")
    subject_id = st.selectbox(
        "Subject",
        summary["subject_id"].tolist(),
        format_func=lambda s: (
            f"{s} ({lookup.at[s, 'risk_category']} risk, score {lookup.at[s, 'risk_score']})"
        ),
    )

    risk, events = get_subject(subject_id)
    if risk is None or events is None:
        st.warning(f"Subject {subject_id} is no longer in the data. Select Reload data.")
        return

    first, second, third, fourth = st.columns(4)
    first.metric("Risk category", risk_label(risk["risk_category"]))
    second.metric("Risk score", risk["risk_score"])
    third.metric("Adverse events", events["n_events"])
    fourth.metric("Treatment arm", events["treatment_arm"] or "Not recorded")
    st.caption(f"Severity of their events: {severity_breakdown(events['events'], options['severities'])}.")

    table = pd.DataFrame(events["events"]).rename(columns=EVENT_LABELS)
    st.dataframe(table, hide_index=True)


def sidebar() -> bool:
    """Connection status and how the score works. Returns True if the API is up."""
    with st.sidebar:
        st.header("AE Safety Explorer")
        st.caption("Adverse events from the CDISC pilot study, served by the Clinical Trial Data API.")

        running = api_is_running()
        if running:
            st.success(f"Connected to the API at {API_URL}")
        else:
            st.error(f"Can't reach the API at {API_URL}")

        # Explanation only: the scoring itself is done by the API.
        st.subheader("How risk is scored")
        st.markdown(
            "Each adverse event adds points by severity: mild 1, moderate 3, severe 5.\n\n"
            f"- {risk_label('Low')}: under 5 points\n"
            f"- {risk_label('Medium')}: 5 to 14 points\n"
            f"- {risk_label('High')}: 15 points or more"
        )

        if st.button("Reload data"):
            st.cache_data.clear()
            st.rerun()
    return running


def show_start_instructions(message: str) -> None:
    st.error(message)
    st.markdown("Start the API in a second terminal, from the `extensions/investigator_app` folder:")
    st.code("uvicorn api:app --reload", language="bash")
    st.markdown("Then select **Reload data** in the sidebar.")


def main() -> None:
    st.set_page_config(page_title="AE Safety Explorer", page_icon="🩺", layout="wide")
    running = sidebar()

    st.title("AE Safety Explorer")
    st.markdown("Who had which adverse events, and which subjects need attention first.")

    if not running:
        show_start_instructions("The app can't reach the Clinical Trial Data API, so there is no data to show.")
        return

    try:
        options = get_options()
        if options is None:  # the plain Question 5 API has no /options endpoint
            show_start_instructions(
                "The API is running, but it is the Question 5 version without the app's "
                "extra endpoints. Stop it and start the extended API instead."
            )
            return
        summary = get_risk_summary()
        if summary.empty:
            st.info("The API returned no adverse event data.")
            return

        ask_tab, cohort_tab, risk_tab, subject_tab = st.tabs(
            ["Ask a question", "Cohort finder", "Risk overview", "Subject profile"]
        )
        with ask_tab:
            ask_a_question(summary)
        with cohort_tab:
            cohort_finder(options, summary)
        with risk_tab:
            risk_overview(summary)
        with subject_tab:
            subject_profile(options, summary)
    except ApiUnavailable:
        show_start_instructions("The connection to the API was lost.")
    except requests.HTTPError as err:
        st.error(f"The API returned an error: {err}. Check the terminal running the API for details.")

    st.caption("Data: CDISC pilot study (pharmaverseadam), for demonstration only.")


main()
