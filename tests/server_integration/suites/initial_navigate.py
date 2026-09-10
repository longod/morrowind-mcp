"""Verify state-changing route navigation from the initial exterior saved game."""

from __future__ import annotations

import time
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


def FindWalkingNode(endpoint: str, timeout: int, invoke, log, minimum_distance: float,
                    maximum_distance: float) -> dict[str, Any]:
    """Select one bounded exterior walking route from live route discovery."""
    route = CallTool(endpoint, timeout, invoke, log, "mw-route-fetch", {})
    nodes = route["result"].get("structuredContent", {}).get("travel_nodes")
    if not isinstance(nodes, list):
        raise RuntimeError(f"mw-route-fetch did not return travel nodes: {route}")
    for node in nodes:
        distance = node.get("walk_distance")
        if isinstance(distance, (int, float)) and minimum_distance <= distance <= maximum_distance and isinstance(node.get("position"), dict):
            return node
    raise RuntimeError(f"mw-route-fetch returned no walking route in the requested distance range: {nodes}")


def CellIdentity(cell: dict[str, Any]) -> str:
    """Return the graph identity format from a serialized player cell."""
    if cell.get("isInterior") is True:
        return "interior:" + cell["id"]
    return f"exterior:{cell['id']}:{cell['gridX']},{cell['gridY']}"


def FindCrossCellWalkingNode(endpoint: str, timeout: int, invoke, log, current_cell_id: str) -> dict[str, Any]:
    """Select a discovered walk-only travel node whose source is another loaded cell."""
    route = CallTool(endpoint, timeout, invoke, log, "mw-route-fetch", {})
    nodes = route["result"].get("structuredContent", {}).get("travel_nodes")
    if not isinstance(nodes, list):
        raise RuntimeError(f"mw-route-fetch did not return travel nodes: {route}")
    for node in nodes:
        if node.get("source_cell_id") != current_cell_id and isinstance(node.get("position"), dict):
            return node
    raise RuntimeError(f"mw-route-fetch returned no walk-reachable travel node outside {current_cell_id}: {nodes}")


def NavigateToNode(endpoint: str, timeout: int, invoke, log, node: dict[str, Any]) -> dict[str, Any]:
    """Start a walking route to one discovered travel-node position."""
    position = node["position"]
    result = CallTool(endpoint, timeout, invoke, log, "mw-route-navigate", {
        "action": "navigate",
        "position_x": position["x"],
        "position_y": position["y"],
        "position_z": position["z"],
    })
    content = result["result"].get("structuredContent", {})
    if not isinstance(content.get("route_node_count"), (int, float)) or not isinstance(content.get("waypoint_count"), (int, float)):
        raise RuntimeError(f"mw-route-navigate did not report route startup counts: {result}")
    return result


def DistanceBetween(first: dict[str, Any], second: dict[str, Any]) -> float:
    """Calculate world-space distance between two serialized player positions."""
    return sum((first[axis] - second[axis]) ** 2 for axis in ("x", "y", "z")) ** 0.5


def WaitForMovement(endpoint: str, timeout: int, invoke, log, initial_position: dict[str, Any]) -> float:
    """Poll for a material player-position change during the bounded navigation window."""
    for _ in range(5):
        time.sleep(2)
        current = CallTool(endpoint, timeout, invoke, log, "mw-player-fetch", {"detail_level": "minimal"})
        position = current["result"]["structuredContent"]["player"]["position"]
        distance = DistanceBetween(position, initial_position)
        if distance >= 16:
            return distance
    return 0


def WaitForCell(endpoint: str, timeout: int, invoke, log, expected_cell_id: str) -> dict[str, Any] | None:
    """Poll the bounded navigation window until the player enters the expected source cell."""
    for _ in range(10):
        time.sleep(2)
        current = CallTool(endpoint, timeout, invoke, log, "mw-player-fetch", {"detail_level": "minimal"})
        player = current["result"].get("structuredContent", {}).get("player", {})
        cell = player.get("cell")
        if isinstance(cell, dict) and CellIdentity(cell) == expected_cell_id:
            return player
    return None


