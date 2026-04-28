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
  local _global=0

  if [ "$sub" = "--global" ]; then
    _global=1
    shift
    sub="${1:-}"
  fi

  case "$sub" in
    status)  _cpm_status ;;
    list)    _cpm_list ;;
    add)     _cpm_add ;;
    remove)  _cpm_remove ;;
    update)  _cpm_update ;;
    edit)    _cpm_edit ;;
    import)  _cpm_import ;;
    clear)   _cpm_clear ;;
    keys)    _cpm_keys ;;
    config)  shift; _cpm_config "$@" ;;
    uninstall) _cpm_uninstall ;;
    help)    _cpm_help ;;
    --help)  _cpm_help ;;
    -h)      _cpm_help ;;
    "")      _cpm_pick "$_global" ;;
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

# ── config get/set ──────────────────────────────────────────────────────

_cpm_config() {
  local key="${1:-}"
  local val="${2:-}"

  if [ -z "$key" ]; then
    echo "Usage: cpm config <key> [value]"
    echo ""
    echo "Keys:"
    echo "  launch   Command to run after picking a model (default: copilot)"
    echo ""
    echo "Examples:"
    echo "  cpm config launch            # show current value"
    echo "  cpm config launch yolo        # set to 'yolo'"
    echo '  cpm config launch ""          # disable auto-launch'
    return 0
  fi

  case "$key" in
    launch)
      if [ -z "$val" ] && [ "$#" -lt 2 ]; then
        # show current value
        local current
        current=$(jq -r '.launch // "copilot"' "$CPM_CONFIG_FILE")
        if [ -z "$current" ]; then
          echo "launch: (disabled)"
        else
          echo "launch: $current"
        fi
      else
        # set value (including empty string to disable)
        jq --arg v "$val" '.launch = $v' "$CPM_CONFIG_FILE" > "$CPM_CONFIG_FILE.tmp" \
          && mv "$CPM_CONFIG_FILE.tmp" "$CPM_CONFIG_FILE"
        if [ -z "$val" ]; then
          echo "✓ Auto-launch disabled"
        else
          echo "✓ launch set to: $val"
        fi
      fi
      ;;
    *)
      echo "cpm config: unknown key '$key'" >&2
      return 1
      ;;
  esac
}

# ── launch copilot (or configured command) ──────────────────────────────

_cpm_launch() {
  local cmd
  cmd=$(jq -r '.launch // "copilot"' "$CPM_CONFIG_FILE")
  if [ -n "$cmd" ]; then
    eval "$cmd"
  fi
}

# ── add provider/model wizard ────────────────────────────────────────────

