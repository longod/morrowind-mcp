"""Run a saved-game or main-menu Morrowind MCP integration suite."""

from __future__ import annotations

import argparse
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
TESTS_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(TESTS_DIR))
sys.path.insert(0, str(SCRIPT_DIR))

from mwmcp_test_support.inspector import InspectorError, InvokeInspector
from mwmcp_test_support.lifecycle import ActivateMorrowindWindow, GetConfiguration, LifecycleError, RemoveTestContext, SetTestContext, StartServer, StopServer, WaitForServer
from mwmcp_test_support.assertions import EvaluateAssertions
from case_api import CaseDefinitionError
from runner import CaseExecutionError, CopyMwseLog, ExecuteSuite, GenerateSummary, IntegrationError, ListSaveNames, ReadinessFailed, ReadinessTimeout, WaitForReady, WriteJson
from suite_loader import LoadCases, LoadSuites


def _EvaluateAssertions(document, assertions):
    """Evaluate portable assertions without importing progression-specific behavior."""
    return EvaluateAssertions(document, assertions)


def CreateArgumentParser() -> argparse.ArgumentParser:
    """Build the CLI parser so selection errors can show its usage consistently."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite")
    parser.add_argument("--list-suites", action="store_true")
    parser.add_argument("--list-saves", action="store_true")
    parser.add_argument("--no-stop", action="store_true")
    parser.add_argument("--no-foreground", action="store_true")
    parser.add_argument("--readiness-timeout", type=int, default=120)
    parser.add_argument("--case-timeout", type=int, default=30)
    return parser


def PrintSuiteSelectionHelp(parser: argparse.ArgumentParser, suites) -> None:
    """Show usage and discovered suites when no executable suite was selected."""
    parser.print_usage(sys.stderr)
    print("Available suites:", file=sys.stderr)
    for suite_id in sorted(suites):
        print(f"  {suite_id}", file=sys.stderr)


def Main() -> int:
    parser = CreateArgumentParser()
    arguments = parser.parse_args()
    try:
        cases = LoadCases(SCRIPT_DIR)
        suites = LoadSuites(SCRIPT_DIR, cases)
    except (CaseDefinitionError, RuntimeError) as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 2
    if arguments.list_suites:
        print("\n".join(sorted(suites)))
        return 0
    repo_root = SCRIPT_DIR.parents[1]
    try:
        configuration = GetConfiguration(repo_root)
    except LifecycleError as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 1
    if arguments.list_saves:
        try:
            print("\n".join(ListSaveNames(Path(configuration["Paths"]["saveDir"]))))
            return 0
        except IntegrationError as error:
            print(f"[ERROR] {error}", file=sys.stderr)
            return 2
    if not arguments.suite or arguments.suite not in suites:
        print("[ERROR] --suite must name an available suite.", file=sys.stderr)
        PrintSuiteSelectionHelp(parser, suites)
        return 2
    suite = suites[arguments.suite]
    if suite.save_name is not None:
        try:
            if suite.save_name not in ListSaveNames(Path(configuration["Paths"]["saveDir"])):
                print(f"[ERROR] Save was not found: {suite.save_name}", file=sys.stderr)
                return 2
        except IntegrationError as error:
            print(f"[ERROR] {error}", file=sys.stderr)
            return 2
    timestamp = datetime.now(UTC).strftime("%Y%m%d_%H%M%S")
    output_dir = repo_root / "tests" / "logs" / "server_integration"
    inspector_log = output_dir / f"inspector_{timestamp}.log"
    result_path = output_dir / f"result_{timestamp}.json"
    mwse_path = output_dir / f"mwse_{timestamp}.log"
    run_id = str(uuid.uuid4())
    status_path = Path(configuration["Paths"]["modDataDir"]) / "tests" / "server-integration-status.json"
    result = {"suite": suite.id, "save_name": suite.save_name, "run_id": run_id, "state": "failed", "cases": []}
    started = False
    inspector_log.parent.mkdir(parents=True, exist_ok=True)

    def Log(line: str) -> None:
        print(line)
        with inspector_log.open("a", encoding="utf-8") as file:
            file.write(line + "\n")

    try:
        WriteJson(status_path, {"run_id": run_id, "state": "pending", "save_name": suite.save_name})
        SetTestContext(repo_root, "skip", True, run_id, suite.save_name)
        StartServer(repo_root)
        started = True
        connection = configuration["Connection"]
        WaitForServer(connection["host"], int(connection["port"]), arguments.readiness_timeout)
        if not arguments.no_foreground:
            if not ActivateMorrowindWindow(repo_root):
                Log("[WARN] Failed to activate Morrowind window in foreground.")
        else:
            Log("[INFO] Skipping foreground activation (--no-foreground).")
        result["ready"] = WaitForReady(status_path, run_id, arguments.readiness_timeout)
        result["cases"] = ExecuteSuite(connection["url"], suite, cases, arguments.case_timeout,
                                       InvokeInspector, _EvaluateAssertions, Log)
        result["state"] = "passed"
        return 0
    except (InspectorError, LifecycleError, IntegrationError, RuntimeError) as error:
        if isinstance(error, CaseExecutionError):
            result["cases"] = error.records
        elif isinstance(error, ReadinessTimeout):
            result["ready_last_observed"] = error.last_status
            Log(f"[FAILED] {error}")
        elif isinstance(error, ReadinessFailed):
            result["ready_last_observed"] = error.status
            Log(f"[FAILED] {error}")
        else:
            Log(f"[FAILED] {error}")
        result["error"] = str(error)
        return 1
    finally:
        if started and not arguments.no_stop:
            StopServer(repo_root)
        if arguments.no_stop:
            result["mwse_log"] = {"state": "live-not-copied"}
        else:
            CopyMwseLog(configuration, mwse_path)
            result["mwse_log"] = {"state": "saved", "path": str(mwse_path)}
        WriteJson(result_path, result)
        GenerateSummary(repo_root, timestamp)
        RemoveTestContext(repo_root)


if __name__ == "__main__":
    raise SystemExit(Main())
