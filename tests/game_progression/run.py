"""Replay recorded Morrowind MCP progression scenarios."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from diagnostics import IsToolPublished, MEMORY_DEBUG_DUMP_OPERATION, SuggestDiagnosticProbes
from inspector import InspectorError, InvokeInspector
from lifecycle import GetConfiguration, LifecycleError, RemoveTestContext, SetTestContext, StartServer, StopServer, WaitForServer
from scenario import EvaluateAssertions, LoadScenario, ResolveTerminationPolicy, ScenarioValidationError


def ParseArguments() -> argparse.Namespace:
    """Parse replay options while keeping scenario policy adjustable."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", type=Path, required=True)
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--no-stop", action="store_true")
    parser.add_argument("--max-elapsed-seconds", type=int)
    parser.add_argument("--max-stalled-cycles", type=int)
    parser.add_argument("--final-wait-seconds", type=int)
    parser.add_argument("--max-retries-per-step", type=int)
    return parser.parse_args()


def WriteJson(path: Path, value: Any) -> None:
    """Write an inspectable UTF-8 run artifact."""
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class WaitUntilTimeout(RuntimeError):
    """Retain the last observation when a readiness condition expires."""

    def __init__(self, message: str, document: dict[str, Any] | None) -> None:
        super().__init__(message)
        self.document = document


def WaitUntil(endpoint: str, wait_until: dict[str, Any]) -> dict[str, Any]:
    """Poll a recorded observation until its replayable assertions succeed."""
    deadline = time.monotonic() + wait_until["timeout_seconds"]
    latest = None
    failures: list[str] = []
    while time.monotonic() < deadline:
        latest = InvokeInspector(endpoint, wait_until["operation"], wait_until["interval_seconds"] + 10)
        failures = EvaluateAssertions(latest.document, wait_until["assertions"])
        if not failures:
            return latest.document
        time.sleep(wait_until["interval_seconds"])
    document = latest.document if latest else None
    raise WaitUntilTimeout(f"wait_until timed out: {', '.join(failures)}", document)


def RecordWaitResponse(entry: dict[str, Any], endpoint: str, wait_until: dict[str, Any]) -> None:
    """Attach successful or final failed readiness evidence to a step artifact."""
    try:
        entry["wait_response"] = WaitUntil(endpoint, wait_until)
    except WaitUntilTimeout as error:
        if error.document is not None:
            entry["wait_response"] = error.document
        raise


def RecordDiagnosticProbes(run: dict[str, Any], endpoint: str, operation: dict[str, Any] | None, timeout_seconds: int) -> None:
    """Capture bounded, related read-only state after a terminal replay outcome."""
    probes = SuggestDiagnosticProbes(operation)
    if not probes:
        return
    records: list[dict[str, Any]] = []
    for probe in probes:
        record: dict[str, Any] = {"operation": probe}
        try:
            record["response"] = InvokeInspector(endpoint, probe, timeout_seconds).document
        except Exception as error:
            # A diagnostic failure must not replace the original terminal result.
            record["error"] = str(error)
        records.append(record)
    run["diagnostic_probes"] = records


def RecordMemoryDebugDump(run: dict[str, Any], endpoint: str, configuration: dict[str, Any], timeout_seconds: int) -> None:
    """Capture a Memory dump only when the terminal tool remains publicly available."""
    record: dict[str, Any] = {
        "operation": MEMORY_DEBUG_DUMP_OPERATION,
        "dump_directory": str(Path(configuration["Paths"]["modDataDir"]) / "memory-dump"),
    }
    try:
        catalog = InvokeInspector(endpoint, {"method": "tools/list"}, timeout_seconds).document
        if not IsToolPublished(catalog, MEMORY_DEBUG_DUMP_OPERATION["tool_name"]):
            record["status"] = "unavailable"
        else:
            response = InvokeInspector(endpoint, MEMORY_DEBUG_DUMP_OPERATION, timeout_seconds)
            record["response"] = response.document
            result = response.result
            if result.get("isError") is True:
                record["status"] = "failed"
            else:
                record["status"] = "succeeded"
    except Exception as error:
        # The dump is terminal diagnostic evidence and cannot replace the progression outcome.
        record["status"] = "failed"
        record["error"] = str(error)
    run["memory_debug_dump"] = record


