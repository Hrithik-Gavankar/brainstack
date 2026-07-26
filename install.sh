#!/usr/bin/env bash
# Engineer Brain — Universal Installer
# Creates a persistent engineering context layer for your AI coding assistant.
#
# Usage:
#   bash install.sh <platform> [workspace_path]
#   bash install.sh --help
#
# Examples:
#   bash install.sh cursor ~/my-workspace
#   bash install.sh claude-code .
#   bash install.sh windsurf

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM="${1:-}"
WORKSPACE="${2:-$(pwd)}"

VERSION="1.0.0"
SUPPORTED_PLATFORMS="cursor claude-code vscode-copilot windsurf aider continue-dev"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
  echo ""
  echo -e "${BOLD}  Engineer Brain${NC} v${VERSION}"
  echo "  A persistent engineering context layer for AI coding assistants."
  echo ""
}

usage() {
  print_banner
  echo "Usage: bash install.sh <platform> [workspace_path]"
  echo ""
  echo "Platforms:"
  echo "  cursor         Cursor IDE (rules + skills)"
  echo "  claude-code    Claude Code (CLAUDE.md)"
  echo "  vscode-copilot VS Code + GitHub Copilot"
  echo "  windsurf       Windsurf / Codeium"
  echo "  aider          Aider CLI"
  echo "  continue-dev   Continue.dev"
  echo ""
  echo "Options:"
  echo "  --help         Show this help message"
  echo "  --version      Show version"
  echo "  --list         List supported platforms"
  echo ""
  echo "Examples:"
  echo "  bash install.sh cursor ~/my-workspace"
  echo "  bash install.sh claude-code ."
  echo ""
  echo "After installation:"
  echo "  1. Fill in your identity (name, role, skills)"
  echo "  2. Run 'engineer-brain update' in your AI assistant"
  echo "  3. That's it — your AI now knows you."
  echo ""
  exit 0
}

success() {
  echo -e "  ${GREEN}✓${NC} $1"
}

info() {
  echo -e "  ${BLUE}→${NC} $1"
}

