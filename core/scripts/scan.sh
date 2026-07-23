#!/usr/bin/env bash
# Engineer Brain Scanner
# Scans git repos under your workspace + optional GitHub activity (gh)
# Usage: bash scan.sh [workspace_path] [days_back]

set -uo pipefail

# CONFIGURE: default workspace (install.sh / first arg override this)
WORKSPACE="${1:-$HOME/path/to/your/workspace}"
DAYS="${2:-7}"

# CONFIGURE: git author pattern (name, username, email fragments)
AUTHOR_PATTERN="your-name\|your-username\|your-email"

# CONFIGURE: pipe-separated repo basenames to flag/exclude from team standup
# metrics (personal side projects cloned into the same workspace). Empty = none.
PERSONAL_REPOS=""

# CONFIGURE: GitHub org/owner names used to filter review results (bash array).
# Empty array = include reviews from all orgs.
GH_OWNERS=()

# CONFIGURE: repos (owner/name) to check for recent releases. Empty = skip.
RELEASE_REPOS=()

SINCE_DATE=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%d 2>/dev/null)

is_personal_repo() {
  [ -z "$PERSONAL_REPOS" ] && return 1
  echo "$1" | grep -Eq "^($PERSONAL_REPOS)$"
}

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
    if is_personal_repo "$name"; then
      echo "### $name (personal — exclude from team standup)"
    else
      echo "### $name"
    fi
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
  name=$(basename "$dir")
  is_personal_repo "$name" && continue
  git -C "$dir" log --all --author="$AUTHOR_PATTERN" \
    --format="%s" --since="$SINCE_DATE" 2>/dev/null || true
done | grep -oE "^(fix|feat|refactor|test|chore|docs|style|ci|perf|build)" | sort | uniq -c | sort -rn
echo ""

echo "## FILES TOUCHED (last $DAYS days)"
echo ""
for dir in "$WORKSPACE"/*/; do
  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")
  is_personal_repo "$name" && continue
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
  name=$(basename "$dir")
  is_personal_repo "$name" && continue
  count=$(git -C "$dir" log --all --author="$AUTHOR_PATTERN" \
    --oneline --since="$SINCE_DATE" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 0 ]; then
    echo "- $name: $count commits"
    total=$((total + count))
  fi
done
echo "- **TOTAL: $total commits in $DAYS days** (team repos only)"
echo ""

echo "## GITHUB ACTIVITY (non-commit signals)"
echo ""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "### Authored PRs updated since $SINCE_DATE"
  gh search prs --author=@me --updated=">=${SINCE_DATE}" --limit 20 \
    --json repository,number,title,state,updatedAt \
    --jq '.[] | "\(.repository.nameWithOwner) #\(.number) [\(.state)] \(.title) (\(.updatedAt[:10]))"' \
    2>/dev/null || echo "(gh authored PR search failed)"
  echo ""

  echo "### Reviews given (PRs updated since $SINCE_DATE)"
  if [ "${#GH_OWNERS[@]}" -gt 0 ]; then
    owners_re=$(IFS='|'; echo "${GH_OWNERS[*]}")
    gh search prs --reviewed-by=@me --updated=">=${SINCE_DATE}" --limit 20 \
      --json repository,number,title,state,updatedAt \
      --jq ".[] | select(.repository.nameWithOwner | test(\"^(${owners_re})/\")) | \"\\(.repository.nameWithOwner) #\\(.number) [\\(.state)] \\(.title) (\\(.updatedAt[:10]))\"" \
      2>/dev/null || echo "(gh review search failed)"
  else
    gh search prs --reviewed-by=@me --updated=">=${SINCE_DATE}" --limit 20 \
      --json repository,number,title,state,updatedAt \
      --jq '.[] | "\(.repository.nameWithOwner) #\(.number) [\(.state)] \(.title) (\(.updatedAt[:10]))"' \
      2>/dev/null || echo "(gh review search failed)"
  fi
  echo ""

  if [ "${#RELEASE_REPOS[@]}" -gt 0 ]; then
    echo "### Recent releases (configured repos)"
    for repo in "${RELEASE_REPOS[@]}"; do
      rel=$(gh release list --repo "$repo" --limit 2 2>/dev/null \
        | awk -v since="$SINCE_DATE" '{
            tag=$3; pub=$4
            if (pub >= since) print tag " published " pub
          }')
      if [ -n "$rel" ]; then
        echo "- $repo: $rel"
      fi
    done
    echo ""
  else
    echo "### Recent releases"
    echo "(RELEASE_REPOS unset — configure owner/name entries in scan.sh to enable)"
    echo ""
  fi
else
  echo "(gh not available or not authenticated — skipping PR/review/release signals)"
  echo ""
fi

echo "=== SCAN COMPLETE ==="
