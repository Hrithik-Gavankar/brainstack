#!/usr/bin/env bash
# Version and compare engineer-brain's BRAIN.md.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: brain-history.sh begin [BRAIN.md]
       brain-history.sh finish [BRAIN.md] [--quiet]
       brain-history.sh diff [BRAIN.md] [days-ago]
       brain-history.sh diff [days-ago]

begin     Save the current brain before an update.
finish    Compare the updated brain with the saved version (use --quiet to suppress output).
diff      Compare the current brain with the newest version at least N days old (default: 0).
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 2; }

command_name=${1:-}
[ -n "$command_name" ] || { usage >&2; exit 2; }
shift

resolve_brain_path() {
  local candidate=${1:-BRAIN.md}
  local dir
  dir=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd) || die "BRAIN.md directory not found"
  printf '%s/%s\n' "$dir" "$(basename "$candidate")"
}

timestamp() { date -u '+%Y%m%dT%H%M%SZ'; }
today_utc() { date -u '+%Y-%m-%d'; }

use_color=false
if [ "${NO_COLOR:-}" = "" ] && { [ -t 1 ] || [ "${FORCE_COLOR:-0}" = "1" ]; }; then
  use_color=true
fi

if $use_color; then
  green=$'\033[32m'; red=$'\033[31m'; yellow=$'\033[33m'; bold=$'\033[1m'; reset=$'\033[0m'
else
  green= red= yellow= bold= reset=
fi

# Emit "repo<TAB>detail" rows from an Active Repositories section.
extract_repos() {
  awk '
    BEGIN { in_section=0 }
    /^## / {
      in_section = ($0 ~ /^## Active Repositories/)
      next
    }
    in_section && /^## / { exit }
    !in_section { next }
    /^\|/ {
      line=$0
      gsub(/^\|[[:space:]]+|[[:space:]]+\|$/, "", line)
      n=split(line, cols, /[[:space:]]*\|[[:space:]]*/)
      name=cols[1]
      if (name == "" || name ~ /^:?-+:?$/ || tolower(name) == "repo") next
      detail=""
      if (n >= 4 && cols[4] != "") detail=detail "last-active " cols[4]
      if (n >= 5 && cols[5] != "") {
        if (detail != "") detail=detail "; "
        detail=detail cols[5]
      }
      if (match($0, /([0-9]+)[[:space:]]+commits?/)) {
        if (detail != "") detail=detail "; "
        detail=detail substr($0, RSTART, RLENGTH)
      }
      printf "%s\t%s\n", name, detail
      next
    }
    /^-[[:space:]]+/ {
      line=$0
      sub(/^-[[:space:]]+/, "", line)
      name=line
      sub(/[[:space:]].*$/, "", name)
      gsub(/[*`]/, "", name)
      if (name == "") next
      detail=line
      sub(/^[^[:space:]]+[[:space:]]*/, "", detail)
      printf "%s\t%s\n", name, detail
    }
  ' "$1"
}

# Emit "skill<TAB>level<TAB>evidence" rows from Expertise Map.
extract_expertise() {
  awk '
    BEGIN { in_section=0; level="" }
    /^## / {
      in_section = ($0 ~ /^## Expertise Map/)
      level=""
      next
    }
    in_section && /^## / { exit }
    !in_section { next }
    /^### / {
      heading=tolower($0)
      if (heading ~ /strong/) level="Strong"
      else if (heading ~ /growing/) level="Growing"
      else if (heading ~ /dormant|proven but/) level="Dormant"
      else level=$0
      sub(/^###[[:space:]]+/, "", level)
      next
    }
    level != "" && /^-[[:space:]]+/ {
      line=$0
      sub(/^-[[:space:]]+/, "", line)
      skill=line
      evidence=""
      if (index(line, ":") > 0) {
        skill=substr(line, 1, index(line, ":") - 1)
        evidence=substr(line, index(line, ":") + 1)
        sub(/^[[:space:]]+/, "", evidence)
      }
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", skill)
      gsub(/[*`]/, "", skill)
      if (skill != "") printf "%s\t%s\t%s\n", skill, level, evidence
    }
  ' "$1"
}

