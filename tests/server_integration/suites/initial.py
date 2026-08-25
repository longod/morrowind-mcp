"""Baseline saved-game smoke checks using the explicit initial0000 save stem."""

from case_api import Run, Suite


SUITE = Suite(
    id="initial",
    save_name="initial0000",
    cases=(Run("tools-available"), Run("player-fetch")),
)
