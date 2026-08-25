"""Portable JSON-pointer assertions shared by Python test runners."""

from __future__ import annotations

from typing import Any


def EvaluateAssertions(document: Any, assertions: list[dict[str, Any]]) -> list[str]:
    """Return assertion failures without pinning dynamic runtime values."""
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
        elif not found or not ContainsAssertionValue(actual, assertion["value"]):
            failures.append(f"{assertion['pointer']} did not contain the recorded value")
    return failures


def ContainsAssertionValue(document: Any, expected: Any) -> bool:
    """Find a value in a scalar or nested JSON container."""
    if isinstance(document, dict):
        return expected in document or any(ContainsAssertionValue(value, expected) for value in document.values())
    if isinstance(document, list):
        return expected in document or any(ContainsAssertionValue(value, expected) for value in document)
    return isinstance(document, str) and expected in document


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