# Best-effort weekly velocity integer from Work Patterns / Velocity sections.
extract_velocity() {
  awk '
    BEGIN { in_section=0; best="" }
    /^## / {
      in_section = ($0 ~ /^## (Work Patterns|Velocity)/)
      next
    }
    in_section && /^## / { exit }
    !in_section { next }
    {
      line=tolower($0)
      if (match($0, /([0-9]+)([[:space:]]*commits?[[:space:]]*\/[[:space:]]*week|[[:space:]]*commits?[[:space:]]+per[[:space:]]+week)/)) {
        if (match($0, /[0-9]+/)) {
          print substr($0, RSTART, RLENGTH)
          exit
        }
      }
      if (line ~ /velocity/ && match($0, /[0-9]+/)) {
        best=substr($0, RSTART, RLENGTH)
      }
    }
    END { if (best != "") print best }
  ' "$1"
}

days_since() {
  local date_str=$1
  case "$date_str" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  local now then
  now=$(date -u +%s)
  if then=$(date -u -j -f '%Y-%m-%d' "$date_str" +%s 2>/dev/null); then
    :
  elif then=$(date -u -d "$date_str" +%s 2>/dev/null); then
    :
  else
    return 1
  fi
  echo $(( (now - then) / 86400 ))
}

lookup_field() {
  # lookup_field file key -> prints value after first TAB for matching key
  local file=$1 key=$2
  awk -F '\t' -v key="$key" '$1 == key { print substr($0, index($0, "\t") + 1); exit }' "$file"
}

