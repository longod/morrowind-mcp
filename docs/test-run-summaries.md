# Test Run Summaries

`tests/summarize_test_runs.ps1` creates `summary_<timestamp>.json` from saved artifacts. Read that summary before inspecting raw logs. It supports `unit_test`, `server_test`, `server_integration`, `sse_test`, `completion_test`, and `terrain_benchmark`.

| Test type | Primary artifact | Companion artifacts |
| --- | --- | --- |
| `unit_test` | `unitwind_<timestamp>.log` | `mwse_<timestamp>.log` |
| `server_test` | `inspector_<timestamp>.log` | `mwse_<timestamp>.log` |
| `server_integration` | `inspector_<timestamp>.log` | `mwse_<timestamp>.log`, `result_<timestamp>.json` |
| `sse_test` | `sse_<timestamp>.log` | `mwse_<timestamp>.log` |
| `completion_test` | `completion_<timestamp>.log` | `mwse_<timestamp>.log` |
| `terrain_benchmark` | `result_<timestamp>.json` | `inspector_<timestamp>.log`, `mwse_<timestamp>.log` |

Artifacts sharing one timestamp describe one run. `mwse_<timestamp>.log` is a raw copy of the log from that Morrowind execution; summary generation never modifies it. Game progression uses its separate `run.json` and `MWSE.log` contract.

Test runners suppress the full JSON that the summarizer emits to stdout. They report only the saved summary path; read that file for the verdict and evidence. If summary generation does not create its expected file, the runner reports a warning and no summary is available to read.

## Reading Results

Summary version `1.1` adds `primary_status` and `mwse_analysis`. `primary_status` is the existing verdict from the primary test artifact. `status` is the final verdict after MWSE analysis. A primary failure is never downgraded. An MWSE event classified as `fail` can change a passing or skipped primary result to `failed`.

`counts` remains the count of primary test cases. `mwse_analysis.counts` reports independent raw-log event counts. `mwse_analysis.events` identifies each event with its line span, matched rule, severity, and short evidence preview.

`warn` and `ignore` events remain visible in the summary but do not change `status`. A missing MWSE artifact is recorded as `missing` and does not change the primary verdict during the initial rollout.

An invalid MWSE policy produces an `inconclusive` summary unless the primary artifact already failed; the policy error is recorded in `mwse_analysis.policy_error`. An MWSE parser failure is recorded separately as `mwse_analysis.analysis_error`.

## MWSE Policy

[tests/mwse_log_policy.json](../tests/mwse_log_policy.json) controls only MWSE event classification. It is intentionally small:

```json
{
  "default": "warn",
  "rules": [
    { "pattern": "stack traceback:", "severity": "fail" }
  ]
}
```

Rules are tested in order and the first matching regular expression wins. `test_type` is optional when a rule is specific to one runner. Valid severities are `fail`, `warn`, and `ignore`; unmatched events use `default`. Add a narrow rule only after inspecting the saved event evidence from a real run.

The parser groups a Morrowind MCP traceback and subsequent HTTP 5xx or JSON-RPC `-32603` response into one event. It also records standalone Morrowind MCP `ERROR` or `WARN` entries. This avoids treating a single request exception as multiple failures while retaining startup and diagnostic messages for review.
