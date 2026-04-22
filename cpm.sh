# cpm — Copilot Provider Model switcher
# Source this file: source cpm.sh  (do NOT execute it)
# Compatible with bash and zsh

CPM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cpm"
CPM_CONFIG_FILE="$CPM_CONFIG_DIR/models.json"

cpm() {
  # ── guard: jq required ──────────────────────────────────────────────
  if ! command -v jq >/dev/null 2>&1; then
    echo "cpm: jq is required but not installed. Install it with your package manager." >&2
    return 1
  fi

  # ── guard: config exists ────────────────────────────────────────────
  if [ ! -f "$CPM_CONFIG_FILE" ]; then
    echo "cpm: config not found at $CPM_CONFIG_FILE" >&2
    echo "     Run the installer or create it manually." >&2
    return 1
  fi

  local sub="${1:-}"

  case "$sub" in
    status)  _cpm_status ;;
    list)    _cpm_list ;;
    edit)    _cpm_edit ;;
    import)  _cpm_import ;;
    clear)   _cpm_clear ;;
    keys)    _cpm_keys ;;
    help)    _cpm_help ;;
    "")      _cpm_pick ;;
    *)
      echo "cpm: unknown command '$sub'" >&2
      _cpm_help
      return 1
      ;;
  esac
}

# ── subcommands ─────────────────────────────────────────────────────────

_cpm_status() {
  if [ -z "${COPILOT_MODEL:-}" ]; then
    echo "No model active."
    return 0
  fi
  echo "Model:         $COPILOT_MODEL"
  echo "Provider URL:  ${COPILOT_PROVIDER_BASE_URL:-<not set>}"
  echo "Provider type: ${COPILOT_PROVIDER_TYPE:-<not set>}"
  if [ -n "${COPILOT_PROVIDER_API_KEY:-}" ]; then
    local _last4
    _last4=$(printf '%s' "$COPILOT_PROVIDER_API_KEY" | tail -c 4)
    echo "API key:       ****${_last4}"
  else
    echo "API key:       <not set>"
  fi
  echo "Max prompt:    ${COPILOT_PROVIDER_MAX_PROMPT_TOKENS:-<not set>}"
  echo "Max output:    ${COPILOT_PROVIDER_MAX_OUTPUT_TOKENS:-<not set>}"
}

_cpm_list() {
  jq -r '
    .providers[] |
    .name as $p |
    .models[] |
    "  \($p) > \(.id)"
  ' "$CPM_CONFIG_FILE"
}

_cpm_edit() {
  "${EDITOR:-vi}" "$CPM_CONFIG_FILE"
}

_cpm_clear() {
  unset COPILOT_PROVIDER_BASE_URL
  unset COPILOT_PROVIDER_TYPE
  unset COPILOT_PROVIDER_API_KEY
  unset COPILOT_MODEL
  unset COPILOT_PROVIDER_MAX_PROMPT_TOKENS
  unset COPILOT_PROVIDER_MAX_OUTPUT_TOKENS
  echo "Cleared all Copilot provider env vars."
}

_cpm_help() {
  cat <<'EOF'
Usage: cpm [command]

Commands:
  (none)    Interactive model picker
  status    Show the currently active model
  list      List all configured models
  keys      Show / set API keys for all providers
  edit      Open models.json in $EDITOR
  import    Import models from VS Code chatLanguageModels.json
  clear     Unset all Copilot provider env vars
  help      Show this help
EOF
}

# ── key management ──────────────────────────────────────────────────────

_cpm_keys() {
  local providers name api_key_env resolved _last4
  providers=$(jq -c '.providers[]' "$CPM_CONFIG_FILE")

  if [ -z "$providers" ]; then
    echo "No providers configured."
    return 0
  fi

  echo "API key status:"
  echo ""

  printf '%s\n' "$providers" | while IFS= read -r provider; do
    name=$(printf '%s' "$provider" | jq -r '.name')
    api_key_env=$(printf '%s' "$provider" | jq -r '.api_key_env // ""')

    if [ -z "$api_key_env" ] || [ "$api_key_env" = "null" ]; then
      echo "  $name: no auth required"
    else
      eval "resolved=\"\${${api_key_env}:-}\""
      if [ -n "$resolved" ]; then
        _last4=$(printf '%s' "$resolved" | tail -c 4)
        echo "  $name: ✓ \$$api_key_env is set (****${_last4})"
      else
        echo "  $name: ✗ \$$api_key_env is NOT set"
      fi
    fi
  done

  # Check if any keys are missing and offer to set them
  local missing_envs _val _key_input any_missing=0
  missing_envs=$(jq -r '.providers[] | select(.api_key_env != null and .api_key_env != "") | .api_key_env' "$CPM_CONFIG_FILE")

  for env_name in $missing_envs; do
    eval "_val=\"\${${env_name}:-}\""
    if [ -z "$_val" ]; then
      any_missing=1
      break
    fi
  done

  if [ "$any_missing" -eq 1 ]; then
    echo ""
    echo "To set a missing key, paste it now (it will be exported in this session"
    echo "and appended to your shell profile for persistence)."
    echo ""

    for env_name in $missing_envs; do
      eval "_val=\"\${${env_name}:-}\""
      if [ -z "$_val" ]; then
        printf "Enter value for \$%s (or press Enter to skip): " "$env_name"
        read -r _key_input
        if [ -n "$_key_input" ]; then
          export "$env_name=$_key_input"
          _cpm_persist_key "$env_name" "$_key_input"
          echo "  ✓ \$$env_name set and saved."
        else
          echo "  Skipped."
        fi
      fi
    done
  fi
}