_cpm_add() {
  echo "Add a model"
  echo ""

  # Step 1: pick or create provider
  local provider_count provider_names
  provider_count=$(jq '.providers | length' "$CPM_CONFIG_FILE")

  local provider_idx=-1
  if [ "$provider_count" -gt 0 ]; then
    echo "Provider:"
    local pi=0
    while [ "$pi" -lt "$provider_count" ]; do
      local pn
      pn=$(jq -r ".providers[$pi].name" "$CPM_CONFIG_FILE")
      echo "  $((pi + 1))) $pn"
      pi=$((pi + 1))
    done
    echo "  $((provider_count + 1))) + New provider"
    echo ""

    local pchoice
    while true; do
      printf "Pick a provider (1-%d): " "$((provider_count + 1))"
      read -r pchoice
      case "$pchoice" in
        ''|*[!0-9]*) echo "Invalid choice." >&2; continue ;;
      esac
      if [ "$pchoice" -ge 1 ] && [ "$pchoice" -le "$((provider_count + 1))" ]; then
        break
      fi
      echo "Invalid choice." >&2
    done

    if [ "$pchoice" -le "$provider_count" ]; then
      provider_idx=$((pchoice - 1))
    fi
  fi

  # Step 2: create new provider if needed
  if [ "$provider_idx" -eq -1 ]; then
    echo ""
    echo "New provider setup:"
    echo ""

    local pname purl ptype pkey

    printf "  Name (e.g. OpenRouter, Ollama): "
    read -r pname
    if [ -z "$pname" ]; then
      echo "Cancelled." >&2
      return 1
    fi

    printf "  Base URL (e.g. https://openrouter.ai/api/v1): "
    read -r purl
    if [ -z "$purl" ]; then
      echo "Cancelled." >&2
      return 1
    fi

    printf "  Provider type [openai]: "
    read -r ptype
    ptype="${ptype:-openai}"

    printf "  API key env var name (e.g. OPENROUTER_API_KEY, blank for none): "
    read -r pkey

    # Append new provider with empty models array
    jq --arg n "$pname" --arg u "$purl" --arg t "$ptype" --arg k "$pkey" \
      '.providers += [{ name: $n, base_url: $u, provider_type: $t, api_key_env: $k, models: [] }]' \
      "$CPM_CONFIG_FILE" > "$CPM_CONFIG_FILE.tmp" && mv "$CPM_CONFIG_FILE.tmp" "$CPM_CONFIG_FILE"

    provider_idx=$(jq '.providers | length - 1' "$CPM_CONFIG_FILE")
    echo ""
    echo "  ✓ Provider '$pname' added"

    # Offer to set API key now
    if [ -n "$pkey" ]; then
      eval "_existing_key=\"\${${pkey}:-}\""
      if [ -z "$_existing_key" ]; then
        echo ""
        printf "  Paste your %s now (or Enter to skip): " "$pkey"
        read -r _key_val
        if [ -n "$_key_val" ]; then
          export "$pkey=$_key_val"
          _cpm_persist_key "$pkey" "$_key_val"
          echo "  ✓ Key set and saved to shell profile."
        fi
      fi
    fi
  fi

  # Step 3: add model to the provider
  echo ""
  echo "New model:"
  echo ""

  local mid mprompt moutput

  printf "  Model ID (e.g. gpt-4o, claude-opus-4-5): "
  read -r mid
  if [ -z "$mid" ]; then
    echo "Cancelled." >&2
    return 1
  fi

  printf "  Max prompt tokens [128000]: "
  read -r mprompt
  mprompt="${mprompt:-128000}"

  printf "  Max output tokens [16000]: "
  read -r moutput
  moutput="${moutput:-16000}"

  jq --argjson pi "$provider_idx" --arg id "$mid" --argjson mp "$mprompt" --argjson mo "$moutput" \
    '.providers[$pi].models += [{ id: $id, max_prompt_tokens: $mp, max_output_tokens: $mo }]' \
    "$CPM_CONFIG_FILE" > "$CPM_CONFIG_FILE.tmp" && mv "$CPM_CONFIG_FILE.tmp" "$CPM_CONFIG_FILE"

  local provname
  provname=$(jq -r ".providers[$provider_idx].name" "$CPM_CONFIG_FILE")

  echo ""
  echo "✓ Added $provname > $mid"
}

# ── remove provider/model ────────────────────────────────────────────────

