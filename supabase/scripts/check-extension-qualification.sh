#!/usr/bin/env bash
# Fail CI when SQL migrations call pgcrypto helpers without the extensions schema.
# Supabase installs pgcrypto in `extensions`; Team Brain RPCs often set
# search_path = public, so bare digest()/gen_random_*() break register/join (42883).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MIG_DIR="$ROOT/supabase/migrations"

if [ ! -d "$MIG_DIR" ]; then
  echo "error: migrations dir not found: $MIG_DIR" >&2
  exit 1
fi

# Match unqualified pgcrypto calls (not preceded by "extensions.").
# Allowed: extensions.digest(...), extensions.gen_random_uuid(), etc.
PATTERN='(^|[^[:alnum:]_.])(digest|gen_random_bytes|gen_random_uuid|crypt|hmac)[[:space:]]*\('

violations=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  # Strip -- line comments, then flag bare pgcrypto calls (not extensions.*).
  hits=$(
    sed -E 's/--.*$//' "$file" \
      | grep -nE "$PATTERN" \
      | grep -vE 'extensions\.(digest|gen_random_bytes|gen_random_uuid|crypt|hmac)[[:space:]]*\(' \
      || true
  )
  if [ -n "$hits" ]; then
    echo "FAIL: unqualified pgcrypto call(s) in $(basename "$file"):" >&2
    echo "$hits" >&2
    echo "  → use extensions.<fn>(...) (see tb_hash_api_key / PR #52)" >&2
    violations=$((violations + 1))
  fi
done < <(find "$MIG_DIR" -maxdepth 1 -type f -name '*.sql' | sort)

# CLI/RPC param drift: register_team was renamed in 60806.
if ! grep -q "p_team_name:\$n, p_admin_name:\$d" "$ROOT/core/scripts/team-brain-api.sh"; then
  echo "FAIL: team-brain-api.sh register_team payload must use p_team_name / p_admin_name" >&2
  violations=$((violations + 1))
fi
if grep -qE "register_team.*p_name:\$|register_team.*p_display_name:\$" "$ROOT/core/scripts/team-brain-api.sh"; then
  echo "FAIL: team-brain-api.sh still sends legacy register_team params (p_name / p_display_name)" >&2
  violations=$((violations + 1))
fi

if [ "$violations" -gt 0 ]; then
  echo "check-extension-qualification: $violations file(s)/check(s) failed" >&2
  exit 1
fi

echo "check-extension-qualification: ok"
