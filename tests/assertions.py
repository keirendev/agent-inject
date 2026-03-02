"""
Assertion functions for validating attack outcomes.

Each function inspects an InvocationResult and returns a structured dict:
  {
    "passed": bool,
    "assertion": str,   # human-readable assertion description
    "evidence": str,    # what was actually found
    "details": dict,    # extra context for reports
  }
"""

import re

from bedrock_client import InvocationResult


def response_contains(result: InvocationResult, substring: str) -> dict:
    """Check that the response text contains a substring (case-insensitive)."""
    found = substring.lower() in result.response_text.lower()
    return {
        "passed": found,
        "assertion": f"Response contains '{substring}'",
        "evidence": (
            _excerpt(result.response_text, substring) if found
            else f"Substring not found in response ({len(result.response_text)} chars)"
        ),
        "details": {"substring": substring, "response_length": len(result.response_text)},
    }


def response_not_contains(result: InvocationResult, substring: str) -> dict:
    """Check that the response text does NOT contain a substring (case-insensitive)."""
    found = substring.lower() in result.response_text.lower()
    return {
        "passed": not found,
        "assertion": f"Response does not contain '{substring}'",
        "evidence": (
            f"Substring found: {_excerpt(result.response_text, substring)}" if found
            else "Substring absent from response"
        ),
        "details": {"substring": substring},
    }


def tool_called(
    result: InvocationResult,
    tool_name: str,
    params: dict | None = None,
) -> dict:
    """Check that a specific tool was called in the trace, optionally with given params."""
    matching_calls = [
        s for s in result.parsed_steps
        if s.get("type") == "Tool Call" and s.get("tool") == tool_name
    ]

    if not matching_calls:
        return {
            "passed": False,
            "assertion": f"Tool '{tool_name}' was called",
            "evidence": f"Tool not found in trace. Tools called: {_tool_list(result)}",
            "details": {"tool_name": tool_name, "expected_params": params},
        }

    if params:
        for call in matching_calls:
            call_params = call.get("parameters", {})
            if all(call_params.get(k) == str(v) for k, v in params.items()):
                return {
                    "passed": True,
                    "assertion": f"Tool '{tool_name}' called with {params}",
                    "evidence": f"Matched call with params: {call_params}",
                    "details": {"tool_name": tool_name, "actual_params": call_params},
                }
        return {
            "passed": False,
            "assertion": f"Tool '{tool_name}' called with {params}",
            "evidence": f"Tool called but params didn't match. Actual calls: {[c.get('parameters') for c in matching_calls]}",
            "details": {"tool_name": tool_name, "expected_params": params, "actual_calls": matching_calls},
        }

    return {
        "passed": True,
        "assertion": f"Tool '{tool_name}' was called",
        "evidence": f"Found {len(matching_calls)} call(s) with params: {matching_calls[0].get('parameters', {})}",
        "details": {"tool_name": tool_name, "call_count": len(matching_calls)},
    }


def tool_not_called(result: InvocationResult, tool_name: str) -> dict:
    """Verify that a specific tool was NOT invoked."""
    matching_calls = [
        s for s in result.parsed_steps
        if s.get("type") == "Tool Call" and s.get("tool") == tool_name
    ]
    return {
        "passed": len(matching_calls) == 0,
        "assertion": f"Tool '{tool_name}' was not called",
        "evidence": (
            f"Tool was called {len(matching_calls)} time(s)" if matching_calls
            else "Tool absent from trace"
        ),
        "details": {"tool_name": tool_name, "calls": matching_calls},
    }


def guardrail_blocked(result: InvocationResult) -> dict:
    """Check that a guardrail BLOCKED the request."""
    guardrail_steps = [
        s for s in result.parsed_steps
        if s.get("type") == "Guardrail" and s.get("action") == "BLOCKED"
    ]
    return {
        "passed": len(guardrail_steps) > 0,
        "assertion": "Guardrail blocked the request",
        "evidence": (
            f"Found {len(guardrail_steps)} BLOCKED action(s)" if guardrail_steps
            else "No guardrail BLOCKED actions in trace"
        ),
        "details": {"guardrail_steps": guardrail_steps},
    }


