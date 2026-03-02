"""
Markdown report generator for test results.

Produces a summary.md report and raw_traces.json file in
tests/results/<scenario>/<timestamp>/.
"""

import json
import os
from datetime import datetime, timezone


def generate_report(
    scenario_name: str,
    test_results: list[dict],
    output_dir: str | None = None,
) -> str:
    """Generate a markdown report and return the path to the summary file.

    Each entry in test_results should have:
      - id, name, description
      - passed: bool (overall)
      - duration_ms: int
      - turns: list of {input, response_text, duration_ms}
      - assertions: list of assertion result dicts
      - parsed_steps: list of trace step dicts (from last turn)
      - trace_events: raw trace events (from last turn)
    """
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")

    if output_dir is None:
        repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        output_dir = os.path.join(repo_root, "tests", "results", scenario_name, timestamp)

    os.makedirs(output_dir, exist_ok=True)

    total = len(test_results)
    passed = sum(1 for t in test_results if t["passed"])
    failed = total - passed
    total_duration = sum(t.get("duration_ms", 0) for t in test_results)

    lines = []
    lines.append(f"# Test Report: {scenario_name}")
    lines.append("")
    lines.append(f"**Generated**: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    lines.append(f"**Total**: {total} | **Passed**: {passed} | **Failed**: {failed}")
    lines.append(f"**Duration**: {total_duration}ms")
    lines.append("")

    # Summary table
    lines.append("## Summary")
    lines.append("")
    lines.append("| # | Test | Result | Duration |")
    lines.append("|---|------|--------|----------|")
    for t in test_results:
        status = "PASS" if t["passed"] else "**FAIL**"
        lines.append(f"| {t['id']} | {t['name']} | {status} | {t.get('duration_ms', 0)}ms |")
    lines.append("")

    # Per-test details
    lines.append("## Details")
    lines.append("")
    for t in test_results:
        status_icon = "PASS" if t["passed"] else "FAIL"
        lines.append(f"### [{status_icon}] {t['id']}: {t['name']}")
        lines.append("")
        if t.get("description"):
            lines.append(f"> {t['description']}")
            lines.append("")

        # Conversation log
        if t.get("turns"):
            lines.append("**Conversation:**")
            lines.append("")
            for i, turn in enumerate(t["turns"]):
                lines.append(f"**Turn {i + 1} — User:**")
                lines.append(f"```")
                lines.append(turn.get("input", ""))
                lines.append(f"```")
                lines.append("")
                lines.append(f"**Turn {i + 1} — Agent** ({turn.get('duration_ms', 0)}ms):")
                lines.append(f"```")
                response = turn.get("response_text", "")
                lines.append(response[:1000] + ("..." if len(response) > 1000 else ""))
                lines.append(f"```")
                lines.append("")

        # Assertion results
        lines.append("**Assertions:**")
        lines.append("")
        lines.append("| Assertion | Result | Evidence |")
        lines.append("|-----------|--------|----------|")
        for a in t.get("assertions", []):
            status = "PASS" if a["passed"] else "**FAIL**"
            evidence = a.get("evidence", "").replace("|", "\\|").replace("\n", " ")[:200]
            assertion_text = a.get("assertion", "").replace("|", "\\|")
            lines.append(f"| {assertion_text} | {status} | {evidence} |")
        lines.append("")

        # Trace summary
        if t.get("parsed_steps"):
            lines.append("**Trace Summary:**")
            lines.append("")
            tool_calls = [s for s in t["parsed_steps"] if s.get("type") == "Tool Call"]
            kb_lookups = [s for s in t["parsed_steps"] if s.get("type") == "KB Lookup"]
            guardrails = [s for s in t["parsed_steps"] if s.get("type") == "Guardrail"]
            lines.append(f"- Tool calls: {len(tool_calls)}")
            for tc in tool_calls:
                lines.append(f"  - `{tc.get('tool', 'unknown')}` → {tc.get('parameters', {})}")
            if kb_lookups:
                lines.append(f"- KB lookups: {len(kb_lookups)}")
            if guardrails:
                lines.append(f"- Guardrail actions: {[g.get('action') for g in guardrails]}")
            lines.append("")

        # Collapsible raw trace
        if t.get("trace_events"):
            lines.append("<details>")
            lines.append("<summary>Raw Trace JSON</summary>")
            lines.append("")
            lines.append("```json")
            lines.append(json.dumps(t["trace_events"], indent=2, default=str)[:5000])
            lines.append("```")
            lines.append("")
            lines.append("</details>")
            lines.append("")

        lines.append("---")
        lines.append("")

    # Write summary file
    summary_path = os.path.join(output_dir, "summary.md")
    with open(summary_path, "w") as f:
        f.write("\n".join(lines))

    # Write raw traces
    traces_path = os.path.join(output_dir, "raw_traces.json")
    raw_data = []
    for t in test_results:
        raw_data.append({
            "id": t["id"],
            "name": t["name"],
            "passed": t["passed"],
            "trace_events": t.get("trace_events", []),
            "turns": t.get("turns", []),
            "assertions": t.get("assertions", []),
        })
    with open(traces_path, "w") as f:
        json.dump(raw_data, f, indent=2, default=str)

    return summary_path
