"""Reusable declarative Inspector cases for server integration suites."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


class CaseDefinitionError(ValueError):
    """Raised when a suite invokes a case with invalid parameters."""


@dataclass(frozen=True)
class CaseDefinition:
    """A reusable Inspector operation with parameterized JSON assertions."""

    id: str
    operation: dict[str, Any]
    assertions: tuple[dict[str, Any], ...] = ()
    parameters: frozenset[str] = frozenset()

    def BuildOperation(self, values: dict[str, Any]) -> dict[str, Any]:
        """Resolve declared parameters while rejecting accidental extra values."""
        supplied = frozenset(values)
        if supplied != self.parameters:
            raise CaseDefinitionError(f"Case {self.id} expects {sorted(self.parameters)}, received {sorted(supplied)}.")
        return ResolveParameters(self.operation, values)

    def BuildAssertions(self, values: dict[str, Any]) -> list[dict[str, Any]]:
        """Resolve parameter values inside assertion definitions."""
        return ResolveParameters(list(self.assertions), values)


@dataclass(frozen=True)
class CaseInvocation:
    """One ordered invocation of a reusable case definition."""

    case_id: str
    parameters: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class Wait:
    """A bounded no-operation wait used for intentional game-state settling."""

    seconds: float

    def __post_init__(self) -> None:
        if not 0 <= self.seconds <= 300:
            raise CaseDefinitionError("Wait seconds must be between 0 and 300.")


@dataclass(frozen=True)
class Suite:
    """One version-controlled main-menu or saved-game integration sequence."""

    id: str
    save_name: str | None
    cases: tuple[CaseInvocation | Wait, ...]


def Param(name: str) -> str:
    """Mark a template value for resolution from a case invocation."""
    return "${" + name + "}"


def Run(case_id: str, **parameters: Any) -> CaseInvocation:
    """Construct an ordered parameterized case invocation."""
    return CaseInvocation(case_id, parameters)


def ResolveParameters(value: Any, parameters: dict[str, Any]) -> Any:
    """Resolve parameter markers recursively without mutating shared definitions."""
    if isinstance(value, str) and value.startswith("${") and value.endswith("}"):
        name = value[2:-1]
        if name not in parameters:
            raise CaseDefinitionError(f"Missing parameter: {name}")
        return parameters[name]
    if isinstance(value, list):
        return [ResolveParameters(item, parameters) for item in value]
    if isinstance(value, tuple):
        return tuple(ResolveParameters(item, parameters) for item in value)
    if isinstance(value, dict):
        return {key: ResolveParameters(item, parameters) for key, item in value.items()}
    return value
