"""Exercise live dialogue retrieval and selection against the pub0000 saved game."""

from __future__ import annotations

import time
from typing import Any

from case_api import Scenario, Suite


def CallTool(endpoint: str, timeout: int, invoke, log, tool_name: str, arguments: dict[str, Any],
             allow_error: bool = False) -> dict[str, Any]:
    """Invoke a tool and retain its complete Inspector exchange in the suite artifact."""
    response = invoke(endpoint, {"method": "tools/call", "tool_name": tool_name, "arguments": arguments}, timeout)
    log(f"[RUN] {' '.join(response.arguments)}")
    if response.stderr:
        log("--- STDERR ---\n" + response.stderr.rstrip())
    if response.stdout:
        log("--- STDOUT ---\n" + response.stdout.rstrip())
    log(f"[EXIT] {response.exit_code}")
    if response.result.get("isError") is True and not allow_error:
        raise RuntimeError(f"{tool_name} returned isError=true: {response.result}")
    return response.document


def CheckDialogueSchemas(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Verify the published dialogue fetch/action schemas before exercising the saved game."""
    response = invoke(endpoint, {"method": "tools/list"}, timeout)
    log(f"[RUN] {' '.join(response.arguments)}")
    if response.stderr:
        log("--- STDERR ---\n" + response.stderr.rstrip())
    if response.stdout:
        log("--- STDOUT ---\n" + response.stdout.rstrip())
    log(f"[EXIT] {response.exit_code}")
    tools = {tool["name"]: tool for tool in response.document["result"]["tools"]}
    fetch = tools.get("mw-dialogue-fetch")
    action = tools.get("mw-dialogue-action")
    if fetch is None or action is None:
        raise RuntimeError("Dialogue tools are missing from tools/list.")
    expected = {"actor", "dialogues", "notifications", "choices", "topics", "services", "persuasion", "unknown_actions"}
    properties = fetch["outputSchema"].get("properties", {})
    if set(properties) != expected:
        raise RuntimeError(f"mw-dialogue-fetch output schema is incomplete: {fetch['outputSchema']}")
    if properties["actor"].get("type") != "object" or any(properties[key].get("type") != "array" for key in expected - {"actor"}):
        raise RuntimeError(f"mw-dialogue-fetch output schema has invalid property types: {fetch['outputSchema']}")
    required = action["inputSchema"].get("required", [])
    kinds = action["inputSchema"]["properties"].get("kind", {}).get("enum", [])
    if required != ["kind"] or kinds != ["topic", "choice", "service", "persuasion", "bye"]:
        raise RuntimeError(f"mw-dialogue-action selector schema is incomplete: {action['inputSchema']}")
    return {"tool_names": ["mw-dialogue-fetch", "mw-dialogue-action"]}


def FetchDialogue(endpoint: str, timeout: int, invoke, log) -> dict[str, Any]:
    """Fetch the live dialogue state and return its structured payload."""
    document = CallTool(endpoint, timeout, invoke, log, "mw-dialogue-fetch", {})
    return document["result"]["structuredContent"]


def Select(endpoint: str, timeout: int, invoke, log, entry: dict[str, Any], include_path: bool = True) -> dict[str, Any]:
    """Select an action using its semantic identity with an optional stale-state path guard."""
    arguments = {key: entry[key] for key in ("kind", "text") if key in entry}
    if include_path:
        arguments["menu_path"] = entry["menu_path"]
    document = CallTool(endpoint, timeout, invoke, log, "mw-dialogue-action", arguments)
    selected = document["result"]["structuredContent"].get("selected")
    if selected is None or selected.get("operation") != "ui_click" or selected.get("requires_follow_up") is not True:
        raise RuntimeError(f"mw-dialogue-action did not return selection evidence: {document}")
    return selected


def OpenDialogue(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Open the NPC directly ahead in pub0000 and wait for MenuDialog to become actionable."""
    unavailable = CallTool(endpoint, timeout, invoke, log, "mw-dialogue-fetch", {}, allow_error=True)
    if unavailable["result"].get("isError") is not True:
        raise RuntimeError("mw-dialogue-fetch was available before MenuDialog was opened.")
    CallTool(endpoint, timeout, invoke, log, "mw-player-action", {"action": "activate", "how": "tap"})
    for _ in range(12):
        document = CallTool(endpoint, timeout, invoke, log, "mw-dialogue-fetch", {}, allow_error=True)
        if document["result"].get("isError") is not True:
            return document["result"]["structuredContent"]
        time.sleep(0.25)
    raise RuntimeError("MenuDialog was not displayed after activating the pub0000 NPC.")


def ReadResource(endpoint: str, timeout: int, invoke, log, uri: str) -> None:
    """Perform a resource read while the dialogue menu remains open."""
    response = invoke(endpoint, {"method": "resources/read", "uri": uri}, timeout)
    log(f"[RUN] {' '.join(response.arguments)}")
    if response.stderr:
        log("--- STDERR ---\n" + response.stderr.rstrip())
    if response.stdout:
        log("--- STDOUT ---\n" + response.stdout.rstrip())
    log(f"[EXIT] {response.exit_code}")
    if response.result.get("contents") is None:
        raise RuntimeError(f"resources/read returned no contents for {uri}: {response.result}")


def FindDialogueNotification(value: Any, expected_prefix: str) -> str | None:
    """Return one MenuDialog notification text having the stable MCP ownership prefix."""
    if isinstance(value, dict):
        text = value.get("text")
        if value.get("name") == "MenuDialog_notify" and isinstance(text, str) and text.startswith(expected_prefix):
            return text
        for child in value.values():
            found = FindDialogueNotification(child, expected_prefix)
            if found is not None:
                return found
    if isinstance(value, list):
        for child in value:
            found = FindDialogueNotification(child, expected_prefix)
            if found is not None:
                return found
    return None


def FetchDialogueMenu(endpoint: str, timeout: int, invoke, log) -> dict[str, Any]:
    """Fetch the complete MenuDialog tree for notification-observation assertions."""
    document = CallTool(endpoint, timeout, invoke, log, "mw-menu-fetch", {"menu_name": "MenuDialog", "output_mode": "tree"})
    return document["result"].get("structuredContent", {}).get("menu", {})


def ExerciseDialogue(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Select a normal topic, then Beds and its blocking choice without opening secondary menus."""
    initial_content = OpenDialogue(endpoint, timeout, invoke, evaluate, log)
    if not isinstance(initial_content.get("actor"), dict) or not initial_content.get("dialogues"):
        raise RuntimeError(f"Initial dialogue fetch lacks actor or conversation text: {initial_content}")
    resource_uri = "morrowind://memory/index.json"
    mcp_notification_prefix = "Morrowind MCP:"
    ReadResource(endpoint, timeout, invoke, log, resource_uri)
    observed_notification = None
    for _ in range(12):
        observed_notification = FindDialogueNotification(FetchDialogueMenu(endpoint, timeout, invoke, log), mcp_notification_prefix)
        if observed_notification is not None:
            break
        time.sleep(0.25)
    else:
        raise RuntimeError("No MCP-owned MenuDialog notification was observed after resources/read; enable notification.resourcesRead.")
    after_resource_read = FetchDialogue(endpoint, timeout, invoke, log)
    if any(entry.get("text") == observed_notification for entry in after_resource_read.get("notifications", [])):
        raise RuntimeError("mw-dialogue-fetch exposed an MCP-owned dialogue notification.")
    content = after_resource_read
    for key, kind in (("topics", "topic"), ("services", "service"), ("persuasion", "persuasion")):
        for entry in content.get(key, []):
            if entry.get("kind") != kind or not entry.get("text") or not entry.get("menu_path"):
                raise RuntimeError(f"Invalid {kind} identity: {entry}")

    normal_topic = next((entry for entry in content.get("topics", []) if entry.get("text", "").lower() != "beds"), None)
    if normal_topic is None:
        raise RuntimeError("pub0000 exposes no non-Beds topic for the normal topic action check.")
    missing_text = CallTool(endpoint, timeout, invoke, log, "mw-dialogue-action", {"kind": "topic"}, allow_error=True)
    if missing_text["result"].get("isError") is not True:
        raise RuntimeError("mw-dialogue-action accepted a topic without text.")
    after_missing_text = FetchDialogue(endpoint, timeout, invoke, log)
    if [entry.get("menu_path") for entry in after_missing_text.get("topics", [])] != [entry.get("menu_path") for entry in content.get("topics", [])]:
        raise RuntimeError("A rejected topic without text changed the dialogue topic list.")
    stale = dict(normal_topic)
    stale["menu_path"] = normal_topic["menu_path"] + "/children/0"
    rejected = CallTool(endpoint, timeout, invoke, log, "mw-dialogue-action", stale, allow_error=True)
    if rejected["result"].get("isError") is not True:
        raise RuntimeError("mw-dialogue-action accepted a stale menu path.")
    after_stale = FetchDialogue(endpoint, timeout, invoke, log)
    if [entry.get("menu_path") for entry in after_stale.get("topics", [])] != [entry.get("menu_path") for entry in content.get("topics", [])]:
        raise RuntimeError("A rejected stale menu path changed the dialogue topic list.")
    Select(endpoint, timeout, invoke, log, normal_topic, include_path=False)
    time.sleep(0.5)
    after_normal = FetchDialogue(endpoint, timeout, invoke, log)
    if not after_normal.get("dialogues"):
        raise RuntimeError("Selecting a normal topic removed dialogue text.")

    beds = next((entry for entry in after_normal.get("topics", []) if entry.get("text", "").lower() == "beds"), None)
    if beds is None:
        raise RuntimeError("pub0000 no longer exposes the Beds topic after a normal topic selection.")
    Select(endpoint, timeout, invoke, log, beds)
    for _ in range(12):
        content = FetchDialogue(endpoint, timeout, invoke, log)
        choices = content.get("choices", [])
        yes = next((entry for entry in choices if entry.get("text", "").lower() == "yes"), None)
        no = next((entry for entry in choices if entry.get("text", "").lower() == "no"), None)
        if yes and no and yes.get("menu_path") != no.get("menu_path"):
            break
        time.sleep(0.25)
    else:
        raise RuntimeError("Beds did not expose distinct Yes and No blocking choices.")
    if any(entry.get("kind") not in {"header", "response"} for entry in content.get("dialogues", [])):
        raise RuntimeError(f"Dialogue history contains an unsupported entry kind: {content['dialogues']}")
    if not any(entry.get("kind") == "header" and entry.get("text") == beds["text"] for entry in content.get("dialogues", [])):
        raise RuntimeError("Beds did not produce a dialogue history header.")
    selected = Select(endpoint, timeout, invoke, log, no)
    for _ in range(12):
        after_choice = FetchDialogue(endpoint, timeout, invoke, log)
        if not after_choice.get("choices") and after_choice.get("topics"):
            break
        time.sleep(0.25)
    else:
        raise RuntimeError("Selecting No did not restore the normal dialogue topic state.")
    rejected_bye = CallTool(endpoint, timeout, invoke, log, "mw-dialogue-action", {"kind": "bye", "text": "not the bye button"}, allow_error=True)
    if rejected_bye["result"].get("isError") is not True:
        raise RuntimeError("mw-dialogue-action accepted a bye shortcut with mismatched text.")
    CallTool(endpoint, timeout, invoke, log, "mw-dialogue-action", {"kind": "bye"})
    for _ in range(12):
        closed = CallTool(endpoint, timeout, invoke, log, "mw-dialogue-fetch", {}, allow_error=True)
        if closed["result"].get("isError") is True:
            break
        time.sleep(0.25)
    else:
        raise RuntimeError("The bye shortcut did not close MenuDialog.")
    return {"initial": initial_content, "normal_topic": normal_topic, "beds": beds, "choice": selected}


SUITE = Suite(
    id="pub0000",
    save_name="pub0000",
    cases=(
        Scenario("dialogue-tool-schemas", CheckDialogueSchemas),
        Scenario("dialogue-fetch-and-action", ExerciseDialogue),
    ),
)