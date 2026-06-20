$processName = "Morrowind"

$running = Get-Process -Name $processName -ErrorAction SilentlyContinue
if (-not $running) {
    Write-Host "[INFO] Morrowind process is not running." -ForegroundColor DarkCyan
    exit 0
}

Stop-Process -Name $processName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
    Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
}

if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
    Write-Host "[WARN] Failed to stop Morrowind process." -ForegroundColor Yellow
    exit 1
}

Write-Host "[INFO] Morrowind process has been stopped." -ForegroundColor DarkCyan
exit 0
