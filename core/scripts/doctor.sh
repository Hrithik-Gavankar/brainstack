#!/usr/bin/env bash
# Engineer Brain Doctor
# Health check and completeness score for your engineering brain
# Usage: bash doctor.sh [workspace_path] [brain_path]

set -uo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Brainstack doctor — health check and completeness score"
  echo ""
  echo "Usage: bash doctor.sh [workspace_path] [brain_path]"
  echo ""
  echo "Arguments:"
  echo "  workspace_path   Path to your workspace directory (for live repo scanning)"
  echo "  brain_path       Path to BRAIN.md (default: ../BRAIN.md relative to script)"
  echo ""
  echo "Scores 7 factors: identity completeness, skills freshness, active repos,"
  echo "sprint context, growth roadmap, velocity consistency, and commit diversity."
  echo "Outputs an overall health percentage with actionable suggestions."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${1:-}"
BRAIN_PATH="${2:-$SCRIPT_DIR/../BRAIN.md}"

if [ -z "$WORKSPACE" ]; then
  echo "Warning: No workspace path provided. Live scan will be skipped."
  echo "Usage: bash doctor.sh [workspace_path] [brain_path]"
  echo ""
fi
SCAN_SCRIPT="$SCRIPT_DIR/scan.sh"

NOW_EPOCH=$(date +%s 2>/dev/null)

if [ ! -f "$BRAIN_PATH" ]; then
  echo "Error: BRAIN.md not found at $BRAIN_PATH"
  echo "Run 'engineer-brain update' to create one."
  exit 1
fi

BRAIN=$(cat "$BRAIN_PATH")

# --- Helpers ---

date_to_epoch() {
  local d="$1"
  # Handle YYYY-MM format by appending -01
  if [[ "$d" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
    d="$d-01"
  fi
  date -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null || date -d "$d" +%s 2>/dev/null || echo 0
}

days_since() {
  local epoch
  epoch=$(date_to_epoch "$1")
  if [ "$epoch" -eq 0 ]; then
    echo 9999
    return
  fi
  echo $(( (NOW_EPOCH - epoch) / 86400 ))
}

progress_bar() {
  local score=$1
  local filled=$(( score / 5 ))
  local empty=$(( 20 - filled ))
  local bar=""
  local i
  for (( i=0; i<filled; i++ )); do
    bar="${bar}█"
  done
  for (( i=0; i<empty; i++ )); do
    bar="${bar}░"
  done
  echo "$bar $score%"
}

check_mark() {
  if [ "$1" -eq 1 ]; then
    printf '✓'
  else
    printf '✗'
  fi
}

extract_section() {
  local header="$1"
  echo "$BRAIN" | awk -v h="$header" '
    $0 ~ "^## " h { found=1; next }
    found && /^## / { exit }
    found { print }
  '
}

# --- Scoring Functions ---

COOLING_REPOS=()

score_identity() {
  local section
  section=$(extract_section "Identity")
  local count=0
  local fields=("Name:" "Role:" "Total experience:" "Workspace:" "Primary tools:" "Career goal:")
  for field in "${fields[@]}"; do
    local line
    line=$(echo "$section" | grep -i "\\*\\*${field}\\*\\*" || true)
    if [ -n "$line" ]; then
      local value
      value=$(echo "$line" | sed 's/.*\*\*.*:\*\* *//')
      if [ -n "$value" ] && ! echo "$value" | grep -qE '^\[.*\]$'; then
        count=$((count + 1))
      fi
    fi
  done
  echo $(( count * 100 / 6 ))
}

score_skills_freshness() {
  local section
  section=$(extract_section "Full Skills Inventory")
  local total=0
  local recent=0
  while IFS= read -r line; do
    [[ "$line" == *"---"* ]] && continue
    [[ "$line" == *"Skill"*"Proficiency"* ]] && continue
    if echo "$line" | grep -qE '^\|.*\|.*\|.*\|.*\|'; then
      local last_used
      last_used=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $(NF-1)); print $(NF-1)}')
      [ -z "$last_used" ] && continue
      [[ "$last_used" == *"["*"]"* ]] && continue
      if [[ "$last_used" =~ ^[0-9]{4}-[0-9]{2} ]]; then
        total=$((total + 1))
        local age
        age=$(days_since "$last_used")
        if [ "$age" -le 90 ]; then
          recent=$((recent + 1))
        fi
      fi
    fi
  done <<< "$section"
  if [ "$total" -eq 0 ]; then
    echo 0
    return
  fi
  echo $(( recent * 100 / total ))
}

