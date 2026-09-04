"""Exercise magic retrieval and UI selection against the dedicated magic test save."""

from __future__ import annotations

import time
from typing import Any

from case_api import Scenario, Suite


def CallTool(endpoint: str, timeout: int, invoke, log, tool_name: str, arguments: dict[str, Any],
             allow_error: bool = False) -> dict[str, Any]:
    """Invoke one tool while retaining its complete Inspector response in scenario details."""
    response = invoke(endpoint, {"method": "tools/call", "tool_name": tool_name, "arguments": arguments}, timeout)
    log(f"[RUN] {' '.join(response.arguments)}")
    if response.stderr:
        log("--- STDERR ---\n" + response.stderr.rstrip())
    if response.stdout:
        log("--- STDOUT ---\n" + response.stdout.rstrip())
    log(f"[EXIT] {response.exit_code}")
    result = response.result
    if result.get("isError") is True and not allow_error:
        raise RuntimeError(f"{tool_name} returned isError=true: {result}")
    return response.document


def FindAction(value: Any, name: str) -> dict[str, Any] | None:
    """Find an enabled click action whose displayed text matches a fetched magic entry exactly."""
    if isinstance(value, dict):
        actions = value.get("actions", value.get("actionable"))
        if value.get("text") == name and value.get("disabled") is not True and isinstance(actions, list) and "mouseClick" in actions:
            return value
        for child in value.values():
            found = FindAction(child, name)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = FindAction(child, name)
            if found:
                return found
    return None


def FindActionAtPath(value: Any, path: str) -> dict[str, Any] | None:
    """Find the enabled mouse-click action advertised at an exact serialized UI path."""
    if isinstance(value, dict):
        actions = value.get("actions", value.get("actionable"))
        if value.get("path") == path and value.get("disabled") is not True and isinstance(actions, list) and "mouseClick" in actions:
            return value
        for child in value.values():
            found = FindActionAtPath(child, path)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = FindActionAtPath(child, path)
            if found:
                return found
    return None


