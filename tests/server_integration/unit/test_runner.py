"""Unit tests for reusable server-integration case and status behavior."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import mock_open, patch

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT.parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(TESTS))

from case_api import CaseDefinition, CaseDefinitionError, Run, Scenario, Suite, Wait
from mwmcp_test_support.inspector import InspectorResponse
from mwmcp_test_support.lifecycle import LifecycleError, PrepareMorrowindInput, SetTestContext
from runner import CaseExecutionError, CopyMwseLog, ExecuteSuite, GenerateSummary, IntegrationError, ListSaveNames, ReadinessFailed, ReadinessTimeout, WaitForReady
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

    def test_execute_suite_runs_stateful_scenario(self) -> None:
        calls: list[str] = []
        def Execute(endpoint, timeout, invoke, evaluate, log):
            calls.append(endpoint)
            log("scenario invoked")
            return {"selected": "spell"}
        suite = Suite("test", None, (Scenario("select-spell", Execute),))
        records = ExecuteSuite("http://test", suite, {}, 1, lambda *args: None, lambda document, assertions: [], lambda message: None)
        self.assertEqual(calls, ["http://test"])
        self.assertEqual(records[0]["details"], {"selected": "spell"})
        self.assertEqual(records[0]["status"], "passed")

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
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            summary_path = root / "tests" / "logs" / "server_integration" / "summary_20260825_123456.json"
            summary_path.parent.mkdir(parents=True)
            summary_path.write_text("{}", encoding="utf-8")
            completed = type("Completed", (), {"returncode": 0})()
            with patch("runner.subprocess.run", return_value=completed) as run:
                result = GenerateSummary(root, "20260825_123456")
        command = run.call_args.args[0]
        self.assertIn("server_integration", command)
        self.assertIn("20260825_123456", command)
        self.assertTrue(run.call_args.kwargs["capture_output"])
        self.assertTrue(result["available"])
        self.assertTrue(result["should_read"])
        self.assertEqual(result["path"], summary_path)

    def test_generate_summary_reports_missing_artifact(self) -> None:
        completed = type("Completed", (), {"returncode": 0})()
        with tempfile.TemporaryDirectory() as directory, patch("runner.subprocess.run", return_value=completed):
            result = GenerateSummary(Path(directory), "20260825_123456")
        self.assertFalse(result["available"])
        self.assertFalse(result["should_read"])
        self.assertEqual(result["warning"], "Test summary was not created.")

    def test_generate_summary_retains_generator_output(self) -> None:
        completed = type("Completed", (), {"returncode": 1, "stdout": "stdout", "stderr": "stderr"})()
        with tempfile.TemporaryDirectory() as directory, patch("runner.subprocess.run", return_value=completed):
            result = GenerateSummary(Path(directory), "20260825_123456")
        self.assertEqual(result["stdout"], "stdout")
        self.assertEqual(result["stderr"], "stderr")

    def test_copy_mwse_log_reports_saved(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_dir = root / "morrowind"
            source_dir.mkdir()
            source = source_dir / "MWSE.log"
            source.write_text("log", encoding="utf-8")
            destination = root / "artifacts" / "mwse.log"
            result = CopyMwseLog({"Paths": {"morrowindInstallDir": str(source_dir)}}, destination)
            self.assertEqual(result, {"state": "saved", "path": str(destination)})
            self.assertEqual(destination.read_text(encoding="utf-8"), "log")

    def test_copy_mwse_log_reports_missing_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "artifacts" / "mwse.log"
            result = CopyMwseLog({"Paths": {"morrowindInstallDir": str(root / "morrowind")}}, destination)
        self.assertEqual(result["state"], "missing")
        self.assertEqual(result["path"], str(destination))
        self.assertFalse(destination.exists())

    def test_copy_mwse_log_reports_copy_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_dir = root / "morrowind"
            source_dir.mkdir()
            (source_dir / "MWSE.log").write_text("log", encoding="utf-8")
            destination = root / "artifacts" / "mwse.log"
            with patch("runner.shutil.copy2", side_effect=OSError("locked")):
                result = CopyMwseLog({"Paths": {"morrowindInstallDir": str(source_dir)}}, destination)
        self.assertEqual(result["state"], "copy_failed")
        self.assertEqual(result["path"], str(destination))
        self.assertEqual(result["error"], "locked")

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

    def test_prepare_morrowind_input_uses_shared_script(self) -> None:
        completed = type("Completed", (), {"returncode": 0})()
        with patch("mwmcp_test_support.lifecycle.subprocess.run", return_value=completed) as invoke:
            PrepareMorrowindInput(Path("C:/repo"))
        command = invoke.call_args.args[0]
        self.assertEqual(Path(command[-1]), Path("C:/repo/tests/prepare_morrowind_input.ps1"))
        self.assertNotIn("mouse_event", " ".join(command))

    def test_prepare_morrowind_input_rejects_script_failure(self) -> None:
        completed = type("Completed", (), {"returncode": 1, "stdout": "", "stderr": "input unavailable"})()
        with patch("mwmcp_test_support.lifecycle.subprocess.run", return_value=completed):
            with self.assertRaisesRegex(LifecycleError, "input unavailable"):
                PrepareMorrowindInput(Path("C:/repo"))

    def test_runner_prepares_input_once_after_readiness(self) -> None:
        events: list[str] = []
        configuration = {
            "Connection": {"host": "127.0.0.1", "port": 8765, "url": "http://127.0.0.1:8765"},
            "Paths": {"modDataDir": "C:/mod-data", "morrowindInstallDir": "C:/morrowind"},
        }
        suite = Suite("suite", None, ())

        def record(name: str):
            def callback(*args, **kwargs):
                events.append(name)

            return callback

        with (
            patch.object(sys, "argv", ["run.py", "--suite", "suite", "--no-stop"]),
            patch("run.GetConfiguration", return_value=configuration),
            patch("run.LoadCases", return_value={}),
            patch("run.LoadSuites", return_value={"suite": suite}),
            patch("run.WriteJson"),
            patch("run.SetTestContext", side_effect=record("context")),
            patch("run.StartServer", side_effect=record("start")),
            patch("run.WaitForServer", side_effect=record("server-ready")),
            patch("run.WaitForReady", side_effect=record("game-ready")),
            patch("run.PrepareMorrowindInput", side_effect=record("prepare")) as prepare_input,
            patch("run.ExecuteSuite", side_effect=record("execute")),
            patch("run.GenerateSummary", return_value={"available": False, "warning": "not needed"}),
            patch("run.RemoveTestContext", side_effect=record("remove")),
            patch("pathlib.Path.open", mock_open()),
        ):
            result = integration_run.Main()

        self.assertEqual(result, 0)
        prepare_input.assert_called_once()
        self.assertLess(events.index("game-ready"), events.index("prepare"))
        self.assertLess(events.index("prepare"), events.index("execute"))

    def test_runner_skips_input_preparation_when_requested(self) -> None:
        configuration = {
            "Connection": {"host": "127.0.0.1", "port": 8765, "url": "http://127.0.0.1:8765"},
            "Paths": {"modDataDir": "C:/mod-data", "morrowindInstallDir": "C:/morrowind"},
        }
        suite = Suite("suite", None, ())
        with (
            patch.object(sys, "argv", ["run.py", "--suite", "suite", "--no-stop", "--no-foreground"]),
            patch("run.GetConfiguration", return_value=configuration),
            patch("run.LoadCases", return_value={}),
            patch("run.LoadSuites", return_value={"suite": suite}),
            patch("run.WriteJson"),
            patch("run.SetTestContext"),
            patch("run.StartServer"),
            patch("run.WaitForServer"),
            patch("run.WaitForReady"),
            patch("run.PrepareMorrowindInput") as prepare_input,
            patch("run.ExecuteSuite"),
            patch("run.GenerateSummary", return_value={"available": False, "warning": "not needed"}),
            patch("run.RemoveTestContext"),
            patch("pathlib.Path.open", mock_open()),
        ):
            result = integration_run.Main()

        self.assertEqual(result, 0)
        prepare_input.assert_not_called()

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