def guardrail_not_blocked(result: InvocationResult) -> dict:
    """Check that no guardrail BLOCKED the request (for attack scenarios)."""
    guardrail_steps = [
        s for s in result.parsed_steps
        if s.get("type") == "Guardrail" and s.get("action") == "BLOCKED"
    ]
    return {
        "passed": len(guardrail_steps) == 0,
        "assertion": "Guardrail did not block the request",
        "evidence": (
            f"Guardrail BLOCKED {len(guardrail_steps)} time(s)" if guardrail_steps
            else "No guardrail blocks in trace"
        ),
        "details": {"guardrail_steps": guardrail_steps},
    }


def kb_retrieved(result: InvocationResult, source_contains: str | None = None) -> dict:
    """Check that KB Results appear in the trace, optionally matching a source URI."""
    kb_steps = [s for s in result.parsed_steps if s.get("type") == "KB Results"]

    if not kb_steps:
        return {
            "passed": False,
            "assertion": "Knowledge base results were retrieved",
            "evidence": "No KB Results steps in trace",
            "details": {},
        }

    if source_contains:
        all_sources = []
        for step in kb_steps:
            for ref in step.get("references", []):
                all_sources.append(ref.get("source", ""))
        matching = [s for s in all_sources if source_contains.lower() in s.lower()]
        return {
            "passed": len(matching) > 0,
            "assertion": f"KB retrieved source containing '{source_contains}'",
            "evidence": (
                f"Matched sources: {matching}" if matching
                else f"No match. Sources found: {all_sources}"
            ),
            "details": {"source_contains": source_contains, "all_sources": all_sources},
        }

    total_refs = sum(len(s.get("references", [])) for s in kb_steps)
    return {
        "passed": True,
        "assertion": "Knowledge base results were retrieved",
        "evidence": f"Found {total_refs} reference(s) across {len(kb_steps)} KB result step(s)",
        "details": {"kb_step_count": len(kb_steps), "total_refs": total_refs},
    }


def response_matches_pattern(result: InvocationResult, regex: str) -> dict:
    """Check that the response text matches a regex pattern."""
    match = re.search(regex, result.response_text, re.IGNORECASE | re.DOTALL)
    return {
        "passed": match is not None,
        "assertion": f"Response matches pattern '{regex}'",
        "evidence": (
            f"Matched: '{match.group(0)[:200]}'" if match
            else "No match found in response"
        ),
        "details": {"pattern": regex},
    }


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _excerpt(text: str, substring: str, context: int = 80) -> str:
    """Return an excerpt of text around the first occurrence of substring."""
    idx = text.lower().find(substring.lower())
    if idx == -1:
        return text[:200]
    start = max(0, idx - context)
    end = min(len(text), idx + len(substring) + context)
    excerpt = text[start:end]
    if start > 0:
        excerpt = "..." + excerpt
    if end < len(text):
        excerpt = excerpt + "..."
    return excerpt


def _tool_list(result: InvocationResult) -> list[str]:
    """Return list of tool names called in the trace."""
    return [
        s.get("tool", "unknown")
        for s in result.parsed_steps
        if s.get("type") == "Tool Call"
    ]


# ---------------------------------------------------------------------------
# Assertion dispatcher — maps YAML type strings to functions
# ---------------------------------------------------------------------------

ASSERTION_REGISTRY = {
    "response_contains": lambda result, cfg: response_contains(result, cfg["value"]),
    "response_not_contains": lambda result, cfg: response_not_contains(result, cfg["value"]),
    "tool_called": lambda result, cfg: tool_called(result, cfg["tool"], cfg.get("params")),
    "tool_not_called": lambda result, cfg: tool_not_called(result, cfg["tool"]),
    "guardrail_blocked": lambda result, _cfg: guardrail_blocked(result),
    "guardrail_not_blocked": lambda result, _cfg: guardrail_not_blocked(result),
    "kb_retrieved": lambda result, cfg: kb_retrieved(result, cfg.get("source_contains")),
    "response_matches_pattern": lambda result, cfg: response_matches_pattern(result, cfg["pattern"]),
}


def run_assertion(result: InvocationResult, assertion_cfg: dict) -> dict:
    """Dispatch a single assertion from a YAML config dict."""
    atype = assertion_cfg["type"]
    if atype not in ASSERTION_REGISTRY:
        return {
            "passed": False,
            "assertion": f"Unknown assertion type: {atype}",
            "evidence": f"Valid types: {list(ASSERTION_REGISTRY.keys())}",
            "details": assertion_cfg,
        }
    return ASSERTION_REGISTRY[atype](result, assertion_cfg)
