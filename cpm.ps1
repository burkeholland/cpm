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
        "add"     { _cpm_add }
        "remove"  { _cpm_remove }
        "update"  { _cpm_update }
        "edit"    { _cpm_edit }
        "import"  { _cpm_import }
        "clear"   { _cpm_clear }
        "keys"    { _cpm_keys }
        "config"  { _cpm_config @args }
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

# ── add provider/model wizard ────────────────────────────────────────────

function _cpm_add {
    $config = Get-Content $script:CpmConfigFile -Raw | ConvertFrom-Json

    Write-Host "Add a model"
    Write-Host ""

    $providerIdx = -1
    $providerCount = $config.providers.Count

    if ($providerCount -gt 0) {
        Write-Host "Provider:"
        for ($i = 0; $i -lt $providerCount; $i++) {
            Write-Host "  $($i + 1)) $($config.providers[$i].name)"
        }
        Write-Host "  $($providerCount + 1)) + New provider"
        Write-Host ""

        do {
            $inp = Read-Host "Pick a provider (1-$($providerCount + 1))"
            $pc = 0
            $valid = [int]::TryParse($inp, [ref]$pc) -and $pc -ge 1 -and $pc -le ($providerCount + 1)
            if (-not $valid) { Write-Host "Invalid choice." }
        } while (-not $valid)

        if ($pc -le $providerCount) {
            $providerIdx = $pc - 1
        }
    }

    if ($providerIdx -eq -1) {
        Write-Host ""
        Write-Host "New provider setup:"
        Write-Host ""

        $pname = Read-Host "  Name (e.g. OpenRouter, Ollama)"
        if (-not $pname) { Write-Host "Cancelled."; return }

        $purl = Read-Host "  Base URL (e.g. https://openrouter.ai/api/v1)"
        if (-not $purl) { Write-Host "Cancelled."; return }

        $ptype = Read-Host "  Provider type [openai]"
        if (-not $ptype) { $ptype = "openai" }

        $pkey = Read-Host "  API key env var name (e.g. OPENROUTER_API_KEY, blank for none)"

        $newProvider = [PSCustomObject]@{
            name          = $pname
            base_url      = $purl
            provider_type = $ptype
            api_key_env   = $pkey
            models        = @()
        }
        $config.providers += $newProvider
        $providerIdx = $config.providers.Count - 1
        Write-Host ""
        Write-Host "  ✓ Provider '$pname' added"

        if ($pkey) {
            $existing = [System.Environment]::GetEnvironmentVariable($pkey)
            if (-not $existing) {
                Write-Host ""
                $keyVal = Read-Host "  Paste your $pkey now (or Enter to skip)"
                if ($keyVal) {
                    [System.Environment]::SetEnvironmentVariable($pkey, $keyVal, "Process")
                    _cpm_persist_key_ps $pkey $keyVal
                    Write-Host "  ✓ Key set and saved to profile."
                }
            }
        }
    }

    Write-Host ""
    Write-Host "New model:"
    Write-Host ""

    $mid = Read-Host "  Model ID (e.g. gpt-4o, claude-opus-4-5)"
    if (-not $mid) { Write-Host "Cancelled."; return }

    $mprompt = Read-Host "  Max prompt tokens [128000]"
    if (-not $mprompt) { $mprompt = "128000" }

    $moutput = Read-Host "  Max output tokens [16000]"
    if (-not $moutput) { $moutput = "16000" }

    $newModel = [PSCustomObject]@{
        id                = $mid
        max_prompt_tokens = [int]$mprompt
        max_output_tokens = [int]$moutput
    }
    $config.providers[$providerIdx].models += $newModel
    $config | ConvertTo-Json -Depth 10 | Set-Content $script:CpmConfigFile

    $provName = $config.providers[$providerIdx].name
    Write-Host ""
    Write-Host "✓ Added $provName > $mid"
}

# ── remove provider/model ────────────────────────────────────────────────