_cpm_remove() {
  echo "Remove a provider or model"
  echo ""

  local provider_count pn model_count mi mid
  provider_count=$(jq '.providers | length' "$CPM_CONFIG_FILE")

  if [ "$provider_count" -eq 0 ]; then
    echo "No providers configured."
    return 0
  fi

  # Show numbered list
  local entries=0 pi=0
  while [ "$pi" -lt "$provider_count" ]; do
    pn=$(jq -r ".providers[$pi].name" "$CPM_CONFIG_FILE")
    model_count=$(jq ".providers[$pi].models | length" "$CPM_CONFIG_FILE")

    entries=$((entries + 1))
    echo "  $entries) ✗ Remove provider '$pn' (and all its models)"

    mi=0
    while [ "$mi" -lt "$model_count" ]; do
      entries=$((entries + 1))
      mid=$(jq -r ".providers[$pi].models[$mi].id" "$CPM_CONFIG_FILE")
      echo "  $entries)   ✗ Remove model '$mid' from $pn"
      mi=$((mi + 1))
    done
    pi=$((pi + 1))
  done
  echo ""

  local choice
  while true; do
    printf "Pick item to remove (1-%d, or 'q' to cancel): " "$entries"
    read -r choice
    if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
      echo "Cancelled."
      return 0
    fi
    case "$choice" in
      ''|*[!0-9]*) echo "Invalid choice." >&2; continue ;;
    esac
    if [ "$choice" -ge 1 ] && [ "$choice" -le "$entries" ]; then
      break
    fi
    echo "Invalid choice." >&2
  done

  # Map choice back to provider/model index
  local idx=0 removed_name removed_mid removed_pn removed_key_env _rm_key rc_file
  pi=0
  while [ "$pi" -lt "$provider_count" ]; do
    model_count=$(jq ".providers[$pi].models | length" "$CPM_CONFIG_FILE")

    idx=$((idx + 1))
    if [ "$idx" -eq "$choice" ]; then
      removed_name=$(jq -r ".providers[$pi].name" "$CPM_CONFIG_FILE")
      removed_key_env=$(jq -r ".providers[$pi].api_key_env // \"\"" "$CPM_CONFIG_FILE")
      jq --argjson i "$pi" 'del(.providers[$i])' "$CPM_CONFIG_FILE" > "$CPM_CONFIG_FILE.tmp" \
        && mv "$CPM_CONFIG_FILE.tmp" "$CPM_CONFIG_FILE"
      echo "✓ Removed provider '$removed_name'"

      # Offer to remove API key from shell profile
      if [ -n "$removed_key_env" ] && [ "$removed_key_env" != "null" ]; then
        rc_file="$HOME/.$(basename "${SHELL:-bash}")rc"
        if [ -f "$rc_file" ] && grep -q "^export ${removed_key_env}=" "$rc_file"; then
          echo ""
          printf "Also remove \$%s from %s? [y/N] " "$removed_key_env" "$rc_file"
          read -r _rm_key
          if [ "$_rm_key" = "y" ] || [ "$_rm_key" = "Y" ]; then
            _cpm_remove_key "$removed_key_env"
          fi
        fi
      fi
      return 0
    fi

    mi=0
    while [ "$mi" -lt "$model_count" ]; do
      idx=$((idx + 1))
      if [ "$idx" -eq "$choice" ]; then
        removed_pn=$(jq -r ".providers[$pi].name" "$CPM_CONFIG_FILE")
        removed_mid=$(jq -r ".providers[$pi].models[$mi].id" "$CPM_CONFIG_FILE")
        jq --argjson pi "$pi" --argjson mi "$mi" 'del(.providers[$pi].models[$mi])' \
          "$CPM_CONFIG_FILE" > "$CPM_CONFIG_FILE.tmp" \
          && mv "$CPM_CONFIG_FILE.tmp" "$CPM_CONFIG_FILE"
        echo "✓ Removed model '$removed_mid' from $removed_pn"
        return 0
      fi
      mi=$((mi + 1))
    done
    pi=$((pi + 1))
  done
}

# ── update provider/model ────────────────────────────────────────────────

_cpm_update() {
  echo "Update a provider or model"
  echo ""
  echo "What do you want to update?"
  echo "  1) A provider's settings"
  echo "  2) A model's settings"
  echo ""

  local what
  while true; do
    printf "Pick (1-2, or 'q' to cancel): "
    read -r what
    if [ "$what" = "q" ] || [ "$what" = "Q" ]; then echo "Cancelled."; return 0; fi
    if [ "$what" = "1" ] || [ "$what" = "2" ]; then break; fi
    echo "Invalid choice." >&2
  done

  local provider_count
  provider_count=$(jq '.providers | length' "$CPM_CONFIG_FILE")

  if [ "$provider_count" -eq 0 ]; then
    echo "No providers configured."
    return 0
  fi

  if [ "$what" = "1" ]; then
    _cpm_update_provider "$provider_count"
  else
    _cpm_update_model "$provider_count"
  fi
}

