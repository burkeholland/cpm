# install.ps1 — cpm installer for PowerShell

$ErrorActionPreference = "Stop"

$CpmConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "cpm" } else { Join-Path $HOME ".config" "cpm" }
$CpmConfigFile = Join-Path $CpmConfigDir "models.json"
$CpmPsFile = Join-Path $CpmConfigDir "cpm.ps1"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue
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
