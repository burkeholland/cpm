#!/usr/bin/env bash
set -euo pipefail

# cpm installer — installs the Copilot Provider Model switcher

CPM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cpm"
CPM_CONFIG_FILE="$CPM_CONFIG_DIR/models.json"
CPM_SHELL_FILE="$CPM_CONFIG_DIR/cpm.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing cpm..."
echo ""

# ── create config dir ────────────────────────────────────────────────
mkdir -p "$CPM_CONFIG_DIR"

# ── copy shell function ──────────────────────────────────────────────
cp "$SCRIPT_DIR/cpm.sh" "$CPM_SHELL_FILE"
echo "✓ Installed shell function to $CPM_SHELL_FILE"

# ── create default config if missing ─────────────────────────────────
if [[ ! -f "$CPM_CONFIG_FILE" ]]; then
  cat > "$CPM_CONFIG_FILE" << 'DEFAULTCONFIG'
{
  "providers": []
}
DEFAULTCONFIG
  echo "✓ Created default config at $CPM_CONFIG_FILE"
else
  echo "✓ Config already exists at $CPM_CONFIG_FILE"
fi

# ── offer VS Code import ────────────────────────────────────────────
_find_vscode_config() {
  local -a paths=()
  case "$(uname -s)" in
    Darwin)
      paths=(
        "$HOME/Library/Application Support/Code - Insiders/User/chatLanguageModels.json"
        "$HOME/Library/Application Support/Code/User/chatLanguageModels.json"
      )
      ;;
    Linux)
      paths=(
        "${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User/chatLanguageModels.json"
        "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/chatLanguageModels.json"
      )
      ;;
  esac
  for p in "${paths[@]}"; do
    if [[ -f "$p" ]]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

vscode_config="$(_find_vscode_config || true)"
if [[ -n "$vscode_config" ]]; then
  echo ""
  echo "Found VS Code models at: $vscode_config"
  read -rp "Import them into cpm? [Y/n] " answer
  if [ "$answer" != "n" ] && [ "$answer" != "N" ]; then
    # Source cpm so we can use the import command
    source "$CPM_SHELL_FILE"
    _cpm_import
  fi
fi

# ── patch shell rc files ────────────────────────────────────────────
SOURCE_LINE="source \"$CPM_SHELL_FILE\""

_patch_rc() {
  local rc_file="$1"
  if [[ -f "$rc_file" ]]; then
    if ! grep -qF "$CPM_SHELL_FILE" "$rc_file"; then
      echo "" >> "$rc_file"
      echo "# cpm — Copilot Provider Model switcher" >> "$rc_file"
      echo "$SOURCE_LINE" >> "$rc_file"
      echo "✓ Added source line to $rc_file"
    else
      echo "✓ Already sourced in $rc_file"
    fi
  fi
}

echo ""

# Detect current shell and patch accordingly
current_shell="$(basename "${SHELL:-bash}")"
case "$current_shell" in
  zsh)
    _patch_rc "$HOME/.zshrc"
    ;;
  bash)
    _patch_rc "$HOME/.bashrc"
    ;;
  *)
    _patch_rc "$HOME/.bashrc"
    ;;
esac

# Also patch zshrc if it exists (many macOS users have both)
if [[ "$current_shell" != "zsh" && -f "$HOME/.zshrc" ]]; then
  _patch_rc "$HOME/.zshrc"
fi

echo ""
echo "Done! Restart your shell or run:"
echo "  $SOURCE_LINE"
echo ""
echo "Then try:  cpm"
