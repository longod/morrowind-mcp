# Resolve the directory that contains this helper so we can read repo-root files reliably.
$script:LoaderDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Walk a dotted path such as paths.mo2ExeFile and return the nested value if it exists.
function Get-NestedValue {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    $node = $Object
    foreach ($segment in $Path) {
        # Treat missing intermediate objects as a hard miss instead of throwing.
        if ($null -eq $node) {
            return $null
        }
        $prop = $node.PSObject.Properties[$segment]
        # Stop early when a property is absent.
        if ($null -eq $prop) {
            return $null
        }
        $node = $prop.Value
    }
    return $node
}

# Return the first candidate that is present and not just whitespace.
function Get-FirstNonEmpty {
    param(
        [object[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        # Null values are ignored so later fallbacks can be considered.
        if ($null -eq $candidate) {
            continue
        }
        $text = [string]$candidate
        # Empty strings are treated as unset.
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }
    }
    return $null
}

# Resolve one config value using the shared precedence: env, then local, then defaults.
function Resolve-ConfigValue {
    param(
        [object]$LocalConfig,
        [object]$DefaultsConfig,
        [string]$LocalPath,
        [string]$EnvName,
        [string]$DefaultPath
    )

    # Each value resolves in the same order: environment override, local, then defaults.
    return Get-FirstNonEmpty -Candidates @(
        # Environment variables win when they provide a usable value.
        (Get-Item -Path "Env:$EnvName" -ErrorAction SilentlyContinue).Value,
        # Local file is the middle layer.
        (Get-NestedValue $LocalConfig -Path $LocalPath.Split('.')),
        # Defaults are the final fallback.
        (Get-NestedValue $DefaultsConfig -Path $DefaultPath.Split('.'))
    )
}

# Load the repo-level config files and return a single object with resolved values.
function Get-MwmcpConfig {
    # Repo-root-relative paths keep this helper independent from the current working directory.
    $repoRoot = (Resolve-Path (Join-Path $script:LoaderDir ".." )).Path
    $defaultsPath = Join-Path $repoRoot "mwmcp.defaults.json"
    $localPath = Join-Path $repoRoot "mwmcp.local.json"

    # Defaults are mandatory because they define the base shape of the configuration.
    if (-not (Test-Path -LiteralPath $defaultsPath)) {
        throw "Defaults config file was not found: $defaultsPath"
    }

    # Load defaults first so all later layers can override them.
    $defaultsConfig = Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $localConfig = $null
    # Local overrides are optional; if the file is missing, we keep using defaults and env values.
    if (Test-Path -LiteralPath $localPath) {
        $localConfig = Get-Content -LiteralPath $localPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }

    # Resolve connection and path settings from env/local/default layers.
    $serverAddress = Resolve-ConfigValue -LocalConfig $localConfig -DefaultsConfig $defaultsConfig -LocalPath "server.address" -EnvName "MWMCP_SERVER_ADDRESS" -DefaultPath "server.address"
    $serverPortRaw = Resolve-ConfigValue -LocalConfig $localConfig -DefaultsConfig $defaultsConfig -LocalPath "server.port" -EnvName "MWMCP_SERVER_PORT" -DefaultPath "server.port"

    $mo2ExeFile = Resolve-ConfigValue -LocalConfig $localConfig -DefaultsConfig $defaultsConfig -LocalPath "paths.mo2ExeFile" -EnvName "MWMCP_MO2_EXE_FILE" -DefaultPath "paths.mo2ExeFile"
    $mo2Application = Resolve-ConfigValue -LocalConfig $localConfig -DefaultsConfig $defaultsConfig -LocalPath "paths.mo2Application" -EnvName "MWMCP_MO2_APPLICATION" -DefaultPath "paths.mo2Application"
    $mo2Profile = Resolve-ConfigValue -LocalConfig $localConfig -DefaultsConfig $defaultsConfig -LocalPath "paths.mo2Profile" -EnvName "MWMCP_MO2_MWSE_PROFILE" -DefaultPath "paths.mo2Profile"
    $morrowindInstallDir = Resolve-ConfigValue -LocalConfig $localConfig -DefaultsConfig $defaultsConfig -LocalPath "paths.morrowindInstallDir" -EnvName "MWMCP_MORROWIND_INSTALL_DIR" -DefaultPath "paths.morrowindInstallDir"
    $mwseConfigDir = Resolve-ConfigValue -LocalConfig $localConfig -DefaultsConfig $defaultsConfig -LocalPath "paths.mwseConfigDir" -EnvName "MWMCP_MWSE_CONFIG_DIR" -DefaultPath "paths.mwseConfigDir"

    $serverPort = 0
    if (-not [int]::TryParse([string]$serverPortRaw, [ref]$serverPort)) {
        throw "server.port must be an integer value: $serverPortRaw"
    }
    if ($serverPort -lt 1024 -or $serverPort -gt 65535) {
        throw "server.port must be between 1024 and 65535: $serverPort"
    }

    $connectionUrl = "http://${serverAddress}:$serverPort"
    $uri = $null
    if (-not [System.Uri]::TryCreate($connectionUrl, [System.UriKind]::Absolute, [ref]$uri)) {
        throw "Invalid connection endpoint from server.address/server.port: $connectionUrl"
    }

    # Return both the source file locations and the resolved runtime values.
    return [pscustomobject]@{
        Files = [pscustomobject]@{
            repoRoot = $repoRoot
            defaults = $defaultsPath
            local = $localPath
        }
        Connection = [pscustomobject]@{
            url = $connectionUrl
            host = $uri.Host
            port = $serverPort
        }
        Paths = [pscustomobject]@{
            mo2ExeFile = $mo2ExeFile
            mo2Application = $mo2Application
            mo2Profile = $mo2Profile
            morrowindInstallDir = $morrowindInstallDir
            mwseConfigDir = $mwseConfigDir
        }
    }
}
