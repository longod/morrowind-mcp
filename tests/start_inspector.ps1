$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "mwmcp_config.ps1")

try {
    $config = Get-MwmcpConfig
}
catch {
    Write-Host "[ERROR] Failed to resolve configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

& npx.cmd --yes @modelcontextprotocol/inspector@latest $config.Connection.url --transport http
exit [int]$LASTEXITCODE
