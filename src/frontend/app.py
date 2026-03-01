"""
NovaCrest AI Security Lab — Frontend Chat Application

Streamlit chat UI for interacting with the NovaCrest Support Agent.
Displays agent responses and a debug trace panel showing reasoning steps,
tool calls, and knowledge base retrievals.
"""

import json
import os
import uuid

import boto3
import streamlit as st

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

AWS_REGION = os.environ.get("AWS_REGION", "ap-southeast-2")
AGENT_ID = os.environ.get("AGENT_ID", "")
AGENT_ALIAS_ID = os.environ.get("AGENT_ALIAS_ID", "")
FRONTEND_PASSWORD = os.environ.get("FRONTEND_PASSWORD", "novacrest-lab")

# ---------------------------------------------------------------------------
# Page config
# ---------------------------------------------------------------------------

st.set_page_config(
    page_title="NovaCrest Support Agent",
    page_icon="🛡️",
    layout="wide",
)

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

if "authenticated" not in st.session_state:
    st.session_state.authenticated = False

if not st.session_state.authenticated:
    st.title("NovaCrest AI Security Lab")
    st.markdown("Enter the lab access password to continue.")
    password = st.text_input("Password", type="password")
    if st.button("Login"):
        if password == FRONTEND_PASSWORD:
            st.session_state.authenticated = True
            st.rerun()
        else:
            st.error("Incorrect password.")
    st.stop()

# ---------------------------------------------------------------------------
# Session state initialization
# ---------------------------------------------------------------------------

if "session_id" not in st.session_state:
    st.session_state.session_id = str(uuid.uuid4())
if "messages" not in st.session_state:
    st.session_state.messages = []
if "traces" not in st.session_state:
    st.session_state.traces = []

# ---------------------------------------------------------------------------
# Bedrock client
# ---------------------------------------------------------------------------

@st.cache_resource
def get_bedrock_client():
    return boto3.client("bedrock-agent-runtime", region_name=AWS_REGION)


def invoke_agent(user_message: str) -> tuple[str, list[dict]]:
    """Invoke the Bedrock Agent and return (response_text, trace_events)."""
    client = get_bedrock_client()

    response = client.invoke_agent(
        agentId=AGENT_ID,
        agentAliasId=AGENT_ALIAS_ID,
        sessionId=st.session_state.session_id,
        inputText=user_message,
        enableTrace=True,
    )

    response_text = ""
    trace_events = []

    for event in response.get("completion", []):
        # Collect response chunks
        if "chunk" in event:
            chunk = event["chunk"]
            if "bytes" in chunk:
                response_text += chunk["bytes"].decode("utf-8")

        # Collect trace data
        if "trace" in event:
            trace_events.append(event["trace"])

    return response_text, trace_events


def format_trace(trace_events: list[dict]) -> list[dict]:
    """Parse trace events into a structured list of steps for display."""
    steps = []

    for trace_event in trace_events:
        trace = trace_event.get("trace", {})

        # Orchestration trace — the main reasoning loop
        orch = trace.get("orchestrationTrace", {})
        if orch:
            # Model invocation input (the prompt sent to the LLM)
            if "modelInvocationInput" in orch:
                mii = orch["modelInvocationInput"]
                steps.append({
                    "type": "Model Input",
                    "text": mii.get("text", "")[:500] + "..." if len(mii.get("text", "")) > 500 else mii.get("text", ""),
                    "traceId": mii.get("traceId", ""),
                })

            # Rationale — the agent's reasoning
            if "rationale" in orch:
                steps.append({
                    "type": "Reasoning",
                    "text": orch["rationale"].get("text", ""),
                    "traceId": orch["rationale"].get("traceId", ""),
                })

            # Invocation input — tool call about to be made
            if "invocationInput" in orch:
                inv = orch["invocationInput"]
                if "actionGroupInvocationInput" in inv:
                    ag = inv["actionGroupInvocationInput"]
                    params = {}
                    for p in ag.get("parameters", []):
                        params[p.get("name", "")] = p.get("value", "")
                    steps.append({
                        "type": "Tool Call",
                        "tool": ag.get("function", ag.get("apiPath", "unknown")),
                        "action_group": ag.get("actionGroupName", ""),
                        "parameters": params,
                        "traceId": inv.get("traceId", ""),
                    })
                if "knowledgeBaseLookupInput" in inv:
                    kb = inv["knowledgeBaseLookupInput"]
                    steps.append({
                        "type": "KB Lookup",
                        "query": kb.get("text", ""),
                        "knowledge_base_id": kb.get("knowledgeBaseId", ""),
                        "traceId": inv.get("traceId", ""),
                    })

            # Observation — result from tool call or KB retrieval
            if "observation" in orch:
                obs = orch["observation"]
                if "actionGroupInvocationOutput" in obs:
                    ag_out = obs["actionGroupInvocationOutput"]
                    steps.append({
                        "type": "Tool Response",
                        "text": ag_out.get("text", ""),
                        "traceId": obs.get("traceId", ""),
                    })
                if "knowledgeBaseLookupOutput" in obs:
                    kb_out = obs["knowledgeBaseLookupOutput"]
                    refs = []
                    for ref in kb_out.get("retrievedReferences", []):
                        content = ref.get("content", {}).get("text", "")
                        location = ref.get("location", {}).get("s3Location", {}).get("uri", "")
                        refs.append({"text": content[:300], "source": location})
                    steps.append({
                        "type": "KB Results",
                        "references": refs,
                        "traceId": obs.get("traceId", ""),
                    })
                if "finalResponse" in obs:
                    steps.append({
                        "type": "Final Response",
                        "text": obs["finalResponse"].get("text", ""),
                        "traceId": obs.get("traceId", ""),
                    })

        # Guardrail trace
        gt = trace.get("guardrailTrace", {})
        if gt:
            action = gt.get("action", "")
            steps.append({
                "type": "Guardrail",
                "action": action,
                "details": gt,
            })

    return steps


