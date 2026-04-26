# install.ps1 — cpm installer for PowerShell

$ErrorActionPreference = "Stop"

function _cpm_join_path {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,
        [Parameter(Mandatory = $true, Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$ChildPath
    )

    $result = $Path
    foreach ($child in $ChildPath) {
        $result = Join-Path $result $child
    }
    return $result
}

$CpmConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "cpm" } else { _cpm_join_path $HOME ".config" "cpm" }
$CpmConfigFile = Join-Path $CpmConfigDir "models.json"
$CpmPsFile = Join-Path $CpmConfigDir "cpm.ps1"
$ScriptPath = if ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $PSCommandPath }
$ScriptDir = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { $null }
$RemoteBase = "https://raw.githubusercontent.com/burkeholland/cpm/main"

Write-Host "Installing cpm..."
Write-Host ""

# ── create config dir ────────────────────────────────────────────────
New-Item -ItemType Directory -Path $CpmConfigDir -Force | Out-Null

# ── copy or download PowerShell function ─────────────────────────────
$localSource = if ($ScriptDir) { Join-Path $ScriptDir "cpm.ps1" } else { $null }

if ($localSource -and (Test-Path $localSource)) {
    Copy-Item $localSource $CpmPsFile -Force
} else {
    Write-Host "Downloading cpm.ps1 from GitHub..."
    Invoke-RestMethod "$RemoteBase/cpm.ps1" -OutFile $CpmPsFile
}
Write-Host "✓ Installed PowerShell function to $CpmPsFile"

# ── create default config if missing ─────────────────────────────────
if (-not (Test-Path $CpmConfigFile)) {
    @'
{
  "providers": []
}
'@ | Set-Content $CpmConfigFile -Encoding UTF8
    Write-Host "✓ Created default config at $CpmConfigFile"
} else {
    Write-Host "✓ Config already exists at $CpmConfigFile"
}

# ── offer VS Code import ────────────────────────────────────────────
$searchPaths = @()
if ($IsWindows -or $env:OS -match "Windows") {
    $searchPaths += _cpm_join_path $env:APPDATA "Code - Insiders" "User" "chatLanguageModels.json"
    $searchPaths += _cpm_join_path $env:APPDATA "Code" "User" "chatLanguageModels.json"
} elseif ($IsMacOS) {
    $searchPaths += _cpm_join_path $HOME "Library" "Application Support" "Code - Insiders" "User" "chatLanguageModels.json"
    $searchPaths += _cpm_join_path $HOME "Library" "Application Support" "Code" "User" "chatLanguageModels.json"
} else {
    $configBase = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
    $searchPaths += _cpm_join_path $configBase "Code - Insiders" "User" "chatLanguageModels.json"
    $searchPaths += _cpm_join_path $configBase "Code" "User" "chatLanguageModels.json"
}

$vscodeFile = $null
foreach ($p in $searchPaths) {
    if (Test-Path $p) {
        $vscodeFile = $p
        break
    }
}

if ($vscodeFile) {
    Write-Host ""
    Write-Host "Found VS Code models at: $vscodeFile"
    $answer = Read-Host "Import them into cpm? [Y/n]"
    if ($answer -ne "n") {
        . $CpmPsFile
        _cpm_import
    }
}

# ── patch PowerShell profile ────────────────────────────────────────
$sourceLine = ". `"$CpmPsFile`""

$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDir = Split-Path $profilePath -Parent

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
if (-not $profileContent -or -not $profileContent.Contains($CpmPsFile)) {
    Add-Content $profilePath "`n# cpm - Copilot Provider Model switcher`n$sourceLine"
    Write-Host "✓ Added source line to $profilePath"
} else {
    Write-Host "✓ Already sourced in $profilePath"
}

Write-Host ""
Write-Host "Done! Restart your shell or run:"
Write-Host "  $sourceLine"
Write-Host ""
Write-Host "Then try:  cpm"
