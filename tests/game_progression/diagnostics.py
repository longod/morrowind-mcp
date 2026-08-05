"""Select low-cost state probes for terminal progression diagnostics."""

from __future__ import annotations

from typing import Any


DIAGNOSTIC_PROBES = {
    "mw-menu-action": ("mw-menu-fetch", "mw-player-fetch"),
    "mw-player-action": ("mw-player-fetch", "mw-target-fetch", "mw-reference-fetch"),
    "mw-player-navigate": ("mw-player-fetch", "mw-world-fetch", "mw-reference-fetch"),
}

MEMORY_DEBUG_DUMP_OPERATION = {
    "method": "tools/call",
    "tool_name": "mw-debug-action",
    "arguments": {"action": "memory:SaveDebugDocuments"},
}


def SuggestDiagnosticProbes(operation: dict[str, Any] | None) -> list[dict[str, Any]]:
    """Return at most two read-only probes relevant to one state-changing tool call."""
    if not isinstance(operation, dict) or operation.get("method") != "tools/call":
        return []
    tool_name = operation.get("tool_name")
    if not isinstance(tool_name, str):
        return []
    return [
        {"method": "tools/call", "tool_name": probe_name, "arguments": {}}
        for probe_name in DIAGNOSTIC_PROBES.get(tool_name, ())
    ]


def IsToolPublished(document: dict[str, Any], tool_name: str) -> bool:
    """Return whether a tools/list result exposes the named public tool."""
    result = document.get("result")
    if not isinstance(result, dict):
        return False
    tools = result.get("tools")
    if not isinstance(tools, list):
        return False
    return any(isinstance(tool, dict) and tool.get("name") == tool_name for tool in tools)
