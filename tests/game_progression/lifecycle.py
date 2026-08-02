"""Morrowind process lifecycle support for isolated progression tests."""

from __future__ import annotations

import json
import socket
import subprocess
import time
from pathlib import Path
from typing import Any


class LifecycleError(RuntimeError):
    """Raised when the local Morrowind MCP server cannot be prepared safely."""


def GetConfiguration(repo_root: Path) -> dict[str, Any]:
    """Resolve the existing PowerShell configuration contract as JSON."""
    command = (
        f". '{repo_root / 'tests' / 'mwmcp_config.ps1'}'; "
        "Get-MwmcpConfig | ConvertTo-Json -Depth 5 -Compress"
    )
    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", command],
        capture_output=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )
    if completed.returncode != 0:
        raise LifecycleError(f"Failed to resolve configuration: {completed.stderr.strip()}")
    try:
        configuration = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise LifecycleError("Configuration helper did not return JSON.") from error
    return configuration


def CreateServerTestSentinel(repo_root: Path) -> tuple[Path, bool]:
    """Disable skipMainMenu without removing a sentinel owned by another run."""
    sentinel = repo_root / "MWSE" / "mods" / "morrowind-mcp" / ".server-test-running"
    sentinel.parent.mkdir(parents=True, exist_ok=True)
    if sentinel.exists():
        return sentinel, False
    sentinel.touch()
    return sentinel, True


def StartServer(repo_root: Path) -> None:
    """Launch Morrowind through the existing MO2 entry point."""
    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-File", str(repo_root / "tests" / "start_server_mo2.ps1")],
        cwd=repo_root,
        capture_output=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )
    if completed.returncode not in {0, 1, 64}:
        raise LifecycleError(f"Server start script failed: {completed.stderr.strip()}")


def WaitForServer(host: str, port: int, timeout_seconds: int) -> None:
    """Wait until TCP proves the MCP endpoint can accept connections."""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=3):
                return
        except OSError:
            time.sleep(3)
    raise LifecycleError(f"Server did not become reachable at {host}:{port}.")


def StopServer(repo_root: Path) -> None:
    """Use the repository's supported Morrowind shutdown path."""
    subprocess.run(
        ["powershell.exe", "-NoProfile", "-File", str(repo_root / "tests" / "stop_server.ps1")],
        cwd=repo_root,
        capture_output=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )
