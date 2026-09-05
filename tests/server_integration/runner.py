"""Lifecycle, status polling, artifact recording, and case execution for integration suites."""

from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

from case_api import CaseDefinition, CaseInvocation, Scenario, Suite, Wait


class IntegrationError(RuntimeError):
    """Raised when the test-only game readiness protocol or a case fails."""


class ReadinessTimeout(IntegrationError):
    """Retains the last matching readiness status for timeout diagnostics."""

    def __init__(self, message: str, last_status: dict[str, Any] | None) -> None:
        super().__init__(message)
        self.last_status = last_status


class ReadinessFailed(IntegrationError):
    """Retains the Lua-reported readiness failure status."""

    def __init__(self, message: str, status: dict[str, Any]) -> None:
        super().__init__(message)
        self.status = status


class CaseExecutionError(IntegrationError):
    """Retains case records when a suite cannot continue after a case failure."""

    def __init__(self, message: str, records: list[dict[str, Any]]) -> None:
        super().__init__(message)
        self.records = records


def WriteJson(path: Path, value: Any) -> None:
    """Write a UTF-8 artifact that remains available after the game exits."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def ListSaveNames(save_dir: Path) -> list[str]:
    """List stable explicit save stems, excluding quicksave from integration selection."""
    if not save_dir.is_dir():
        raise IntegrationError(f"Save directory was not found: {save_dir}")
    return [path.stem for path in sorted(save_dir.glob("*.ess")) if path.stem.lower() not in {"quicksave", "quiksave"}]


def ReadStatus(status_path: Path) -> dict[str, Any]:
    """Read one retained readiness status document."""
    return json.loads(status_path.read_text(encoding="utf-8"))


def WaitForReady(status_path: Path, run_id: str, timeout_seconds: int) -> dict[str, Any]:
    """Wait for matching retained Lua status instead of treating TCP as game readiness."""
    deadline = time.monotonic() + timeout_seconds
    last_error = None
    last_status = None
    while time.monotonic() < deadline:
        try:
            status = ReadStatus(status_path)
            if status.get("run_id") == run_id:
                last_status = status
                state = status.get("state")
                if state == "ready":
                    return status
                if state == "failed":
                    raise ReadinessFailed(status.get("error", "Lua integration load failed."), status)
        except FileNotFoundError:
            pass
        except json.JSONDecodeError as error:
            last_error = error
        except OSError as error:
            last_error = error
        time.sleep(1)
    detail = f" Last status error: {last_error}" if last_error else ""
    raise ReadinessTimeout(f"Timed out waiting for integration readiness.{detail}", last_status)


def ExecuteSuite(endpoint: str, suite: Suite, cases: dict[str, CaseDefinition], timeout_seconds: int,
                 invoke, evaluate, log) -> list[dict[str, Any]]:
    """Run suite invocations in declared order while retaining every Inspector response."""
    records: list[dict[str, Any]] = []
    for index, invocation in enumerate(suite.cases):
        if isinstance(invocation, Wait):
            log(f"[CASE] wait: {invocation.seconds:.1f} seconds")
            time.sleep(invocation.seconds)
            log(f"[PASSED] wait: {invocation.seconds:.1f} seconds")
            records.append({"kind": "wait", "seconds": invocation.seconds, "status": "passed"})
            continue
        if isinstance(invocation, Scenario):
            log(f"[SCENARIO] {invocation.id}")
            record = {"kind": "scenario", "id": invocation.id}
            try:
                details = invocation.execute(endpoint, timeout_seconds, invoke, evaluate, log)
                if details is not None:
                    record["details"] = details
            except (IntegrationError, RuntimeError) as error:
                record["status"] = "failed"
                record["error"] = str(error)
                records.append(record)
                log(f"[FAILED] {invocation.id}: {error}")
                for remaining in suite.cases[index + 1:]:
                    skipped_id = f"wait: {remaining.seconds:.1f} seconds" if isinstance(remaining, Wait) else remaining.id
                    records.append({"kind": "scenario" if isinstance(remaining, Scenario) else "case", "id": skipped_id,
                                    "status": "skipped"})
                    log(f"[SKIPPED] {skipped_id}")
                raise CaseExecutionError(str(error), records) from error
            record["status"] = "passed"
            records.append(record)
            log(f"[PASSED] {invocation.id}")
            continue
        if not isinstance(invocation, CaseInvocation):
            raise IntegrationError(f"Suite {suite.id} has an invalid invocation.")
        definition = cases[invocation.case_id]
        operation = definition.BuildOperation(invocation.parameters)
        log(f"[CASE] {definition.id}")
        record = {"kind": "case", "id": definition.id, "parameters": invocation.parameters}
        try:
            response = invoke(endpoint, operation, timeout_seconds)
            log(f"[RUN] {' '.join(response.arguments)}")
            if response.stderr:
                log("--- STDERR ---\n" + response.stderr.rstrip())
            if response.stdout:
                log("--- STDOUT ---\n" + response.stdout.rstrip())
            log(f"[EXIT] {response.exit_code}")
            record["response"] = response.document
            result = response.result
            if result.get("isError") is True:
                raise IntegrationError(f"Case {definition.id} returned isError=true.")
            failures = evaluate(response.document, definition.BuildAssertions(invocation.parameters))
            if failures:
                raise IntegrationError(f"Case {definition.id} assertions failed: {', '.join(failures)}")
        except (IntegrationError, RuntimeError) as error:
            record["status"] = "failed"
            record["error"] = str(error)
            records.append(record)
            log(f"[FAILED] {definition.id}: {error}")
            for remaining in suite.cases[index + 1:]:
                if isinstance(remaining, Wait):
                    skipped_id = f"wait: {remaining.seconds:.1f} seconds"
                    skipped = {"kind": "wait", "seconds": remaining.seconds, "status": "skipped"}
                else:
                    skipped_id = remaining.case_id
                    skipped = {"kind": "case", "id": remaining.case_id, "parameters": remaining.parameters, "status": "skipped"}
                records.append(skipped)
                log(f"[SKIPPED] {skipped_id}")
            raise CaseExecutionError(str(error), records) from error
        log(f"[PASSED] {definition.id}")
        record["status"] = "passed"
        records.append(record)
    return records


def CopyMwseLog(configuration: dict[str, Any], destination: Path) -> None:
    """Copy the final MWSE log as timestamped evidence without reading a live file later."""
    source = Path(configuration["Paths"]["morrowindInstallDir"]) / "MWSE.log"
    if source.is_file():
        shutil.copy2(source, destination)


def GenerateSummary(repo_root: Path, timestamp: str) -> dict[str, Any]:
    """Generate a summary without forwarding its JSON output to the integration runner."""
    summary_path = repo_root / "tests" / "logs" / "server_integration" / f"summary_{timestamp}.json"
    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-File", str(repo_root / "tests" / "summarize_test_runs.ps1"),
         "-TestType", "server_integration", "-RunTimestamp", timestamp],
        cwd=repo_root,
        check=False,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    if completed.returncode != 0:
        return {"available": False, "path": summary_path, "should_read": False,
                "warning": f"Summary generator exited with code {completed.returncode}."}
    if not summary_path.is_file():
        return {"available": False, "path": summary_path, "should_read": False,
                "warning": "Test summary was not created."}
    return {"available": True, "path": summary_path, "should_read": True, "warning": None}
