"""MCP Inspector CLI adapter used by recorded progression scenarios."""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from typing import Any


class InspectorError(RuntimeError):
    """Raised when Inspector cannot provide a successful JSON-RPC result."""


@dataclass(frozen=True)
class InspectorResponse:
    """Captured Inspector result retained in run logs and assertions."""

    arguments: list[str]
    exit_code: int
    stdout: str
    stderr: str
    document: dict[str, Any]

    @property
    def result(self) -> dict[str, Any]:
        """Return a successful MCP result envelope."""
        result = self.document.get("result")
        if isinstance(result, dict):
            return result
        if "error" in self.document:
            message = self.document["error"].get("message", "unknown MCP error")
            raise InspectorError(f"MCP returned an error: {message}")
        if self.exit_code != 0:
            detail = self.stderr.strip() or self.stdout.strip()
            suffix = f" {detail}" if detail else ""
            raise InspectorError(f"Inspector exited with code {self.exit_code}.{suffix}")
        raise InspectorError("Inspector response has no result object.")


def FormatToolArgument(value: Any) -> str:
    """Preserve Inspector's scalar CLI syntax while encoding structured values as JSON."""
    if isinstance(value, str):
        return value
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(value, separators=(",", ":"))


def InvokeInspector(endpoint: str, operation: dict[str, Any], timeout_seconds: int) -> InspectorResponse:
    """Execute one recorded MCP operation through the Inspector CLI."""
    arguments = [
        "npx.cmd",
        "--yes",
        "@modelcontextprotocol/inspector",
        "--cli",
        endpoint,
        "--transport",
        "http",
        "--connect-timeout",
        str(timeout_seconds * 1000),
        "--format",
        "json",
        "--method",
        operation["method"],
    ]
    if operation["method"] == "tools/call":
        arguments.extend(["--tool-name", operation["tool_name"]])
        for name, value in operation.get("arguments", {}).items():
            arguments.extend(["--tool-arg", f"{name}={FormatToolArgument(value)}"])
    elif operation["method"] == "resources/read":
        arguments.extend(["--uri", operation["uri"]])
    elif operation["method"] == "prompts/get":
        arguments.extend(["--prompt-name", operation["prompt_name"]])

    completed = subprocess.run(
        arguments,
        capture_output=True,
        check=False,
        encoding="utf-8",
        errors="replace",
        timeout=timeout_seconds + 15,
    )
    try:
        document = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise InspectorError("Inspector did not return JSON.") from error
    if not isinstance(document, dict):
        raise InspectorError("Inspector response root must be an object.")
    return InspectorResponse(arguments, completed.returncode, completed.stdout, completed.stderr, document)
