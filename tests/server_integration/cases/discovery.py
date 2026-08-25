"""Reusable initialize and discovery method cases."""

from case_api import CaseDefinition


CASES = {
    "initialize": CaseDefinition(
        id="initialize",
        operation={"method": "initialize"},
        assertions=(
            {"pointer": "/result/protocolVersion", "operator": "exists"},
            {"pointer": "/result/serverInfo", "operator": "exists"},
            {"pointer": "/result/capabilities", "operator": "exists"},
        ),
    ),
    "tools-available": CaseDefinition(
        id="tools-available",
        operation={"method": "tools/list"},
        assertions=({"pointer": "/result/tools", "operator": "exists"},),
    ),
    "resources-available": CaseDefinition(
        id="resources-available",
        operation={"method": "resources/list"},
        assertions=(
            {"pointer": "/result/resources", "operator": "exists"},
            {"pointer": "/result/resources", "operator": "contains", "value": "morrowind://memory/index.json"},
        ),
    ),
    "resource-templates-available": CaseDefinition(
        id="resource-templates-available",
        operation={"method": "resources/templates/list"},
        assertions=(
            {"pointer": "/result/resourceTemplates", "operator": "exists"},
            {"pointer": "/result/resourceTemplates", "operator": "contains", "value": "morrowind://memory/{collection}/{entity_id}/{document}.json"},
            {"pointer": "/result/resourceTemplates", "operator": "contains", "value": "morrowind://screenshot/{file}"},
        ),
    ),
    "prompts-available": CaseDefinition(
        id="prompts-available",
        operation={"method": "prompts/list"},
        assertions=(
            {"pointer": "/result/prompts", "operator": "exists"},
            {"pointer": "/result/prompts", "operator": "contains", "value": "mw-loar"},
            {"pointer": "/result/prompts", "operator": "contains", "value": "mw-role"},
            {"pointer": "/result/prompts", "operator": "contains", "value": "mw-todo"},
            {"pointer": "/result/prompts", "operator": "contains", "value": "mw-translate"},
            {"pointer": "/result/prompts", "operator": "contains", "value": "mw-walkthrough"},
        ),
    ),
}