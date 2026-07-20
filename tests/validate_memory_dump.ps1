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
$conversationActorCount = 0

function Convert-MemoryUriToPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $relativePath = ($Uri -replace '^morrowind://', '') -replace '/', '\'
    return [System.IO.Path]::GetFullPath((Join-Path $DumpRoot $relativePath))
}

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

$documentsByPath = @{}
foreach ($documentInfo in $documents) {
    $documentsByPath[[System.IO.Path]::GetFullPath($documentInfo.File).ToLowerInvariant()] = $documentInfo
}

$reachableDocuments = @()
$visitedPaths = @{}
$queue = [System.Collections.Queue]::new()
$rootPath = [System.IO.Path]::GetFullPath((Join-Path $DumpRoot "memory\index.json"))
$rootKey = $rootPath.ToLowerInvariant()
if ($documentsByPath.ContainsKey($rootKey)) {
    $queue.Enqueue($rootPath)
}
else {
    $issues.Add("Memory root document not found: file=$rootPath")
}

while ($queue.Count -gt 0) {
    $path = [string]$queue.Dequeue()
    $pathKey = $path.ToLowerInvariant()
    if ($visitedPaths.ContainsKey($pathKey)) {
        continue
    }
    $visitedPaths[$pathKey] = $true

    if (-not $documentsByPath.ContainsKey($pathKey)) {
        $issues.Add("Reachable document file not found: file=$path")
        continue
    }

    $documentInfo = $documentsByPath[$pathKey]
    $reachableDocuments += $documentInfo
    foreach ($link in @($documentInfo.Json.links)) {
        if ($link -and $link.uri -like "morrowind://memory/*") {
            $targetPath = Convert-MemoryUriToPath -Uri $link.uri
            $targetKey = $targetPath.ToLowerInvariant()
            if (-not $documentsByPath.ContainsKey($targetKey)) {
                $issues.Add("Broken link: parent=$($documentInfo.File) uri=$($link.uri)")
            }
            elseif (-not $visitedPaths.ContainsKey($targetKey)) {
                $queue.Enqueue($targetPath)
            }
        }
    }
}

foreach ($documentInfo in $reachableDocuments) {
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
        foreach ($field in @("id", "base_id", "reference_id", "identity_kind", "is_instance", "facts", "interaction")) {
            if ($null -eq $document.data.PSObject.Properties[$field]) {
                $issues.Add(("Actor missing data.{0}: file={1}" -f $field, $documentInfo.File))
            }
        }
        if ($null -ne $document.data.PSObject.Properties["interaction"]) {
            foreach ($field in @("state", "source_kinds", "activation_count", "conversation_count")) {
                if ($null -eq $document.data.interaction.PSObject.Properties[$field]) {
                    $issues.Add(("Actor missing data.interaction.{0}: file={1}" -f $field, $documentInfo.File))
                }
            }
        }
        if ($document.subject -and [string]::IsNullOrWhiteSpace($document.subject.tes3_type)) {
            $issues.Add("Actor missing subject.tes3_type: file=$($documentInfo.File)")
        }

        $sourceKinds = @($document.data.interaction.source_kinds)
        $activationCount = if ($null -ne $document.data.interaction.PSObject.Properties["activation_count"]) { [int]$document.data.interaction.activation_count } else { 0 }
        $conversationCount = if ($null -ne $document.data.interaction.PSObject.Properties["conversation_count"]) { [int]$document.data.interaction.conversation_count } else { 0 }
        if (
            $document.data.interaction.state -eq "conversed" -and
            $activationCount -gt 0 -and
            $conversationCount -gt 0 -and
            $sourceKinds -contains "activation_target_changed" -and
            $sourceKinds -contains "activate" -and
            $sourceKinds -contains "menu_dialog"
        ) {
            $conversationActorCount++
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
            $targetPath = Convert-MemoryUriToPath -Uri $link.uri
            if (-not $documentsByPath.ContainsKey($targetPath.ToLowerInvariant())) {
                $issues.Add("Broken link: parent=$($documentInfo.File) uri=$($link.uri)")
            }
        }
        if ($document.data_type -eq "actor_index" -and $link.rel -eq "actor") {
            $description = [string]$link.description
            foreach ($token in @("data_type=", "base_id=", "reference_id=", "identity_kind=", "interaction_state=")) {
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

$actorCount = @($reachableDocuments | Where-Object { $_.Json.data_type -in @("npc_summary", "creature_summary") }).Count
Write-Host "[PASSED] Memory dump traversal: documents=$($reachableDocuments.Count) actors=$actorCount conversationActors=$conversationActorCount root=$DumpRoot" -ForegroundColor Green
exit 0
