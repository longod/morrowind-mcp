
$TargetIP = "localhost"
$TargetPort = 33427
$MaxTry = 10
$IntervalSeconds = 3
$McpJson = "mcp.json"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $ScriptDir

Write-Host "Starting the server..." -ForegroundColor Cyan
Start-Process "./start_server_mo2.bat" -NoNewWindow

$ProgressPreference = 'SilentlyContinue' # Suppress progress from Test-NetConnection
for ($TryCount = 1; $TryCount -le $MaxTry; $TryCount++) {
    # Test network connection and suppress warning/information logs
    $Result = Test-NetConnection -ComputerName $TargetIP -Port $TargetPort -WarningAction Ignore -InformationAction Ignore
    if ($Result.TcpTestSucceeded) {
        Write-Host "[SUCCESS] Started server is responding on ${TargetIP}:${TargetPort}." -ForegroundColor Green
        break
    }
    if ($TryCount -lt $MaxTry) {
        Start-Sleep -Seconds $IntervalSeconds
    }
}
if (-not $Result.TcpTestSucceeded) {
    Write-Host "[ERROR] Failed to connect to the server at ${TargetIP}:${TargetPort}." -ForegroundColor Red
    Pop-Location
    exit -1
}

# Write-Host "Running tests..." -ForegroundColor Cyan

$TestResult = 0

$Methods = @(
    "tools/list",
    "resources/list",
    "prompts/list",
    "resources/templates/list"
)
# "tools/call", "--tool-name", "-tool-arg",
# "resources/read", "--uri"
# "prompts/get", "--prompt-name",
# "logging/setLevel", "--log-level", "debug",

# https://github.com/modelcontextprotocol/inspector/pull/1337
# Assertion failed: !(handle->flags & UV_HANDLE_CLOSING), file src\win\async.c, line 94
# all tests always failed! FIX IT NOW!
function Invoke-MCPInspector {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $commandArguments = @(
        "--yes",
        "@modelcontextprotocol/inspector",
        "--cli",
        "--config", $McpJson
    )
    if ($Arguments) { $commandArguments += $Arguments }

    Write-Host "[RUN] $($Arguments -join ' ')" -ForegroundColor Cyan
    # Keep inspector output visible without leaking it into function return values.
    & npx @commandArguments 2>&1 | ForEach-Object { Write-Host $_ }
    $result = $LASTEXITCODE
    if ($result -ne 0) {
        Write-Host "[FAILED] $result" -ForegroundColor Red
    } else {
        Write-Host "[PASSED]" -ForegroundColor Green
    }
    return [int]$result
}

# test log level
$TestResult = $TestResult -bor (Invoke-MCPInspector "--method" "logging/setLevel" "--log-level" "trace")

# test list
foreach ($method in $Methods) {
    $TestResult = $TestResult -bor (Invoke-MCPInspector "--method" $method)
}

# TODO test tool/call
# TODO test resources/read
# TODO test prompts/get

Write-Host "Stopping the server..." -ForegroundColor Cyan
Start-Process "./stop_server.bat" -Wait -NoNewWindow

Pop-Location

exit $TestResult
