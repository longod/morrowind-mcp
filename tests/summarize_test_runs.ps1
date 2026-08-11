[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("unit_test", "server_test", "sse_test", "terrain_benchmark")]
    [string]$TestType,
    [ValidatePattern("^\d{8}_\d{6}$")]
    [string]$RunTimestamp,
    [string[]]$RequirePattern = @(),
    [string[]]$ForbidPattern = @(),
    [string]$ArtifactsRoot
)

$ErrorActionPreference = "Stop"
$workspaceRoot = Split-Path -Parent $PSScriptRoot

# Only saved, timestamped artifacts are inputs to a summary.
if (-not $ArtifactsRoot) {
    $ArtifactsRoot = Join-Path $PSScriptRoot "logs"
}
$ArtifactsRoot = [IO.Path]::GetFullPath($ArtifactsRoot)
$directory = Join-Path $ArtifactsRoot $TestType

$primaryMap = @{
    unit_test = @("unitwind", "log")
    server_test = @("inspector", "log")
    sse_test = @("sse", "log")
    terrain_benchmark = @("result", "json")
}
$primaryName, $primaryExtension = $primaryMap[$TestType]

function Relative([string]$Path) {
    return [IO.Path]::GetRelativePath($workspaceRoot, $Path).Replace("\", "/")
}

function Rule([string]$Id, [string]$Source, [string]$Pattern, [string]$Kind = "default", [string]$Role = "assertion", [bool]$IncludeDetails = $true) {
    try {
        $null = [regex]::new($Pattern, "IgnoreCase")
        return [pscustomobject]@{
            id = $Id
            source = $Source
            pattern = $Pattern
            kind = $Kind
            role = $Role
            include_details = $IncludeDetails
        }
    }
    catch {
        throw "Invalid $Kind regular expression '$Pattern': $($_.Exception.Message)"
    }
}

function CustomRule([string]$Value, [string]$Kind, [int]$Index) {
    $colon = $Value.IndexOf(":")
    if ($colon -lt 1) {
        throw "$Kind pattern '$Value' must use source:regex (for example primary:^\[PASSED\])."
    }

    $source = $Value.Substring(0, $colon).ToLowerInvariant()
    $pattern = $Value.Substring($colon + 1)
    if ($source -notin "primary", "inspector", "mwse", "result") {
        throw "Invalid $Kind pattern source '$source'."
    }
    if (-not $pattern) {
        throw "$Kind pattern '$Value' has an empty regular expression."
    }

    return Rule ("custom-{0}-{1}" -f $Kind.ToLowerInvariant(), $Index) $source $pattern $Kind.ToLowerInvariant()
}

function MatchRules([object[]]$Rules, [hashtable]$Paths) {
    return @($Rules | ForEach-Object {
        $matchingLines = if (Test-Path -LiteralPath $Paths[$_.source] -PathType Leaf) {
            @(Select-String -LiteralPath $Paths[$_.source] -Pattern $_.pattern)
        }
        else {
            @()
        }
        $numbers = if ($_.include_details) {
            @($matchingLines | ForEach-Object { $_.LineNumber })
        }
        else {
            @()
        }

        $result = [ordered]@{
            id = $_.id
            source = $_.source
            pattern = $_.pattern
            kind = $_.kind
            role = $_.role
            match_count = $matchingLines.Count
        }
        if ($_.include_details) {
            $result.line_numbers = @($numbers)
            $result.line_matches = @($matchingLines | Select-Object -First 10 | ForEach-Object {
                [pscustomobject]@{
                    line = $_.LineNumber
                    text = $_.Line.Substring(0, [Math]::Min(300, $_.Line.Length))
                }
            })
        }
        [pscustomobject]$result
    })
}
function Inspector([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ complete = $false; nonzero = 0 }
    }

    $runs = @(Select-String -LiteralPath $Path -Pattern "^\[RUN\]").Count
    $exits = @(Select-String -LiteralPath $Path -Pattern "^\[EXIT\]\s+-?\d+\s*$")
    $nonzero = @($exits | Where-Object { $_.Line -notmatch "^\[EXIT\]\s+0\s*$" }).Count
    return [pscustomobject]@{
        complete = ($runs -gt 0 -and $runs -eq $exits.Count)
        nonzero = $nonzero
    }
}

if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    throw "Artifact directory was not found: $directory"
}