def CheckSpellToolSchemas(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Verify the published generic output schemas and spell-select selector contract."""
    response = invoke(endpoint, {"method": "tools/list"}, timeout)
    log(f"[RUN] {' '.join(response.arguments)}")
    if response.stderr:
        log("--- STDERR ---\n" + response.stderr.rstrip())
    if response.stdout:
        log("--- STDOUT ---\n" + response.stdout.rstrip())
    log(f"[EXIT] {response.exit_code}")
    tools = {tool["name"]: tool for tool in response.document["result"]["tools"]}
    fetch = tools.get("mw-spell-fetch")
    select = tools.get("mw-spell-select")
    if fetch is None or select is None:
        raise RuntimeError("Spell tools are missing from tools/list.")
    fetch_required = fetch["outputSchema"].get("required", [])
    if set(fetch_required) != {"spells", "powers", "magic_items"}:
        raise RuntimeError(f"mw-spell-fetch output required is incomplete: {fetch_required}")
    for key in ("spells", "powers", "magic_items"):
        if fetch["outputSchema"]["properties"].get(key, {}).get("type") != "array":
            raise RuntimeError(f"mw-spell-fetch output {key} is not a generic JSON array schema.")
    if select["outputSchema"]["properties"].get("selected", {}).get("type") != "object":
        raise RuntimeError("mw-spell-select selected is not a generic JSON object schema.")
    required = select["inputSchema"].get("required", [])
    categories = select["inputSchema"]["properties"].get("category", {}).get("enum", [])
    if required != ["category"] or categories != ["spell", "power", "magic_item"]:
        raise RuntimeError("mw-spell-select category selector schema is incomplete.")
    return {"tool_names": ["mw-spell-fetch", "mw-spell-select"]}


def OpenMagicMenu(endpoint: str, timeout: int, invoke, log) -> dict[str, Any]:
    """Open MenuMagic only through the established menuMode tap and wait for its live tree."""
    for _ in range(2):
        CallTool(endpoint, timeout, invoke, log, "mw-player-action", {"action": "menuMode", "how": "tap"})
        for _ in range(12):
            menu = CallTool(endpoint, timeout, invoke, log, "mw-menu-fetch", {
                "menu_name": "MenuMagic", "output_mode": "both",
            })
            content = menu["result"].get("structuredContent", {})
            if content.get("menu"):
                return content
            time.sleep(0.25)
        # A native selection can close MenuMagic without leaving menu mode; its next tap exits that mode.
        # The second tap is the same established action and opens MenuMagic from the now-active game view.
    raise RuntimeError("MenuMagic was not displayed after mw-player-action menuMode tap.")


def SelectFetchedMagic(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Exercise fetch filtering and select one live clickable entry from every fetched category."""
    unavailable = CallTool(endpoint, timeout, invoke, log, "mw-spell-select", {
        "category": "spell", "id": "missing",
    }, allow_error=True)
    unavailable_result = unavailable["result"]
    if unavailable_result.get("isError") is not True:
        raise RuntimeError("mw-spell-select was available before MenuMagic was opened.")
    expected_guidance = (
        "Unavailable because: The game is not in menu mode.\n"
        "Available when: The game is in menu mode.\n"
        "Related tool: `mw-spell-fetch` reports the current player spellbook state.\n"
        "Related tool: `mw-menu-fetch` reports the current MenuMagic UI state and menu paths."
    )
    unavailable_text = unavailable_result.get("content", [{}])[0].get("text")
    unavailable_guidance = unavailable_result.get("structuredContent", {}).get("guidance")
    if unavailable_text != expected_guidance or unavailable_guidance != expected_guidance:
        raise RuntimeError(f"mw-spell-select unavailable guidance has an unexpected format: {unavailable_result}")

    fetch = CallTool(endpoint, timeout, invoke, log, "mw-spell-fetch", {})
    content = fetch["result"]["structuredContent"]
    for key, category in (("spells", "spell"), ("powers", "power"), ("magic_items", "magic_item")):
        entries = content.get(key)
        if not isinstance(entries, list) or not entries:
            raise RuntimeError(f"mw-spell-fetch returned no {key} for magictes0000.")
        for entry in entries:
            if entry.get("category") != category or not entry.get("id") or not entry.get("name"):
                raise RuntimeError(f"mw-spell-fetch {key} entry lacks a round-trippable identity: {entry}")
    for item in content["magic_items"]:
        if item.get("enchantmentCastType") not in {"castOnce", "onUse"}:
            raise RuntimeError(f"mw-spell-fetch included a non-castable magic item: {item}")

    menu_content = OpenMagicMenu(endpoint, timeout, invoke, log)
    stable_entry, stable_action = next((
        (entry, FindAction(menu_content, entry["name"]))
        for entry in content["spells"]
        if FindAction(menu_content, entry["name"]) is not None
    ), (None, None))
    if stable_entry is None or stable_action is None:
        raise RuntimeError("No enabled MenuMagic spell click action was found for rejection checks.")
    for arguments in (
        {"category": "spell"},
        {"category": "spell", "id": stable_entry["id"], "menu_path": "not-a-menu-path"},
        {"category": "spell", "id": stable_entry["id"] + "-missing"},
    ):
        rejected = CallTool(endpoint, timeout, invoke, log, "mw-spell-select", arguments, allow_error=True)
        if rejected["result"].get("isError") is not True:
            raise RuntimeError(f"mw-spell-select accepted invalid selection arguments: {arguments}")
        if rejected["result"].get("structuredContent", {}).get("selected") is not None:
            raise RuntimeError(f"mw-spell-select reported a selection for rejected arguments: {arguments}")
    menu_after_rejection = CallTool(endpoint, timeout, invoke, log, "mw-menu-fetch", {
        "menu_name": "MenuMagic", "output_mode": "both",
    })["result"].get("structuredContent", {})
    if FindActionAtPath(menu_after_rejection, stable_action["path"]) is None:
        raise RuntimeError("Zero-match spell selection clicked or closed MenuMagic.")

    selected = []
    for key, category in (("spells", "spell"), ("powers", "power"), ("magic_items", "magic_item")):
        menu_content = OpenMagicMenu(endpoint, timeout, invoke, log)
        match = next(((entry, FindAction(menu_content, entry["name"])) for entry in content[key]
                      if FindAction(menu_content, entry["name"]) is not None), None)
        if match is None:
            raise RuntimeError(f"No enabled MenuMagic click action was found for any fetched {category}.")
        entry, action = match
        arguments = {
            "category": category,
            "id": entry["id"],
            "name": entry["name"],
        }
        if category != "spell":
            arguments["menu_path"] = action["path"]
        response = CallTool(endpoint, timeout, invoke, log, "mw-spell-select", arguments)
        result = response["result"]["structuredContent"]["selected"]
        expected = {
            "category": category,
            "id": entry["id"],
            "name": entry["name"],
            "operation": "ui_click",
            "requires_follow_up": True,
        }
        if {key: result.get(key) for key in expected} != expected:
            raise RuntimeError(f"mw-spell-select returned unexpected selection evidence: {result}")
        if FindActionAtPath(menu_content, result.get("menu_path", "")) is None:
            raise RuntimeError(f"mw-spell-select returned a non-clickable selection path: {result}")
        selected.append(result)
        # The native click closes MenuMagic on the next UI frame before menuMode can open it again.
        time.sleep(0.5)
    return {"fetch": content, "selected": selected}


SUITE = Suite(
    id="magictes0000",
    save_name="magictes0000",
    cases=(
        Scenario("spell-tool-schemas", CheckSpellToolSchemas),
        Scenario("spell-fetch-and-select", SelectFetchedMagic),
    ),
)
