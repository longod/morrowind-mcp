"""Scenario loading and structural validation for game progression replay."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class ScenarioValidationError(ValueError):
    """Raised when a progression scenario cannot be replayed safely."""


DEFAULT_TERMINATION_POLICY = {
    "max_elapsed_seconds": 1800,
    "max_stalled_cycles": 3,
    "final_wait_seconds": 30,
    "max_retries_per_step": 5,
    "stop_server_on_stalled": True,
}


def LoadScenario(path: Path) -> dict[str, Any]:
    """Load a scenario file and reject invalid replay contracts."""
    try:
        scenario = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ScenarioValidationError(f"Unable to read scenario: {path}") from error
    except json.JSONDecodeError as error:
        raise ScenarioValidationError(f"Scenario is not valid JSON: {error}") from error

    ValidateScenario(scenario)
    return scenario


def ResolveTerminationPolicy(
    scenario: dict[str, Any], overrides: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Merge default, scenario, and command-line termination settings."""
    policy = dict(DEFAULT_TERMINATION_POLICY)
    policy.update(scenario.get("termination_policy", {}))
    if overrides:
        policy.update({key: value for key, value in overrides.items() if value is not None})
    ValidateTerminationPolicy(policy)
    return policy


def ValidateScenario(scenario: Any) -> None:
    """Validate fields required for deterministic replay and agent interpretation."""
    if not isinstance(scenario, dict):
        raise ScenarioValidationError("Scenario root must be an object.")
    if scenario.get("schema_version") != 1:
        raise ScenarioValidationError("schema_version must be 1.")
    if not isinstance(scenario.get("name"), str) or not scenario["name"].strip():
        raise ScenarioValidationError("name must be a non-empty string.")
    bootstrap = scenario.get("bootstrap")
    if not isinstance(bootstrap, dict) or bootstrap.get("start_mode") != "new_game":
        raise ScenarioValidationError("bootstrap.start_mode must be new_game.")
    steps = scenario.get("steps")
    if not isinstance(steps, list) or not steps:
        raise ScenarioValidationError("steps must be a non-empty array.")

    step_ids: set[str] = set()
    for index, step in enumerate(steps):
        ValidateStep(step, index, step_ids)
    expected_error_indices = [index for index, step in enumerate(steps) if "expected_error" in step]
    if len(expected_error_indices) > 1:
        raise ScenarioValidationError("steps may contain at most one expected_error.")
    if expected_error_indices and expected_error_indices[0] != len(steps) - 1:
        raise ScenarioValidationError("expected_error must be on the final step.")
    ValidateTerminationPolicy(ResolveTerminationPolicy(scenario))


def ValidateStep(step: Any, index: int, step_ids: set[str]) -> None:
    """Validate one recorded action without constraining runtime-specific values."""
    if not isinstance(step, dict):
        raise ScenarioValidationError(f"steps[{index}] must be an object.")
    step_id = step.get("id")
    if not isinstance(step_id, str) or not step_id.strip():
        raise ScenarioValidationError(f"steps[{index}].id must be a non-empty string.")
    if step_id in step_ids:
        raise ScenarioValidationError(f"steps[{index}].id duplicates {step_id!r}.")
    step_ids.add(step_id)

    if not isinstance(step.get("intent"), str) or not step["intent"].strip():
        raise ScenarioValidationError(f"steps[{index}].intent must be a non-empty string.")
    operation = step.get("operation")
    if not isinstance(operation, dict):
        raise ScenarioValidationError(f"steps[{index}].operation must be an object.")
    method = operation.get("method")
    if method not in {"tools/call", "resources/read", "resources/list", "tools/list", "prompts/list", "prompts/get"}:
        raise ScenarioValidationError(f"steps[{index}].operation.method is unsupported.")
    if method == "tools/call" and not isinstance(operation.get("tool_name"), str):
        raise ScenarioValidationError(f"steps[{index}].operation.tool_name is required for tools/call.")
    if method == "tools/call" and "arguments" in operation and not isinstance(operation["arguments"], dict):
        raise ScenarioValidationError(f"steps[{index}].operation.arguments must be an object.")
    if method == "resources/read" and not isinstance(operation.get("uri"), str):
        raise ScenarioValidationError(f"steps[{index}].operation.uri is required for resources/read.")
    if method == "prompts/get" and not isinstance(operation.get("prompt_name"), str):
        raise ScenarioValidationError(f"steps[{index}].operation.prompt_name is required for prompts/get.")
    ValidateAssertions(step.get("assertions", []), f"steps[{index}].assertions")
    ValidateExpectedError(step.get("expected_error"), f"steps[{index}].expected_error")
    ValidateAssessment(step.get("assessment"), f"steps[{index}].assessment")
    ValidateScreenshots(step.get("screenshots"), f"steps[{index}].screenshots")
    wait_until = step.get("wait_until")
    if wait_until is not None:
        if not isinstance(wait_until, dict):
            raise ScenarioValidationError(f"steps[{index}].wait_until must be an object.")
        if not isinstance(wait_until.get("operation"), dict):
            raise ScenarioValidationError(f"steps[{index}].wait_until.operation must be an object.")
        wait_operation = wait_until["operation"]
        wait_method = wait_operation.get("method")
        if wait_method not in {"tools/call", "resources/read", "resources/list", "tools/list", "prompts/list", "prompts/get"}:
            raise ScenarioValidationError(f"steps[{index}].wait_until.operation.method is unsupported.")
        ValidateAssertions(wait_until.get("assertions", []), f"steps[{index}].wait_until.assertions")
        for field in ("timeout_seconds", "interval_seconds"):
            value = wait_until.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or value < 1:
                raise ScenarioValidationError(f"steps[{index}].wait_until.{field} must be a positive integer.")