# When the caller does not provide a timestamp, use the newest primary artifact.
if (-not $RunTimestamp) {
    $candidate = Get-ChildItem -LiteralPath $directory -File -Filter ("{0}_*.{1}" -f $primaryName, $primaryExtension) |
        Where-Object { $_.BaseName -match ("^{0}_\d{{8}}_\d{{6}}$" -f $primaryName) } |
        Sort-Object LastWriteTime, Name -Descending |
        Select-Object -First 1

    if (-not $candidate) {
        throw "No usable $TestType primary artifact was found in $directory."
    }

    $RunTimestamp = [regex]::Match($candidate.BaseName, "\d{8}_\d{6}$").Value
}

# Companion artifacts are accepted only when they share the primary run timestamp.
$paths = @{
    primary = Join-Path $directory ("{0}_{1}.{2}" -f $primaryName, $RunTimestamp, $primaryExtension)
    inspector = Join-Path $directory "inspector_$RunTimestamp.log"
    mwse = Join-Path $directory "mwse_$RunTimestamp.log"
    result = Join-Path $directory "result_$RunTimestamp.json"
}

$defaults = switch ($TestType) {
    "unit_test" {
        @(
            Rule "unit-failed" "primary" "^\[UnitWind\].*MORROWIND-MCP\..*\bFAILED\b"
            Rule "unit-pass" "primary" "^\[UnitWind\].*MORROWIND-MCP\..*\bPASSED\b"
            Rule "unitwind" "primary" "\[UnitWind\]" "default" "execution-evidence" $false
        )
    }
    "server_test" {
        @(
            Rule "server-passed" "primary" "\[PASSED\]"
            Rule "server-failed" "primary" "\[FAILED\]"
            Rule "server-skipped" "primary" "\[SKIPPED\]"
            Rule "server-inspector-nonzero" "primary" "^\[EXIT\]\s+(?!0\s*$)-?\d+\s*$"
        )
    }
    "sse_test" {
        @(
            Rule "sse-pass" "primary" "\[PASSED\]\s+Received SSE notification:\s+notifications/message"
            Rule "sse-failed" "primary" "\[(FAILED|ERROR)\]"
        )
    }
    "terrain_benchmark" {
        @(
            Rule "terrain-inspector-nonzero" "inspector" "^\[EXIT\]\s+(?!0\s*$)-?\d+\s*$"
        )
    }
}

$custom = @()
for ($i = 0; $i -lt $RequirePattern.Count; $i++) {
    $custom += CustomRule $RequirePattern[$i] "Require" ($i + 1)
}
for ($i = 0; $i -lt $ForbidPattern.Count; $i++) {
    $custom += CustomRule $ForbidPattern[$i] "Forbid" ($i + 1)
}

$ruleMatches = MatchRules (@($defaults) + @($custom)) $paths
$byId = @{}
$ruleMatches | ForEach-Object {
    $byId[$_.id] = $_
}

$status = "inconclusive"
$reasons = @()
$counts = [ordered]@{
    passed = 0
    failed = 0
    skipped = 0
}
$primaryExists = Test-Path -LiteralPath $paths.primary -PathType Leaf
 switch ($TestType) {
     "unit_test" {
        $counts.failed = $byId["unit-failed"].match_count
        $counts.passed = $byId["unit-pass"].match_count

        if (-not $primaryExists) {
            $reasons += "Primary UnitWind artifact is missing."
        }
        elseif ($counts.failed) {
            $status = "failed"
            $reasons += "UnitWind artifact contains FAILED evidence."
        }
        elseif ($counts.passed -and $byId["unitwind"].match_count) {
            $status = "passed"
            $reasons += "Suite pass and UnitWind evidence are present."
        }
        else {
            $reasons += "UnitWind artifact lacks terminal suite pass evidence."
        }
    }
    "server_test" {
        $inspect = Inspector $paths.primary
        $counts.passed = $byId["server-passed"].match_count
        $counts.failed = $byId["server-failed"].match_count + $byId["server-inspector-nonzero"].match_count
        $counts.skipped = $byId["server-skipped"].match_count

        if (-not $primaryExists) {
            $reasons += "Primary Inspector artifact is missing."
        }
        elseif (-not $inspect.complete) {
            $reasons += "Inspector artifact has missing or malformed [RUN]/[EXIT] blocks."
        }
        elseif ($counts.failed) {
            $status = "failed"
            $reasons += "Inspector artifact contains failure evidence."
        }
        elseif ($counts.skipped -and -not $counts.passed) {
            $status = "skipped"
            $reasons += "Saved evidence records only skipped cases."
        }
        elseif ($counts.passed) {
            $status = "passed"
            $reasons += "Saved evidence contains [PASSED] case markers."
        }
        else {
            $reasons += "Zero Inspector exits alone do not prove server test assertions passed."
        }
    }
    "sse_test" {
        $counts.failed = $byId["sse-failed"].match_count
        $counts.passed = $byId["sse-pass"].match_count

        if (-not $primaryExists) {
            $reasons += "Primary SSE artifact is missing."
        }
        elseif ($counts.failed) {
            $status = "failed"
            $reasons += "SSE artifact contains [FAILED] or [ERROR]."
        }
        elseif ($counts.passed) {
            $status = "passed"
            $reasons += "Required notifications/message pass marker is present."
        }
        else {
            $reasons += "SSE artifact lacks a terminal notifications/message pass marker."
        }
    }
    "terrain_benchmark" {
        $inspect = Inspector $paths.inspector
        $counts.failed += $byId["terrain-inspector-nonzero"].match_count

        if (-not $primaryExists) {
            $reasons += "Primary terrain result artifact is missing."
        }
        else {
            try {
                $result = Get-Content -LiteralPath $paths.result -Raw | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                $result = $null
                $reasons += "Terrain result JSON is invalid."
            }

            if ($result -and $result.state -eq "failed") {
                $status = "failed"
                $counts.failed++
                $reasons += "Terrain result explicitly reports state=failed."
            }
            elseif ($result) {
                $ready = $result.state -eq "ready"
                foreach ($resolution in "64", "128", "256") {
                    $entry = if ($result.results) { $result.results.PSObject.Properties[$resolution].Value }
                    if (-not $entry -or $entry.samples -lt 1 -or $null -eq $entry.height) {
                        $ready = $false
                    }
                }

                if ($ready) {
                    $status = "passed"
                    $counts.passed = 3
                    $reasons += "Terrain result has ready 64/128/256 measurements."
                }
                else {
                    $reasons += "Terrain result lacks ready 64/128/256 measurements."
                }
            }
        }

        if ($byId["terrain-inspector-nonzero"].match_count) {
            $status = "failed"
            $reasons += "Associated Inspector artifact contains a nonzero [EXIT]."
        }
    }
}

