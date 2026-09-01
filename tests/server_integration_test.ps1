[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArguments
)

$ErrorActionPreference = "Stop"
$python = if ($env:MWMCP_PYTHON_EXE) { $env:MWMCP_PYTHON_EXE } else { Join-Path $HOME ".local\bin\python3.14.exe" }
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw "Python 3.14 was not found: $python. Set MWMCP_PYTHON_EXE to a Python 3.14 executable."
}

# The runner publishes GNU-style usage, so pass every GNU argument through unchanged.
# Map documented PowerShell spellings without allowing PowerShell type conversion to reinterpret values.
$powerShellToGnu = @{
    "-Suite" = "--suite"
    "-ListSuites" = "--list-suites"
    "-ListSaves" = "--list-saves"
    "-NoStop" = "--no-stop"
    "-NoForeground" = "--no-foreground"
    "-ReadinessTimeout" = "--readiness-timeout"
    "-CaseTimeout" = "--case-timeout"
}
$arguments = @("$PSScriptRoot\server_integration\run.py")
foreach ($argument in $CliArguments) {
    if ($powerShellToGnu.ContainsKey($argument)) {
        $arguments += $powerShellToGnu[$argument]
    }
    else {
        $arguments += $argument
    }
}
& $python @arguments
exit $LASTEXITCODE
