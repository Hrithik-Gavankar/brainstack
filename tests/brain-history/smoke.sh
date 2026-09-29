#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/core/scripts/brain-history.sh"
TMPWS=$(mktemp -d)
trap 'rm -rf "$TMPWS"' EXIT
BRAIN="$TMPWS/BRAIN.md"

# Realistic BRAIN.md shape (## sections + ### expertise buckets + table repos).
cat >"$BRAIN" <<'EOF'
# Engineer Brain

## Active Repositories

| Repo | Role | Contribution Level | Last Active | Focus Area |
|------|------|--------------------|-------------|------------|
| frontend-dashboard | Owner | Heavy | 2026-06-01 | UI |
| api | Primary | Moderate | 2026-07-10 | services |

## Expertise Map

### Strong (proven at current and past roles)
- Go: 20 commits across 2 repos

### Growing (actively building)
- Python: 8 commits, growing

### Proven but dormant (reactivation targets)

## Work Patterns

### Velocity Trend
- Velocity: 18 commits/week
EOF

bash "$SCRIPT" begin "$BRAIN"
test -f "$TMPWS/history/.update-base"
grep -Fxq '*' "$TMPWS/history/.gitignore"
grep -Fxq '.*' "$TMPWS/history/.gitignore"
grep -Fxq '!.gitignore' "$TMPWS/history/.gitignore"
test "$(find "$TMPWS/history" -name '*-before*.md' | wc -l | tr -d ' ')" -eq 1

cat >"$BRAIN" <<'EOF'
# Engineer Brain

## Active Repositories

| Repo | Role | Contribution Level | Last Active | Focus Area |
|------|------|--------------------|-------------|------------|
| api | Primary | Moderate | 2026-07-12 | services |
| ansible-navigator | Contributor | Light | 2026-07-12 | CLI tooling (3 commits) |

## Expertise Map

### Strong (proven at current and past roles)
- Go: 20 commits across 2 repos
- Python: 11 commits, daily usage across 3 repos

### Growing (actively building)

### Proven but dormant (reactivation targets)

## Work Patterns

### Velocity Trend
- Velocity: 22 commits/week
EOF

env -u NO_COLOR FORCE_COLOR=1 bash "$SCRIPT" finish "$BRAIN" >"$TMPWS/diff.out"

grep -q 'Brain Updated —' "$TMPWS/diff.out"
grep -q 'Changes detected:' "$TMPWS/diff.out"
grep -q 'New repo contributed to: ansible-navigator' "$TMPWS/diff.out"
grep -q 'Cooling repo: frontend-dashboard' "$TMPWS/diff.out"
grep -q 'no commits in' "$TMPWS/diff.out"
grep -q 'Expertise change: Python moved from "Growing" → "Strong"' "$TMPWS/diff.out"
grep -q 'hit 10-commit threshold' "$TMPWS/diff.out"
grep -q 'Velocity: 18 commits/week → 22 commits/week (+22%)' "$TMPWS/diff.out"
grep -q 'Detailed diff:' "$TMPWS/diff.out"
grep -Fq $'\033[32m' "$TMPWS/diff.out"
grep -Fq $'\033[31m' "$TMPWS/diff.out"
grep -Fq $'\033[33m' "$TMPWS/diff.out"
grep -Fq '+| ansible-navigator' "$TMPWS/diff.out"
test ! -e "$TMPWS/history/.update-base"

bash "$SCRIPT" diff "$BRAIN" 0 >"$TMPWS/history-diff.out"
grep -q 'ansible-navigator' "$TMPWS/history-diff.out"
grep -q 'Brain changes' "$TMPWS/history-diff.out"
if grep -q 'Brain Updated —' "$TMPWS/history-diff.out"; then
  echo "history diff must not use the update header" >&2
  exit 1
fi