score_active_repos() {
  local section
  section=$(extract_section "Active Repositories")
  local active=0
  local total=0
  COOLING_REPOS=()
  while IFS= read -r line; do
    [[ "$line" == *"---"* ]] && continue
    [[ "$line" == *"Repo"*"Role"* ]] && continue
    if echo "$line" | grep -qE '^\|.*\|.*\|.*\|.*\|'; then
      local repo last_active
      repo=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
      last_active=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $5); print $5}')
      [ -z "$last_active" ] && continue
      [[ "$last_active" == *"["*"]"* ]] && continue
      if [[ "$last_active" =~ ^[0-9]{4}-[0-9]{2} ]]; then
        total=$((total + 1))
        local age
        age=$(days_since "$last_active")
        if [ "$age" -le 30 ]; then
          active=$((active + 1))
        elif [ "$age" -gt 30 ] && [ "$age" -lt 9999 ]; then
          COOLING_REPOS+=("  - ${repo} (${age} days)")
        fi
      fi
    fi
  done <<< "$section"
  if [ "$total" -eq 0 ]; then
    echo 0
    return
  fi
  echo $(( active * 100 / total ))
}

score_sprint_context() {
  local section
  section=$(extract_section "Current Sprint Context")
  local score=0
  local branch_rows
  branch_rows=$(echo "$section" | grep -cE '^\|.*\|.*\|.*\|' || true)
  local header_rows
  header_rows=$(echo "$section" | grep -cE '^\|.*Repo.*Branch' || true)
  local sep_rows
  sep_rows=$(echo "$section" | grep -cE '^\|.*---' || true)
  local data_rows=$(( branch_rows - header_rows - sep_rows ))
  if [ "$data_rows" -gt 0 ]; then
    local has_real_data
    has_real_data=$(echo "$section" | grep -E '^\|' | grep -v 'Repo' | grep -v '\-\-\-' | grep -vE '^\|.*\[.*\].*\|.*\[.*\]' | head -1 || true)
    if [ -n "$has_real_data" ]; then
      score=$((score + 50))
    fi
  fi
  local achievements
  achievements=$(echo "$section" | grep -cE '^[0-9]+\.' || true)
  if [ "$achievements" -gt 0 ]; then
    local real_achievements
    real_achievements=$(echo "$section" | grep -E '^[0-9]+\.' | grep -v '\[Achievement' | head -1 || true)
    if [ -n "$real_achievements" ]; then
      score=$((score + 50))
    fi
  fi
  echo "$score"
}

score_growth_roadmap() {
  local section
  section=$(extract_section "Growth Areas & Feedback Loop")
  local unchecked checked
  unchecked=$(echo "$section" | grep -cE '^\- \[ \]' || true)
  checked=$(echo "$section" | grep -ciE '^\- \[x\]' || true)
  local total=$((unchecked + checked))
  if [ "$total" -eq 0 ]; then
    echo 0
    return
  fi
  # Base score from completion (0-80%), bonus for having active goals (+20%)
  local base=$(( checked * 80 / total ))
  local bonus=0
  if [ "$unchecked" -gt 0 ]; then
    bonus=20
  fi
  local score=$(( base + bonus ))
  if [ "$score" -gt 100 ]; then
    score=100
  fi
  echo "$score"
}

