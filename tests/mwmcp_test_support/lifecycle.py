"""PowerShell-backed lifecycle support shared by Python test runners."""

from __future__ import annotations

import json
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


class LifecycleError(RuntimeError):
    """Raised when the local Morrowind MCP server cannot be prepared safely."""


def _InvokePowerShell(repo_root: Path, command: str) -> subprocess.CompletedProcess[str]:
    """Run a repository lifecycle command without duplicating PowerShell ownership."""
    return subprocess.run(["powershell.exe", "-NoProfile", "-Command", command], cwd=repo_root,
                          capture_output=True, check=False, encoding="utf-8", errors="replace")


def GetConfiguration(repo_root: Path) -> dict[str, Any]:
    """Resolve the existing PowerShell configuration contract as JSON."""
    command = f". '{repo_root / 'tests' / 'mwmcp_config.ps1'}'; Get-MwmcpConfig | ConvertTo-Json -Depth 5 -Compress"
    completed = _InvokePowerShell(repo_root, command)
    if completed.returncode != 0:
        raise LifecycleError(f"Failed to resolve configuration: {completed.stderr.strip()}")
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise LifecycleError("Configuration helper did not return JSON.") from error


def SetTestContext(repo_root: Path, mode: str, accept_disclaimer: bool, run_id: str | None = None,
                   save_name: str | None = None) -> None:
    """Create the shared test context through the PowerShell lifecycle helper."""
    integration = ""
    if run_id is not None:
        if save_name is None:
            integration = f" -ServerIntegrationRunId '{run_id}' -ServerIntegrationMainMenu"
        else:
            integration = f" -ServerIntegrationRunId '{run_id}' -ServerIntegrationSaveName '{save_name.replace("'", "''")}'"
    command = (f". '{repo_root / 'tests' / 'mwmcp_test_context.ps1'}'; "
               f"Set-MwmcpTestContext -UnitTestMode '{mode}' -AcceptDisclaimer ${str(accept_disclaimer).lower()}{integration}")
    completed = _InvokePowerShell(repo_root, command)
    if completed.returncode != 0:
        raise LifecycleError(f"Failed to set test context: {completed.stderr.strip()}")


def RemoveTestContext(repo_root: Path) -> None:
    """Remove only the shared context; retained integration status remains evidence."""
    completed = _InvokePowerShell(repo_root, f". '{repo_root / 'tests' / 'mwmcp_test_context.ps1'}'; Remove-MwmcpTestContext")
    if completed.returncode != 0:
        print(f"[WARN] Failed to remove test context: {completed.stderr.strip()}", file=sys.stderr)


def StartServer(repo_root: Path) -> None:
    """Launch Morrowind through the supported MO2 entry point."""
    completed = subprocess.run(["powershell.exe", "-NoProfile", "-File", str(repo_root / "tests" / "start_server_mo2.ps1")],
                               cwd=repo_root, capture_output=True, check=False, encoding="utf-8", errors="replace")
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


def ActivateMorrowindWindow(repo_root: Path) -> bool:
    """Best-effort foreground activation for input-driven integration cases."""
    command = (
        "$deadline = (Get-Date).AddSeconds(10); "
        "do { "
        "$process = Get-Process -Name Morrowind -ErrorAction SilentlyContinue | "
        "Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1; "
        "if ($process) { "
        "try { if ((New-Object -ComObject WScript.Shell).AppActivate($process.Id)) { exit 0 } } catch {} "
        "}; Start-Sleep -Milliseconds 500 "
        "} while ((Get-Date) -lt $deadline); exit 1"
    )
    return _InvokePowerShell(repo_root, command).returncode == 0


def StopServer(repo_root: Path) -> None:
    """Use the repository-supported Morrowind shutdown path."""
    subprocess.run(["powershell.exe", "-NoProfile", "-File", str(repo_root / "tests" / "stop_server.ps1")],
                   cwd=repo_root, capture_output=True, check=False, encoding="utf-8", errors="replace")
