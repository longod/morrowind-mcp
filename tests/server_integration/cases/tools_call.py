"""Reusable read-only tools/call cases."""

from case_api import CaseDefinition


CASES = {
    "capabilities-fetch": CaseDefinition(
        id="capabilities-fetch",
        operation={"method": "tools/call", "tool_name": "mw-capabilities-fetch", "arguments": {}},
        assertions=({"pointer": "/result/structuredContent/tools", "operator": "exists"},),
    ),
    "menu-fetch": CaseDefinition(
        id="menu-fetch",
        operation={"method": "tools/call", "tool_name": "mw-menu-fetch", "arguments": {}},
        assertions=({"pointer": "/result", "operator": "exists"},),
    ),
    "menu-actions-fetch": CaseDefinition(
        id="menu-actions-fetch",
        operation={"method": "tools/call", "tool_name": "mw-menu-fetch", "arguments": {"output_mode": "actions"}},
        assertions=({"pointer": "/result/structuredContent/actions", "operator": "exists"},),
    ),
    "player-fetch": CaseDefinition(
        id="player-fetch",
        operation={"method": "tools/call", "tool_name": "mw-player-fetch", "arguments": {}},
        assertions=({"pointer": "/result", "operator": "exists"},),
    ),
    "inventory-fetch": CaseDefinition(
        id="inventory-fetch",
        operation={"method": "tools/call", "tool_name": "mw-inventory-fetch", "arguments": {}},
        assertions=({"pointer": "/result/structuredContent/inventory", "operator": "exists"},),
    ),
    "reference-fetch": CaseDefinition(
        id="reference-fetch",
        operation={"method": "tools/call", "tool_name": "mw-reference-fetch", "arguments": {}},
        assertions=(
            {"pointer": "/result/structuredContent/serialization", "operator": "exists"},
            {"pointer": "/result/structuredContent/activators", "operator": "exists"},
            {"pointer": "/result/structuredContent/actors", "operator": "exists"},
            {"pointer": "/result/structuredContent/statics", "operator": "exists"},
        ),
    ),
    "reference-fetch-active": CaseDefinition(
        id="reference-fetch-active",
        operation={"method": "tools/call", "tool_name": "mw-reference-fetch", "arguments": {"scope": "active"}},
        assertions=({"pointer": "/result/structuredContent/serialization", "operator": "exists"},),
    ),
    "reference-fetch-minimal": CaseDefinition(
        id="reference-fetch-minimal",
        operation={"method": "tools/call", "tool_name": "mw-reference-fetch", "arguments": {"detail_level": "minimal"}},
        assertions=({"pointer": "/result/structuredContent/serialization/detailLevel", "operator": "equals", "value": "minimal"},),
    ),
    "reference-fetch-standard": CaseDefinition(
        id="reference-fetch-standard",
        operation={"method": "tools/call", "tool_name": "mw-reference-fetch", "arguments": {"detail_level": "standard"}},
        assertions=({"pointer": "/result/structuredContent/serialization/detailLevel", "operator": "equals", "value": "standard"},),
    ),
    "route-fetch": CaseDefinition(
        id="route-fetch",
        operation={"method": "tools/call", "tool_name": "mw-route-fetch", "arguments": {}},
        assertions=(
            {"pointer": "/result/structuredContent/travel_nodes", "operator": "exists"},
        ),
    ),
    "target-fetch": CaseDefinition(
        id="target-fetch",
        operation={"method": "tools/call", "tool_name": "mw-target-fetch", "arguments": {}},
        assertions=(
            {"pointer": "/result/structuredContent", "operator": "exists"},
            {"pointer": "/result/structuredContent/serialization", "operator": "exists"},
        ),
    ),
    "world-fetch": CaseDefinition(
        id="world-fetch",
        operation={"method": "tools/call", "tool_name": "mw-world-fetch", "arguments": {}},
        assertions=({"pointer": "/result/structuredContent/world", "operator": "exists"},),
    ),
}