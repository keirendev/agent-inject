"""
Bedrock Agent client for programmatic invocation and trace parsing.

Extracted and generalized from src/frontend/app.py for use in the
automated test harness. Supports single-turn and multi-turn conversations.
"""

import json
import os
import subprocess
import time
import uuid
from dataclasses import dataclass, field


@dataclass
class InvocationResult:
    """Result of a single agent invocation."""

    response_text: str
    trace_events: list[dict]
    parsed_steps: list[dict]
    session_id: str
    duration_ms: int


def invoke_agent(
    client,
    agent_id: str,
    agent_alias_id: str,
    session_id: str,
    message: str,
) -> InvocationResult:
    """Invoke a Bedrock Agent and return a structured result.

    Adapted from src/frontend/app.py invoke_agent(), but decoupled from
    Streamlit and returning an InvocationResult instead of a tuple.
    """
    start = time.monotonic()

    response = client.invoke_agent(
        agentId=agent_id,
        agentAliasId=agent_alias_id,
        sessionId=session_id,
        inputText=message,
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

    duration_ms = int((time.monotonic() - start) * 1000)
    parsed_steps = parse_trace(trace_events)

    return InvocationResult(
        response_text=response_text,
        trace_events=trace_events,
        parsed_steps=parsed_steps,
        session_id=session_id,
        duration_ms=duration_ms,
    )


def parse_trace(trace_events: list[dict]) -> list[dict]:
    """Parse trace events into a structured list of steps.

    Extracted from src/frontend/app.py format_trace() (lines 80-164).
    Produces step dicts with types: Model Input, Reasoning, Tool Call,
    KB Lookup, Tool Response, KB Results, Final Response, Guardrail.
    """
    steps = []

    for trace_event in trace_events:
        trace = trace_event.get("trace", {})

        orch = trace.get("orchestrationTrace", {})
        if orch:
            if "modelInvocationInput" in orch:
                mii = orch["modelInvocationInput"]
                text = mii.get("text", "")
                steps.append({
                    "type": "Model Input",
                    "text": text[:500] + "..." if len(text) > 500 else text,
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
                        location = (
                            ref.get("location", {})
                            .get("s3Location", {})
                            .get("uri", "")
                        )
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


class AgentSession:
    """Manages a multi-turn conversation with a Bedrock Agent.

    Maintains a persistent session_id across turns, which is critical
    for chained attacks and context-poisoning scenarios.
    """

    def __init__(
        self,
        client,
        agent_id: str,
        agent_alias_id: str,
        session_id: str | None = None,
    ):
        self.client = client
        self.agent_id = agent_id
        self.agent_alias_id = agent_alias_id
        self.session_id = session_id or str(uuid.uuid4())
        self.history: list[InvocationResult] = []

    def send(self, message: str) -> InvocationResult:
        """Send a message and return the result, preserving session context."""
        result = invoke_agent(
            client=self.client,
            agent_id=self.agent_id,
            agent_alias_id=self.agent_alias_id,
            session_id=self.session_id,
            message=message,
        )
        self.history.append(result)
        return result


def get_agent_config(tf_dir: str | None = None) -> dict:
    """Resolve agent_id and agent_alias_id from terraform output or env vars.

    Tries terraform output first (if tf_dir provided), falls back to
    AGENT_ID / AGENT_ALIAS_ID environment variables.
    """
    agent_id = os.environ.get("AGENT_ID", "")
    agent_alias_id = os.environ.get("AGENT_ALIAS_ID", "")
    region = os.environ.get("AWS_REGION", "ap-southeast-2")

    if tf_dir and not (agent_id and agent_alias_id):
        try:
            agent_id = subprocess.check_output(
                ["terraform", "output", "-raw", "agent_id"],
                cwd=tf_dir,
                stderr=subprocess.DEVNULL,
            ).decode().strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass

        try:
            agent_alias_id = subprocess.check_output(
                ["terraform", "output", "-raw", "agent_alias_id"],
                cwd=tf_dir,
                stderr=subprocess.DEVNULL,
            ).decode().strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass

    if not agent_id or not agent_alias_id:
        raise RuntimeError(
            "Could not resolve agent config. Set AGENT_ID and AGENT_ALIAS_ID "
            "environment variables, or run from a directory with terraform state."
        )

    return {
        "agent_id": agent_id,
        "agent_alias_id": agent_alias_id,
        "region": region,
    }