# Newest-by-mtime: a lexicographically-first but older file must not win.
real_snap=$(find "$TMPWS/history" -name '*-before*.md' | head -1)
newer_name="$TMPWS/history/19990101T000000Z-0-before.md"
cp "$real_snap" "$newer_name"
# Decoy content on the original path, then force its mtime into the past so
# writing does not make it look newest.
printf '# decoy\n## Active Repositories\n| WrongRepo | x | x | 2020-01-01 | x |\n' >"$real_snap"
touch -t 202001010000 "$real_snap"
touch "$newer_name"
bash "$SCRIPT" diff "$BRAIN" 0 >"$TMPWS/mtime-diff.out"
grep -q 'ansible-navigator' "$TMPWS/mtime-diff.out"
if grep -q 'WrongRepo' "$TMPWS/mtime-diff.out"; then
  echo "diff picked stale snapshot by name instead of mtime" >&2
  exit 1
fi

# days-only form from the workspace that owns BRAIN.md
(
  cd "$TMPWS"
  bash "$SCRIPT" diff 0 >"$TMPWS/cwd-diff.out"
)
grep -q 'ansible-navigator' "$TMPWS/cwd-diff.out"

bash "$SCRIPT" begin "$BRAIN"
quiet_out=$(bash "$SCRIPT" finish "$BRAIN" --quiet)
test -z "$quiet_out"

set +e
bash "$SCRIPT" diff "$BRAIN" nope >"$TMPWS/error.out" 2>&1
rc=$?
set -e
test "$rc" -eq 2
grep -q 'non-negative integer' "$TMPWS/error.out"

# Unchanged brain after begin/finish
bash "$SCRIPT" begin "$BRAIN"
unchanged=$(bash "$SCRIPT" finish "$BRAIN")
grep -q 'Brain unchanged' <<<"$unchanged"

# Bold table repo names must not look like new/cooling when only markdown changes.
cat >"$BRAIN" <<'EOF'
# Engineer Brain

## Active Repositories

| Repo | Role | Contribution Level | Last Active | Focus Area |
|------|------|--------------------|-------------|------------|
| **api** | Primary | Moderate | 2026-07-12 | services |

## Expertise Map

### Strong (proven at current and past roles)
- Go: 20 commits

### Growing (actively building)

## Work Patterns

### Velocity Trend
- Velocity increased 2.5x
EOF

bash "$SCRIPT" begin "$BRAIN"
cat >"$BRAIN" <<'EOF'
# Engineer Brain

## Active Repositories

| Repo | Role | Contribution Level | Last Active | Focus Area |
|------|------|--------------------|-------------|------------|
| api | Primary | Moderate | 2026-07-12 | services |

## Expertise Map

### Strong (proven at current and past roles)
- Go: 20 commits

### Growing (actively building)

## Work Patterns

### Velocity Trend
- Velocity trend is up this month
EOF

bold_out=$(bash "$SCRIPT" finish "$BRAIN")
if grep -q 'New repo contributed to: api' <<<"$bold_out"; then
  echo "bold table normalization failed: reported api as new" >&2
  exit 1
fi
if grep -q 'Cooling repo: api' <<<"$bold_out"; then
  echo "bold table normalization failed: reported api as cooling" >&2
  exit 1
fi
if grep -q 'Velocity:' <<<"$bold_out"; then
  echo "loose velocity fallback must not emit commits/week from prose" >&2
  exit 1
fi

# Explicit commits/week still detected when present.
bash "$SCRIPT" begin "$BRAIN"
cat >"$BRAIN" <<'EOF'
# Engineer Brain

## Active Repositories

| Repo | Role | Contribution Level | Last Active | Focus Area |
|------|------|--------------------|-------------|------------|
| api | Primary | Moderate | 2026-07-12 | services |

## Expertise Map

### Strong (proven at current and past roles)
- Go: 20 commits

### Growing (actively building)

## Work Patterns

### Velocity Trend
- Velocity: 10 commits/week
EOF
vel_out=$(bash "$SCRIPT" finish "$BRAIN")
grep -q 'Velocity: 10 commits/week' <<<"$vel_out"

echo "brain-history smoke passed"