# Custom rules only add failure conditions; they cannot upgrade a default verdict.
$customFailures = @($custom | Where-Object {
    ($_.kind -eq "require" -and $byId[$_.id].match_count -eq 0) -or
    ($_.kind -eq "forbid" -and $byId[$_.id].match_count -gt 0)
})
if ($customFailures.Count) {
    $reasons += "Custom rule failure: $($customFailures.id -join ', ')."
    if ($status -in "passed", "skipped") {
        $status = "failed"
        $counts.failed++
    }
}

$sources = @("primary")
foreach ($source in "inspector", "mwse", "result") {
    $hasMatches = @($ruleMatches | Where-Object {
        $_.source -eq $source -and $_.match_count -gt 0
    }).Count -gt 0
    $isMissingRequiredSource = @($customFailures | Where-Object {
        $_.source -eq $source
    }).Count -gt 0
    if ($hasMatches -or $isMissingRequiredSource) {
        $sources += $source
    }
}

$evidence = @($sources | ForEach-Object {
    $source = $_
    $found = @()
    foreach ($ruleMatch in $ruleMatches) {
        if ($ruleMatch.source -eq $source -and $ruleMatch.match_count -gt 0) {
            $found += $ruleMatch
        }
    }

    $numbers = @($found.line_numbers | Select-Object -Unique)
    $previewsByLine = [ordered]@{}
    foreach ($ruleMatch in $found) {
        foreach ($lineMatch in $ruleMatch.line_matches) {
            $previewsByLine[$lineMatch.line] = $lineMatch
        }
    }
    $previews = @($previewsByLine.Values | Select-Object -First 10)

    [ordered]@{
        kind = $source
        path = Relative $paths[$source]
        exists = (Test-Path -LiteralPath $paths[$source] -PathType Leaf)
        matched_rule_ids = @($found | ForEach-Object { $_.id })
        line_numbers = @($numbers)
        previews = $previews
    }
})

$summary = [ordered]@{
    schema = "morrowind-mcp.test-run-summary"
    version = "1.0"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    test_type = $TestType
    run_timestamp = $RunTimestamp
    status = $status
    counts = $counts
    reasons = @($reasons)
    rules = @($ruleMatches | ForEach-Object {
        $rule = [ordered]@{
            id = $_.id
            source = $_.source
            pattern = $_.pattern
            kind = $_.kind
            role = $_.role
            match_count = $_.match_count
        }
        if ($_.include_details) {
            $rule.line_numbers = @($_.line_numbers)
        }
        [pscustomobject]$rule
    })
    evidence = $evidence
}

$json = $summary | ConvertTo-Json -Depth 12
Set-Content -LiteralPath (Join-Path $directory "summary_$RunTimestamp.json") -Value $json -Encoding UTF8
Write-Output $json
