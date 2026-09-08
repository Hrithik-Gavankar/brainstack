#!/usr/bin/env bash
# Smoke: pending review CLI wiring (#67). No Supabase required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API="$ROOT/core/scripts/team-brain-api.sh"

bash "$API" --help | grep -q 'pending list' || { echo "FAIL: help missing pending list"; exit 1; }
bash "$API" --help | grep -q '\-\-queue' || { echo "FAIL: help missing remember --queue"; exit 1; }

# Routing: unknown subcommand should not be "unknown command: pending"
set +e
out=$(TEAM_BRAIN_SUPABASE_URL= TEAM_BRAIN_API_KEY=x bash "$API" pending bogus 2>&1)
set -e
echo "$out" | grep -q 'pending list|approve|reject' \
  || { echo "FAIL: pending bogus should show usage; got: $out"; exit 1; }

echo "OK pending-review-smoke"
