# Agent Instructions

## What this project does

`cpm` (Copilot Provider Model switcher) is a shell function (Bash/Zsh via `cpm.sh`, PowerShell via `cpm.ps1`) that lets users interactively switch between BYOK provider models for GitHub Copilot CLI by setting `COPILOT_*` environment variables.

## Rules for agents

- **Always update `docs/index.html`** whenever you add a new flag/command or change the installation instructions. The commands section (look for `class="cmd-list"`) mirrors the command reference in `README.md` and `_cpm_help`.
- When adding a new flag or command, update all three places: `cpm.sh`, `cpm.ps1`, and `docs/index.html` (and `README.md`).
- Installation instructions appear in the `docs/index.html` hero section (look for `class="install-section"`). Update them if the install commands change.