# Persist a key to the user's shell profile
_cpm_persist_key() {
  local env_name="$1" key_value="$2"
  local rc_file=""
  local current_shell
  current_shell=$(basename "${SHELL:-bash}")

  case "$current_shell" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    *)    rc_file="$HOME/.bashrc" ;;
  esac

  if [ -f "$rc_file" ]; then
    # Remove any existing line for this env var
    local tmp_rc
    tmp_rc=$(grep -v "^export ${env_name}=" "$rc_file")
    printf '%s\n' "$tmp_rc" > "$rc_file"
  fi

  printf '\nexport %s="%s"\n' "$env_name" "$key_value" >> "$rc_file"
}

# ── interactive picker ──────────────────────────────────────────────────

_cpm_pick() {
  # Get a flat JSON array of all model entries
  local all_json
  all_json=$(jq -c '
    [.providers[] |
     .name as $p |
     .base_url as $url |
     (.provider_type // "openai") as $type |
     .api_key_env as $key_env |
     .models[] |
     {
       label: "\($p) > \(.id)",
       base_url: $url,
       provider_type: $type,
       api_key_env: ($key_env // ""),
       model: .id,
       max_prompt: (.max_prompt_tokens // 0),
       max_output: (.max_output_tokens // 0)
     }]
  ' "$CPM_CONFIG_FILE")

  local count
  count=$(printf '%s' "$all_json" | jq 'length')

  if [ "$count" -eq 0 ]; then
    echo "No models configured. Run 'cpm edit' to add some." >&2
    return 1
  fi

  # total = BYOK models + 1 for built-in
  local total=$((count + 1))

  echo "Pick a model:"
  echo ""
  echo "  1) Copilot (built-in)"
  local _label i=0
  while [ "$i" -lt "$count" ]; do
    _label=$(printf '%s' "$all_json" | jq -r ".[$i].label")
    echo "  $((i + 2))) $_label"
    i=$((i + 1))
  done
  echo ""

  local choice
  while true; do
    printf "Enter number (1-%d): " "$total"
    read -r choice
    case "$choice" in
      ''|*[!0-9]*) echo "Invalid choice." >&2; continue ;;
    esac
    if [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ]; then
      break
    fi
    echo "Invalid choice." >&2
  done

  # Option 1 = built-in (clear all BYOK vars)
  if [ "$choice" -eq 1 ]; then
    _cpm_clear
    echo ""
    echo "✓ Switched to Copilot (built-in)"
    echo ""
    copilot
    return 0
  fi

  local idx=$((choice - 2))
  local selected
  selected=$(printf '%s' "$all_json" | jq -c ".[$idx]")

  local base_url provider_type api_key_env model max_prompt max_output
  base_url=$(printf '%s' "$selected" | jq -r '.base_url')
  provider_type=$(printf '%s' "$selected" | jq -r '.provider_type')
  api_key_env=$(printf '%s' "$selected" | jq -r '.api_key_env')
  model=$(printf '%s' "$selected" | jq -r '.model')
  max_prompt=$(printf '%s' "$selected" | jq -r '.max_prompt')
  max_output=$(printf '%s' "$selected" | jq -r '.max_output')

  # Set env vars
  export COPILOT_PROVIDER_BASE_URL="$base_url"
  export COPILOT_PROVIDER_TYPE="$provider_type"
  export COPILOT_MODEL="$model"

  # Resolve API key from the env var name (portable indirect expansion)
  if [ -n "$api_key_env" ] && [ "$api_key_env" != "null" ]; then
    local resolved_key
    eval "resolved_key=\"\${${api_key_env}:-}\""
    if [ -n "$resolved_key" ]; then
      export COPILOT_PROVIDER_API_KEY="$resolved_key"
    else
      echo ""
      echo "⚠ \$$api_key_env is not set."
      printf "  Paste your API key now (or press Enter to skip): "
      read -r _key_input
      if [ -n "$_key_input" ]; then
        export "$api_key_env=$_key_input"
        export COPILOT_PROVIDER_API_KEY="$_key_input"
        _cpm_persist_key "$api_key_env" "$_key_input"
        echo "  ✓ Key set and saved to shell profile."
      else
        echo "  Skipped — set \$$api_key_env before using Copilot." >&2
        unset COPILOT_PROVIDER_API_KEY
      fi
    fi
  else
    unset COPILOT_PROVIDER_API_KEY
  fi

  # Token limits (only set if > 0)
  if [ "$max_prompt" -gt 0 ] 2>/dev/null; then
    export COPILOT_PROVIDER_MAX_PROMPT_TOKENS="$max_prompt"
  else
    unset COPILOT_PROVIDER_MAX_PROMPT_TOKENS
  fi
  if [ "$max_output" -gt 0 ] 2>/dev/null; then
    export COPILOT_PROVIDER_MAX_OUTPUT_TOKENS="$max_output"
  else
    unset COPILOT_PROVIDER_MAX_OUTPUT_TOKENS
  fi

  local label
  label=$(printf '%s' "$selected" | jq -r '.label')
  echo ""
  echo "✓ Switched to $label"
  echo ""
  copilot
}

# ── VS Code import ──────────────────────────────────────────────────────

_cpm_import() {
  local vscode_file=""
  local search_path1="" search_path2=""

  case "$(uname -s)" in
    Darwin)
      search_path1="$HOME/Library/Application Support/Code - Insiders/User/chatLanguageModels.json"
      search_path2="$HOME/Library/Application Support/Code/User/chatLanguageModels.json"
      ;;
    Linux)
      search_path1="${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User/chatLanguageModels.json"
      search_path2="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/chatLanguageModels.json"
      ;;
    *)
      echo "cpm import: auto-detect not supported on this OS." >&2
      return 1
      ;;
  esac

  if [ -f "$search_path1" ]; then
    vscode_file="$search_path1"
  elif [ -f "$search_path2" ]; then
    vscode_file="$search_path2"
  fi

  if [ -z "$vscode_file" ]; then
    echo "cpm import: no chatLanguageModels.json found." >&2
    echo "Searched:" >&2
    echo "  $search_path1" >&2
    echo "  $search_path2" >&2
    return 1
  fi

  echo "Found: $vscode_file"

  # Map vendor to provider_type; skip "copilot" entries
  local imported
  imported=$(jq '
    [.[] | select(.vendor != "copilot") |
     {
       name: .name,
       base_url: (.models[0].url // ""),
       provider_type: (
         if .vendor == "anthropic" then "anthropic"
         elif .vendor == "azure" then "azure"
         else "openai"
         end
       ),
       api_key_env: ((.name | gsub("[^a-zA-Z0-9]"; "_") | ascii_upcase) + "_API_KEY"),
       models: [.models[] | {
         id: .id,
         max_prompt_tokens: (.maxInputTokens // 0),
         max_output_tokens: (.maxOutputTokens // 0)
       }]
     }
    ]
  ' "$vscode_file")

  local count
  count=$(printf '%s' "$imported" | jq 'length')

  if [ "$count" -eq 0 ]; then
    echo "No importable providers found (skipped GitHub-hosted models)."
    return 0
  fi

  echo "Found $count provider(s) to import:"
  printf '%s' "$imported" | jq -r '.[] | "  \(.name) (\(.models | length) model(s))"'

  # Merge into existing config
  if [ -f "$CPM_CONFIG_FILE" ]; then
    local existing_names
    existing_names=$(jq -r '[.providers[].name] | .[]' "$CPM_CONFIG_FILE")

    local new_providers="[]"
    local i=0
    while [ "$i" -lt "$count" ]; do
      local pname
      pname=$(printf '%s' "$imported" | jq -r ".[$i].name")
      if printf '%s\n' "$existing_names" | grep -qxF "$pname"; then
        echo "  Skipping '$pname' (already in config)"
      else
        new_providers=$(printf '%s' "$new_providers" | jq --argjson entry "$(printf '%s' "$imported" | jq ".[$i]")" '. + [$entry]')
      fi
      i=$((i + 1))
    done

    local new_count
    new_count=$(printf '%s' "$new_providers" | jq 'length')
    if [ "$new_count" -gt 0 ]; then
      jq --argjson new "$new_providers" '.providers += $new' "$CPM_CONFIG_FILE" > "$CPM_CONFIG_FILE.tmp" \
        && mv "$CPM_CONFIG_FILE.tmp" "$CPM_CONFIG_FILE"
      echo "Imported $new_count new provider(s) into $CPM_CONFIG_FILE"
    else
      echo "All providers already exist. Nothing to import."
    fi
  else
    mkdir -p "$CPM_CONFIG_DIR"
    printf '%s' "$imported" | jq '{providers: .}' > "$CPM_CONFIG_FILE"
    echo "Created $CPM_CONFIG_FILE with $count provider(s)"
  fi

  echo ""
  echo "Remember to set your API key env vars:"
  printf '%s' "$imported" | jq -r '.[] | "  export \(.api_key_env)=your-key-here"'
}
