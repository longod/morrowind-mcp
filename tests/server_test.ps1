$MaxTry = 10
$IntervalSeconds = 3

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "mwmcp_config.ps1")

try {
    $Config = Get-MwmcpConfig
}
catch {
    Write-Host "[ERROR] Failed to resolve configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Workaround for Inspector issue/PR #1337:
# https://github.com/modelcontextprotocol/inspector/issues/1334
# https://github.com/modelcontextprotocol/inspector/pull/1337
# "Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)" が混在しても
# stdout が有効 JSON かつ実エラーが無ければ成功扱いにする。
function Invoke-MCPInspector {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $commandArguments = @(
        "--yes",
        "@modelcontextprotocol/inspector",
        "--cli",
        $Config.Connection.url,
        "--transport",
        "http"
    )
    if ($Arguments) { $commandArguments += $Arguments }

    Write-Host "[RUN] $($Arguments -join ' ')" -ForegroundColor Cyan
    # 判定のために標準出力(JSON本体)と標準エラー(エラーメッセージ)を分離して取得する。
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        & npx.cmd @commandArguments 1> $stdoutFile 2> $stderrFile
        $result = [int]$LASTEXITCODE

        $stdoutText = if (Test-Path $stdoutFile) { Get-Content -Path $stdoutFile -Raw } else { "" }
        $stderrText = if (Test-Path $stderrFile) { Get-Content -Path $stderrFile -Raw } else { "" }

        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            $stderrText -split "`r?`n" | ForEach-Object { if ($_ -ne "") { Write-Host $_ } }
        }
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
            $stdoutText -split "`r?`n" | ForEach-Object { if ($_ -ne "") { Write-Host $_ } }
        }

        # Inspector の既知問題で出るノイズ行を定義する。
        $assertionPattern = "Assertion failed: !\(handle->flags & UV_HANDLE_CLOSING\)"
        $knownExitLinePattern = "^Failed with exit code:\s*3221226505\s*$"
        $hasKnownAssertion = $stderrText -match $assertionPattern

        # stdout が正しい JSON として読めるなら、MCP メソッド自体は成功しているとみなせる。
        $hasValidJson = $false
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
            try {
                $null = $stdoutText | ConvertFrom-Json -ErrorAction Stop
                $hasValidJson = $true
            }
            catch {
                $hasValidJson = $false
            }
        }

        # 既知ノイズを除いた stderr が残る場合は、実際の失敗(例: Method not found)と判定する。
        $filteredStderrLines = @()
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            $filteredStderrLines = $stderrText -split "`r?`n" | Where-Object {
                $_ -and
                $_ -notmatch $assertionPattern -and
                $_ -notmatch $knownExitLinePattern
            }
        }
        $hasRealStderrError = $filteredStderrLines.Count -gt 0

        # TODO 成功は、jsonの精査も行いたい
        if ($result -eq 0) {
            Write-Host "[PASSED]" -ForegroundColor Green
            return 0
        }

        # Issue/PR #1337 のワークアラウンド:
        # exit code は 1 でも、stdout が有効 JSON かつ stderr が既知ノイズのみなら成功扱いにする。
        if ($result -eq 1 -and $hasKnownAssertion -and $hasValidJson -and -not $hasRealStderrError) {
            Write-Host "[PASSED] (Known UV handle assertion ignored)" -ForegroundColor Green
            return 0
        }

        Write-Host "[FAILED] $result" -ForegroundColor Red
        return $result
    }
    finally {
        Remove-Item -Path $stdoutFile -ErrorAction SilentlyContinue
        Remove-Item -Path $stderrFile -ErrorAction SilentlyContinue
    }
}

$TargetIP = $Config.Connection.host
$TargetPort = [int]$Config.Connection.port
$StartScriptPath = ".\start_server_mo2.ps1"
$StopScriptPath = ".\stop_server.ps1"

$ExitCode = 0

Push-Location $ScriptDir
try {
    if (-not (Test-Path -LiteralPath $StartScriptPath)) {
        Write-Host "[ERROR] $StartScriptPath was not found." -ForegroundColor Red
        $ExitCode = 1
        return
    }

    if (-not (Test-Path -LiteralPath $StopScriptPath)) {
        Write-Host "[ERROR] $StopScriptPath was not found." -ForegroundColor Red
        $ExitCode = 1
        return
    }

    & $StartScriptPath
    $StartExitCode = [int]$LASTEXITCODE
    if ($StartExitCode -ne 0) {
        Write-Host "[WARN] $StartScriptPath exited non-zero: start=$StartExitCode" -ForegroundColor Yellow
    }
    $ExitCode = $StartExitCode

    $ProgressPreference = 'SilentlyContinue' # Suppress progress from Test-NetConnection
    for ($TryCount = 1; $TryCount -le $MaxTry; $TryCount++) {
        # Test network connection and suppress warning/information logs
        $Result = Test-NetConnection -ComputerName $TargetIP -Port $TargetPort -WarningAction Ignore -InformationAction Ignore
        if ($Result.TcpTestSucceeded) {
            Write-Host "[INFO] Started server is responding on ${TargetIP}:${TargetPort}." -ForegroundColor Green
            break
        }
        if ($TryCount -lt $MaxTry) {
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
    if (-not $Result.TcpTestSucceeded) {
        Write-Host "[ERROR] Failed to connect to the server at ${TargetIP}:${TargetPort}." -ForegroundColor Red
        $ExitCode = $ExitCode -bor 1
        return
    }

    # TODO 成功を期待するテストのみなので、失敗を期待するテストも欲しい。無効な引数などで通信は成功するが、内容がエラーになることを確認する。
    # TODO luaからテストケースをある程度自動生成したい
    $TestCases = @(
        @("--method", "logging/setLevel", "--log-level", "trace"),
        @("--method", "tools/list"),
        @("--method", "resources/list"),
        @("--method", "prompts/list"),
        @("--method", "resources/templates/list"),
        @("--method", "tools/call", "--tool-name", "mw_take_screenshot", "--tool-arg", "fileName=test"),
        @("--method", "tools/call", "--tool-name", "mw_test_tool"), # no args
        @("--method", "resources/read", "--uri", "mwmcp://data-files/MWSE/mods/morrowind-mcp/temp/test.jpg"),
        @("--method", "prompts/get", "--prompt-name", "placeholder")
    )

    $TestResult = 0
    foreach ($Test in $TestCases) {
        $TestResult = $TestResult -bor (Invoke-MCPInspector $Test)
    }

    $ExitCode = $ExitCode -bor $TestResult

}
finally {
    Write-Host "[INFO] Stopping the server..." -ForegroundColor Cyan
    & $StopScriptPath
    if ([int]$LASTEXITCODE -ne 0) {
        Write-Host "[WARN] $StopScriptPath exit code: $LASTEXITCODE" -ForegroundColor Yellow
    }

    Pop-Location
}

exit $ExitCode
