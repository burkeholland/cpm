# cpm — Copilot Provider Model Switcher

Switch between BYOK (Bring Your Own Key) models for [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models) with one command.

```
$ cpm
Pick a model:

  1) MiniMax > MiniMax-M2.7
  2) Ollama > llama3.2
  3) Anthropic > claude-opus-4-5

Enter number (1-3): 1

✓ Switched to MiniMax > MiniMax-M2.7
```

## Install

**Bash / Zsh (macOS, Linux)**

```bash
git clone https://github.com/your-user/cpm.git && cd cpm && bash install.sh
```

**PowerShell (Windows, macOS, Linux)**

```powershell
git clone https://github.com/your-user/cpm.git; cd cpm; .\install.ps1
```

The installer will:

1. Copy the shell function to `~/.config/cpm/`
2. Create a default `models.json` config
3. Offer to import models from VS Code (if found)
4. Add a `source` line to your shell rc file

## Dependencies

| Shell | Dependency |
|---|---|
| Bash / Zsh | [`jq`](https://jqlang.github.io/jq/) |
| PowerShell | None (uses built-in `ConvertFrom-Json`) |

Install jq:

```bash
# macOS
brew install jq

# Ubuntu / Debian
sudo apt install jq

# Fedora
sudo dnf install jq
```

## Commands

| Command | Description |
|---|---|
| `cpm` | Interactive model picker |
| `cpm status` | Show the currently active model and env vars |
| `cpm list` | List all configured models |
| `cpm keys` | Show API key status and set missing keys |
| `cpm edit` | Open `models.json` in `$EDITOR` |
| `cpm import` | Import models from VS Code `chatLanguageModels.json` |
| `cpm clear` | Unset all Copilot provider env vars |
| `cpm help` | Show help |

## Configuration

Config lives at `~/.config/cpm/models.json`:

```json
{
  "providers": [
    {
      "name": "MiniMax",
      "base_url": "https://api.minimax.io/v1",
      "provider_type": "openai",
      "api_key_env": "MINIMAX_API_KEY",
      "models": [
        {
          "id": "MiniMax-M2.7",
          "max_prompt_tokens": 128000,
          "max_output_tokens": 16000
        }
      ]
    }
  ]
}
```

### Field reference

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Display name for the provider |
| `base_url` | Yes | Provider API base URL |
| `provider_type` | No | `openai` (default), `azure`, or `anthropic` |
| `api_key_env` | No | Name of env var holding the API key. Empty or omitted = no auth (e.g. Ollama) |
| `models[].id` | Yes | Model identifier passed to the provider |
| `models[].max_prompt_tokens` | No | Sets `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` |
| `models[].max_output_tokens` | No | Sets `COPILOT_PROVIDER_MAX_OUTPUT_TOKENS` |

### Adding a provider

Edit the config directly:

```bash
cpm edit
```

Or add a block to the `providers` array:

```json
{
  "name": "Ollama",
  "base_url": "http://localhost:11434",
  "provider_type": "openai",
  "api_key_env": "",
  "models": [
    { "id": "llama3.2", "max_prompt_tokens": 128000, "max_output_tokens": 4096 },
    { "id": "qwen2.5-coder", "max_prompt_tokens": 128000, "max_output_tokens": 8192 }
  ]
}
```

## Setting API Keys

`cpm` never stores API keys in the config file — it reads them from environment variables.

The easiest way to set keys is:

```bash
cpm keys
```

This shows which keys are set and which are missing, then prompts you to paste any missing keys. The keys are exported in your current session **and** saved to your shell profile (`~/.zshrc` or `~/.bashrc`) for persistence.

You can also be prompted inline: when you pick a model with `cpm` and the key is missing, it will ask you to paste it right then.

Alternatively, set them manually in your shell profile:

```bash
# ~/.bashrc or ~/.zshrc
export MINIMAX_API_KEY="your-key-here"
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
```

```powershell
# PowerShell $PROFILE
$env:MINIMAX_API_KEY = "your-key-here"
$env:ANTHROPIC_API_KEY = "sk-ant-..."
```

If the referenced env var is not set when you pick a model, `cpm` will warn you.

## VS Code Import

If you've configured custom models in VS Code (Stable or Insiders) via the BYOK model picker, `cpm` can import them:

```bash
cpm import
```

This reads `chatLanguageModels.json`, skips GitHub-hosted models, and maps each entry into the cpm config format. It generates env var names automatically (e.g. `MINIMAX_API_KEY`) — you'll need to set the actual key values yourself.

## Environment Variables Set

When you pick a model, `cpm` exports these into your current shell:

| Variable | Source |
|---|---|
| `COPILOT_PROVIDER_BASE_URL` | `providers[].base_url` |
| `COPILOT_PROVIDER_TYPE` | `providers[].provider_type` |
| `COPILOT_PROVIDER_API_KEY` | Resolved from `providers[].api_key_env` |
| `COPILOT_MODEL` | `models[].id` |
| `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` | `models[].max_prompt_tokens` (if set) |
| `COPILOT_PROVIDER_MAX_OUTPUT_TOKENS` | `models[].max_output_tokens` (if set) |

Run `cpm clear` to unset all of them and return to the default GitHub-hosted model.

## How It Works

`cpm` is a **shell function** (not a standalone script) because it needs to set environment variables in your current shell session. That's why it's sourced rather than executed.

## License

MIT
