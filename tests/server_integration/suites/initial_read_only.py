"""Run every remaining read-only common case after loading initial0000."""

from case_api import Run, Suite


SUITE = Suite(
    id="initial-read-only",
    save_name="initial0000",
    cases=(
        Run("player-fetch"),
        Run("inventory-fetch"),
        Run("reference-fetch"),
        Run("reference-fetch-active"),
        Run("reference-fetch-minimal"),
        Run("reference-fetch-standard"),
        Run("target-fetch"),
        Run("world-fetch"),
        Run("memory-player-index-read"),
        Run("memory-player-inventory-read"),
        Run("memory-player-equipment-read"),
        Run("memory-player-spellbook-read"),
        Run("memory-player-progression-read"),
        Run("memory-player-vitals-read"),
        Run("memory-player-visited-cells-read"),
        Run("memory-player-journal-read"),
        Run("memory-player-quests-read"),
        Run("prompt-get-role"),
        Run("prompt-get-todo"),
        Run("prompt-get-translate"),
        Run("prompt-get-walkthrough"),
    ),
)