_cpm_update_provider() {
  local provider_count="$1"
  local pn pi pchoice pidx

  echo ""
  echo "Pick a provider to update:"
  pi=0
  while [ "$pi" -lt "$provider_count" ]; do
    pn=$(jq -r ".providers[$pi].name" "$CPM_CONFIG_FILE")
    echo "  $((pi + 1))) $pn"
    pi=$((pi + 1))
  done
  echo ""

  while true; do
    printf "Pick (1-%d): " "$provider_count"
    read -r pchoice
    case "$pchoice" in
      ''|*[!0-9]*) echo "Invalid choice." >&2; continue ;;
    esac
    if [ "$pchoice" -ge 1 ] && [ "$pchoice" -le "$provider_count" ]; then break; fi
    echo "Invalid choice." >&2
  done

  local pidx=$((pchoice - 1))
  local cur_name cur_url cur_type cur_key

  cur_name=$(jq -r ".providers[$pidx].name" "$CPM_CONFIG_FILE")
  cur_url=$(jq -r ".providers[$pidx].base_url" "$CPM_CONFIG_FILE")
  cur_type=$(jq -r ".providers[$pidx].provider_type // \"openai\"" "$CPM_CONFIG_FILE")
  cur_key=$(jq -r ".providers[$pidx].api_key_env // \"\"" "$CPM_CONFIG_FILE")

  echo ""
  echo "Editing '$cur_name' (press Enter to keep current value):"
  echo ""

  local new_name new_url new_type new_key

  printf "  Name [%s]: " "$cur_name"
  read -r new_name
  new_name="${new_name:-$cur_name}"

  printf "  Base URL [%s]: " "$cur_url"
  read -r new_url
  new_url="${new_url:-$cur_url}"

  printf "  Provider type [%s]: " "$cur_type"
  read -r new_type
  new_type="${new_type:-$cur_type}"

  printf "  API key env var [%s]: " "$cur_key"
  read -r new_key
  new_key="${new_key:-$cur_key}"

  jq --argjson i "$pidx" --arg n "$new_name" --arg u "$new_url" --arg t "$new_type" --arg k "$new_key" \
    '.providers[$i].name = $n | .providers[$i].base_url = $u | .providers[$i].provider_type = $t | .providers[$i].api_key_env = $k' \
    "$CPM_CONFIG_FILE" > "$CPM_CONFIG_FILE.tmp" && mv "$CPM_CONFIG_FILE.tmp" "$CPM_CONFIG_FILE"

  echo ""
  echo "✓ Updated provider '$new_name'"
}

_cpm_update_model() {
  local provider_count="$1"
  local pn model_count mi mid mchoice
  local total=0 pi=0 idx=0 target_pi=0 target_mi=0

  # Build flat list of all models
  echo ""
  echo "Pick a model to update:"
  while [ "$pi" -lt "$provider_count" ]; do
    pn=$(jq -r ".providers[$pi].name" "$CPM_CONFIG_FILE")
    model_count=$(jq ".providers[$pi].models | length" "$CPM_CONFIG_FILE")
    mi=0
    while [ "$mi" -lt "$model_count" ]; do
      total=$((total + 1))
      mid=$(jq -r ".providers[$pi].models[$mi].id" "$CPM_CONFIG_FILE")
      echo "  $total) $pn > $mid"
      mi=$((mi + 1))
    done
    pi=$((pi + 1))
  done

  if [ "$total" -eq 0 ]; then
    echo "  No models configured."
    return 0
  fi
  echo ""

  while true; do
    printf "Pick (1-%d): " "$total"
    read -r mchoice
    case "$mchoice" in
      ''|*[!0-9]*) echo "Invalid choice." >&2; continue ;;
    esac
    if [ "$mchoice" -ge 1 ] && [ "$mchoice" -le "$total" ]; then break; fi
    echo "Invalid choice." >&2
  done

  # Map choice to provider/model indices
  pi=0
  while [ "$pi" -lt "$provider_count" ]; do
    model_count=$(jq ".providers[$pi].models | length" "$CPM_CONFIG_FILE")
    mi=0
    while [ "$mi" -lt "$model_count" ]; do
      idx=$((idx + 1))
      if [ "$idx" -eq "$mchoice" ]; then
        target_pi=$pi
        target_mi=$mi
      fi
      mi=$((mi + 1))
    done
    pi=$((pi + 1))
  done

  local cur_id cur_prompt cur_output cur_pn
  cur_pn=$(jq -r ".providers[$target_pi].name" "$CPM_CONFIG_FILE")
  cur_id=$(jq -r ".providers[$target_pi].models[$target_mi].id" "$CPM_CONFIG_FILE")
  cur_prompt=$(jq -r ".providers[$target_pi].models[$target_mi].max_prompt_tokens // 128000" "$CPM_CONFIG_FILE")
  cur_output=$(jq -r ".providers[$target_pi].models[$target_mi].max_output_tokens // 16000" "$CPM_CONFIG_FILE")

  echo ""
  echo "Editing '$cur_pn > $cur_id' (press Enter to keep current value):"
  echo ""

  local new_id new_prompt new_output

  printf "  Model ID [%s]: " "$cur_id"
  read -r new_id
  new_id="${new_id:-$cur_id}"

  printf "  Max prompt tokens [%s]: " "$cur_prompt"
  read -r new_prompt
  new_prompt="${new_prompt:-$cur_prompt}"

  printf "  Max output tokens [%s]: " "$cur_output"
  read -r new_output
  new_output="${new_output:-$cur_output}"

  jq --argjson pi "$target_pi" --argjson mi "$target_mi" \
    --arg id "$new_id" --argjson mp "$new_prompt" --argjson mo "$new_output" \
    '.providers[$pi].models[$mi].id = $id | .providers[$pi].models[$mi].max_prompt_tokens = $mp | .providers[$pi].models[$mi].max_output_tokens = $mo' \
    "$CPM_CONFIG_FILE" > "$CPM_CONFIG_FILE.tmp" && mv "$CPM_CONFIG_FILE.tmp" "$CPM_CONFIG_FILE"

  echo ""
  echo "✓ Updated $cur_pn > $new_id"
}