def VerifyStepResult(response: Any, step: dict[str, Any]) -> None:
    """Accept an expected terminal tool error while rejecting unexpected MCP failures."""
    result = response.result
    expected_error = step.get("expected_error")
    is_error = result.get("isError") is True
    if not expected_error:
        if is_error:
            raise InspectorError(f"Tool step {step['id']} returned isError=true.")
        return

    if not is_error:
        raise RuntimeError(f"Step {step['id']} expected an MCP tool error.")
    message = "\n".join(
        content.get("text", "")
        for content in result.get("content", [])
        if isinstance(content, dict) and isinstance(content.get("text"), str)
    )
    if expected_error["message_contains"] not in message:
        raise RuntimeError(f"Step {step['id']} returned an unexpected tool error: {message}")


def Main() -> int:
    """Validate or replay one scenario, stopping Morrowind after terminal outcomes."""
    arguments = ParseArguments()
    try:
        scenario = LoadScenario(arguments.scenario)
        policy = ResolveTerminationPolicy(scenario, {
            "max_elapsed_seconds": arguments.max_elapsed_seconds,
            "max_stalled_cycles": arguments.max_stalled_cycles,
            "final_wait_seconds": arguments.final_wait_seconds,
            "max_retries_per_step": arguments.max_retries_per_step,
        })
    except ScenarioValidationError as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 2

    if arguments.validate_only:
        print(f"[PASSED] Scenario is valid: {arguments.scenario}")
        return 0

    repo_root = Path(__file__).resolve().parents[2]
    output_dir = repo_root / "tests" / "logs" / "game_progression" / datetime.now(UTC).strftime("%Y%m%d_%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=False)
    run = {"scenario": str(arguments.scenario), "policy": policy, "steps": [], "outcome": {"status": "failed"}}
    started = time.monotonic()
    endpoint = None
    last_operation = None

    try:
        configuration = GetConfiguration(repo_root)
        SetTestContext(repo_root, "skip", True)
        StartServer(repo_root)
        connection = configuration["Connection"]
        WaitForServer(connection["host"], int(connection["port"]), 60)
        endpoint = connection["url"]

        for step in scenario["steps"]:
            if time.monotonic() - started > policy["max_elapsed_seconds"]:
                raise RuntimeError("Scenario exceeded max_elapsed_seconds.")
            last_operation = step["operation"]
            response = InvokeInspector(endpoint, last_operation, policy["max_retries_per_step"] * 10)
            VerifyStepResult(response, step)
            failures = EvaluateAssertions(response.document, step.get("assertions", []))
            if failures:
                raise RuntimeError(f"Step {step['id']} assertions failed: {', '.join(failures)}")
            entry = {"id": step["id"], "intent": step["intent"], "response": response.document}
            run["steps"].append(entry)
            if "wait_until" in step:
                RecordWaitResponse(entry, endpoint, step["wait_until"])

        expected_outcome = scenario.get("outcome", "completed")
        if expected_outcome in {"failed", "stalled"}:
            RecordDiagnosticProbes(run, endpoint, last_operation, policy["max_retries_per_step"] * 10)
            RecordMemoryDebugDump(run, endpoint, configuration, policy["max_retries_per_step"] * 10)
        run["outcome"] = {"status": expected_outcome, "message": "All recorded steps completed."}
        return 0
    except (InspectorError, LifecycleError, RuntimeError) as error:
        if endpoint is not None:
            RecordDiagnosticProbes(run, endpoint, last_operation, policy["max_retries_per_step"] * 10)
            RecordMemoryDebugDump(run, endpoint, configuration, policy["max_retries_per_step"] * 10)
        run["outcome"] = {"status": "failed", "message": str(error)}
        print(f"[ERROR] {error}", file=sys.stderr)
        return 1
    finally:
        WriteJson(output_dir / "run.json", run)
        mwse_log = Path(configuration["Paths"]["morrowindInstallDir"]) / "MWSE.log" if "configuration" in locals() else None
        if mwse_log and mwse_log.exists():
            shutil.copy2(mwse_log, output_dir / "MWSE.log")
        if not arguments.no_stop:
            StopServer(repo_root)
        RemoveTestContext(repo_root)


if __name__ == "__main__":
    raise SystemExit(Main())
