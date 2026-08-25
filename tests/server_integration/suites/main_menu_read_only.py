"""Run every read-only common case available before loading a saved game."""

from case_api import Run, Suite


SUITE = Suite(
    id="main-menu-read-only",
    save_name=None,
    cases=(
        Run("initialize"),
        Run("tools-available"),
        Run("resources-available"),
        Run("resource-templates-available"),
        Run("prompts-available"),
        Run("capabilities-fetch"),
        Run("menu-fetch"),
        Run("menu-actions-fetch"),
        Run("memory-root-read"),
        Run("prompt-get-loar"),
    ),
)