_cpm_help() {
  cat <<'EOF'
Usage: cpm [--global] [command]

Flags:
  --global  Keep COPILOT_* env vars set in the current shell after launch
            (by default they are only set for the duration of the launched session)

Commands:
  (none)    Interactive model picker
  status    Show the currently active model
  list      List all configured models
  add       Add a new provider or model
  remove    Remove a provider or model
  update    Edit a provider or model's settings
  keys      Show / set API keys for all providers
  config    Get/set config values (e.g. cpm config launch yolo)
  edit      Open models.json in $EDITOR
  import    Import models from VS Code chatLanguageModels.json
  clear     Unset all Copilot provider env vars
  uninstall Remove cpm config, script, and profile entries
  help      Show this help
EOF
}

_cpm_uninstall() {
  printf "This will remove cpm config and scripts. Continue? [y/N] "
  read -r answer
  if [ "$answer" != "y" ]; then
    echo "Cancelled."
    return 0
  fi

  # Remove source lines from shell rc files
  local rc_files=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile")
  for rc in "${rc_files[@]}"; do
    if [ -f "$rc" ] && grep -qF "cpm" "$rc"; then
      grep -vF "cpm" "$rc" > "${rc}.tmp" && mv "${rc}.tmp" "$rc"
      echo "[ok] Cleaned $rc"
    fi
  done

  # Remove config directory
  if [ -d "$CPM_CONFIG_DIR" ]; then
    rm -rf "$CPM_CONFIG_DIR"
    echo "[ok] Removed $CPM_CONFIG_DIR"
  fi

  # Clear env vars
  _cpm_clear

  echo ""
  echo "cpm has been uninstalled. Restart your shell to complete."
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

_cpm_remove_key() {
  local env_name="$1"
  local rc_file=""
  local current_shell
  current_shell=$(basename "${SHELL:-bash}")

  case "$current_shell" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    *)    rc_file="$HOME/.bashrc" ;;
  esac

  if [ -f "$rc_file" ] && grep -q "^export ${env_name}=" "$rc_file"; then
    local tmp_rc
    tmp_rc=$(grep -v "^export ${env_name}=" "$rc_file")
    printf '%s\n' "$tmp_rc" > "$rc_file"
    unset "$env_name"
    echo "  ✓ Removed $env_name from $rc_file"
  fi
}

# ── interactive picker ──────────────────────────────────────────────────

_cpm_pick() {
  local _global="${1:-0}"

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
    _cpm_launch
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
  _cpm_launch
  if [ "$_global" -eq 0 ]; then
    _cpm_clear >/dev/null
  fi
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
