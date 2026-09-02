"""Discover suite files and reusable case definitions without a central registry."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from case_api import CaseDefinition, CaseDefinitionError, CaseInvocation, Scenario, Suite


def _LoadModule(path: Path, prefix: str):
    specification = importlib.util.spec_from_file_location(f"{prefix}_{path.stem}", path)
    if specification is None or specification.loader is None:
        raise CaseDefinitionError(f"Cannot load {path}.")
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    specification.loader.exec_module(module)
    return module


def LoadCases(root: Path) -> dict[str, CaseDefinition]:
    """Load CASES mappings and reject duplicate reusable case IDs."""
    cases: dict[str, CaseDefinition] = {}
    for path in sorted((root / "cases").glob("*.py")):
        if path.name == "__init__.py":
            continue
        module = _LoadModule(path, "server_integration_cases")
        for case_id, definition in getattr(module, "CASES", {}).items():
            if not isinstance(definition, CaseDefinition) or definition.id != case_id or case_id in cases:
                raise CaseDefinitionError(f"Invalid or duplicate case definition: {case_id}")
            cases[case_id] = definition
    return cases


def LoadSuites(root: Path, cases: dict[str, CaseDefinition]) -> dict[str, Suite]:
    """Load one SUITE per file and validate IDs, save stems, and case references."""
    suites: dict[str, Suite] = {}
    for path in sorted((root / "suites").glob("*.py")):
        if path.name == "__init__.py":
            continue
        suite = getattr(_LoadModule(path, "server_integration_suites"), "SUITE", None)
        if not isinstance(suite, Suite) or not suite.id or suite.id in suites:
            raise CaseDefinitionError(f"Invalid or duplicate suite in {path.name}")
        if suite.save_name is not None and (not suite.save_name or suite.save_name.lower() in {"quicksave", "quiksave"} or ".ess" in suite.save_name.lower()):
            raise CaseDefinitionError(f"Suite {suite.id} has an unsafe save name.")
        for invocation in suite.cases:
            if isinstance(invocation, CaseInvocation):
                if invocation.case_id not in cases:
                    raise CaseDefinitionError(f"Suite {suite.id} references unknown case {invocation.case_id}.")
                cases[invocation.case_id].BuildOperation(invocation.parameters)
            elif not isinstance(invocation, Scenario) and invocation.__class__.__name__ != "Wait":
                raise CaseDefinitionError(f"Suite {suite.id} has an invalid invocation.")
        suites[suite.id] = suite
    return suites