function _cpm_remove {
    $config = Get-Content $script:CpmConfigFile -Raw | ConvertFrom-Json

    Write-Host "Remove a provider or model"
    Write-Host ""

    if ($config.providers.Count -eq 0) {
        Write-Host "No providers configured."
        return
    }

    # Build flat list
    $items = @()
    foreach ($provider in $config.providers) {
        $pi = [array]::IndexOf($config.providers, $provider)
        $items += [PSCustomObject]@{ Type = "provider"; PI = $pi; MI = -1; Label = "✗ Remove provider '$($provider.name)' (and all its models)" }
        for ($mi = 0; $mi -lt $provider.models.Count; $mi++) {
            $items += [PSCustomObject]@{ Type = "model"; PI = $pi; MI = $mi; Label = "  ✗ Remove model '$($provider.models[$mi].id)' from $($provider.name)" }
        }
    }

    for ($i = 0; $i -lt $items.Count; $i++) {
        Write-Host "  $($i + 1)) $($items[$i].Label)"
    }
    Write-Host ""

    do {
        $inp = Read-Host "Pick item to remove (1-$($items.Count), or 'q' to cancel)"
        if ($inp -eq 'q') { Write-Host "Cancelled."; return }
        $choice = 0
        $valid = [int]::TryParse($inp, [ref]$choice) -and $choice -ge 1 -and $choice -le $items.Count
        if (-not $valid) { Write-Host "Invalid choice." }
    } while (-not $valid)

    $selected = $items[$choice - 1]

    if ($selected.Type -eq "provider") {
        $name = $config.providers[$selected.PI].name
        $config.providers = @($config.providers | Where-Object { $_ -ne $config.providers[$selected.PI] })
        $config | ConvertTo-Json -Depth 10 | Set-Content $script:CpmConfigFile
        Write-Host "✓ Removed provider '$name'"
    } else {
        $pn = $config.providers[$selected.PI].name
        $mn = $config.providers[$selected.PI].models[$selected.MI].id
        $config.providers[$selected.PI].models = @($config.providers[$selected.PI].models | Where-Object { $_ -ne $config.providers[$selected.PI].models[$selected.MI] })
        $config | ConvertTo-Json -Depth 10 | Set-Content $script:CpmConfigFile
        Write-Host "✓ Removed model '$mn' from $pn"
    }
}

# ── update provider/model ────────────────────────────────────────────────

function _cpm_update {
    $config = Get-Content $script:CpmConfigFile -Raw | ConvertFrom-Json

    Write-Host "Update a provider or model"
    Write-Host ""
    Write-Host "What do you want to update?"
    Write-Host "  1) A provider's settings"
    Write-Host "  2) A model's settings"
    Write-Host ""

    do {
        $inp = Read-Host "Pick (1-2, or 'q' to cancel)"
        if ($inp -eq 'q') { Write-Host "Cancelled."; return }
        $valid = $inp -eq '1' -or $inp -eq '2'
        if (-not $valid) { Write-Host "Invalid choice." }
    } while (-not $valid)

    if ($inp -eq '1') {
        # Update provider
        if ($config.providers.Count -eq 0) { Write-Host "No providers configured."; return }

        Write-Host ""
        Write-Host "Pick a provider to update:"
        for ($i = 0; $i -lt $config.providers.Count; $i++) {
            Write-Host "  $($i + 1)) $($config.providers[$i].name)"
        }
        Write-Host ""

        do {
            $pinp = Read-Host "Pick (1-$($config.providers.Count))"
            $pc = 0
            $pvalid = [int]::TryParse($pinp, [ref]$pc) -and $pc -ge 1 -and $pc -le $config.providers.Count
            if (-not $pvalid) { Write-Host "Invalid choice." }
        } while (-not $pvalid)

        $p = $config.providers[$pc - 1]
        Write-Host ""
        Write-Host "Editing '$($p.name)' (press Enter to keep current value):"
        Write-Host ""

        $newName = Read-Host "  Name [$($p.name)]"
        if (-not $newName) { $newName = $p.name }

        $newUrl = Read-Host "  Base URL [$($p.base_url)]"
        if (-not $newUrl) { $newUrl = $p.base_url }

        $curType = if ($p.provider_type) { $p.provider_type } else { "openai" }
        $newType = Read-Host "  Provider type [$curType]"
        if (-not $newType) { $newType = $curType }

        $curKey = if ($p.api_key_env) { $p.api_key_env } else { "" }
        $newKey = Read-Host "  API key env var [$curKey]"
        if (-not $newKey) { $newKey = $curKey }

        $p.name = $newName
        $p.base_url = $newUrl
        $p | Add-Member -NotePropertyName "provider_type" -NotePropertyValue $newType -Force
        $p | Add-Member -NotePropertyName "api_key_env" -NotePropertyValue $newKey -Force
        $config | ConvertTo-Json -Depth 10 | Set-Content $script:CpmConfigFile
        Write-Host ""
        Write-Host "✓ Updated provider '$newName'"
    } else {
        # Update model
        $items = @()
        foreach ($provider in $config.providers) {
            $pi = [array]::IndexOf($config.providers, $provider)
            for ($mi = 0; $mi -lt $provider.models.Count; $mi++) {
                $items += [PSCustomObject]@{ PI = $pi; MI = $mi; Label = "$($provider.name) > $($provider.models[$mi].id)" }
            }
        }

        if ($items.Count -eq 0) { Write-Host "No models configured."; return }

        Write-Host ""
        Write-Host "Pick a model to update:"
        for ($i = 0; $i -lt $items.Count; $i++) {
            Write-Host "  $($i + 1)) $($items[$i].Label)"
        }
        Write-Host ""

        do {
            $minp = Read-Host "Pick (1-$($items.Count))"
            $mc = 0
            $mvalid = [int]::TryParse($minp, [ref]$mc) -and $mc -ge 1 -and $mc -le $items.Count
            if (-not $mvalid) { Write-Host "Invalid choice." }
        } while (-not $mvalid)

        $sel = $items[$mc - 1]
        $m = $config.providers[$sel.PI].models[$sel.MI]
        $pn = $config.providers[$sel.PI].name

        Write-Host ""
        Write-Host "Editing '$pn > $($m.id)' (press Enter to keep current value):"
        Write-Host ""

        $newId = Read-Host "  Model ID [$($m.id)]"
        if (-not $newId) { $newId = $m.id }

        $curPrompt = if ($m.max_prompt_tokens) { $m.max_prompt_tokens } else { 128000 }
        $newPrompt = Read-Host "  Max prompt tokens [$curPrompt]"
        if (-not $newPrompt) { $newPrompt = $curPrompt }

        $curOutput = if ($m.max_output_tokens) { $m.max_output_tokens } else { 16000 }
        $newOutput = Read-Host "  Max output tokens [$curOutput]"
        if (-not $newOutput) { $newOutput = $curOutput }

        $m.id = $newId
        $m | Add-Member -NotePropertyName "max_prompt_tokens" -NotePropertyValue ([int]$newPrompt) -Force
        $m | Add-Member -NotePropertyName "max_output_tokens" -NotePropertyValue ([int]$newOutput) -Force
        $config | ConvertTo-Json -Depth 10 | Set-Content $script:CpmConfigFile
        Write-Host ""
        Write-Host "✓ Updated $pn > $newId"
    }
}

