#!/usr/bin/env bash
# Engineer Brain — Google Calendar Integration (read-only)
# Thin wrapper around gcal_lib.py so non-MCP platforms (Claude Code, Copilot,
# Windsurf, Aider, Continue.dev) get the same calendar signal as the gcal MCP.
#
# Usage: bash gcal.sh <command> [args]
#   authorize --client-secrets <path> [--calendar-id ID] [--out PATH]   one-time OAuth setup
#   status [--json]                                                    config status (no secrets)
#   calendars [--json]                                                 list visible calendars
#   today [--calendar-id ID] [--json] [--sync]                        today's events
#   upcoming [days] [--calendar-id ID] [--json] [--sync]              next N days (default 7)
#   range <since> <until> [--calendar-id ID] [--json]                  events in a date range
#
# Credential resolution: $GCAL_CREDENTIALS_PATH > ./.gcal/credentials.json >
#   ~/.config/engineer-brain/gcal/credentials.json
# See mcp/gcal/README.md for full setup instructions.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_LIB="${SCRIPT_DIR}/gcal_lib.py"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required for gcal.sh (stdlib only, no extra deps)." >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  python3 "$PY_LIB" --help
  exit 1
fi

exec python3 "$PY_LIB" "$@"
