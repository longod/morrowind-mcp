"""Verify route discovery against the dedicated closed-door saved game."""

from __future__ import annotations

from typing import Any

from case_api import Scenario, Suite


def CallTool(endpoint: str, timeout: int, invoke, log, tool_name: str, arguments: dict[str, Any],
             allow_error: bool = False) -> dict[str, Any]:
    """Call a tool with native JSON argument values and retain the Inspector exchange."""
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


def VerifyRouteDiscovery(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Check the route node response and native JSON-array arguments without moving the player."""
    route = CallTool(endpoint, timeout, invoke, log, "mw-route-fetch", {})
    nodes = route["result"].get("structuredContent", {}).get("travel_nodes")
    if not isinstance(nodes, list) or not nodes:
        raise RuntimeError(f"mw-route-fetch returned no travel nodes: {route}")
    node = nodes[0]
    if node.get("kind") != "door" or not isinstance(node.get("reference_id"), str) or not isinstance(node.get("position"), dict):
        raise RuntimeError(f"mw-route-fetch returned an invalid travel node: {node}")
    destinations = node.get("destinations")
    if not isinstance(destinations, list) or not destinations:
        raise RuntimeError(f"mw-route-fetch returned a node without destinations: {node}")
    destination = destinations[0]
    if not isinstance(destination.get("cell_id"), str) or not isinstance(destination.get("marker_position"), dict):
        raise RuntimeError(f"mw-route-fetch returned an invalid destination: {destination}")

    actors = CallTool(endpoint, timeout, invoke, log, "mw-reference-fetch", {
        "category": ["actors"],
        "detail_level": "minimal",
        "scope": "nearby",
    })
    actor_arguments = " ".join(actors.get("_arguments", []))
    actor_entries = actors["result"].get("structuredContent", {}).get("actors")
    if not isinstance(actor_entries, list):
        raise RuntimeError(f"mw-reference-fetch did not return an actors array: {actors}")
    return {
        "travel_node": node,
        "actor_count": len(actor_entries),
        "array_argument": actor_arguments,
    }


def VerifyBlockedRoute(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Verify travel-node guidance is returned before an unreachable route can move the player."""
    route = CallTool(endpoint, timeout, invoke, log, "mw-route-fetch", {})
    node = route["result"]["structuredContent"]["travel_nodes"][0]
    destination = node["destinations"][0]
    before = CallTool(endpoint, timeout, invoke, log, "mw-player-fetch", {"detail_level": "minimal"})
    result = CallTool(endpoint, timeout, invoke, log, "mw-route-navigate", {
        "action": "navigate",
        "cell_id": destination["cell_id"],
        "position_x": destination["marker_position"]["x"],
        "position_y": destination["marker_position"]["y"],
        "position_z": destination["marker_position"]["z"],
    }, allow_error=True)
    response = result["result"]
    content = response.get("structuredContent", {})
    if response.get("isError") is not True:
        raise RuntimeError(f"mw-route-navigate unexpectedly started an unreachable route: {response}")
    if content.get("reason") not in {"requires_travel_activation", "no_path"}:
        raise RuntimeError(f"mw-route-navigate returned no route failure reason: {response}")
    if content.get("movement_started") is not False:
        raise RuntimeError(f"mw-route-navigate did not report movement_started=false: {response}")
    if not any(candidate.get("reference_id") == node["reference_id"] for candidate in content.get("travel_nodes", [])):
        raise RuntimeError(f"mw-route-navigate omitted the selected travel node: {response}")
    after = CallTool(endpoint, timeout, invoke, log, "mw-player-fetch", {"detail_level": "minimal"})
    if after["result"]["structuredContent"]["player"]["position"] != before["result"]["structuredContent"]["player"]["position"]:
        raise RuntimeError("mw-route-navigate changed player position despite reporting no route start.")
    return {"reason": content["reason"], "travel_node": node["reference_id"]}


def VerifyUnwalkableDestination(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Verify route discovery preserves false for an explicitly unreachable destination."""
    route = CallTool(endpoint, timeout, invoke, log, "mw-route-fetch", {})
    node = route["result"]["structuredContent"]["travel_nodes"][0]
    destination = node["destinations"][0]
    result = CallTool(endpoint, timeout, invoke, log, "mw-route-fetch", {
        "cell_id": destination["cell_id"],
        "position_x": destination["marker_position"]["x"],
        "position_y": destination["marker_position"]["y"],
        "position_z": destination["marker_position"]["z"],
    })
    content = result["result"].get("structuredContent", {})
    if content.get("destination_walkable") is not False:
        raise RuntimeError(f"mw-route-fetch did not preserve destination_walkable=false: {result}")
    return {"destination_walkable": content["destination_walkable"], "travel_node": node["reference_id"]}


def VerifyUnresolvedDestination(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Verify preflight navigation failures consistently report that movement did not start."""
    before = CallTool(endpoint, timeout, invoke, log, "mw-player-fetch", {"detail_level": "minimal"})
    result = CallTool(endpoint, timeout, invoke, log, "mw-route-navigate", {
        "action": "navigate",
        "cell_id": "Morrowind MCP Missing Test Cell",
        "position_x": 0,
        "position_y": 0,
        "position_z": 0,
    }, allow_error=True)
    response = result["result"]
    content = response.get("structuredContent", {})
    if response.get("isError") is not True or content.get("movement_started") is not False:
        raise RuntimeError(f"mw-route-navigate did not report a non-moving unresolved-cell failure: {response}")
    after = CallTool(endpoint, timeout, invoke, log, "mw-player-fetch", {"detail_level": "minimal"})
    if after["result"]["structuredContent"]["player"]["position"] != before["result"]["structuredContent"]["player"]["position"]:
        raise RuntimeError("mw-route-navigate changed player position for an unresolved destination cell.")
    return {"movement_started": content["movement_started"]}


SUITE = Suite(
    id="door0000",
    save_name="door0000",
    cases=(
        Scenario("route-discovery-and-array-arguments", VerifyRouteDiscovery),
        Scenario("unreachable-route-guidance", VerifyBlockedRoute),
        Scenario("unwalkable-destination-preserves-false", VerifyUnwalkableDestination),
        Scenario("unresolved-destination-does-not-move", VerifyUnresolvedDestination),
    ),
)