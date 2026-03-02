"""
pytest integration for the NovaCrest test harness.

Allows running attack tests via pytest:
  pytest tests/ --scenario=secure-baseline -v
  pytest tests/ --scenario=scenario-rag-poisoning -v
"""

import os
import sys

import boto3
import pytest
import yaml

# Ensure local imports work
TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
if TESTS_DIR not in sys.path:
    sys.path.insert(0, TESTS_DIR)

from assertions import run_assertion
from bedrock_client import AgentSession, get_agent_config


# ---------------------------------------------------------------------------
# pytest CLI options
# ---------------------------------------------------------------------------

def pytest_addoption(parser):
    parser.addoption(
        "--scenario",
        action="store",
        default=None,
        help="Scenario name to test (matches YAML filename prefix)",
    )
    parser.addoption(
        "--agent-id",
        action="store",
        default=None,
        help="Override Bedrock Agent ID",
    )
    parser.addoption(
        "--agent-alias-id",
        action="store",
        default=None,
        help="Override Bedrock Agent Alias ID",
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def agent_config(request):
    """Resolve agent configuration from CLI args, env vars, or terraform."""
    agent_id = request.config.getoption("--agent-id")
    alias_id = request.config.getoption("--agent-alias-id")

    if agent_id and alias_id:
        return {
            "agent_id": agent_id,
            "agent_alias_id": alias_id,
            "region": os.environ.get("AWS_REGION", "ap-southeast-2"),
        }

    repo_root = os.path.dirname(TESTS_DIR)
    tf_dir = os.path.join(repo_root, "terraform")
    return get_agent_config(tf_dir if os.path.isdir(tf_dir) else None)


@pytest.fixture(scope="session")
def bedrock_client(agent_config):
    """Create a shared Bedrock Agent Runtime client."""
    return boto3.client(
        "bedrock-agent-runtime",
        region_name=agent_config["region"],
    )


@pytest.fixture
def agent_session(bedrock_client, agent_config):
    """Create a fresh AgentSession for each test."""
    return AgentSession(
        client=bedrock_client,
        agent_id=agent_config["agent_id"],
        agent_alias_id=agent_config["agent_alias_id"],
    )


# ---------------------------------------------------------------------------
# Test parametrization from YAML definitions
# ---------------------------------------------------------------------------

def _load_scenario_tests(scenario_filter):
    """Load test cases from YAML definitions for parametrization."""
    definitions_dir = os.path.join(TESTS_DIR, "definitions")
    test_cases = []

    for fname in sorted(os.listdir(definitions_dir)):
        if not fname.endswith((".yaml", ".yml")):
            continue
        if scenario_filter and not fname.startswith(scenario_filter):
            continue

        path = os.path.join(definitions_dir, fname)
        with open(path) as f:
            data = yaml.safe_load(f)

        scenario_name = data.get("scenario", {}).get("name", fname)
        for test in data.get("tests", []):
            test_cases.append(
                pytest.param(
                    test,
                    id=f"{scenario_name}::{test['id']}",
                )
            )

    return test_cases


def pytest_generate_tests(metafunc):
    """Parametrize tests from YAML definitions."""
    if "test_definition" in metafunc.fixturenames:
        scenario = metafunc.config.getoption("--scenario")
        cases = _load_scenario_tests(scenario)
        if cases:
            metafunc.parametrize("test_definition", cases)
        else:
            pytest.skip("No test definitions found")


# ---------------------------------------------------------------------------
# Generic parametrized test function
# ---------------------------------------------------------------------------

def test_scenario(test_definition, agent_session):
    """Execute a single test case from a YAML definition."""
    from bedrock_client import InvocationResult

    all_parsed_steps = []
    all_trace_events = []

    for turn in test_definition["turns"]:
        result = agent_session.send(turn["input"])
        all_parsed_steps.extend(result.parsed_steps)
        all_trace_events.extend(result.trace_events)

    last_result = agent_session.history[-1]
    combined_result = InvocationResult(
        response_text=last_result.response_text,
        trace_events=all_trace_events,
        parsed_steps=all_parsed_steps,
        session_id=agent_session.session_id,
        duration_ms=sum(r.duration_ms for r in agent_session.history),
    )

    failures = []
    for acfg in test_definition.get("assertions", []):
        if acfg["type"] in ("response_contains", "response_not_contains", "response_matches_pattern"):
            ar = run_assertion(last_result, acfg)
        else:
            ar = run_assertion(combined_result, acfg)

        if not ar["passed"]:
            failures.append(f"{ar['assertion']}: {ar['evidence']}")

    if failures:
        pytest.fail(
            f"Test {test_definition['id']} failed:\n" + "\n".join(f"  - {f}" for f in failures)
        )
