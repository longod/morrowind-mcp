$ErrorActionPreference = "Stop"

if (-not ("MorrowindMcpInputCapture" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class MorrowindMcpInputCapture {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
}
"@
}

$activated = $false
$deadline = (Get-Date).AddSeconds(10)
do {
    $process = Get-Process -Name "Morrowind" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1
    if ($process) {
        try {
            if ((New-Object -ComObject WScript.Shell).AppActivate($process.Id)) {
                Write-Host "[INFO] Activated Morrowind window in foreground." -ForegroundColor Green
                $activated = $true
                break
            }
        }
        catch {
            Write-Host "[WARN] Failed to activate Morrowind window: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)

if (-not $activated) {
    Write-Host "[ERROR] Failed to activate an active Morrowind window." -ForegroundColor Red
    exit 1
}

$clientRect = [MorrowindMcpInputCapture+RECT]::new()
if (-not [MorrowindMcpInputCapture]::GetClientRect($process.MainWindowHandle, [ref]$clientRect)) {
    Write-Host "[ERROR] Failed to get the Morrowind client rectangle." -ForegroundColor Red
    exit 1
}

$clientCenter = [MorrowindMcpInputCapture+POINT]::new()
$clientCenter.X = [int](($clientRect.Right - $clientRect.Left) / 2)
$clientCenter.Y = [int](($clientRect.Bottom - $clientRect.Top) / 2)
if (-not [MorrowindMcpInputCapture]::ClientToScreen($process.MainWindowHandle, [ref]$clientCenter)) {
    Write-Host "[ERROR] Failed to resolve Morrowind client coordinates." -ForegroundColor Red
    exit 1
}

$originalCursor = [MorrowindMcpInputCapture+POINT]::new()
$restoreCursor = [MorrowindMcpInputCapture]::GetCursorPos([ref]$originalCursor)
if (-not [MorrowindMcpInputCapture]::SetCursorPos($clientCenter.X, $clientCenter.Y)) {
    Write-Host "[ERROR] Failed to move the cursor to the Morrowind client area." -ForegroundColor Red
    exit 1
}

[MorrowindMcpInputCapture]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
[MorrowindMcpInputCapture]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
if ($restoreCursor) {
    [MorrowindMcpInputCapture]::SetCursorPos($originalCursor.X, $originalCursor.Y) | Out-Null
}

Write-Host "[INFO] Sent client click to Morrowind to request mouse capture." -ForegroundColor Green
exit 0