def ValidateAssessment(assessment: Any, path: str) -> None:
    """Validate optional agent reasoning retained for debugging and reproduction."""
    if assessment is None:
        return
    if not isinstance(assessment, dict):
        raise ScenarioValidationError(f"{path} must be an object.")
    for field in ("situation", "evidence", "decision"):
        value = assessment.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ScenarioValidationError(f"{path}.{field} must be a non-empty string.")
    candidates = assessment.get("candidate_actions")
    if not isinstance(candidates, list) or not all(isinstance(candidate, str) for candidate in candidates):
        raise ScenarioValidationError(f"{path}.candidate_actions must be an array of strings.")


def ValidateScreenshots(screenshots: Any, path: str) -> None:
    """Validate optional MCP screenshot references without pinning generated URIs."""
    if screenshots is None:
        return
    if not isinstance(screenshots, list):
        raise ScenarioValidationError(f"{path} must be an array.")
    for index, screenshot in enumerate(screenshots):
        if not isinstance(screenshot, dict):
            raise ScenarioValidationError(f"{path}[{index}] must be an object.")
        for field in ("purpose", "uri"):
            value = screenshot.get(field)
            if not isinstance(value, str) or not value.strip():
                raise ScenarioValidationError(f"{path}[{index}].{field} must be a non-empty string.")


def ValidateAssertions(assertions: Any, path: str) -> None:
    """Validate portable response checks that both runners and agents can interpret."""
    if not isinstance(assertions, list):
        raise ScenarioValidationError(f"{path} must be an array.")
    for index, assertion in enumerate(assertions):
        if not isinstance(assertion, dict):
            raise ScenarioValidationError(f"{path}[{index}] must be an object.")
        if not isinstance(assertion.get("pointer"), str) or not assertion["pointer"].startswith("/"):
            raise ScenarioValidationError(f"{path}[{index}].pointer must be an RFC 6901 pointer.")
        operator = assertion.get("operator")
        if operator not in {"exists", "equals", "contains"}:
            raise ScenarioValidationError(f"{path}[{index}].operator is unsupported.")
        if operator != "exists" and "value" not in assertion:
            raise ScenarioValidationError(f"{path}[{index}].value is required for {operator}.")


def EvaluateAssertions(document: Any, assertions: list[dict[str, Any]]) -> list[str]:
    """Return assertion failures without making dynamic runtime values part of the contract."""
    failures: list[str] = []
    for assertion in assertions:
        found, actual = ResolveJsonPointer(document, assertion["pointer"])
        operator = assertion["operator"]
        if operator == "exists":
            if not found:
                failures.append(f"{assertion['pointer']} does not exist")
        elif operator == "equals":
            if not found or actual != assertion["value"]:
                failures.append(f"{assertion['pointer']} did not equal the recorded value")
        elif not found or not isinstance(actual, (list, str, dict)) or assertion["value"] not in actual:
            failures.append(f"{assertion['pointer']} did not contain the recorded value")
    return failures


def ResolveJsonPointer(document: Any, pointer: str) -> tuple[bool, Any]:
    """Resolve RFC 6901 object and array paths without an external dependency."""
    current = document
    for token in pointer.lstrip("/").split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        if isinstance(current, dict) and token in current:
            current = current[token]
        elif isinstance(current, list) and token.isdecimal() and int(token) < len(current):
            current = current[int(token)]
        else:
            return False, None
    return True, current


def ValidateTerminationPolicy(policy: Any) -> None:
    """Keep adjustable stop criteria within conservative, meaningful bounds."""
    if not isinstance(policy, dict):
        raise ScenarioValidationError("termination_policy must be an object.")
    positive_fields = ("max_elapsed_seconds", "max_stalled_cycles", "final_wait_seconds", "max_retries_per_step")
    for field in positive_fields:
        value = policy.get(field)
        if not isinstance(value, int) or isinstance(value, bool) or value < 1:
            raise ScenarioValidationError(f"termination_policy.{field} must be a positive integer.")
    if not isinstance(policy.get("stop_server_on_stalled"), bool):
        raise ScenarioValidationError("termination_policy.stop_server_on_stalled must be boolean.")


def ValidateExpectedError(expected_error: Any, path: str) -> None:
    """Validate an intentional MCP tool failure recorded as a terminal outcome."""
    if expected_error is None:
        return
    if not isinstance(expected_error, dict):
        raise ScenarioValidationError(f"{path} must be an object.")
    message = expected_error.get("message_contains")
    if not isinstance(message, str) or not message.strip():
        raise ScenarioValidationError(f"{path}.message_contains must be a non-empty string.")
