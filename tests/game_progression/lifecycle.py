"""Compatibility exports for progression scripts using shared lifecycle support."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from mwmcp_test_support.lifecycle import (
    ActivateMorrowindWindow,
    GetConfiguration,
    LifecycleError,
    RemoveTestContext,
    SetTestContext,
    StartServer,
    StopServer,
    WaitForServer,
)
