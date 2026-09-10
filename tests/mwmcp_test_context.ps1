# Provides one shared test context for every runner that launches Morrowind.
$script:TestContextDir = Join-Path $PSScriptRoot "..\MWSE\mods\morrowind-mcp\tests"
$script:TestContextPath = Join-Path $script:TestContextDir "test-context.json"
$script:LegacySentinelPaths = @(
    (Join-Path $PSScriptRoot "..\MWSE\mods\morrowind-mcp\.unit-test-targets"),
    (Join-Path $PSScriptRoot "..\MWSE\mods\morrowind-mcp\.server-test-running")
)

function Convert-ToFileUri {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        return ([System.Uri]::new($fullPath)).AbsoluteUri
    }
    catch {
        return $Path
    }
}

function Remove-MwmcpTestContext {
    # Cleanup is deliberately unconditional because test runners are serialized.
    if (Test-Path -LiteralPath $script:TestContextPath) {
        Remove-Item -LiteralPath $script:TestContextPath -Force -ErrorAction SilentlyContinue
        Write-Host "[INFO] Removed test context: $(Convert-ToFileUri -Path $script:TestContextPath)" -ForegroundColor DarkCyan
    }
}

function Invoke-MwmcpTestRunSummary {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("unit_test", "server_test", "server_integration", "sse_test", "completion_test", "terrain_benchmark")]
        [string]$TestType,
        [Parameter(Mandatory = $true)]
        [string]$RunTimestamp
        ,
        [string]$ArtifactsRoot = (Join-Path $PSScriptRoot "logs")
    )

    $summaryScriptPath = Join-Path $PSScriptRoot "summarize_test_runs.ps1"
        $summaryPath = Join-Path (Join-Path $ArtifactsRoot $TestType) "summary_$RunTimestamp.json"
    if (-not (Test-Path -LiteralPath $summaryScriptPath)) {
        Write-Host "[WARN] Test summary script was not found: $summaryScriptPath" -ForegroundColor Yellow
            return [pscustomobject]@{
                available = $false
                path = $summaryPath
                should_read = $false
                warning = "Test summary script was not found."
            }
    }

    try {
            & $summaryScriptPath -TestType $TestType -RunTimestamp $RunTimestamp -ArtifactsRoot $ArtifactsRoot | Out-Null
            if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
                $warning = "Test summary was not created."
                Write-Host "[WARN] Failed to generate $TestType summary: $warning" -ForegroundColor Yellow
                return [pscustomobject]@{
                    available = $false
                    path = $summaryPath
                    should_read = $false
                    warning = $warning
                }
        }

            Write-Host "[INFO] Test summary: $(Convert-ToFileUri -Path $summaryPath); read this file for status and evidence." -ForegroundColor DarkCyan
            return [pscustomobject]@{
                available = $true
                path = $summaryPath
                should_read = $true
                warning = $null
            }
    }
    catch {
        Write-Host "[WARN] Failed to generate $TestType summary: $($_.Exception.Message)" -ForegroundColor Yellow
            return [pscustomobject]@{
                available = $false
                path = $summaryPath
                should_read = $false
                warning = $_.Exception.Message
            }
    }
}

function Set-MwmcpTestContext {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("run", "run-and-exit", "skip")]
        [string]$UnitTestMode,
        [string[]]$UnitTestTargets = @(),
        [string]$UnitTestRunId,
        [bool]$SuppressAutoContinue = $true,
        [bool]$AcceptDisclaimer = $false,
        [string]$ServerIntegrationRunId,
        [string]$ServerIntegrationSaveName,
        [switch]$ServerIntegrationMainMenu
    )

    if (Test-Path -LiteralPath $script:TestContextPath) {
        $existing = Get-Content -LiteralPath $script:TestContextPath -Raw -ErrorAction SilentlyContinue
        $singleLineContent = ($existing -replace "\s+", " ").Trim()
        Write-Host "[WARN] Stale test context detected and replaced: $(Convert-ToFileUri -Path $script:TestContextPath); content=$singleLineContent" -ForegroundColor Yellow
        Remove-Item -LiteralPath $script:TestContextPath -Force -ErrorAction SilentlyContinue
    }

    foreach ($legacyPath in $script:LegacySentinelPaths) {
        if (Test-Path -LiteralPath $legacyPath) {
            Write-Host "[WARN] Legacy test sentinel detected and removed: $(Convert-ToFileUri -Path $legacyPath)" -ForegroundColor Yellow
            Remove-Item -LiteralPath $legacyPath -Force -ErrorAction SilentlyContinue
        }
    }

    New-Item -ItemType Directory -Path $script:TestContextDir -Force | Out-Null
    $context = [ordered]@{
        version = 1
        suppress_auto_continue = $SuppressAutoContinue
        accept_disclaimer = $AcceptDisclaimer
        unit_test = [ordered]@{
            mode = $UnitTestMode
            targets = @($UnitTestTargets)
            run_id = $UnitTestRunId
        }
    }
    if ($ServerIntegrationRunId) {
        if ($ServerIntegrationMainMenu -and $ServerIntegrationSaveName) {
            throw "ServerIntegrationMainMenu cannot be combined with ServerIntegrationSaveName."
        }
        $context.server_integration = [ordered]@{
            run_id = $ServerIntegrationRunId
            save_name = if ($ServerIntegrationMainMenu) { $null } else { $ServerIntegrationSaveName }
        }
    }
    $json = $context | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($script:TestContextPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[INFO] Created test context: $(Convert-ToFileUri -Path $script:TestContextPath); unit_test.mode=$UnitTestMode" -ForegroundColor DarkCyan
}