def HasNearbyActor(endpoint: str, timeout: int, invoke, log) -> bool:
    """Inspect nearby actors and target state once before a lateral recovery attempt."""
    references = CallTool(endpoint, timeout, invoke, log, "mw-reference-fetch", {
        "category": ["actors"],
        "detail_level": "minimal",
        "scope": "nearby",
    })
    CallTool(endpoint, timeout, invoke, log, "mw-target-fetch", {"detail_level": "minimal"})
    actors = references["result"].get("structuredContent", {}).get("actors")
    if not isinstance(actors, list):
        raise RuntimeError(f"mw-reference-fetch did not return nearby actors: {references}")
    for actor in actors:
        distance = actor.get("distance", {}).get("units")
        if isinstance(distance, (int, float)) and distance <= 128:
            return True
    return False


def VerifyWalkOnlyRouteMovesPlayer(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Verify a stable exterior walk-only route starts input and materially moves the player."""
    node = FindWalkingNode(endpoint, timeout, invoke, log, 1800, 3500)
    before = CallTool(endpoint, timeout, invoke, log, "mw-player-fetch", {"detail_level": "minimal"})
    before_position = before["result"]["structuredContent"]["player"]["position"]
    NavigateToNode(endpoint, timeout, invoke, log, node)
    try:
        distance = WaitForMovement(endpoint, timeout, invoke, log, before_position)
        if distance >= 16:
            return {"distance_moved": distance, "travel_node": node["reference_id"], "recovery_used": False}
        if not HasNearbyActor(endpoint, timeout, invoke, log):
            raise RuntimeError("mw-route-navigate made no progress and no nearby actor justified lateral recovery.")
        CallTool(endpoint, timeout, invoke, log, "mw-player-action", {
            "action": "right",
            "how": "push",
            "seconds": 1,
        })
        NavigateToNode(endpoint, timeout, invoke, log, node)
        distance = WaitForMovement(endpoint, timeout, invoke, log, before_position)
        if distance >= 16:
            return {"distance_moved": distance, "travel_node": node["reference_id"], "recovery_used": True}
    finally:
        CallTool(endpoint, timeout, invoke, log, "mw-route-navigate", {"action": "cancel_navigation"}, allow_error=True)
    raise RuntimeError("mw-route-navigate started but did not materially move the player within ten seconds.")


def VerifyWalkOnlyRouteCrossesExteriorCell(endpoint: str, timeout: int, invoke, evaluate, log) -> dict[str, Any]:
    """Verify route navigation reaches a discovered travel node source in a neighboring exterior cell."""
    before = CallTool(endpoint, timeout, invoke, log, "mw-player-fetch", {"detail_level": "minimal"})
    initial_cell = before["result"]["structuredContent"]["player"]["cell"]
    initial_cell_id = CellIdentity(initial_cell)
    node = FindCrossCellWalkingNode(endpoint, timeout, invoke, log, initial_cell_id)
    source_cell_id = node.get("source_cell_id")
    if not isinstance(source_cell_id, str):
        raise RuntimeError(f"Cross-cell travel node did not include source_cell_id: {node}")
    NavigateToNode(endpoint, timeout, invoke, log, node)
    try:
        player = WaitForCell(endpoint, timeout, invoke, log, source_cell_id)
        if player is None:
            raise RuntimeError(f"mw-route-navigate did not enter cross-cell travel-node source {source_cell_id} within twenty seconds.")
        return {
            "travel_node": node["reference_id"],
            "initial_cell_id": initial_cell_id,
            "source_cell_id": source_cell_id,
            "final_position": player.get("position"),
        }
    finally:
        CallTool(endpoint, timeout, invoke, log, "mw-route-navigate", {"action": "cancel_navigation"}, allow_error=True)


SUITE = Suite(
    id="initial-navigate",
    save_name="initial0000",
    cases=(
        Scenario("walk-only-route-moves-player", VerifyWalkOnlyRouteMovesPlayer),
        Scenario("walk-only-route-crosses-exterior-cell", VerifyWalkOnlyRouteCrossesExteriorCell),
    ),
)
