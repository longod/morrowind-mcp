"""Reusable JSON resources/read cases."""

from case_api import CaseDefinition


def JsonResourceCase(case_id: str, uri: str) -> CaseDefinition:
    """Build a read-only JSON resource case with the shared response contract."""
    return CaseDefinition(
        id=case_id,
        operation={"method": "resources/read", "uri": uri},
        assertions=({"pointer": "/result/contents/0/text", "operator": "exists"},),
    )


CASES = {
    "memory-root-read": CaseDefinition(
        id="memory-root-read",
        operation={"method": "resources/read", "uri": "morrowind://memory/index.json"},
        assertions=(
            {"pointer": "/result/contents/0/mimeType", "operator": "equals", "value": "application/json"},
            {"pointer": "/result/contents/0/text", "operator": "exists"},
        ),
    ),
    "memory-player-index-read": JsonResourceCase("memory-player-index-read", "morrowind://memory/player/index.json"),
    "memory-player-inventory-read": JsonResourceCase("memory-player-inventory-read", "morrowind://memory/player/inventory.json"),
    "memory-player-equipment-read": JsonResourceCase("memory-player-equipment-read", "morrowind://memory/player/equipment.json"),
    "memory-player-spellbook-read": JsonResourceCase("memory-player-spellbook-read", "morrowind://memory/player/spellbook.json"),
    "memory-player-progression-read": JsonResourceCase("memory-player-progression-read", "morrowind://memory/player/progression.json"),
    "memory-player-vitals-read": JsonResourceCase("memory-player-vitals-read", "morrowind://memory/player/vitals.json"),
    "memory-player-visited-cells-read": JsonResourceCase("memory-player-visited-cells-read", "morrowind://memory/player/visited-cells.json"),
    "memory-player-journal-read": JsonResourceCase("memory-player-journal-read", "morrowind://memory/player/journal.json"),
    "memory-player-quests-read": JsonResourceCase("memory-player-quests-read", "morrowind://memory/player/quests.json"),
}