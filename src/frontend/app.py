"""
NovaCrest AI Security Lab -- Frontend Chat Application

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

# ---------------------------------------------------------------------------
# Page config
# ---------------------------------------------------------------------------

st.set_page_config(
    page_title="NovaCrest Support Agent",
    page_icon="🛡️",
    layout="wide",
)

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
        if "chunk" in event:
            chunk = event["chunk"]
            if "bytes" in chunk:
                response_text += chunk["bytes"].decode("utf-8")
        if "trace" in event:
            trace_events.append(event["trace"])

    return response_text, trace_events


def format_trace(trace_events: list[dict]) -> list[dict]:
    """Parse trace events into a structured list of steps for display."""
    steps = []

    for trace_event in trace_events:
        trace = trace_event.get("trace", {})

        orch = trace.get("orchestrationTrace", {})
        if orch:
            if "modelInvocationInput" in orch:
                mii = orch["modelInvocationInput"]
                steps.append({
                    "type": "Model Input",
                    "text": mii.get("text", "")[:500] + "..." if len(mii.get("text", "")) > 500 else mii.get("text", ""),
                    "traceId": mii.get("traceId", ""),
                })

            if "rationale" in orch:
                steps.append({
                    "type": "Reasoning",
                    "text": orch["rationale"].get("text", ""),
                    "traceId": orch["rationale"].get("traceId", ""),
                })

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
            st.markdown("**Reasoning**")
            st.text(step.get("text", ""))

        elif step_type == "Tool Call":
            st.markdown(f"**Tool Call: `{step.get('tool', '')}`**")
            st.json(step.get("parameters", {}))

        elif step_type == "Tool Response":
            st.markdown("**Tool Response**")
            try:
                st.json(json.loads(step.get("text", "{}")))
            except (json.JSONDecodeError, TypeError):
                st.text(step.get("text", ""))

        elif step_type == "KB Lookup":
            st.markdown("**Knowledge Base Query**")
            st.text(step.get("query", ""))

        elif step_type == "KB Results":
            st.markdown(f"**KB Results** ({len(step.get('references', []))} documents)")
            for ref in step.get("references", []):
                st.caption(ref.get("source", ""))
                st.text(ref.get("text", "")[:200])

        elif step_type == "Guardrail":
            action = step.get("action", "")
            if action == "BLOCKED":
                label = "BLOCKED"
            elif action == "NONE":
                label = "PASSED (no intervention)"
            else:
                label = action
            st.markdown(f"**Guardrail: {label}**")

        elif step_type == "Model Input":
            with st.expander("Model Input (truncated)", expanded=False):
                st.text(step.get("text", ""))

        elif step_type == "Final Response":
            st.markdown("**Final Response**")
            st.text(step.get("text", "")[:200])

        if i < len(steps) - 1:
            st.divider()


# ---------------------------------------------------------------------------
# Sidebar -- trace panel and session info
# ---------------------------------------------------------------------------

with st.sidebar:
    st.subheader("Agent Trace")
    if st.session_state.traces:
        latest = st.session_state.traces[-1]
        st.caption(f"Query: {latest['query']}")
        render_trace(latest["steps"])
        with st.expander("Raw Trace JSON", expanded=False):
            st.json(latest["raw"])
        if len(st.session_state.traces) > 1:
            with st.expander(f"Previous Traces ({len(st.session_state.traces) - 1})", expanded=False):
                for i, t in enumerate(reversed(st.session_state.traces[:-1])):
                    st.caption(f"Query: {t['query']}")
                    render_trace(t["steps"])
                    st.divider()
    else:
        st.caption("Send a message to see the agent's reasoning trace here.")

    st.markdown("---")
    st.caption(f"Session: `{st.session_state.session_id[:8]}...`")
    st.caption(f"Agent: `{AGENT_ID}`")
    st.caption(f"Region: `{AWS_REGION}`")

    if st.button("New Conversation"):
        st.session_state.session_id = str(uuid.uuid4())
        st.session_state.messages = []
        st.session_state.traces = []
        st.rerun()

# ---------------------------------------------------------------------------
# Main UI -- chat area
# ---------------------------------------------------------------------------

st.title("NovaCrest Support Agent")

if not AGENT_ID or not AGENT_ALIAS_ID:
    st.error("AGENT_ID and AGENT_ALIAS_ID environment variables must be set.")
    st.stop()

# 1. Render all historical messages
for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])

# 2. Chat input at root level -- Streamlit pins this to the bottom via CSS
if prompt := st.chat_input("Ask NovaCrest Support..."):
    # Show user message immediately in this render cycle
    with st.chat_message("user"):
        st.markdown(prompt)
    st.session_state.messages.append({"role": "user", "content": prompt})

    # Show assistant response in this render cycle
    with st.chat_message("assistant"):
        with st.spinner("Thinking..."):
            try:
                response_text, trace_events = invoke_agent(prompt)
                st.markdown(response_text)

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
