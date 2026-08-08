#!/usr/bin/env bash
# Engineer Brain Scanner
# Scans git repos under your workspace + optional GitHub activity (gh)
#
# Usage:
#   bash scan.sh [workspace_path] [days_back]
#   bash scan.sh [workspace_path] [days_back] --json
#   bash scan.sh --json [workspace_path] [days_back]
#
# Text mode (default) prints human/AI-readable sections.
# --json emits one JSON object on stdout (requires python3); stderr stays quiet
# except for fatal errors. Pipe to jq for filtering.

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: scan.sh [workspace_path] [days_back] [--json]
       scan.sh --json [workspace_path] [days_back]
       scan.sh --help

Options:
  --json    Emit structured JSON (requires python3). Default is text.
  --help    Show this help and exit.

Positional:
  workspace_path   Directory containing git repos (default: configured WORKSPACE)
  days_back        Lookback window in days (default: 7)
EOF
}

OUTPUT_FORMAT="text"
POSITIONAL=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      OUTPUT_FORMAT="json"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        POSITIONAL+=("$1")
        shift
      done
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# CONFIGURE: default workspace (install.sh / first positional override this)
WORKSPACE="${POSITIONAL[0]:-$HOME/path/to/your/workspace}"
DAYS="${POSITIONAL[1]:-7}"

if [ "${#POSITIONAL[@]}" -gt 2 ]; then
  echo "error: unexpected arguments: ${POSITIONAL[*]:2}" >&2
  usage >&2
  exit 2
fi

if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || [ "$DAYS" -lt 1 ]; then
  echo "error: days_back must be a positive integer (got: $DAYS)" >&2
  exit 2
fi

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
SCAN_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
SCAN_TIME_LOCAL=$(date '+%Y-%m-%d %H:%M:%S')

is_personal_repo() {
  [ -z "$PERSONAL_REPOS" ] && return 1
  echo "$1" | grep -Eq "^($PERSONAL_REPOS)$"
}

commit_type() {
  # Conventional-commit prefix; empty string when none match.
  echo "$1" | grep -oE "^(fix|feat|refactor|test|chore|docs|style|ci|perf|build)" | head -1 || true
}

# ---------------------------------------------------------------------------
# Collect once into a temp workspace, then emit text or JSON.
# ---------------------------------------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

COMMITS_TSV="$TMP/commits.tsv"
BRANCHES_TSV="$TMP/branches.tsv"
UNCOMMITTED_TSV="$TMP/uncommitted.tsv"
FILES_TSV="$TMP/files.tsv"
VELOCITY_TSV="$TMP/velocity.tsv"
PRS_JSON="$TMP/authored_prs.json"
REVIEWS_JSON="$TMP/reviews.json"
RELEASES_TSV="$TMP/releases.tsv"
GH_STATUS="$TMP/gh_status.txt"

: >"$COMMITS_TSV"
: >"$BRANCHES_TSV"
: >"$UNCOMMITTED_TSV"
: >"$FILES_TSV"
: >"$VELOCITY_TSV"
: >"$RELEASES_TSV"
echo "unavailable" >"$GH_STATUS"
echo "[]" >"$PRS_JSON"
echo "[]" >"$REVIEWS_JSON"

