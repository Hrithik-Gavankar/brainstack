#!/usr/bin/env bash
# Engineer Brain Scanner
# Scans all git repos under your workspace and outputs structured data
# Usage: bash scan.sh [workspace_path] [days_back]

set -uo pipefail

WORKSPACE="${1:-$HOME/path/to/your/workspace}"
DAYS="${2:-7}"

# CONFIGURE: Set your git author pattern (name, username, email fragments)
AUTHOR_PATTERN="your-name\|your-username\|your-email"

SINCE_DATE=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%d 2>/dev/null)

echo "=== ENGINEER BRAIN SCAN ==="
echo "Workspace: $WORKSPACE"
echo "Period: last $DAYS days (since $SINCE_DATE)"
echo "Scan time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

echo "## RECENT COMMITS"
echo ""
for dir in "$WORKSPACE"/*/; do
  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")
  commits=$(git -C "$dir" log --all --author="$AUTHOR_PATTERN" \
    --format="%h|%ad|%s" --date=short --since="$SINCE_DATE" 2>/dev/null || true)
  if [ -n "$commits" ]; then
    echo "### $name"
    echo "$commits"
    echo ""
  fi
done

echo "## ACTIVE BRANCHES"
echo ""
for dir in "$WORKSPACE"/*/; do
  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")
  current=$(git -C "$dir" branch --show-current 2>/dev/null || echo "detached")
  if [ "$current" != "main" ] && [ "$current" != "master" ] && [ "$current" != "detached" ]; then
    ahead=$(git -C "$dir" log --oneline "main..HEAD" 2>/dev/null | wc -l | tr -d ' ')
    echo "- $name: **$current** ($ahead commits ahead of main)"
  fi
done
echo ""

echo "## UNCOMMITTED CHANGES"
echo ""
for dir in "$WORKSPACE"/*/; do
  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")
  status=$(git -C "$dir" status --porcelain 2>/dev/null | head -5)
  if [ -n "$status" ]; then
    echo "### $name"
    echo "$status"
    echo ""
  fi
done

echo "## COMMIT TYPE BREAKDOWN (last $DAYS days)"
echo ""
for dir in "$WORKSPACE"/*/; do
  [ -d "$dir/.git" ] || continue
  git -C "$dir" log --all --author="$AUTHOR_PATTERN" \
    --format="%s" --since="$SINCE_DATE" 2>/dev/null || true
done | grep -oE "^(fix|feat|refactor|test|chore|docs|style|ci|perf|build)" | sort | uniq -c | sort -rn
echo ""

echo "## FILES TOUCHED (last $DAYS days)"
echo ""
for dir in "$WORKSPACE"/*/; do
  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")
  files=$(git -C "$dir" log --all --author="$AUTHOR_PATTERN" \
    --name-only --format="" --since="$SINCE_DATE" 2>/dev/null | sort -u)
  if [ -n "$files" ]; then
    echo "### $name"
    echo "$files" | head -20
    echo ""
  fi
done

echo "## VELOCITY"
echo ""
total=0
for dir in "$WORKSPACE"/*/; do
  [ -d "$dir/.git" ] || continue
  count=$(git -C "$dir" log --all --author="$AUTHOR_PATTERN" \
    --oneline --since="$SINCE_DATE" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 0 ]; then
    name=$(basename "$dir")
    echo "- $name: $count commits"
    total=$((total + count))
  fi
done
echo "- **TOTAL: $total commits in $DAYS days**"
echo ""

echo "=== SCAN COMPLETE ==="