summarize_changes() {
  local old=$1 new=$2
  local old_repos new_repos old_exp new_exp
  local changes=0
  old_repos=$(mktemp)
  new_repos=$(mktemp)
  old_exp=$(mktemp)
  new_exp=$(mktemp)

  extract_repos "$old" | sort -u >"$old_repos"
  extract_repos "$new" | sort -u >"$new_repos"
  extract_expertise "$old" | sort -u >"$old_exp"
  extract_expertise "$new" | sort -u >"$new_exp"

  # New repos (in new, not in old)
  while IFS=$'\t' read -r repo detail || [ -n "${repo:-}" ]; do
    [ -n "${repo:-}" ] || continue
    if ! awk -F '\t' -v key="$repo" '$1 == key { found=1 } END { exit !found }' "$old_repos"; then
      changes=1
      local suffix=""
      if [[ "$detail" =~ ([0-9]+[[:space:]]+commits?) ]]; then
        suffix=" (${BASH_REMATCH[1]})"
      elif [ -n "$detail" ]; then
        suffix=" (${detail})"
      fi
      printf '%s+ New repo contributed to: %s%s%s\n' "$green" "$repo" "$suffix" "$reset"
    fi
  done <"$new_repos"

  # Cooling / removed repos (in old, not in new)
  while IFS=$'\t' read -r repo detail || [ -n "${repo:-}" ]; do
    [ -n "${repo:-}" ] || continue
    if ! awk -F '\t' -v key="$repo" '$1 == key { found=1 } END { exit !found }' "$new_repos"; then
      changes=1
      local cooling_note=""
      if [[ "$detail" =~ last-active[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        local last_active="${BASH_REMATCH[1]}"
        local age
        if age=$(days_since "$last_active"); then
          cooling_note=" (no commits in ${age} days)"
        else
          cooling_note=" (last active ${last_active})"
        fi
      elif [ -n "$detail" ]; then
        cooling_note=" (${detail})"
      fi
      printf '%s- Cooling repo: %s%s%s\n' "$red" "$repo" "$cooling_note" "$reset"
    fi
  done <"$old_repos"

  # Expertise level moves / changes
  local skills skill
  skills=$(awk -F '\t' '{ print $1 }' "$old_exp" "$new_exp" | sort -u)
  while IFS= read -r skill || [ -n "${skill:-}" ]; do
    [ -n "$skill" ] || continue
    local old_row new_row old_level new_level old_ev new_ev hint
    old_row=$(lookup_field "$old_exp" "$skill" || true)
    new_row=$(lookup_field "$new_exp" "$skill" || true)
    old_level=${old_row%%$'\t'*}
    new_level=${new_row%%$'\t'*}
    old_ev=${old_row#*$'\t'}
    new_ev=${new_row#*$'\t'}
    [ "$old_ev" = "$old_row" ] && old_ev=""
    [ "$new_ev" = "$new_row" ] && new_ev=""

    if [ -z "$old_row" ] && [ -n "$new_row" ]; then
      changes=1
      printf '%s+ Expertise added: %s → "%s"%s\n' "$green" "$skill" "$new_level" "$reset"
    elif [ -n "$old_row" ] && [ -z "$new_row" ]; then
      changes=1
      printf '%s- Expertise removed: %s (was "%s")%s\n' "$red" "$skill" "$old_level" "$reset"
    elif [ -n "$old_row" ] && [ -n "$new_row" ] && [ "$old_level" != "$new_level" ]; then
      changes=1
      hint=""
      if [[ "$new_ev" =~ ([0-9]+)[[:space:]]+commits? ]] && [ "${BASH_REMATCH[1]}" -ge 10 ]; then
        hint=" (hit 10-commit threshold)"
      fi
      printf '%s~ Expertise change: %s moved from "%s" → "%s"%s%s\n' \
        "$yellow" "$skill" "$old_level" "$new_level" "$hint" "$reset"
    elif [ -n "$old_row" ] && [ -n "$new_row" ] && [ "$old_ev" != "$new_ev" ]; then
      changes=1
      printf '%s~ Expertise update: %s (%s)%s\n' "$yellow" "$skill" "$new_level" "$reset"
    fi
  done <<<"$skills"

  # Velocity shift
  local old_v new_v delta pct sign
  old_v=$(extract_velocity "$old" || true)
  new_v=$(extract_velocity "$new" || true)
  if [ -n "$old_v" ] && [ -n "$new_v" ] && [ "$old_v" != "$new_v" ]; then
    changes=1
    delta=$((new_v - old_v))
    if [ "$old_v" -gt 0 ]; then
      pct=$(( (delta * 100) / old_v ))
    else
      pct=0
    fi
    if [ "$delta" -ge 0 ]; then sign="+"; else sign=""; fi
    printf '%s~ Velocity: %s commits/week → %s commits/week (%s%s%%)%s\n' \
      "$yellow" "$old_v" "$new_v" "$sign" "$pct" "$reset"
  elif [ -z "$old_v" ] && [ -n "$new_v" ]; then
    changes=1
    printf '%s+ Velocity: %s commits/week%s\n' "$green" "$new_v" "$reset"
  fi

  rm -f "$old_repos" "$new_repos" "$old_exp" "$new_exp"
  # 0 = at least one categorized change printed; 1 = none (caller shows fallback)
  if [ "$changes" -eq 1 ]; then
    return 0
  fi
  return 1
}

# Newest *-before*.md by mtime (portable macOS/Linux). Avoids lexical
# sort picking the wrong file when same-second PID suffixes exist.
newest_snapshot() {
  local best="" best_mtime=-1 f mtime
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    if mtime=$(stat -f '%m' "$f" 2>/dev/null); then
      :
    elif mtime=$(stat -c '%Y' "$f" 2>/dev/null); then
      :
    else
      continue
    fi
    if [ -z "$best" ] || [ "$mtime" -ge "$best_mtime" ]; then
      best=$f
      best_mtime=$mtime
    fi
  done
  [ -n "$best" ] && printf '%s\n' "$best"
}

show_diff() {
  local old=$1
  # mode: update (after finish) | history (engineer-brain diff)
  local mode=${2:-update}
  [ -f "$old" ] || die "history version not found: $old"
  [ -f "$brain_path" ] || die "BRAIN.md not found: $brain_path"

  diff_file=$(mktemp)
  trap 'rm -f "${diff_file:-}"' EXIT
  local status=0
  diff -u "$old" "$brain_path" >"$diff_file" || status=$?
  [ "$status" -le 1 ] || die "could not compare brain versions"

  if [ "$status" -eq 0 ]; then
    printf '%sBrain unchanged%s — no new learning detected.\n' "$bold" "$reset"
    return
  fi

  if [ "$mode" = history ]; then
    printf '%s%sBrain changes%s (vs saved history)\n\n' "$bold" "$yellow" "$reset"
  else
    printf '%s%sBrain Updated — %s%s\n\n' "$bold" "$yellow" "$(today_utc)" "$reset"
  fi
  printf 'Changes detected:\n'
  if ! summarize_changes "$old" "$brain_path"; then
    printf '%s~ Other BRAIN.md edits (see detailed diff)%s\n' "$yellow" "$reset"
  fi

  printf '\nDetailed diff:\n'
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      +++*|---*)
        # Show relative labels instead of absolute temp paths when possible
        case "$line" in
          ---*) printf '%s--- previous BRAIN.md%s\n' "$bold" "$reset" ;;
          +++*) printf '%s+++ current BRAIN.md%s\n' "$bold" "$reset" ;;
        esac
        ;;
      +*) printf '%s%s%s\n' "$green" "$line" "$reset" ;;
      -*) printf '%s%s%s\n' "$red" "$line" "$reset" ;;
      @@*) printf '%s%s%s\n' "$yellow" "$line" "$reset" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <"$diff_file"
}

