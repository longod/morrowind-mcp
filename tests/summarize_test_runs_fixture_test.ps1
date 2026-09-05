[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$summarizeScriptPath = Join-Path $PSScriptRoot "summarize_test_runs.ps1"
$testContextScriptPath = Join-Path $PSScriptRoot "mwmcp_test_context.ps1"
$artifactsRoot = Join-Path ([IO.Path]::GetTempPath()) ("mwmcp-summary-fixture-" + [guid]::NewGuid().ToString("N"))
$timestamp = "20260905_120000"
$directory = Join-Path $artifactsRoot "server_test"

function Write-Fixture([string]$Path, [string]$Content) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Assert-Equal([object]$Actual, [object]$Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Write-Policy([string]$Content) {
    $path = Join-Path $artifactsRoot "policy.json"
    Write-Fixture $path $Content
    return $path
}

try {
    Write-Fixture (Join-Path $directory "inspector_$timestamp.log") @"
[RUN] --method tools/list
[EXIT] 0
--- STDERR ---
<empty>
--- STDOUT ---
{}

[PASSED] tools list
"@
    $mwsePath = Join-Path $directory "mwse_$timestamp.log"
    $rawMwseLog = @"
[morrowind-mcp (http_server) | server/http_server.lua | ERROR | 00:30.619] Failed to execute method tools/call
...object_summary.lua:362: Missing summary serializer for TES3 object type: miscItem
stack traceback:
    ...object_summary.lua:362: in function 'AnyObject'
[morrowind-mcp (http_server) | server/http_server.lua | ERROR | 00:30.619] json error: 500
HTTP/1.1 500 Internal Server Error
{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal error"},"id":3}
[morrowind-mcp (http_server) | server/http_server.lua | TRACE | 00:31.667] Request:
"@
    Write-Fixture $mwsePath $rawMwseLog

    $summary = & $summarizeScriptPath -TestType server_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot | ConvertFrom-Json

    Assert-Equal $summary.primary_status "passed" "Primary status should remain visible."
    Assert-Equal $summary.status "failed" "A traceback event should fail the summary."
    Assert-Equal $summary.mwse_analysis.counts.events 1 "Related traceback and HTTP error signals should be one event."
    Assert-Equal $summary.mwse_analysis.counts.fail 1 "Traceback event severity should be fail."
    Assert-Equal $summary.mwse_analysis.events[0].severity "fail" "Traceback rule should apply."
    Assert-Equal $summary.mwse_analysis.events[0].start_line 1 "Event should start at its ERROR header."
    Assert-Equal $summary.mwse_analysis.events[0].end_line 7 "Event should end before the next request."
    Assert-Equal (Get-Content -LiteralPath $mwsePath -Raw) $rawMwseLog "Summary must not modify the raw MWSE artifact."

    . $testContextScriptPath
    $summaryResult = Invoke-MwmcpTestRunSummary -TestType server_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot

    Assert-Equal $summaryResult.available $true "Summary helper should report an available summary."
    Assert-Equal $summaryResult.should_read $true "Available summary should be read for status and evidence."
    Assert-Equal $summaryResult.path (Join-Path $directory "summary_$timestamp.json") "Summary helper should return the timestamped summary path."

    $firstMatchPolicy = Write-Policy @"
{"default":"warn","rules":[{"pattern":"Missing summary serializer","severity":"warn"},{"pattern":"stack traceback:","severity":"fail"}]}
"@
    $firstMatchSummary = & $summarizeScriptPath -TestType server_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot -MwsePolicyPath $firstMatchPolicy | ConvertFrom-Json
    Assert-Equal $firstMatchSummary.status "passed" "The first matching policy rule should win."
    Assert-Equal $firstMatchSummary.mwse_analysis.events[0].severity "warn" "First-match policy severity should apply."

    $scopedPolicy = Write-Policy @"
{"default":"warn","rules":[{"pattern":"Failed to execute method","severity":"ignore","test_type":"sse_test"}]}
"@
    Write-Fixture (Join-Path $artifactsRoot "sse_test/sse_$timestamp.log") "[PASSED] Received SSE notification: notifications/message`n"
    Write-Fixture (Join-Path $artifactsRoot "sse_test/mwse_$timestamp.log") $rawMwseLog
    $unscopedSummary = & $summarizeScriptPath -TestType server_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot -MwsePolicyPath $scopedPolicy | ConvertFrom-Json
    $scopedSummary = & $summarizeScriptPath -TestType sse_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot -MwsePolicyPath $scopedPolicy | ConvertFrom-Json
    Assert-Equal $unscopedSummary.mwse_analysis.events[0].severity "warn" "A test-type rule must not apply to another test type."
    Assert-Equal $scopedSummary.mwse_analysis.events[0].severity "ignore" "A matching test-type rule should retain an ignored event."
    Assert-Equal $scopedSummary.mwse_analysis.counts.ignore 1 "Ignored event count should be recorded."

    Write-Fixture (Join-Path $directory "inspector_$timestamp.log") @"
[RUN] --method tools/list
[EXIT] 0
[FAILED] primary failure
"@
    $failedPrimarySummary = & $summarizeScriptPath -TestType server_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot | ConvertFrom-Json
    Assert-Equal $failedPrimarySummary.primary_status "failed" "Primary failures should be retained."
    Assert-Equal $failedPrimarySummary.status "failed" "MWSE analysis must not downgrade a primary failure."

    Write-Fixture (Join-Path $directory "inspector_$timestamp.log") @"
[RUN] --method tools/list
[EXIT] 0
[PASSED] tools list
"@
    Write-Fixture $mwsePath "unrelated output`nstack traceback:`n    frame`n[morrowind-mcp (http_server) | server/http_server.lua | TRACE | 00:31.667] Request:`n"
    $headerlessSummary = & $summarizeScriptPath -TestType server_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot | ConvertFrom-Json
    Assert-Equal $headerlessSummary.mwse_analysis.events[0].start_line 2 "Headerless tracebacks should start at their traceback line."
    Assert-Equal $headerlessSummary.mwse_analysis.events[0].end_line 3 "Tracebacks should stop before the next MCP log header."

    Write-Fixture $mwsePath "stack traceback:`n    frame`n[other-mod | module.lua | WARN | 00:31.667] Unrelated message`n"
    $otherModSummary = & $summarizeScriptPath -TestType server_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot | ConvertFrom-Json
    Assert-Equal $otherModSummary.mwse_analysis.events[0].end_line 2 "Tracebacks should stop before another mod's log header."

    $invalidPolicy = Write-Policy "{"
    $invalidPolicySummary = & $summarizeScriptPath -TestType server_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot -MwsePolicyPath $invalidPolicy | ConvertFrom-Json
    Assert-Equal $invalidPolicySummary.status "inconclusive" "Invalid policy should produce an inconclusive summary."
    if ([string]::IsNullOrWhiteSpace($invalidPolicySummary.mwse_analysis.policy_error)) {
        throw "Invalid policy should be recorded in the summary."
    }

    Write-Fixture $mwsePath "[morrowind-mcp (http_server) | server/http_server.lua | WARN | 00:31.000] EnumName found no mapping`n"
    $warningSummary = & $summarizeScriptPath -TestType server_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot | ConvertFrom-Json

    Assert-Equal $warningSummary.status "passed" "Unclassified MWSE events should not fail a passing primary result."
    Assert-Equal $warningSummary.mwse_analysis.counts.warn 1 "Unclassified event should use the default warning severity."

    Remove-Item -LiteralPath $mwsePath -Force
    $missingMwseSummary = & $summarizeScriptPath -TestType server_test -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot | ConvertFrom-Json
    Assert-Equal $missingMwseSummary.status "passed" "Missing MWSE artifacts should not change the primary verdict."
    Assert-Equal $missingMwseSummary.mwse_analysis.artifact.availability "missing" "Missing MWSE artifacts should be reported."

    Write-Fixture (Join-Path $artifactsRoot "unit_test/unitwind_$timestamp.log") "[UnitWind] MORROWIND-MCP.TEST PASSED`n"
    Write-Fixture (Join-Path $artifactsRoot "server_integration/inspector_$timestamp.log") "[RUN] --method tools/list`n[EXIT] 0`n[PASSED] tools list`n"
    Write-Fixture (Join-Path $artifactsRoot "completion_test/completion_$timestamp.log") "[PASSED] Completion responses are deterministic.`n"
    Write-Fixture (Join-Path $artifactsRoot "terrain_benchmark/result_$timestamp.json") '{"state":"ready","case_keys":["64"],"results":{"64":{"samples":1,"height":0}}}'
    foreach ($testType in "unit_test", "server_integration", "completion_test", "terrain_benchmark") {
        $smokeSummary = & $summarizeScriptPath -TestType $testType -RunTimestamp $timestamp -ArtifactsRoot $artifactsRoot | ConvertFrom-Json
        Assert-Equal $smokeSummary.status "passed" "Summary smoke test should pass for $testType."
        Assert-Equal $smokeSummary.version "1.1" "Summary schema version should identify MWSE analysis fields."
    }

    Write-Output "[PASSED] summarize_test_runs MWSE analysis fixture"
}
finally {
    if (Test-Path -LiteralPath $artifactsRoot) {
        Remove-Item -LiteralPath $artifactsRoot -Recurse -Force
    }
}
