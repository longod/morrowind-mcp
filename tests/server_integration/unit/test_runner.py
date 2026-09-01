"""Unit tests for reusable server-integration case and status behavior."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT.parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(TESTS))

from case_api import CaseDefinition, CaseDefinitionError, Run, Suite, Wait
from mwmcp_test_support.inspector import InspectorResponse
from mwmcp_test_support.lifecycle import SetTestContext
from runner import CaseExecutionError, ExecuteSuite, GenerateSummary, IntegrationError, ListSaveNames, ReadinessFailed, ReadinessTimeout, WaitForReady
from suite_loader import LoadCases, LoadSuites
import run as integration_run


class IntegrationRunnerTests(unittest.TestCase):
    """Validate static runner behavior without launching Morrowind or Inspector."""

    def test_lists_non_quicksave_stems(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Seyda Neen.ess").touch()
            (root / "Quicksave.ess").touch()
            (root / "Quiksave.ess").touch()
            self.assertEqual(ListSaveNames(root), ["Seyda Neen"])

    def test_wait_for_ready_requires_matching_run_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status_path = Path(directory) / "status.json"
            status_path.write_text(json.dumps({"run_id": "old", "state": "ready"}), encoding="utf-8")
            with patch("runner.time.monotonic", side_effect=[0, 1]), patch("runner.time.sleep"):
                with self.assertRaisesRegex(IntegrationError, "Timed out"):
                    WaitForReady(status_path, "new", 1)

    def test_readiness_timeout_retains_matching_last_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status_path = Path(directory) / "status.json"
            status = {"run_id": "run-1", "state": "loading"}
            status_path.write_text(json.dumps(status), encoding="utf-8")
            with patch("runner.time.monotonic", side_effect=[0, 0, 1]), patch("runner.time.sleep"):
                with self.assertRaises(ReadinessTimeout) as context:
                    WaitForReady(status_path, "run-1", 1)
            self.assertEqual(context.exception.last_status, status)

    def test_wait_for_ready_retries_transient_read_errors(self) -> None:
        with patch("runner.ReadStatus", side_effect=OSError("sharing violation")), patch("runner.time.monotonic", side_effect=[0, 1]), patch("runner.time.sleep"):
            with self.assertRaises(ReadinessTimeout):
                WaitForReady(Path("status.json"), "run-1", 1)

    def test_readiness_failure_retains_lua_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status_path = Path(directory) / "status.json"
            status = {"run_id": "run-1", "state": "failed", "loaded_filename": "quiksave", "quickload": True}
            status_path.write_text(json.dumps(status), encoding="utf-8")
            with self.assertRaises(ReadinessFailed) as context:
                WaitForReady(status_path, "run-1", 1)
            self.assertEqual(context.exception.status, status)

    def test_wait_for_ready_accepts_matching_ready_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status_path = Path(directory) / "status.json"
            status_path.write_text(json.dumps({"run_id": "run-1", "state": "ready"}), encoding="utf-8")
            self.assertEqual(WaitForReady(status_path, "run-1", 1)["state"], "ready")

    def test_execute_suite_reuses_parameterized_case_and_wait(self) -> None:
        definition = CaseDefinition("read", {"method": "resources/read", "uri": "${uri}"}, parameters=frozenset({"uri"}))
        suite = Suite("test", None, (Run("read", uri="first"), Wait(0), Run("read", uri="second")))
        calls: list[str] = []
        log: list[str] = []
        def Invoke(endpoint, operation, timeout):
            calls.append(operation["uri"])
            return InspectorResponse(["inspector"], 0, "{}", "", {"result": {}})
        records = ExecuteSuite("http://test", suite, {"read": definition}, 1, Invoke, lambda document, assertions: [], log.append)
        self.assertEqual(calls, ["first", "second"])
        self.assertEqual([record["status"] for record in records], ["passed", "passed", "passed"])

    def test_execute_suite_records_failed_case_and_skips_remaining_cases(self) -> None:
        definition = CaseDefinition("read", {"method": "resources/read", "uri": "${uri}"}, parameters=frozenset({"uri"}))
        suite = Suite("test", None, (Run("read", uri="first"), Wait(1), Run("read", uri="second")))
        log: list[str] = []
        response = InspectorResponse(["inspector"], 0, "{}", "", {"result": {}})

        with self.assertRaises(CaseExecutionError) as context:
            ExecuteSuite("http://test", suite, {"read": definition}, 1, lambda *args: response,
                         lambda document, assertions: ["expected failure"], log.append)

        self.assertEqual([record["status"] for record in context.exception.records], ["failed", "skipped", "skipped"])
        self.assertIn("[FAILED] read", "\n".join(log))
        self.assertIn("[SKIPPED] read", "\n".join(log))

    def test_loader_rejects_unknown_case(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "cases").mkdir()
            (root / "suites").mkdir()
            (root / "cases" / "common.py").write_text("from case_api import CaseDefinition\nCASES = {'known': CaseDefinition('known', {'method': 'tools/list'})}\n", encoding="utf-8")
            (root / "suites" / "bad.py").write_text("from case_api import Run, Suite\nSUITE = Suite('bad', None, (Run('missing'),))\n", encoding="utf-8")
            with self.assertRaisesRegex(CaseDefinitionError, "unknown case"):
                LoadSuites(root, LoadCases(root))

    def test_generate_summary_uses_server_integration_type(self) -> None:
        with patch("runner.subprocess.run") as run:
            GenerateSummary(Path("C:/repo"), "20260825_123456")
        command = run.call_args.args[0]
        self.assertIn("server_integration", command)
        self.assertIn("20260825_123456", command)

    def test_main_menu_context_uses_explicit_switch(self) -> None:
        completed = type("Completed", (), {"returncode": 0, "stderr": ""})()
        with patch("mwmcp_test_support.lifecycle._InvokePowerShell", return_value=completed) as invoke:
            SetTestContext(Path("C:/repo"), "skip", True, "run-1", None)
        command = invoke.call_args.args[1]
        self.assertIn("-ServerIntegrationMainMenu", command)
        self.assertNotIn("-ServerIntegrationSaveName", command)

    def test_saved_game_context_escapes_save_name(self) -> None:
        completed = type("Completed", (), {"returncode": 0, "stderr": ""})()
        with patch("mwmcp_test_support.lifecycle._InvokePowerShell", return_value=completed) as invoke:
            SetTestContext(Path("C:/repo"), "skip", True, "run-1", "Nerevar's Test")
        command = invoke.call_args.args[1]
        self.assertIn("-ServerIntegrationSaveName 'Nerevar''s Test'", command)

    def test_runner_reports_suite_loading_errors_without_traceback(self) -> None:
        with patch.object(sys, "argv", ["run.py"]), patch("run.LoadCases", side_effect=CaseDefinitionError("invalid suite")), patch("builtins.print") as print:
            self.assertEqual(integration_run.Main(), 2)
        self.assertTrue(any("[ERROR] invalid suite" in str(call) for call in print.call_args_list))

    def test_parser_enables_foreground_activation_by_default(self) -> None:
        with patch.object(sys, "argv", ["run.py"]):
            self.assertFalse(integration_run.CreateArgumentParser().parse_args().no_foreground)

    def test_parser_accepts_no_foreground(self) -> None:
        with patch.object(sys, "argv", ["run.py", "--no-foreground"]):
            self.assertTrue(integration_run.CreateArgumentParser().parse_args().no_foreground)


if __name__ == "__main__":
    unittest.main()
