#!/usr/bin/env bash
# Scaffold local Team Brain layout for demo / v1 (file-backed sync).
# Usage: bash team-init.sh [workspace_path]

set -uo pipefail

WORKSPACE="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_SRC="$(cd "$SCRIPT_DIR/../team" && pwd)"
DEST="$WORKSPACE/.team-brain"

if [ -d "$DEST" ] && [ -f "$DEST/team.yaml" ]; then
  echo "Team Brain already present at $DEST"
  echo "Edit TEAM.md / team.yaml / initiatives/ as needed."
  exit 0
fi

mkdir -p "$DEST/initiatives"
cp "$TEAM_SRC/TEAM.md" "$DEST/TEAM.md"
cp "$TEAM_SRC/team.yaml.example" "$DEST/team.yaml"
cp "$TEAM_SRC/initiatives/_TEMPLATE.md" "$DEST/initiatives/_TEMPLATE.md"
cp "$TEAM_SRC/TEAM_COMMANDS.md" "$DEST/TEAM_COMMANDS.md"

# Starter demo initiative (safe to rename/delete)
cp "$TEAM_SRC/initiatives/_TEMPLATE.md" "$DEST/initiatives/DEMO-1.md"
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's/\[INITIATIVE-ID\]/DEMO-1/; s/\[Title\]/Demo initiative/' "$DEST/initiatives/DEMO-1.md" 2>/dev/null || true
else
  sed -i 's/\[INITIATIVE-ID\]/DEMO-1/; s/\[Title\]/Demo initiative/' "$DEST/initiatives/DEMO-1.md" 2>/dev/null || true
fi

cat >> "$DEST/team.yaml" <<'EOF'

# Demo initiative entry (edit or remove)
# initiatives:
#   - id: DEMO-1
#     title: "Demo initiative"
#     status: active
#     file: initiatives/DEMO-1.md
EOF

echo "Team Brain scaffolded at $DEST"
echo "Next:"
echo "  1. Edit $DEST/TEAM.md and $DEST/team.yaml"
echo "  2. Run /team-brain attach DEMO-1 (or your initiative id)"
echo "  3. Share .team-brain/ with teammates via git (commit / PR / pull)"