# Collect local git signals
for dir in "$WORKSPACE"/*/; do
  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")
  personal="false"
  if is_personal_repo "$name"; then
    personal="true"
  fi

  # Commits
  while IFS='|' read -r hash cdate subject; do
    [ -n "${hash:-}" ] || continue
    ctype=$(commit_type "$subject")
    # TSVs use ASCII unit separator-ish fields; tabs in subject are flattened.
    safe_subject=${subject//$'\t'/ }
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$name" "$hash" "$cdate" "$safe_subject" "$ctype" "$personal" >>"$COMMITS_TSV"
  done < <(git -C "$dir" log --all --author="$AUTHOR_PATTERN" \
    --format="%h|%ad|%s" --date=short --since="$SINCE_DATE" 2>/dev/null || true)

  # Active non-default branches
  current=$(git -C "$dir" branch --show-current 2>/dev/null || echo "detached")
  if [ "$current" != "main" ] && [ "$current" != "master" ] && [ "$current" != "detached" ]; then
    ahead=$(git -C "$dir" log --oneline "main..HEAD" 2>/dev/null | wc -l | tr -d ' ')
    printf '%s\t%s\t%s\n' "$name" "$current" "$ahead" >>"$BRANCHES_TSV"
  fi

  # Uncommitted (first 5 porcelain lines, matching text mode)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    safe_line=${line//$'\t'/ }
    printf '%s\t%s\n' "$name" "$safe_line" >>"$UNCOMMITTED_TSV"
  done < <(git -C "$dir" status --porcelain 2>/dev/null | head -5 || true)

  # Files + velocity exclude personal repos (team metrics)
  if [ "$personal" = "false" ]; then
    while IFS= read -r fpath; do
      [ -n "$fpath" ] || continue
      safe_path=${fpath//$'\t'/ }
      printf '%s\t%s\n' "$name" "$safe_path" >>"$FILES_TSV"
    done < <(git -C "$dir" log --all --author="$AUTHOR_PATTERN" \
      --name-only --format="" --since="$SINCE_DATE" 2>/dev/null | sort -u | head -20 || true)

    count=$(git -C "$dir" log --all --author="$AUTHOR_PATTERN" \
      --oneline --since="$SINCE_DATE" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
      printf '%s\t%s\n' "$name" "$count" >>"$VELOCITY_TSV"
    fi
  fi
done

# Collect optional GitHub activity
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "available" >"$GH_STATUS"

  gh search prs --author=@me --updated=">=${SINCE_DATE}" --limit 20 \
    --json repository,number,title,state,updatedAt \
    >"$PRS_JSON" 2>/dev/null || echo "[]" >"$PRS_JSON"

  if [ "${#GH_OWNERS[@]}" -gt 0 ] && command -v python3 >/dev/null 2>&1; then
    owners_re=$(IFS='|'; echo "${GH_OWNERS[*]}")
    OWNERS_RE="$owners_re" gh search prs --reviewed-by=@me --updated=">=${SINCE_DATE}" --limit 20 \
      --json repository,number,title,state,updatedAt \
      2>/dev/null \
      | python3 -c '
import json, os, re, sys
# GH_OWNERS entries are org/owner name fragments joined by "|"; treat as regex alternation
# (same contract as the previous jq test() filter).
owners = re.compile("^(%s)/" % os.environ["OWNERS_RE"])
rows = json.load(sys.stdin)
print(json.dumps([
    r for r in rows
    if owners.match((r.get("repository") or {}).get("nameWithOwner") or "")
]))
' >"$REVIEWS_JSON" || echo "[]" >"$REVIEWS_JSON"
  else
    # Unfiltered when GH_OWNERS empty, or python3 missing (filter needs python3).
    gh search prs --reviewed-by=@me --updated=">=${SINCE_DATE}" --limit 20 \
      --json repository,number,title,state,updatedAt \
      >"$REVIEWS_JSON" 2>/dev/null || echo "[]" >"$REVIEWS_JSON"
  fi

  if [ "${#RELEASE_REPOS[@]}" -gt 0 ]; then
    for repo in "${RELEASE_REPOS[@]}"; do
      while IFS= read -r rel_line; do
        [ -n "$rel_line" ] || continue
        tag=${rel_line%%$'\t'*}
        pub=${rel_line#*$'\t'}
        printf '%s\t%s\t%s\n' "$repo" "$tag" "$pub" >>"$RELEASES_TSV"
      done < <(
        gh release list --repo "$repo" --limit 2 2>/dev/null \
          | awk -v since="$SINCE_DATE" 'BEGIN{OFS="\t"} {
              # gh columns: TITLE  TYPE  TAG NAME  PUBLISHED
              tag=$3; pub=$4
              if (pub >= since) print tag, pub
            }' || true
      )
    done
  fi
fi

emit_text() {
  echo "=== ENGINEER BRAIN SCAN ==="
  echo "Workspace: $WORKSPACE"
  echo "Period: last $DAYS days (since $SINCE_DATE)"
  echo "Scan time: $SCAN_TIME_LOCAL"
  echo ""

  echo "## RECENT COMMITS"
  echo ""
  current_repo=""
  while IFS=$'\t' read -r repo hash cdate subject ctype personal; do
    [ -n "$repo" ] || continue
    if [ "$repo" != "$current_repo" ]; then
      [ -n "$current_repo" ] && echo ""
      if [ "$personal" = "true" ]; then
        echo "### $repo (personal — exclude from team standup)"
      else
        echo "### $repo"
      fi
      current_repo="$repo"
    fi
    echo "${hash}|${cdate}|${subject}"
  done <"$COMMITS_TSV"
  [ -n "$current_repo" ] && echo ""
  [ -s "$COMMITS_TSV" ] || true

  echo "## ACTIVE BRANCHES"
  echo ""
  while IFS=$'\t' read -r repo branch ahead; do
    [ -n "$repo" ] || continue
    echo "- $repo: **$branch** ($ahead commits ahead of main)"
  done <"$BRANCHES_TSV"
  echo ""

  echo "## UNCOMMITTED CHANGES"
  echo ""
  current_repo=""
  while IFS=$'\t' read -r repo line; do
    [ -n "$repo" ] || continue
    if [ "$repo" != "$current_repo" ]; then
      [ -n "$current_repo" ] && echo ""
      echo "### $repo"
      current_repo="$repo"
    fi
    echo "$line"
  done <"$UNCOMMITTED_TSV"
  [ -n "$current_repo" ] && echo ""

  echo "## COMMIT TYPE BREAKDOWN (last $DAYS days)"
  echo ""
  if [ -s "$COMMITS_TSV" ]; then
    awk -F'\t' '$6 != "true" && $5 != "" { print $5 }' "$COMMITS_TSV" \
      | sort | uniq -c | sort -rn
  fi
  echo ""

  echo "## FILES TOUCHED (last $DAYS days)"
  echo ""
  current_repo=""
  while IFS=$'\t' read -r repo fpath; do
    [ -n "$repo" ] || continue
    if [ "$repo" != "$current_repo" ]; then
      [ -n "$current_repo" ] && echo ""
      echo "### $repo"
      current_repo="$repo"
    fi
    echo "$fpath"
  done <"$FILES_TSV"
  [ -n "$current_repo" ] && echo ""

  echo "## VELOCITY"
  echo ""
  total=0
  while IFS=$'\t' read -r repo count; do
    [ -n "$repo" ] || continue
    echo "- $repo: $count commits"
    total=$((total + count))
  done <"$VELOCITY_TSV"
  echo "- **TOTAL: $total commits in $DAYS days** (team repos only)"
  echo ""

  echo "## GITHUB ACTIVITY (non-commit signals)"
  echo ""
  format_gh_prs() {
    # Prefer jq (common with gh); fall back to python3. Text mode must not
    # hard-require python3 — only --json does.
    local file=$1
    local failed_msg=$2
    if [ ! -s "$file" ]; then
      return 0
    fi
    if command -v jq >/dev/null 2>&1; then
      jq -r '.[] | "\(.repository.nameWithOwner) #\(.number) [\(.state)] \(.title) (\(.updatedAt[0:10]))"' "$file" \
        2>/dev/null || echo "$failed_msg"
    elif command -v python3 >/dev/null 2>&1; then
      FAILED_MSG="$failed_msg" python3 - "$file" <<'PY' || echo "$failed_msg"
import json, os, sys
path = sys.argv[1]
try:
    rows = json.load(open(path, encoding="utf-8"))
except Exception:
    print(os.environ.get("FAILED_MSG", "(gh format failed)"))
    raise SystemExit(0)
for r in rows:
    repo = (r.get("repository") or {}).get("nameWithOwner", "?")
    num = r.get("number", "?")
    state = r.get("state", "?")
    title = r.get("title", "")
    updated = (r.get("updatedAt") or "")[:10]
    print(f"{repo} #{num} [{state}] {title} ({updated})")
PY
    else
      echo "(install jq or python3 to format GitHub activity from cached JSON)"
    fi
  }

  gh_state=$(cat "$GH_STATUS")
  if [ "$gh_state" = "available" ]; then
    echo "### Authored PRs updated since $SINCE_DATE"
    format_gh_prs "$PRS_JSON" "(gh authored PR search failed)"
    echo ""

    echo "### Reviews given (PRs updated since $SINCE_DATE)"
    format_gh_prs "$REVIEWS_JSON" "(gh review search failed)"
    echo ""

    if [ "${#RELEASE_REPOS[@]}" -gt 0 ]; then
      echo "### Recent releases (configured repos)"
      if [ -s "$RELEASES_TSV" ]; then
        while IFS=$'\t' read -r repo tag pub; do
          echo "- $repo: $tag published $pub"
        done <"$RELEASES_TSV"
      fi
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
}

emit_json() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "error: --json requires python3 on PATH" >&2
    exit 1
  fi

  WORKSPACE="$WORKSPACE" DAYS="$DAYS" SINCE_DATE="$SINCE_DATE" \
  SCAN_TIME="$SCAN_TIME" AUTHOR_PATTERN="$AUTHOR_PATTERN" \
  COMMITS_TSV="$COMMITS_TSV" BRANCHES_TSV="$BRANCHES_TSV" \
  UNCOMMITTED_TSV="$UNCOMMITTED_TSV" FILES_TSV="$FILES_TSV" \
  VELOCITY_TSV="$VELOCITY_TSV" PRS_JSON="$PRS_JSON" \
  REVIEWS_JSON="$REVIEWS_JSON" RELEASES_TSV="$RELEASES_TSV" \
  GH_STATUS="$GH_STATUS" \
  python3 <<'PY'
import json
import os
from collections import OrderedDict, defaultdict

def read_tsv(path, nfields):
    rows = []
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return rows
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t", nfields - 1)
            while len(parts) < nfields:
                parts.append("")
            rows.append(parts)
    return rows

commits = []
for repo, hash_, date, message, ctype, personal in read_tsv(os.environ["COMMITS_TSV"], 6):
    commits.append({
        "repo": repo,
        "hash": hash_,
        "date": date,
        "message": message,
        "type": ctype or None,
        "personal": personal == "true",
    })

branches = []
for repo, branch, ahead in read_tsv(os.environ["BRANCHES_TSV"], 3):
    try:
        ahead_n = int(ahead)
    except ValueError:
        ahead_n = 0
    branches.append({
        "repo": repo,
        "branch": branch,
        "ahead_of_main": ahead_n,
    })

uncommitted_map = OrderedDict()
for repo, line in read_tsv(os.environ["UNCOMMITTED_TSV"], 2):
    uncommitted_map.setdefault(repo, []).append(line)
uncommitted = [{"repo": repo, "files": files} for repo, files in uncommitted_map.items()]

type_breakdown = OrderedDict()
counts = defaultdict(int)
for c in commits:
    if c["personal"]:
        continue
    if c["type"]:
        counts[c["type"]] += 1
for key, value in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
    type_breakdown[key] = value

files_map = OrderedDict()
for repo, path in read_tsv(os.environ["FILES_TSV"], 2):
    files_map.setdefault(repo, []).append(path)

per_repo = OrderedDict()
total = 0
for repo, count in read_tsv(os.environ["VELOCITY_TSV"], 2):
    try:
        n = int(count)
    except ValueError:
        n = 0
    per_repo[repo] = n
    total += n

def load_gh_list(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, list) else []
    except Exception:
        return []

def normalize_prs(rows):
    out = []
    for r in rows:
        repo = (r.get("repository") or {}).get("nameWithOwner")
        out.append({
            "repository": repo,
            "number": r.get("number"),
            "title": r.get("title"),
            "state": r.get("state"),
            "updated_at": r.get("updatedAt"),
        })
    return out

releases = []
for repo, tag, published in read_tsv(os.environ["RELEASES_TSV"], 3):
    releases.append({
        "repository": repo,
        "tag": tag,
        "published": published,
    })

gh_available = open(os.environ["GH_STATUS"], encoding="utf-8").read().strip() == "available"

payload = {
    "metadata": {
        "workspace": os.environ["WORKSPACE"],
        "period_days": int(os.environ["DAYS"]),
        "since": os.environ["SINCE_DATE"],
        "scan_time": os.environ["SCAN_TIME"],
        "author_pattern": os.environ["AUTHOR_PATTERN"],
    },
    "commits": commits,
    "branches": branches,
    "uncommitted": uncommitted,
    "type_breakdown": type_breakdown,
    "files_touched": files_map,
    "velocity": {
        "total": total,
        "period_days": int(os.environ["DAYS"]),
        "per_repo": per_repo,
        "scope": "team_repos_only",
    },
    "github": {
        "available": gh_available,
        "authored_prs": normalize_prs(load_gh_list(os.environ["PRS_JSON"])) if gh_available else [],
        "reviews": normalize_prs(load_gh_list(os.environ["REVIEWS_JSON"])) if gh_available else [],
        "releases": releases if gh_available else [],
    },
}

print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=False))
PY
}

case "$OUTPUT_FORMAT" in
  json) emit_json ;;
  text) emit_text ;;
  *)
    echo "error: unknown output format: $OUTPUT_FORMAT" >&2
    exit 2
    ;;
esac
