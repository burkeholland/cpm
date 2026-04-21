# cpm.ps1 — Copilot Provider Model switcher for PowerShell
# Dot-source this file:  . ./cpm.ps1  (do NOT run it directly)

$script:CpmConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "cpm" } else { Join-Path $HOME ".config" "cpm" }
$script:CpmConfigFile = Join-Path $script:CpmConfigDir "models.json"

function cpm {
    param(
        [Parameter(Position = 0)]
        [string]$Command = ""
    )

    if (-not (Test-Path $script:CpmConfigFile)) {
        Write-Error "cpm: config not found at $($script:CpmConfigFile)`nRun the installer or create it manually."
        return
    }

    switch ($Command) {
        "status"  { _cpm_status }
        "list"    { _cpm_list }
        "edit"    { _cpm_edit }
        "import"  { _cpm_import }
        "clear"   { _cpm_clear }
        "keys"    { _cpm_keys }
        "help"    { _cpm_help }
        ""        { _cpm_pick }
        default {
            Write-Error "cpm: unknown command '$Command'"
            _cpm_help
        }
    }
}

# ── subcommands ──────────────────────────────────────────────────────────

function _cpm_status {
    if (-not $env:COPILOT_MODEL) {
        Write-Host "No model active."
        return
    }
    Write-Host "Model:         $env:COPILOT_MODEL"
    Write-Host "Provider URL:  $(if ($env:COPILOT_PROVIDER_BASE_URL) { $env:COPILOT_PROVIDER_BASE_URL } else { '<not set>' })"
    Write-Host "Provider type: $(if ($env:COPILOT_PROVIDER_TYPE) { $env:COPILOT_PROVIDER_TYPE } else { '<not set>' })"
    if ($env:COPILOT_PROVIDER_API_KEY) {
        $masked = "****" + $env:COPILOT_PROVIDER_API_KEY.Substring([Math]::Max(0, $env:COPILOT_PROVIDER_API_KEY.Length - 4))
        Write-Host "API key:       $masked"
    } else {
        Write-Host "API key:       <not set>"
    }
    Write-Host "Max prompt:    $(if ($env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS) { $env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS } else { '<not set>' })"
    Write-Host "Max output:    $(if ($env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS) { $env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS } else { '<not set>' })"
}

function _cpm_list {
    $config = Get-Content $script:CpmConfigFile -Raw | ConvertFrom-Json
    foreach ($provider in $config.providers) {
        foreach ($model in $provider.models) {
            Write-Host "  $($provider.name) > $($model.id)"
        }
    }
}

function _cpm_edit {
    $editor = if ($env:EDITOR) { $env:EDITOR } else { "notepad" }
    & $editor $script:CpmConfigFile
}

function _cpm_clear {
    Remove-Item Env:COPILOT_PROVIDER_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:COPILOT_PROVIDER_TYPE -ErrorAction SilentlyContinue
    Remove-Item Env:COPILOT_PROVIDER_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:COPILOT_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS -ErrorAction SilentlyContinue
    Remove-Item Env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS -ErrorAction SilentlyContinue
    Write-Host "Cleared all Copilot provider env vars."
}

