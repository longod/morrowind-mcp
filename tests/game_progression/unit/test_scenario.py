"""Unit tests for the game progression scenario contract."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scenario import EvaluateAssertions, ResolveTerminationPolicy, ScenarioValidationError, ValidateScenario
from diagnostics import SuggestDiagnosticProbes
from inspector import FormatToolArgument, InspectorError, InspectorResponse
from run import RecordDiagnosticProbes, RecordWaitResponse, WaitUntil, WaitUntilTimeout


def NewScenario() -> dict:
    """Return the smallest replayable scenario used by contract tests."""
    return {
        "schema_version": 1,
        "name": "new-game-smoke",
        "bootstrap": {"start_mode": "new_game"},
        "steps": [
            {
                "id": "list-tools",
                "intent": "Discover tools available before selecting NEW GAME.",
                "operation": {"method": "tools/list"},
            }
        ],
    }


class ScenarioTests(unittest.TestCase):
    """Verify static validation without launching Morrowind."""

    def test_accepts_minimal_new_game_scenario(self) -> None:
        ValidateScenario(NewScenario())

    def test_rejects_non_new_game_bootstrap(self) -> None:
        scenario = NewScenario()
        scenario["bootstrap"]["start_mode"] = "load_game"

        with self.assertRaisesRegex(ScenarioValidationError, "start_mode"):
            ValidateScenario(scenario)

    def test_command_line_policy_overrides_scenario_policy(self) -> None:
        scenario = NewScenario()
        scenario["termination_policy"] = {"max_stalled_cycles": 2}

        policy = ResolveTerminationPolicy(scenario, {"max_stalled_cycles": 4})

        self.assertEqual(policy["max_stalled_cycles"], 4)
        self.assertEqual(policy["max_elapsed_seconds"], 1800)

    def test_rejects_duplicate_step_ids(self) -> None:
        scenario = NewScenario()
        scenario["steps"].append(dict(scenario["steps"][0]))

        with self.assertRaisesRegex(ScenarioValidationError, "duplicates"):
            ValidateScenario(scenario)

    def test_evaluates_json_pointer_assertions(self) -> None:
        document = {"result": {"tools": [{"name": "mw-menu-fetch"}]}}

        failures = EvaluateAssertions(document, [
            {"pointer": "/result/tools/0/name", "operator": "equals", "value": "mw-menu-fetch"},
            {"pointer": "/result/tools", "operator": "exists"},
        ])

        self.assertEqual(failures, [])

    def test_formats_inspector_tool_arguments_without_string_quotes(self) -> None:
        self.assertEqual(FormatToolArgument("mouseClick"), "mouseClick")
        self.assertEqual(FormatToolArgument(True), "true")
        self.assertEqual(FormatToolArgument({"menu": "new"}), '{"menu":"new"}')

    def test_accepts_agent_assessment_and_screenshot_reference(self) -> None:
        scenario = NewScenario()
        scenario["steps"][0]["assessment"] = {
            "situation": "The main menu is visible.",
            "evidence": "menu-fetch exposed a NEW GAME candidate.",
            "candidate_actions": ["Select the observed NEW GAME candidate."],
            "decision": "Record the candidate before selecting it.",
        }
        scenario["steps"][0]["screenshots"] = [{
            "purpose": "main-menu-before-new-game",
            "uri": "morrowind://screenshot/main-menu.jpg",
        }]

        ValidateScenario(scenario)

    def test_accepts_expected_terminal_tool_error(self) -> None:
        scenario = NewScenario()
        scenario["steps"][0]["expected_error"] = {
            "message_contains": "menu_path points to a missing child",
        }

        ValidateScenario(scenario)

    def test_rejects_expected_error_without_message(self) -> None:
        scenario = NewScenario()
        scenario["steps"][0]["expected_error"] = {}

        with self.assertRaisesRegex(ScenarioValidationError, "message_contains"):
            ValidateScenario(scenario)

    def test_rejects_expected_error_before_final_step(self) -> None:
        scenario = NewScenario()
        scenario["steps"][0]["expected_error"] = {"message_contains": "expected"}
        scenario["steps"].append({"id": "next", "intent": "Continue replay.", "operation": {"method": "tools/list"}})

        with self.assertRaisesRegex(ScenarioValidationError, "final step"):
            ValidateScenario(scenario)

    def test_rejects_multiple_expected_errors(self) -> None:
        scenario = NewScenario()
        scenario["steps"][0]["expected_error"] = {"message_contains": "first"}
        scenario["steps"].append({
            "id": "terminal",
            "intent": "Record another terminal error.",
            "operation": {"method": "tools/list"},
            "expected_error": {"message_contains": "second"},
        })

        with self.assertRaisesRegex(ScenarioValidationError, "at most one"):
            ValidateScenario(scenario)


class InspectorResponseTests(unittest.TestCase):
    """Guard CLI adapter behavior that lets expected tool errors replay."""

    def _MakeResponse(self, exit_code: int, document: dict, stderr: str = "") -> InspectorResponse:
        return InspectorResponse(arguments=[], exit_code=exit_code, stdout="", stderr=stderr, document=document)

    def test_returns_tool_result_when_inspector_exit_code_is_nonzero(self) -> None:
        # Inspector CLI exits with 5 whenever a tool returns isError: true.
        tool_result = {"isError": True, "content": [{"type": "text", "text": "menu_path points to a missing child."}]}
        response = self._MakeResponse(5, {"result": tool_result})

        self.assertEqual(response.result, tool_result)

    def test_raises_with_exit_detail_when_no_result_and_exit_code_nonzero(self) -> None:
        response = self._MakeResponse(3221226505, {}, stderr="fatal: access violation")

        with self.assertRaisesRegex(InspectorError, "3221226505.*access violation"):
            _ = response.result

    def test_raises_with_error_message_when_json_rpc_error_present(self) -> None:
        response = self._MakeResponse(0, {"error": {"message": "method not found"}})

        with self.assertRaisesRegex(InspectorError, "method not found"):
            _ = response.result


class WaitUntilTests(unittest.TestCase):
    """Verify readiness failures retain their most useful diagnostic evidence."""

    def test_timeout_retains_final_observation(self) -> None:
        document = {"result": {"structuredContent": {"menu": {"name": "MenuName"}}}}
        response = InspectorResponse(arguments=[], exit_code=0, stdout="", stderr="", document=document)
        wait_until = {
            "operation": {"method": "tools/list"},
            "assertions": [{"pointer": "/result/structuredContent/menu/name", "operator": "equals", "value": "MenuMessage"}],
            "timeout_seconds": 1,
            "interval_seconds": 1,
        }

        with patch("run.InvokeInspector", return_value=response), patch("run.time.monotonic", side_effect=[0, 0, 1]), patch("run.time.sleep"):
            with self.assertRaises(WaitUntilTimeout) as context:
                WaitUntil("http://localhost", wait_until)

        self.assertEqual(context.exception.document, document)

    def test_records_final_observation_on_timeout(self) -> None:
        document = {"result": {"structuredContent": {"menu": {"name": "MenuName"}}}}
        entry: dict = {}
        timeout = WaitUntilTimeout("wait_until timed out", document)

        with patch("run.WaitUntil", side_effect=timeout):
            with self.assertRaises(WaitUntilTimeout):
                RecordWaitResponse(entry, "http://localhost", {"operation": {"method": "tools/list"}})

        self.assertEqual(entry["wait_response"], document)


class DiagnosticProbeTests(unittest.TestCase):
    """Keep terminal diagnostics related to the triggering state-changing tool."""

    def test_menu_action_selects_menu_and_player_probes(self) -> None:
        probes = SuggestDiagnosticProbes({"method": "tools/call", "tool_name": "mw-menu-action"})

        self.assertEqual([probe["tool_name"] for probe in probes], ["mw-menu-fetch", "mw-player-fetch"])

    def test_read_only_operation_does_not_select_diagnostic_probes(self) -> None:
        self.assertEqual(SuggestDiagnosticProbes({"method": "tools/call", "tool_name": "mw-menu-fetch"}), [])

    def test_records_probe_error_without_replacing_terminal_outcome(self) -> None:
        run: dict = {}
        operation = {"method": "tools/call", "tool_name": "mw-menu-action"}

        with patch("run.InvokeInspector", side_effect=InspectorError("server stopped")):
            RecordDiagnosticProbes(run, "http://localhost", operation, 10)

        self.assertEqual(len(run["diagnostic_probes"]), 2)
        self.assertEqual(run["diagnostic_probes"][0]["error"], "server stopped")


if __name__ == "__main__":
    unittest.main()