score_velocity_consistency() {
  local section
  section=$(extract_section "Work Patterns")
  local values=()
  while IFS= read -r line; do
    local count
    count=$(echo "$line" | grep -oE '[0-9]+ commits' | grep -oE '^[0-9]+' || true)
    if [ -n "$count" ]; then
      values+=("$count")
    fi
  done <<< "$section"
  if [ "${#values[@]}" -lt 2 ]; then
    echo 50
    return
  fi
  local drops=0
  local i
  for (( i=1; i<${#values[@]}; i++ )); do
    local prev=${values[$((i-1))]}
    local curr=${values[$i]}
    if [ "$prev" -gt 0 ]; then
      local change=$(( (prev - curr) * 100 / prev ))
      if [ "$change" -gt 30 ]; then
        drops=$((drops + 1))
      fi
    fi
  done
  local score=$(( 100 - drops * 25 ))
  if [ "$score" -lt 0 ]; then
    score=0
  fi
  echo "$score"
}

DOMINANT_TYPE=""
DOMINANT_PCT=0

score_commit_diversity() {
  local breakdown="$1"
  DOMINANT_TYPE=""
  DOMINANT_PCT=0
  if [ -z "$breakdown" ]; then
    local section
    section=$(extract_section "Work Patterns")
    breakdown=$(echo "$section" | grep -E '^\s*(fix|feat|refactor|test|chore|docs|style|ci|perf|build)' || true)
    if [ -z "$breakdown" ]; then
      echo 50
      return
    fi
    local max_pct=0
    local max_type=""
    while IFS= read -r line; do
      local pct
      pct=$(echo "$line" | grep -oE '\([0-9]+%\)' | grep -oE '[0-9]+' || true)
      local typ
      typ=$(echo "$line" | grep -oE '(fix|feat|refactor|test|chore|docs|style|ci|perf|build)' | head -1 || true)
      if [ -n "$pct" ] && [ "$pct" -gt "$max_pct" ]; then
        max_pct=$pct
        max_type=$typ
      fi
    done <<< "$breakdown"
    DOMINANT_TYPE="$max_type"
    DOMINANT_PCT=$max_pct
  else
    local total=0
    local max_count=0
    local max_type=""
    while IFS= read -r line; do
      local count
      count=$(echo "$line" | awk '{print $1}')
      local typ
      typ=$(echo "$line" | awk '{print $2}')
      [ -z "$count" ] && continue
      total=$((total + count))
      if [ "$count" -gt "$max_count" ]; then
        max_count=$count
        max_type=$typ
      fi
    done <<< "$breakdown"
    if [ "$total" -eq 0 ]; then
      echo 50
      return
    fi
    DOMINANT_TYPE="$max_type"
    DOMINANT_PCT=$(( max_count * 100 / total ))
  fi
  if [ "$DOMINANT_PCT" -le 60 ]; then
    echo 100
  else
    local score=$(( 100 - (DOMINANT_PCT - 60) * 100 / 40 ))
    if [ "$score" -lt 0 ]; then
      score=0
    fi
    echo "$score"
  fi
}

# --- Live Scan ---

SCAN_AVAILABLE=0
SCAN_OUTPUT=""
REPOS_TRACKED=0
ACTIVE_THIS_WEEK=0
COMMIT_BREAKDOWN=""

if [ -f "$SCAN_SCRIPT" ] && [ -d "$WORKSPACE" ]; then
  SCAN_OUTPUT=$(bash "$SCAN_SCRIPT" "$WORKSPACE" 30 2>/dev/null || true)
  if [ -n "$SCAN_OUTPUT" ]; then
    SCAN_AVAILABLE=1
    REPOS_TRACKED=$(echo "$SCAN_OUTPUT" | awk '/^## VELOCITY/,/^## |^===/' | grep -cE '^- .+: [0-9]+ commits' || true)
    SEVEN_DAYS_AGO=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d 2>/dev/null)
    ACTIVE_THIS_WEEK=$(echo "$SCAN_OUTPUT" | awk -v cutoff="$SEVEN_DAYS_AGO" '
      /^## RECENT COMMITS/,/^## ACTIVE BRANCHES/ {
        if (/^### /) { repo = substr($0, 5) }
        else if (/\|/) {
          split($0, a, "|")
          if (a[2] >= cutoff) { repos[repo] = 1 }
        }
      }
      END { c=0; for(r in repos) c++; print c }
    ')
    COMMIT_BREAKDOWN=$(echo "$SCAN_OUTPUT" | awk '/^## COMMIT TYPE BREAKDOWN/,/^$/' | grep -E '^\s+[0-9]' || true)
  fi
fi

# --- Compute Scores ---

S_IDENTITY=$(score_identity)
S_SKILLS=$(score_skills_freshness)
S_REPOS=$(score_active_repos)
S_SPRINT=$(score_sprint_context)
S_GROWTH=$(score_growth_roadmap)
S_VELOCITY=$(score_velocity_consistency)
S_DIVERSITY=$(score_commit_diversity "$COMMIT_BREAKDOWN")

OVERALL=$(( (S_IDENTITY * 15 + S_SKILLS * 20 + S_REPOS * 15 + S_SPRINT * 15 + S_GROWTH * 10 + S_VELOCITY * 15 + S_DIVERSITY * 10) / 100 ))

# --- Readiness Checks & Dormant Skills (single pass) ---

SKILLS_UPDATED=0
DORMANT_SKILLS=()
skills_section=$(extract_section "Full Skills Inventory")
while IFS= read -r line; do
  if echo "$line" | grep -qE '^\|.*\|.*\|.*\|.*\|'; then
    [[ "$line" == *"---"* ]] && continue
    [[ "$line" == *"Skill"*"Proficiency"* ]] && continue
    sk_last=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $(NF-1)); print $(NF-1)}')
    if [[ "$sk_last" =~ ^[0-9]{4}-[0-9]{2} ]]; then
      sk_age=$(days_since "$sk_last")
      if [ "$sk_age" -le 30 ]; then
        SKILLS_UPDATED=1
      fi
      sk_prof=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
      if [[ "$sk_prof" == "Strong" ]] && [ "$sk_age" -gt 90 ] && [ "$sk_age" -lt 9999 ]; then
        sk_name=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
        DORMANT_SKILLS+=("${sk_name} expertise hasn't been exercised in ${sk_age} days")
      fi
    fi
  fi
done <<< "$skills_section"

STANDUP_READY=0
if [ "$S_IDENTITY" -ge 50 ] && { [ "$SCAN_AVAILABLE" -eq 1 ] || [ "$S_SPRINT" -gt 0 ]; }; then
  STANDUP_READY=1
fi

QUARTERLY_READY=0
if [ "$S_IDENTITY" -ge 50 ] && [ "$S_SKILLS" -ge 30 ] && [ "$S_VELOCITY" -ge 30 ]; then
  QUARTERLY_READY=1
fi

# --- Growth Suggestions ---

SUGGESTIONS=()

if [ -n "$COMMIT_BREAKDOWN" ]; then
  has_refactor=$(echo "$COMMIT_BREAKDOWN" | grep -c 'refactor' || true)
  has_perf=$(echo "$COMMIT_BREAKDOWN" | grep -c 'perf' || true)
  if [ "$has_refactor" -eq 0 ] && [ "$has_perf" -eq 0 ]; then
    SUGGESTIONS+=("No architecture/performance-related commits this month")
  fi
  has_test=$(echo "$COMMIT_BREAKDOWN" | grep -c 'test' || true)
  if [ "$has_test" -eq 0 ]; then
    SUGGESTIONS+=("No test-related commits this month — consider adding test coverage")
  fi
fi

if [ "${#DORMANT_SKILLS[@]}" -gt 0 ]; then
  for dormant in "${DORMANT_SKILLS[@]}"; do
    SUGGESTIONS+=("$dormant")
  done
fi

if [ "$S_VELOCITY" -lt 75 ]; then
  SUGGESTIONS+=("Commit velocity has notable drops — review your work cadence")
fi

if [ "$DOMINANT_PCT" -gt 60 ] && [ -n "$DOMINANT_TYPE" ]; then
  SUGGESTIONS+=("${DOMINANT_PCT}% of commits are ${DOMINANT_TYPE} — consider diversifying your work mix")
fi

if [ "$S_GROWTH" -eq 0 ]; then
  SUGGESTIONS+=("No growth goals defined — add targets to your Growth Roadmap")
fi

# --- Output Report ---

echo "🧠 Brainstack Health"
echo ""
printf "Engineering Context:     %d%%\n" "$OVERALL"
if [ "$SCAN_AVAILABLE" -eq 1 ]; then
  printf "Repositories Tracked:    %d\n" "$REPOS_TRACKED"
  printf "Active This Week:        %d\n" "$ACTIVE_THIS_WEEK"
fi
printf "Skills Updated:          %s\n" "$(check_mark "$SKILLS_UPDATED")"
printf "Standup Ready:           %s\n" "$(check_mark "$STANDUP_READY")"
printf "Quarterly Review Ready:  %s\n" "$(check_mark "$QUARTERLY_READY")"

if [ "${#COOLING_REPOS[@]}" -gt 0 ]; then
  echo ""
  echo "Cooling Repositories:"
  for repo_line in "${COOLING_REPOS[@]}"; do
    echo "$repo_line"
  done
fi

if [ "${#SUGGESTIONS[@]}" -gt 0 ]; then
  echo ""
  echo "Growth Suggestions:"
  shown=0
  for suggestion in "${SUGGESTIONS[@]}"; do
    echo "  - $suggestion"
    shown=$((shown + 1))
    [ "$shown" -ge 5 ] && break
  done
fi

echo ""
echo "Overall Brain Health"
progress_bar "$OVERALL"