function _cpm_help {
    Write-Host @"
Usage: cpm [command]

Commands:
  (none)    Interactive model picker
  status    Show the currently active model
  list      List all configured models
  keys      Show / set API keys for all providers
  edit      Open models.json in `$EDITOR
  import    Import models from VS Code chatLanguageModels.json
  clear     Unset all Copilot provider env vars
  help      Show this help
"@
}

# ── interactive picker ───────────────────────────────────────────────────

function _cpm_pick {
    $config = Get-Content $script:CpmConfigFile -Raw | ConvertFrom-Json
    $entries = @()

    foreach ($provider in $config.providers) {
        foreach ($model in $provider.models) {
            $entries += [PSCustomObject]@{
                Label        = "$($provider.name) > $($model.id)"
                BaseUrl      = $provider.base_url
                ProviderType = if ($provider.provider_type) { $provider.provider_type } else { "openai" }
                ApiKeyEnv    = if ($provider.api_key_env) { $provider.api_key_env } else { "" }
                Model        = $model.id
                MaxPrompt    = if ($model.max_prompt_tokens) { $model.max_prompt_tokens } else { 0 }
                MaxOutput    = if ($model.max_output_tokens) { $model.max_output_tokens } else { 0 }
            }
        }
    }

    if ($entries.Count -eq 0) {
        Write-Error "No models configured. Run 'cpm edit' to add some."
        return
    }

    $total = $entries.Count + 1

    Write-Host "Pick a model:"
    Write-Host ""
    Write-Host "  1) Copilot (built-in)"
    for ($i = 0; $i -lt $entries.Count; $i++) {
        Write-Host "  $($i + 2)) $($entries[$i].Label)"
    }
    Write-Host ""

    do {
        $input = Read-Host "Enter number (1-$total)"
        $choice = 0
        $valid = [int]::TryParse($input, [ref]$choice) -and $choice -ge 1 -and $choice -le $total
        if (-not $valid) { Write-Host "Invalid choice." }
    } while (-not $valid)

    # Option 1 = built-in (clear all BYOK vars)
    if ($choice -eq 1) {
        _cpm_clear
        Write-Host ""
        Write-Host "✓ Switched to Copilot (built-in)"
        return
    }

    $selected = $entries[$choice - 2]

    $env:COPILOT_PROVIDER_BASE_URL = $selected.BaseUrl
    $env:COPILOT_PROVIDER_TYPE = $selected.ProviderType
    $env:COPILOT_MODEL = $selected.Model

    # Resolve API key
    if ($selected.ApiKeyEnv -and $selected.ApiKeyEnv -ne "") {
        $resolvedKey = [System.Environment]::GetEnvironmentVariable($selected.ApiKeyEnv)
        if ($resolvedKey) {
            $env:COPILOT_PROVIDER_API_KEY = $resolvedKey
        } else {
            Write-Host ""
            Write-Host "⚠ `$$($selected.ApiKeyEnv) is not set."
            $keyInput = Read-Host "  Paste your API key now (or press Enter to skip)"
            if ($keyInput) {
                [System.Environment]::SetEnvironmentVariable($selected.ApiKeyEnv, $keyInput, "Process")
                $env:COPILOT_PROVIDER_API_KEY = $keyInput
                _cpm_persist_key_ps $selected.ApiKeyEnv $keyInput
                Write-Host "  ✓ Key set and saved to PowerShell profile."
            } else {
                Write-Host "  Skipped — set `$$($selected.ApiKeyEnv) before using Copilot."
                Remove-Item Env:COPILOT_PROVIDER_API_KEY -ErrorAction SilentlyContinue
            }
        }
    } else {
        Remove-Item Env:COPILOT_PROVIDER_API_KEY -ErrorAction SilentlyContinue
    }

    # Token limits
    if ($selected.MaxPrompt -gt 0) {
        $env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = $selected.MaxPrompt.ToString()
    } else {
        Remove-Item Env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS -ErrorAction SilentlyContinue
    }
    if ($selected.MaxOutput -gt 0) {
        $env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = $selected.MaxOutput.ToString()
    } else {
        Remove-Item Env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "✓ Switched to $($selected.Label)"
}

# ── key management ───────────────────────────────────────────────────────

function _cpm_keys {
    $config = Get-Content $script:CpmConfigFile -Raw | ConvertFrom-Json

    if (-not $config.providers -or $config.providers.Count -eq 0) {
        Write-Host "No providers configured."
        return
    }

    Write-Host "API key status:"
    Write-Host ""

    foreach ($provider in $config.providers) {
        $envName = $provider.api_key_env
        if (-not $envName -or $envName -eq "") {
            Write-Host "  $($provider.name): no auth required"
        } else {
            $val = [System.Environment]::GetEnvironmentVariable($envName)
            if ($val) {
                $last4 = $val.Substring([Math]::Max(0, $val.Length - 4))
                Write-Host "  $($provider.name): ✓ `$$envName is set (****$last4)"
            } else {
                Write-Host "  $($provider.name): ✗ `$$envName is NOT set"
            }
        }
    }

    # Offer to set missing keys
    $anyMissing = $false
    foreach ($provider in $config.providers) {
        $envName = $provider.api_key_env
        if ($envName -and $envName -ne "") {
            $val = [System.Environment]::GetEnvironmentVariable($envName)
            if (-not $val) { $anyMissing = $true; break }
        }
    }

    if ($anyMissing) {
        Write-Host ""
        Write-Host "To set a missing key, paste it now (it will be exported in this session"
        Write-Host "and appended to your PowerShell profile for persistence)."
        Write-Host ""

        foreach ($provider in $config.providers) {
            $envName = $provider.api_key_env
            if ($envName -and $envName -ne "") {
                $val = [System.Environment]::GetEnvironmentVariable($envName)
                if (-not $val) {
                    $keyInput = Read-Host "Enter value for `$$envName (or press Enter to skip)"
                    if ($keyInput) {
                        [System.Environment]::SetEnvironmentVariable($envName, $keyInput, "Process")
                        _cpm_persist_key_ps $envName $keyInput
                        Write-Host "  ✓ `$$envName set and saved."
                    } else {
                        Write-Host "  Skipped."
                    }
                }
            }
        }
    }
}

