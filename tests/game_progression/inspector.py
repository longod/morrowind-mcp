"""Compatibility exports for progression scripts using shared Inspector support."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from mwmcp_test_support.inspector import FormatToolArgument, InspectorError, InspectorResponse, InvokeInspector
