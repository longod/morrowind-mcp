param(
    [string]$DumpRoot
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "mwmcp_config.ps1")

try {
    $Config = Get-MwmcpConfig
}
catch {
    Write-Host "[ERROR] Failed to resolve configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($DumpRoot)) {
    $DumpRoot = Join-Path $Config.Paths.modDataDir "memory-dump"
}

$MemoryRoot = Join-Path $DumpRoot "memory"
if (-not (Test-Path -LiteralPath $MemoryRoot)) {
    Write-Host "[FAILED] Memory dump root not found: $MemoryRoot" -ForegroundColor Red
    exit 1
}

$issues = [System.Collections.Generic.List[string]]::new()
$documents = @()

foreach ($file in Get-ChildItem -LiteralPath $MemoryRoot -Recurse -Filter "*.json" -File) {
    try {
        $json = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
        $documents += [pscustomobject]@{
            File = $file.FullName
            Json = $json
        }
    }
    catch {
        $issues.Add("Invalid JSON: file=$($file.FullName) error=$($_.Exception.Message)")
    }
}

foreach ($documentInfo in $documents) {
    $document = $documentInfo.Json
    foreach ($field in @("schema_version", "type", "data_type", "title", "source", "data")) {
        if ($null -eq $document.PSObject.Properties[$field]) {
            $issues.Add(("Missing {0}: file={1}" -f $field, $documentInfo.File))
        }
    }

    if ($document.type -match '^memory\.(index|collection)$' -and $null -ne $document.data.PSObject.Properties["links"]) {
        $issues.Add("Index/collection duplicates links inside data: file=$($documentInfo.File)")
    }

    if ($document.data_type -in @("npc_summary", "creature_summary")) {
        foreach ($field in @("id", "base_id", "reference_id", "identity_kind", "is_instance", "reference")) {
            if ($null -eq $document.data.PSObject.Properties[$field]) {
                $issues.Add(("Actor missing data.{0}: file={1}" -f $field, $documentInfo.File))
            }
        }
        if ($document.subject -and [string]::IsNullOrWhiteSpace($document.subject.tes3_type)) {
            $issues.Add("Actor missing subject.tes3_type: file=$($documentInfo.File)")
        }
    }

    foreach ($link in @($document.links)) {
        if ($null -eq $link) {
            continue
        }
        if ([string]::IsNullOrWhiteSpace($link.uri)) {
            $issues.Add("Link is missing uri: file=$($documentInfo.File)")
            continue
        }
        if ($link.uri -like "morrowind://memory/*") {
            $relativePath = ($link.uri -replace '^morrowind://', '') -replace '/', '\'
            $targetPath = Join-Path $DumpRoot $relativePath
            if (-not (Test-Path -LiteralPath $targetPath)) {
                $issues.Add("Broken link: parent=$($documentInfo.File) uri=$($link.uri)")
            }
        }
        if ($document.data_type -eq "actor_index" -and $link.rel -eq "actor") {
            $description = [string]$link.description
            foreach ($token in @("data_type=", "base_id=", "reference_id=", "identity_kind=")) {
                if (-not $description.Contains($token)) {
                    $issues.Add("Actor link description missing $token parent=$($documentInfo.File) child=$($link.uri)")
                }
            }
        }
    }
}

if ($issues.Count -gt 0) {
    Write-Host "[FAILED] Memory dump traversal: issues=$($issues.Count)" -ForegroundColor Red
    foreach ($issue in ($issues | Select-Object -First 50)) {
        Write-Host "  $issue" -ForegroundColor DarkYellow
    }
    exit 1
}

$actorCount = @($documents | Where-Object { $_.Json.data_type -in @("npc_summary", "creature_summary") }).Count
Write-Host "[PASSED] Memory dump traversal: documents=$($documents.Count) actors=$actorCount root=$DumpRoot" -ForegroundColor Green
exit 0