function _cpm_persist_key_ps {
    param([string]$EnvName, [string]$KeyValue)

    $profilePath = $PROFILE.CurrentUserCurrentHost
    $profileDir = Split-Path $profilePath -Parent

    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    # Remove existing line for this env var
    $content = Get-Content $profilePath -ErrorAction SilentlyContinue
    if ($content) {
        $content = $content | Where-Object { $_ -notmatch "^\`$env:${EnvName}\s*=" }
        $content | Set-Content $profilePath -Encoding UTF8
    }

    Add-Content $profilePath "`n`$env:$EnvName = `"$KeyValue`""
}

# ── VS Code import ───────────────────────────────────────────────────────

function _cpm_import {
    $searchPaths = @()

    if ($IsWindows -or $env:OS -match "Windows") {
        $searchPaths += Join-Path $env:APPDATA "Code - Insiders" "User" "chatLanguageModels.json"
        $searchPaths += Join-Path $env:APPDATA "Code" "User" "chatLanguageModels.json"
    } elseif ($IsMacOS) {
        $searchPaths += Join-Path $HOME "Library" "Application Support" "Code - Insiders" "User" "chatLanguageModels.json"
        $searchPaths += Join-Path $HOME "Library" "Application Support" "Code" "User" "chatLanguageModels.json"
    } else {
        $configBase = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
        $searchPaths += Join-Path $configBase "Code - Insiders" "User" "chatLanguageModels.json"
        $searchPaths += Join-Path $configBase "Code" "User" "chatLanguageModels.json"
    }

    $vscodeFile = $null
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            $vscodeFile = $p
            break
        }
    }

    if (-not $vscodeFile) {
        Write-Error "cpm import: no chatLanguageModels.json found.`nSearched:`n  $($searchPaths -join "`n  ")"
        return
    }

    Write-Host "Found: $vscodeFile"
    $vscodeConfig = Get-Content $vscodeFile -Raw | ConvertFrom-Json

    # Filter out copilot-vendor entries
    $importable = $vscodeConfig | Where-Object { $_.vendor -ne "copilot" }

    if (-not $importable -or @($importable).Count -eq 0) {
        Write-Host "No importable providers found (skipped GitHub-hosted models)."
        return
    }

    $newProviders = @()
    foreach ($entry in @($importable)) {
        $providerType = switch ($entry.vendor) {
            "anthropic" { "anthropic" }
            "azure"     { "azure" }
            default     { "openai" }
        }
        $envName = ($entry.name -replace '[^a-zA-Z0-9]', '_').ToUpper() + "_API_KEY"

        $models = @()
        foreach ($m in $entry.models) {
            $models += [PSCustomObject]@{
                id               = $m.id
                max_prompt_tokens = if ($m.maxInputTokens) { $m.maxInputTokens } else { 0 }
                max_output_tokens = if ($m.maxOutputTokens) { $m.maxOutputTokens } else { 0 }
            }
        }

        $baseUrl = ""
        if ($entry.models -and $entry.models.Count -gt 0 -and $entry.models[0].url) {
            $baseUrl = $entry.models[0].url
        }

        $newProviders += [PSCustomObject]@{
            name          = $entry.name
            base_url      = $baseUrl
            provider_type = $providerType
            api_key_env   = $envName
            models        = $models
        }
    }

    Write-Host "Found $($newProviders.Count) provider(s) to import:"
    foreach ($p in $newProviders) {
        Write-Host "  $($p.name) ($($p.models.Count) model(s))"
    }

    # Merge into existing config
    if (Test-Path $script:CpmConfigFile) {
        $existing = Get-Content $script:CpmConfigFile -Raw | ConvertFrom-Json
        $existingNames = $existing.providers | ForEach-Object { $_.name }
        $toAdd = @()
        foreach ($p in $newProviders) {
            if ($existingNames -contains $p.name) {
                Write-Host "  Skipping '$($p.name)' (already in config)"
            } else {
                $toAdd += $p
            }
        }
        if ($toAdd.Count -gt 0) {
            $existing.providers = @($existing.providers) + $toAdd
            $existing | ConvertTo-Json -Depth 10 | Set-Content $script:CpmConfigFile -Encoding UTF8
            Write-Host "Imported $($toAdd.Count) new provider(s) into $($script:CpmConfigFile)"
        } else {
            Write-Host "All providers already exist. Nothing to import."
        }
    } else {
        New-Item -ItemType Directory -Path $script:CpmConfigDir -Force | Out-Null
        [PSCustomObject]@{ providers = $newProviders } | ConvertTo-Json -Depth 10 | Set-Content $script:CpmConfigFile -Encoding UTF8
        Write-Host "Created $($script:CpmConfigFile) with $($newProviders.Count) provider(s)"
    }

    Write-Host ""
    Write-Host "Remember to set your API key env vars:"
    foreach ($p in $newProviders) {
        Write-Host "  `$env:$($p.api_key_env) = 'your-key-here'"
    }
}