error() {
  echo -e "  ${RED}✗${NC} $1" >&2
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
fi

if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
  echo "engineer-brain v${VERSION}"
  exit 0
fi

if [ "${1:-}" = "--list" ]; then
  echo "Supported platforms:"
  for p in $SUPPORTED_PLATFORMS; do
    echo "  - $p"
  done
  exit 0
fi

if [ -z "$PLATFORM" ]; then
  print_banner
  error "No platform specified."
  echo ""
  echo "  Run: bash install.sh <platform> [workspace_path]"
  echo "  See: bash install.sh --help"
  echo ""
  exit 1
fi

PLATFORM_VALID=false
for p in $SUPPORTED_PLATFORMS; do
  if [ "$p" = "$PLATFORM" ]; then
    PLATFORM_VALID=true
    break
  fi
done

if [ "$PLATFORM_VALID" = false ]; then
  error "Unsupported platform: '$PLATFORM'"
  echo ""
  echo "  Supported: $SUPPORTED_PLATFORMS"
  echo "  See: bash install.sh --help"
  echo ""
  exit 1
fi

WORKSPACE="$(cd "$WORKSPACE" 2>/dev/null && pwd || echo "$WORKSPACE")"

if [ ! -d "$WORKSPACE" ]; then
  error "Workspace directory does not exist: $WORKSPACE"
  echo "  Create it first or specify a valid path."
  exit 1
fi

print_banner
echo -e "  Platform:  ${BOLD}$PLATFORM${NC}"
echo -e "  Workspace: ${BOLD}$WORKSPACE${NC}"
echo ""

install_core() {
  mkdir -p "$WORKSPACE/.engineer-brain/scripts"
  cp "$SCRIPT_DIR/core/BRAIN.md" "$WORKSPACE/.engineer-brain/BRAIN.md"
  cp "$SCRIPT_DIR/core/scripts/scan.sh" "$WORKSPACE/.engineer-brain/scripts/scan.sh"
  cp "$SCRIPT_DIR/core/scripts/doctor.sh" "$WORKSPACE/.engineer-brain/scripts/doctor.sh"
  cp "$SCRIPT_DIR/core/COMMANDS.md" "$WORKSPACE/.engineer-brain/COMMANDS.md"
  chmod +x "$WORKSPACE/.engineer-brain/scripts/scan.sh"
  chmod +x "$WORKSPACE/.engineer-brain/scripts/doctor.sh"
  success "Core files installed (.engineer-brain/)"
}

detect_git_author() {
  local author_name author_email
  author_name=$(git config --global user.name 2>/dev/null || echo "")
  author_email=$(git config --global user.email 2>/dev/null || echo "")

  if [ -n "$author_name" ] && [ -n "$author_email" ]; then
    echo "${author_name}\\|${author_email}"
  elif [ -n "$author_name" ]; then
    echo "$author_name"
  else
    echo ""
  fi
}

configure_scanner() {
  local scan_file="$1"
  local detected_author
  detected_author=$(detect_git_author)

  if [ -n "$detected_author" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|AUTHOR_PATTERN=\".*\"|AUTHOR_PATTERN=\"$detected_author\"|" "$scan_file" 2>/dev/null || true
    else
      sed -i "s|AUTHOR_PATTERN=\".*\"|AUTHOR_PATTERN=\"$detected_author\"|" "$scan_file" 2>/dev/null || true
    fi
    success "Auto-configured scanner with git author: $detected_author"
  else
    info "Could not detect git author — configure manually in scan.sh"
  fi
}

install_cursor() {
  mkdir -p "$WORKSPACE/.cursor/rules"
  mkdir -p "$WORKSPACE/.cursor/skills/engineer-brain/scripts"
  mkdir -p "$WORKSPACE/.cursor/skills/team-brain/scripts"
  cp "$SCRIPT_DIR/platforms/cursor/rules/engineer-brain.mdc" "$WORKSPACE/.cursor/rules/"
  cp "$SCRIPT_DIR/platforms/cursor/skills/engineer-brain/SKILL.md" "$WORKSPACE/.cursor/skills/engineer-brain/"
  cp "$SCRIPT_DIR/core/BRAIN.md" "$WORKSPACE/.cursor/skills/engineer-brain/BRAIN.md"
  cp "$SCRIPT_DIR/core/scripts/scan.sh" "$WORKSPACE/.cursor/skills/engineer-brain/scripts/scan.sh"
  cp "$SCRIPT_DIR/core/scripts/doctor.sh" "$WORKSPACE/.cursor/skills/engineer-brain/scripts/doctor.sh"
  cp "$SCRIPT_DIR/platforms/cursor/skills/team-brain/SKILL.md" "$WORKSPACE/.cursor/skills/team-brain/"
  cp "$SCRIPT_DIR/core/scripts/team-init.sh" "$WORKSPACE/.cursor/skills/team-brain/scripts/team-init.sh"
  cp "$SCRIPT_DIR/core/team/TEAM_COMMANDS.md" "$WORKSPACE/.cursor/skills/team-brain/TEAM_COMMANDS.md"
  chmod +x "$WORKSPACE/.cursor/skills/engineer-brain/scripts/scan.sh"
  chmod +x "$WORKSPACE/.cursor/skills/engineer-brain/scripts/doctor.sh"
  chmod +x "$WORKSPACE/.cursor/skills/team-brain/scripts/team-init.sh"
  success "Cursor rules and skills installed (.cursor/) — engineer-brain + team-brain"
  configure_scanner "$WORKSPACE/.cursor/skills/engineer-brain/scripts/scan.sh"
}

install_claude_code() {
  install_core
  cp "$SCRIPT_DIR/platforms/claude-code/CLAUDE.md" "$WORKSPACE/CLAUDE.md"
  success "Claude Code instructions installed (CLAUDE.md)"
  configure_scanner "$WORKSPACE/.engineer-brain/scripts/scan.sh"
}

install_vscode_copilot() {
  install_core
  mkdir -p "$WORKSPACE/.github"
  cp "$SCRIPT_DIR/platforms/vscode-copilot/.github/copilot-instructions.md" "$WORKSPACE/.github/"
  success "Copilot instructions installed (.github/copilot-instructions.md)"
  configure_scanner "$WORKSPACE/.engineer-brain/scripts/scan.sh"
}

install_windsurf() {
  install_core
  cp "$SCRIPT_DIR/platforms/windsurf/.windsurfrules" "$WORKSPACE/.windsurfrules"
  success "Windsurf rules installed (.windsurfrules)"
  configure_scanner "$WORKSPACE/.engineer-brain/scripts/scan.sh"
}

install_aider() {
  install_core
  cp "$SCRIPT_DIR/platforms/aider/CONVENTIONS.md" "$WORKSPACE/CONVENTIONS.md"
  success "Aider conventions installed (CONVENTIONS.md)"
  configure_scanner "$WORKSPACE/.engineer-brain/scripts/scan.sh"
}

install_continue_dev() {
  install_core
  mkdir -p "$WORKSPACE/.continue"
  cp "$SCRIPT_DIR/platforms/continue-dev/.continue/rules.md" "$WORKSPACE/.continue/"
  success "Continue.dev rules installed (.continue/rules.md)"
  configure_scanner "$WORKSPACE/.engineer-brain/scripts/scan.sh"
}

case "$PLATFORM" in
  cursor)       install_cursor ;;
  claude-code)  install_claude_code ;;
  vscode-copilot) install_vscode_copilot ;;
  windsurf)     install_windsurf ;;
  aider)        install_aider ;;
  continue-dev) install_continue_dev ;;
esac

echo ""
echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Edit the context file — fill in your name, role, and skills"
echo "  2. Open your AI assistant and run: engineer-brain update"
echo "     (This auto-populates your brain from git history)"
echo ""
echo "  That's it. Your AI now knows you."
echo ""
echo -e "  ${BLUE}Docs:${NC} https://github.com/Hrithik-Gavankar/engineer-brain"
echo ""
