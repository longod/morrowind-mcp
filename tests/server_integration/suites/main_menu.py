"""MCP smoke checks that run without loading a save game."""

from case_api import Run, Suite


SUITE = Suite(
    id="main-menu",
    save_name=None,
    cases=(Run("tools-available"), Run("menu-fetch")),
)
