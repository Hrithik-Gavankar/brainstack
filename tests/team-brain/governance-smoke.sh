#!/usr/bin/env bash
# Governance RPC smoke tests — requires live Supabase + applied migrations.
# Skips gracefully when credentials are not configured.
#
# Usage:
#   export TEAM_BRAIN_SUPABASE_URL=...
#   export TEAM_BRAIN_SUPABASE_ANON_KEY=...
#   export TEAM_BRAIN_MEMBER_API_KEY=tb_...      # member role
#   export TEAM_BRAIN_VIEWER_API_KEY=tb_...      # viewer role (optional)
#   export TEAM_BRAIN_ADMIN_API_KEY=tb_...       # admin role (optional)
#   export TEAM_BRAIN_TEST_JIRA_KEY=DEMO-1
#   export TEAM_BRAIN_TEST_SOURCE_REF=DEMO-1#governance-smoke
#   bash tests/team-brain/governance-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API="$ROOT/core/scripts/team-brain-api.sh"

need() {
  local var="$1"
  if [ -z "${!var:-}" ]; then
    echo "SKIP governance-smoke: set $var (and other TEAM_BRAIN_* vars) to run live RPC tests"
    exit 0
  fi
}

need TEAM_BRAIN_SUPABASE_URL
need TEAM_BRAIN_SUPABASE_ANON_KEY
need TEAM_BRAIN_MEMBER_API_KEY
need TEAM_BRAIN_TEST_JIRA_KEY
need TEAM_BRAIN_TEST_SOURCE_REF

export TEAM_BRAIN_SUPABASE_URL
export TEAM_BRAIN_SUPABASE_ANON_KEY
KEY="$TEAM_BRAIN_TEST_JIRA_KEY"
REF="$TEAM_BRAIN_TEST_SOURCE_REF"

rpc_as() {
  local api_key="$1"
  local fn="$2"
  local payload="$3"
  local url="${TEAM_BRAIN_SUPABASE_URL%/}/rest/v1/rpc/${fn}"
  curl -sS -X POST "$url" \
    -H "apikey: ${TEAM_BRAIN_SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${TEAM_BRAIN_SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg k "$api_key" --argjson body "$payload" '$body + {p_api_key:$k}')"
}

echo "→ member remember + delete tombstone"
export TEAM_BRAIN_API_KEY="$TEAM_BRAIN_MEMBER_API_KEY"
export TEAM_BRAIN_DIR="${TEAM_BRAIN_DIR:-$PWD/.team-brain}"
bash "$API" attach "$KEY" "$KEY" active >/dev/null 2>&1 || true
bash "$API" remember "$KEY" note --source-ref "$REF" "governance smoke $(date +%s)" >/dev/null

if [ -n "${TEAM_BRAIN_VIEWER_API_KEY:-}" ]; then
  echo "→ viewer delete forbidden"
  out=$(rpc_as "$TEAM_BRAIN_VIEWER_API_KEY" delete_memory \
    "$(jq -n --arg j "$KEY" --arg r "$REF" '{p_jira_key:$j,p_source_ref:$r}')" 2>&1 || true)
  echo "$out" | grep -qi 'delete requires member role\|forbidden' \
    || { echo "FAIL: viewer delete should be forbidden: $out"; exit 1; }
fi

echo "→ member delete"
export TEAM_BRAIN_API_KEY="$TEAM_BRAIN_MEMBER_API_KEY"
bash "$API" delete "$KEY" --source-ref "$REF" >/dev/null

echo "→ recall excludes tombstone"
recall_out=$(bash "$API" recall "$KEY" 2>/dev/null || echo '{}')
if echo "$recall_out" | jq -e --arg r "$REF" '
  [(.memories // .captures // [])[] | select(.source_ref == $r)] | length > 0
' >/dev/null 2>&1; then
  echo "FAIL: tombstoned memory still in recall output"
  exit 1
fi

if [ -n "${TEAM_BRAIN_ADMIN_API_KEY:-}" ]; then
  echo "→ admin list_members has no api_key"
  members=$(rpc_as "$TEAM_BRAIN_ADMIN_API_KEY" list_members '{}')
  if echo "$members" | jq -e '.. | objects | select(has("api_key"))' >/dev/null 2>&1; then
    echo "FAIL: list_members leaked api_key"
    exit 1
  fi
fi

echo "→ remember undeletes tombstone"
undelete=$(bash "$API" remember "$KEY" note --source-ref "$REF" "restored body $(date +%s)")
if ! echo "$undelete" | jq -e '.undeleted == true or .updated == true' >/dev/null 2>&1; then
  echo "WARN: expected undeleted:true or updated:true (got: $undelete)"
fi
recall2=$(bash "$API" recall "$KEY" 2>/dev/null || echo '{}')
echo "$recall2" | jq -e --arg r "$REF" '
  [(.memories // .captures // [])[] | select(.source_ref == $r)] | length > 0
' >/dev/null || { echo "FAIL: memory not visible after undelete remember"; exit 1; }

echo "OK governance-smoke"