case "$command_name" in
  begin)
    brain_path=$(resolve_brain_path "${1:-BRAIN.md}")
    [ "$#" -le 1 ] || die "begin accepts only an optional BRAIN.md path"
    [ -f "$brain_path" ] || die "BRAIN.md not found: $brain_path"
    brain_dir=$(dirname "$brain_path")
    history_dir="$brain_dir/history"
    pending_file="$history_dir/.update-base"
    mkdir -p "$history_dir"
    # History contains personal data. A self-ignoring directory protects installed
    # workspaces even when their root .gitignore predates this feature.
    # Always refresh so upgrades fix older '*'-only ignore files that missed dotfiles.
    printf '*\n.*\n!.gitignore\n' >"$history_dir/.gitignore"
    # Include PID so same-second begins never collide on one filename.
    snapshot="$history_dir/$(timestamp)-$$-before.md"
    cp "$brain_path" "$snapshot"
    printf '%s\n' "$snapshot" >"$pending_file"
    ;;
  finish)
    quiet=false
    brain_arg=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --quiet) quiet=true ;;
        --*) die "unknown finish option: $1" ;;
        *)
          [ -z "$brain_arg" ] || die "finish accepts only one BRAIN.md path"
          brain_arg=$1
          ;;
      esac
      shift
    done
    brain_path=$(resolve_brain_path "${brain_arg:-BRAIN.md}")
    brain_dir=$(dirname "$brain_path")
    history_dir="$brain_dir/history"
    pending_file="$history_dir/.update-base"
    [ -f "$pending_file" ] || die "no update snapshot found; run begin before finish"
    IFS= read -r snapshot <"$pending_file"
    rm -f "$pending_file"
    $quiet || show_diff "$snapshot" update
    ;;
  diff)
    brain_arg=""
    days=""
    case "$#" in
      0) ;;
      1)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          days=$1
        else
          brain_arg=$1
        fi
        ;;
      2)
        brain_arg=$1
        days=$2
        ;;
      *) die "diff accepts at most one BRAIN.md path and one days-ago value" ;;
    esac
    days=${days:-0}
    case "$days" in ''|*[!0-9]*) die "days-ago must be a non-negative integer" ;; esac
    brain_path=$(resolve_brain_path "${brain_arg:-BRAIN.md}")
    brain_dir=$(dirname "$brain_path")
    history_dir="$brain_dir/history"
    [ -d "$history_dir" ] || die "no brain history found; run an update first"
    if [ "$days" -eq 0 ]; then
      snapshot=$(find "$history_dir" -type f -name '*-before*.md' | newest_snapshot)
    else
      snapshot=$(find "$history_dir" -type f -name '*-before*.md' -mtime "+$((days - 1))" | newest_snapshot)
    fi
    [ -n "${snapshot:-}" ] || die "no brain version found from at least $days day(s) ago"
    show_diff "$snapshot" history
    ;;
  --help|-h) usage ;;
  *) die "unknown command: $command_name" ;;
esac
