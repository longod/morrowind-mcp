$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "mwmcp_config.ps1")

try {
    $config = Get-MwmcpConfig
}
catch {
    Write-Host "[ERROR] Failed to resolve configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$mo2ExeFile = $config.Paths.mo2ExeFile
$mo2Application = $config.Paths.mo2Application
$mo2Profile = $config.Paths.mo2Profile

if (-not (Test-Path -LiteralPath $mo2ExeFile)) {
    Write-Host "[ERROR] MO2 executable was not found: $mo2ExeFile" -ForegroundColor Red
    exit 1
}

$shortcut = "moshortcut://$mo2Profile`:$mo2Application"
Write-Host "[INFO] Launching: $mo2ExeFile $shortcut" -ForegroundColor DarkCyan
& $mo2ExeFile $shortcut
# 戻り値が0以外でも正常に起動している可能性があるようだ。1, 64など。
if ([int]$LASTEXITCODE -ne 0) {
    Write-Host "[WARN] MO2 launch command exited with code: $LASTEXITCODE" -ForegroundColor Yellow
}
exit $LASTEXITCODE
