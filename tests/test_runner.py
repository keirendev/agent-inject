#!/usr/bin/env python3
"""
CLI test runner for the NovaCrest AI Security Lab.

Sends attack payloads to the deployed Bedrock Agent, captures traces,
validates outcomes against assertions, and generates markdown reports.

Usage:
  python tests/test_runner.py --scenario scenario-rag-poisoning
  python tests/test_runner.py --all
  python tests/test_runner.py --test-id test-001
  python tests/test_runner.py --dry-run --all
  python tests/test_runner.py --verbose --scenario secure-baseline
"""

import argparse
import os
import sys
import time

import yaml

# Ensure the tests/ directory is on the path for local imports
TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
if TESTS_DIR not in sys.path:
    sys.path.insert(0, TESTS_DIR)

import boto3

from assertions import run_assertion
from bedrock_client import AgentSession, get_agent_config
from report import generate_report

DEFINITIONS_DIR = os.path.join(TESTS_DIR, "definitions")


# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------

def _supports_color():
    return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()

if _supports_color():
    GREEN = "\033[0;32m"
    RED = "\033[0;31m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    BOLD = "\033[1m"
    NC = "\033[0m"
else:
    GREEN = RED = YELLOW = BLUE = BOLD = NC = ""


def info(msg):
    print(f"{BLUE}[INFO]{NC} {msg}")


def success(msg):
    print(f"{GREEN}[PASS]{NC} {msg}")


def fail(msg):
    print(f"{RED}[FAIL]{NC} {msg}")


def warn(msg):
    print(f"{YELLOW}[WARN]{NC} {msg}")


# ---------------------------------------------------------------------------
# YAML loading
# ---------------------------------------------------------------------------

def load_definition(path: str) -> dict:
    """Load and validate a YAML test definition."""
    with open(path) as f:
        data = yaml.safe_load(f)

    # Basic validation
    if "scenario" not in data:
        raise ValueError(f"Missing 'scenario' key in {path}")
    if "tests" not in data:
        raise ValueError(f"Missing 'tests' key in {path}")
    for test in data["tests"]:
        if "id" not in test:
            raise ValueError(f"Test missing 'id' in {path}")
        if "turns" not in test or not test["turns"]:
            raise ValueError(f"Test {test['id']} has no 'turns' in {path}")
    return data


def find_definitions(scenario: str | None = None) -> list[str]:
    """Find YAML definition files, optionally filtered by scenario name."""
    paths = []
    for fname in sorted(os.listdir(DEFINITIONS_DIR)):
        if not fname.endswith((".yaml", ".yml")):
            continue
        if scenario and not fname.startswith(scenario):
            continue
        paths.append(os.path.join(DEFINITIONS_DIR, fname))
    return paths


# ---------------------------------------------------------------------------
# Test execution
# ---------------------------------------------------------------------------

def execute_test(
    test_def: dict,
    client,
    agent_id: str,
    agent_alias_id: str,
    verbose: bool = False,
) -> dict:
    """Execute a single test case and return a result dict."""
    test_id = test_def["id"]
    test_name = test_def.get("name", test_id)

    session = AgentSession(client, agent_id, agent_alias_id)
    turns_data = []
    all_parsed_steps = []
    all_trace_events = []
    total_duration = 0

    for i, turn in enumerate(test_def["turns"]):
        user_input = turn["input"]
        if verbose:
            info(f"  Turn {i + 1}: {user_input[:80]}{'...' if len(user_input) > 80 else ''}")

        result = session.send(user_input)
        total_duration += result.duration_ms
        all_parsed_steps.extend(result.parsed_steps)
        all_trace_events.extend(result.trace_events)

        turns_data.append({
            "input": user_input,
            "response_text": result.response_text,
            "duration_ms": result.duration_ms,
        })

        if verbose:
            info(f"    Response ({result.duration_ms}ms): {result.response_text[:120]}{'...' if len(result.response_text) > 120 else ''}")

        # Per-turn assertions
        if "assertions" in turn:
            for acfg in turn["assertions"]:
                run_assertion(result, acfg)

    # Run test-level assertions against the last turn's result
    last_result = session.history[-1] if session.history else None
    assertion_results = []

    # For test-level assertions, build a combined result with all steps
    if last_result:
        from bedrock_client import InvocationResult
        combined_result = InvocationResult(
            response_text=last_result.response_text,
            trace_events=all_trace_events,
            parsed_steps=all_parsed_steps,
            session_id=session.session_id,
            duration_ms=total_duration,
        )

        for acfg in test_def.get("assertions", []):
            # Use combined result for tool_called/kb_retrieved (span all turns)
            # Use last result for response_contains (only final response matters)
            if acfg["type"] in ("response_contains", "response_not_contains", "response_matches_pattern"):
                ar = run_assertion(last_result, acfg)
            else:
                ar = run_assertion(combined_result, acfg)
            assertion_results.append(ar)

    all_passed = all(a["passed"] for a in assertion_results) if assertion_results else True

    return {
        "id": test_id,
        "name": test_name,
        "description": test_def.get("description", ""),
        "passed": all_passed,
        "duration_ms": total_duration,
        "turns": turns_data,
        "assertions": assertion_results,
        "parsed_steps": all_parsed_steps,
        "trace_events": all_trace_events,
    }


def run_scenario(
    definition_path: str,
    client,
    agent_id: str,
    agent_alias_id: str,
    test_id_filter: str | None = None,
    verbose: bool = False,
    dry_run: bool = False,
) -> list[dict]:
    """Run all tests in a scenario definition and return results."""
    data = load_definition(definition_path)
    scenario = data["scenario"]
    scenario_name = scenario.get("name", "Unknown")

    info(f"Scenario: {BOLD}{scenario_name}{NC}")
    if scenario.get("setup_notes"):
        warn(f"Setup: {scenario['setup_notes']}")

    tests = data["tests"]
    if test_id_filter:
        tests = [t for t in tests if t["id"] == test_id_filter]
        if not tests:
            warn(f"No test with id '{test_id_filter}' found in {definition_path}")
            return []

    if dry_run:
        for t in tests:
            turns = len(t.get("turns", []))
            assertions = len(t.get("assertions", []))
            info(f"  [DRY RUN] {t['id']}: {t.get('name', '')} ({turns} turns, {assertions} assertions)")
        return []

    results = []
    for t in tests:
        test_start = time.monotonic()
        info(f"  Running: {t['id']} — {t.get('name', '')}")

        try:
            result = execute_test(t, client, agent_id, agent_alias_id, verbose)
            results.append(result)

            if result["passed"]:
                success(f"  {t['id']}: All assertions passed ({result['duration_ms']}ms)")
            else:
                failed_assertions = [a for a in result["assertions"] if not a["passed"]]
                fail(f"  {t['id']}: {len(failed_assertions)} assertion(s) failed ({result['duration_ms']}ms)")
                for a in failed_assertions:
                    fail(f"    - {a['assertion']}: {a['evidence']}")

        except Exception as e:
            fail(f"  {t['id']}: Error — {e}")
            results.append({
                "id": t["id"],
                "name": t.get("name", t["id"]),
                "description": t.get("description", ""),
                "passed": False,
                "duration_ms": int((time.monotonic() - test_start) * 1000),
                "turns": [],
                "assertions": [{
                    "passed": False,
                    "assertion": "Test execution",
                    "evidence": str(e),
                    "details": {},
                }],
                "parsed_steps": [],
                "trace_events": [],
            })

    return results


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="NovaCrest AI Security Lab — Test Runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --scenario secure-baseline
  %(prog)s --scenario scenario-rag-poisoning --verbose
  %(prog)s --all --dry-run
  %(prog)s --test-id test-001 --scenario secure-baseline
  %(prog)s --agent-id ABCDE12345 --agent-alias-id FGHIJ67890 --all
        """,
    )
    parser.add_argument(
        "--scenario", "-s",
        help="Run tests for a specific scenario (matches filename prefix)",
    )
    parser.add_argument(
        "--all", "-a",
        action="store_true",
        help="Run all test definitions",
    )
    parser.add_argument(
        "--test-id", "-t",
        help="Run a single test by ID (requires --scenario)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate YAML definitions without invoking the agent",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Print conversation turns and traces to stdout",
    )
    parser.add_argument(
        "--agent-id",
        help="Override agent ID (default: from terraform output or AGENT_ID env var)",
    )
    parser.add_argument(
        "--agent-alias-id",
        help="Override agent alias ID (default: from terraform output or AGENT_ALIAS_ID env var)",
    )
    parser.add_argument(
        "--region",
        default=None,
        help="AWS region (default: from AWS_REGION env var or ap-southeast-2)",
    )

    args = parser.parse_args()

    if not args.scenario and not args.all:
        parser.error("Specify --scenario <name> or --all")

    if args.test_id and not args.scenario:
        parser.error("--test-id requires --scenario")

    # Resolve agent config
    if args.agent_id and args.agent_alias_id:
        config = {
            "agent_id": args.agent_id,
            "agent_alias_id": args.agent_alias_id,
            "region": args.region or os.environ.get("AWS_REGION", "ap-southeast-2"),
        }
    elif args.dry_run:
        config = {"agent_id": "dry-run", "agent_alias_id": "dry-run", "region": "us-east-1"}
    else:
        repo_root = os.path.dirname(TESTS_DIR)
        tf_dir = os.path.join(repo_root, "terraform")
        config = get_agent_config(tf_dir if os.path.isdir(tf_dir) else None)

    if not args.dry_run:
        region = args.region or config["region"]
        client = boto3.client("bedrock-agent-runtime", region_name=region)
    else:
        client = None

    # Find definitions
    if args.all:
        definition_paths = find_definitions()
    else:
        definition_paths = find_definitions(args.scenario)

    if not definition_paths:
        warn(f"No test definitions found{' for ' + args.scenario if args.scenario else ''}")
        warn(f"Looked in: {DEFINITIONS_DIR}")
        sys.exit(1)

    info(f"Found {len(definition_paths)} definition(s)")
    print()

    # Run tests
    all_results = {}
    overall_passed = 0
    overall_failed = 0

    for defn_path in definition_paths:
        data = load_definition(defn_path)
        scenario_name = data["scenario"].get("tfvars", os.path.basename(defn_path).replace(".yaml", ""))

        results = run_scenario(
            defn_path,
            client,
            config["agent_id"],
            config["agent_alias_id"],
            test_id_filter=args.test_id,
            verbose=args.verbose,
            dry_run=args.dry_run,
        )

        if results:
            all_results[scenario_name] = results
            for r in results:
                if r["passed"]:
                    overall_passed += 1
                else:
                    overall_failed += 1

        print()

    # Generate reports
    if not args.dry_run and all_results:
        print()
        info("Generating reports...")
        for scenario_name, results in all_results.items():
            report_path = generate_report(scenario_name, results)
            info(f"  Report: {report_path}")

    # Summary
    print()
    total = overall_passed + overall_failed
    if args.dry_run:
        info("Dry run complete — all definitions validated successfully")
    elif total > 0:
        if overall_failed == 0:
            success(f"All {total} test(s) passed")
        else:
            fail(f"{overall_failed}/{total} test(s) failed")
    else:
        warn("No tests were executed")

    sys.exit(1 if overall_failed > 0 else 0)


if __name__ == "__main__":
    main()