def render_trace(steps: list[dict]):
    """Render trace steps in the sidebar."""
    for i, step in enumerate(steps):
        step_type = step.get("type", "Unknown")

        if step_type == "Reasoning":
            st.markdown(f"**💭 Reasoning**")
            st.text(step.get("text", ""))

        elif step_type == "Tool Call":
            st.markdown(f"**🔧 Tool Call: `{step.get('tool', '')}`**")
            st.json(step.get("parameters", {}))

        elif step_type == "Tool Response":
            st.markdown(f"**📋 Tool Response**")
            try:
                st.json(json.loads(step.get("text", "{}")))
            except (json.JSONDecodeError, TypeError):
                st.text(step.get("text", ""))

        elif step_type == "KB Lookup":
            st.markdown(f"**📚 Knowledge Base Query**")
            st.text(step.get("query", ""))

        elif step_type == "KB Results":
            st.markdown(f"**📄 KB Results** ({len(step.get('references', []))} documents)")
            for ref in step.get("references", []):
                st.caption(ref.get("source", ""))
                st.text(ref.get("text", "")[:200])

        elif step_type == "Guardrail":
            action = step.get("action", "")
            icon = "🚫" if action == "BLOCKED" else "✅"
            st.markdown(f"**{icon} Guardrail: {action}**")

        elif step_type == "Model Input":
            with st.expander("Model Input (truncated)", expanded=False):
                st.text(step.get("text", ""))

        elif step_type == "Final Response":
            st.markdown(f"**✅ Final Response**")
            st.text(step.get("text", "")[:200])

        if i < len(steps) - 1:
            st.divider()


# ---------------------------------------------------------------------------
# Main UI
# ---------------------------------------------------------------------------

# Header
col1, col2 = st.columns([3, 1])
with col1:
    st.title("NovaCrest Support Agent")
with col2:
    if st.button("New Conversation"):
        st.session_state.session_id = str(uuid.uuid4())
        st.session_state.messages = []
        st.session_state.traces = []
        st.rerun()

# Check config
if not AGENT_ID or not AGENT_ALIAS_ID:
    st.error("AGENT_ID and AGENT_ALIAS_ID environment variables must be set.")
    st.stop()

# Layout: chat on left, trace on right
chat_col, trace_col = st.columns([2, 1])

with chat_col:
    # Display message history
    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

    # Chat input
    if prompt := st.chat_input("Ask NovaCrest Support..."):
        # Add user message
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        # Invoke agent
        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                try:
                    response_text, trace_events = invoke_agent(prompt)
                    st.markdown(response_text)

                    # Store for display
                    st.session_state.messages.append(
                        {"role": "assistant", "content": response_text}
                    )
                    parsed_trace = format_trace(trace_events)
                    st.session_state.traces.append({
                        "query": prompt,
                        "steps": parsed_trace,
                        "raw": trace_events,
                    })
                except Exception as e:
                    error_msg = f"Error invoking agent: {str(e)}"
                    st.error(error_msg)
                    st.session_state.messages.append(
                        {"role": "assistant", "content": error_msg}
                    )

with trace_col:
    st.subheader("Agent Trace")
    if st.session_state.traces:
        # Show most recent trace
        latest = st.session_state.traces[-1]
        st.caption(f"Query: {latest['query']}")
        render_trace(latest["steps"])

        # Raw JSON viewer
        with st.expander("Raw Trace JSON", expanded=False):
            st.json(latest["raw"])

        # Previous traces
        if len(st.session_state.traces) > 1:
            with st.expander(f"Previous Traces ({len(st.session_state.traces) - 1})", expanded=False):
                for i, t in enumerate(reversed(st.session_state.traces[:-1])):
                    st.caption(f"Query: {t['query']}")
                    render_trace(t["steps"])
                    st.divider()
    else:
        st.caption("Send a message to see the agent's reasoning trace here.")

# Footer
st.sidebar.markdown("---")
st.sidebar.caption(f"Session: `{st.session_state.session_id[:8]}...`")
st.sidebar.caption(f"Agent: `{AGENT_ID}`")
st.sidebar.caption(f"Region: `{AWS_REGION}`")