function _cpm_help {
    Write-Host @"
Usage: cpm [command]

Commands:
  (none)    Interactive model picker
  status    Show the currently active model
  list      List all configured models
  add       Add a new provider or model
  remove    Remove a provider or model
  update    Edit a provider or model's settings
  keys      Show / set API keys for all providers
  config    Get/set config values (e.g. cpm config launch yolo)
  edit      Open models.json in `$EDITOR
  import    Import models from VS Code chatLanguageModels.json
  clear     Unset all Copilot provider env vars
  help      Show this help
"@
}

# ── config get/set ───────────────────────────────────────────────────────

function _cpm_config {
    param(
        [Parameter(Position = 0)]
        [string]$Key = "",
        [Parameter(Position = 1)]
        [string]$Value
    )

    if (-not $Key) {
        Write-Host "Usage: cpm config <key> [value]"
        Write-Host ""
        Write-Host "Keys:"
        Write-Host "  launch   Command to run after picking a model (default: copilot)"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  cpm config launch            # show current value"
        Write-Host "  cpm config launch yolo        # set to 'yolo'"
        Write-Host '  cpm config launch ""          # disable auto-launch'
        return
    }

    switch ($Key) {
        "launch" {
            $config = Get-Content $script:CpmConfigFile -Raw | ConvertFrom-Json
            if (-not $PSBoundParameters.ContainsKey('Value')) {
                $current = if ($null -ne $config.launch) { $config.launch } else { "copilot" }
                if (-not $current) { Write-Host "launch: (disabled)" } else { Write-Host "launch: $current" }
            } else {
                $config | Add-Member -NotePropertyName "launch" -NotePropertyValue $Value -Force
                $config | ConvertTo-Json -Depth 10 | Set-Content $script:CpmConfigFile
                if (-not $Value) { Write-Host "✓ Auto-launch disabled" } else { Write-Host "✓ launch set to: $Value" }
            }
        }
        default {
            Write-Error "cpm config: unknown key '$Key'"
        }
    }
}

# ── launch copilot (or configured command) ───────────────────────────────

function _cpm_launch {
    $config = Get-Content $script:CpmConfigFile -Raw | ConvertFrom-Json
    $cmd = if ($null -ne $config.launch) { $config.launch } else { "copilot" }
    if ($cmd) {
        Invoke-Expression $cmd
    }
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
        Write-Host ""
        _cpm_launch
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
    Write-Host ""
    _cpm_launch
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
