#!/usr/bin/env bash
# Engineer Brain — Universal Installer
# Installs engineer-brain for any supported AI coding assistant
# Usage: bash install.sh <platform> [workspace_path]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM="${1:-}"
WORKSPACE="${2:-$(pwd)}"

SUPPORTED_PLATFORMS="cursor, claude-code, vscode-copilot, windsurf, aider, continue-dev"

usage() {
  echo "Engineer Brain — Universal Installer"
  echo ""
  echo "Usage: bash install.sh <platform> [workspace_path]"
  echo ""
  echo "Supported platforms:"
  echo "  cursor         — Cursor IDE (rules + skills)"
  echo "  claude-code    — Claude Code (CLAUDE.md)"
  echo "  vscode-copilot — VS Code + GitHub Copilot (.github/copilot-instructions.md)"
  echo "  windsurf       — Windsurf / Codeium (.windsurfrules)"
  echo "  aider          — Aider (CONVENTIONS.md)"
  echo "  continue-dev   — Continue.dev (.continue/rules.md)"
  echo ""
  echo "Examples:"
  echo "  bash install.sh cursor ~/my-workspace"
  echo "  bash install.sh claude-code ."
  echo "  bash install.sh windsurf"
  echo ""
  exit 1
}

if [ -z "$PLATFORM" ]; then
  usage
fi

if [[ ! "$SUPPORTED_PLATFORMS" == *"$PLATFORM"* ]]; then
  echo "Error: Unsupported platform '$PLATFORM'"
  echo "Supported: $SUPPORTED_PLATFORMS"
  exit 1
fi

echo "Installing Engineer Brain for: $PLATFORM"
echo "Target workspace: $WORKSPACE"
echo ""

install_core() {
  mkdir -p "$WORKSPACE/.engineer-brain/scripts"
  cp "$SCRIPT_DIR/core/BRAIN.md" "$WORKSPACE/.engineer-brain/BRAIN.md"
  cp "$SCRIPT_DIR/core/scripts/scan.sh" "$WORKSPACE/.engineer-brain/scripts/scan.sh"
  cp "$SCRIPT_DIR/core/COMMANDS.md" "$WORKSPACE/.engineer-brain/COMMANDS.md"
  chmod +x "$WORKSPACE/.engineer-brain/scripts/scan.sh"
  echo "  [OK] Core files installed to .engineer-brain/"
}

install_cursor() {
  mkdir -p "$WORKSPACE/.cursor/rules"
  mkdir -p "$WORKSPACE/.cursor/skills/engineer-brain/scripts"
  cp "$SCRIPT_DIR/platforms/cursor/rules/engineer-brain.mdc" "$WORKSPACE/.cursor/rules/"
  cp "$SCRIPT_DIR/platforms/cursor/skills/engineer-brain/SKILL.md" "$WORKSPACE/.cursor/skills/engineer-brain/"
  cp "$SCRIPT_DIR/core/BRAIN.md" "$WORKSPACE/.cursor/skills/engineer-brain/BRAIN.md"
  cp "$SCRIPT_DIR/core/scripts/scan.sh" "$WORKSPACE/.cursor/skills/engineer-brain/scripts/scan.sh"
  chmod +x "$WORKSPACE/.cursor/skills/engineer-brain/scripts/scan.sh"
  echo "  [OK] Cursor rules and skills installed to .cursor/"
}

install_claude_code() {
  install_core
  cp "$SCRIPT_DIR/platforms/claude-code/CLAUDE.md" "$WORKSPACE/CLAUDE.md"
  echo "  [OK] Claude Code instructions installed (CLAUDE.md)"
}

install_vscode_copilot() {
  install_core
  mkdir -p "$WORKSPACE/.github"
  cp "$SCRIPT_DIR/platforms/vscode-copilot/.github/copilot-instructions.md" "$WORKSPACE/.github/"
  echo "  [OK] Copilot instructions installed (.github/copilot-instructions.md)"
}

install_windsurf() {
  install_core
  cp "$SCRIPT_DIR/platforms/windsurf/.windsurfrules" "$WORKSPACE/.windsurfrules"
  echo "  [OK] Windsurf rules installed (.windsurfrules)"
}

install_aider() {
  install_core
  cp "$SCRIPT_DIR/platforms/aider/CONVENTIONS.md" "$WORKSPACE/CONVENTIONS.md"
  echo "  [OK] Aider conventions installed (CONVENTIONS.md)"
  echo ""
  echo "  Note: Add this to your .aider.conf.yml:"
  echo "    read:"
  echo "      - CONVENTIONS.md"
  echo "      - .engineer-brain/BRAIN.md"
  echo "      - .engineer-brain/COMMANDS.md"
}

install_continue_dev() {
  install_core
  mkdir -p "$WORKSPACE/.continue"
  cp "$SCRIPT_DIR/platforms/continue-dev/.continue/rules.md" "$WORKSPACE/.continue/"
  echo "  [OK] Continue.dev rules installed (.continue/rules.md)"
}

case "$PLATFORM" in
  cursor)
    install_cursor
    ;;
  claude-code)
    install_claude_code
    ;;
  vscode-copilot)
    install_vscode_copilot
    ;;
  windsurf)
    install_windsurf
    ;;
  aider)
    install_aider
    ;;
  continue-dev)
    install_continue_dev
    ;;
esac

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Edit the context file — fill in [YOUR NAME], [YOUR ROLE], etc."
echo "  2. Edit .engineer-brain/scripts/scan.sh — set WORKSPACE and AUTHOR_PATTERN"
echo "  3. Run 'engineer-brain update' in your AI assistant to auto-populate BRAIN.md"
echo ""
echo "For full docs: https://github.com/Hrithik-Gavankar/engineer-brain"
