#!/usr/bin/env bash
# Team Brain — Supabase RPC client
# Usage:
#   export TEAM_BRAIN_SUPABASE_URL=https://xxxx.supabase.co
#   export TEAM_BRAIN_SUPABASE_ANON_KEY=eyJ...
#   export TEAM_BRAIN_API_KEY=tb_...   # after register/join (or use credentials file)
#   bash team-brain-api.sh <command> [args...]
#
# Commands: onboard | register | join | whoami | attach | capture | sync | list | mirror | status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_HINT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PUBLIC_ENV="${TEAM_BRAIN_PUBLIC_ENV:-$REPO_HINT/supabase/project.public.env}"

# Resolve .team-brain relative to CWD first, then parent of repo
TEAM_DIR="${TEAM_BRAIN_DIR:-}"
if [ -z "$TEAM_DIR" ]; then
  if [ -d "$PWD/.team-brain" ]; then
    TEAM_DIR="$PWD/.team-brain"
  elif [ -d "$REPO_HINT/../.team-brain" ]; then
    TEAM_DIR="$(cd "$REPO_HINT/.." && pwd)/.team-brain"
  else
    TEAM_DIR="$PWD/.team-brain"
  fi
fi

CRED_FILE="${TEAM_BRAIN_CREDENTIALS:-$TEAM_DIR/credentials.json}"
CONFIG_YAML="${TEAM_BRAIN_CONFIG:-$TEAM_DIR/team.yaml}"

die() { echo "error: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

need_cmd curl
need_cmd jq

load_public_env() {
  [ -f "$PUBLIC_ENV" ] || return 0
  # shellcheck disable=SC1090
  set -a
  # Only export the known keys (ignore comments / blank lines)
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      TEAM_BRAIN_SUPABASE_URL=*|TEAM_BRAIN_SUPABASE_ANON_KEY=*|TEAM_BRAIN_JIRA_SITE=*)
        export "$line"
        ;;
    esac
  done <"$PUBLIC_ENV"
  set +a
}

seed_team_yaml_from_public() {
  load_public_env
  [ -n "${TEAM_BRAIN_SUPABASE_URL:-}" ] || die "missing TEAM_BRAIN_SUPABASE_URL (expected $PUBLIC_ENV)"
  [ -n "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" ] || die "missing TEAM_BRAIN_SUPABASE_ANON_KEY (expected $PUBLIC_ENV)"
  mkdir -p "$TEAM_DIR/initiatives"
  if [ ! -f "$TEAM_DIR/.gitignore" ]; then
    echo "credentials.json" >"$TEAM_DIR/.gitignore"
  fi
  if [ ! -f "$CONFIG_YAML" ]; then
    cat >"$CONFIG_YAML" <<EOF
version: 1
team:
  name: "(joined via onboard)"
sync:
  backend: supabase
  supabase_url: ${TEAM_BRAIN_SUPABASE_URL}
  supabase_anon_key: ${TEAM_BRAIN_SUPABASE_ANON_KEY}
jira:
  site: ${TEAM_BRAIN_JIRA_SITE:-https://redhat.atlassian.net}
initiatives: []
EOF
    echo "Seeded $CONFIG_YAML from $PUBLIC_ENV" >&2
  fi
}

load_config() {
  # Prefer env → team.yaml → committed public project config
  if [ -z "${TEAM_BRAIN_SUPABASE_URL:-}" ] || [ -z "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" ]; then
    if [ -f "$CONFIG_YAML" ]; then
      TEAM_BRAIN_SUPABASE_URL=${TEAM_BRAIN_SUPABASE_URL:-$(grep -E '^\s*supabase_url:' "$CONFIG_YAML" | head -1 | sed 's/.*supabase_url:[[:space:]]*//' | tr -d '"' | tr -d "'")}
      TEAM_BRAIN_SUPABASE_ANON_KEY=${TEAM_BRAIN_SUPABASE_ANON_KEY:-$(grep -E '^\s*supabase_anon_key:' "$CONFIG_YAML" | head -1 | sed 's/.*supabase_anon_key:[[:space:]]*//' | tr -d '"' | tr -d "'")}
    fi
  fi
  if [ -z "${TEAM_BRAIN_SUPABASE_URL:-}" ] || [ -z "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" ]; then
    load_public_env
  fi
  if [ -z "${TEAM_BRAIN_API_KEY:-}" ] && [ -f "$CRED_FILE" ]; then
    TEAM_BRAIN_API_KEY=$(jq -r '.api_key // empty' "$CRED_FILE")
  fi
}

require_supabase() {
  load_config
  [ -n "${TEAM_BRAIN_SUPABASE_URL:-}" ] || die "set TEAM_BRAIN_SUPABASE_URL or sync.supabase_url in $CONFIG_YAML"
  [ -n "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" ] || die "set TEAM_BRAIN_SUPABASE_ANON_KEY or sync.supabase_anon_key in $CONFIG_YAML"
}

require_api_key() {
  load_config
  [ -n "${TEAM_BRAIN_API_KEY:-}" ] || die "set TEAM_BRAIN_API_KEY or run register/join (credentials at $CRED_FILE)"
}

rpc() {
  local fn="$1"
  local body="$2"
  require_supabase
  local url="${TEAM_BRAIN_SUPABASE_URL%/}/rest/v1/rpc/${fn}"
  local resp http
  resp=$(curl -sS -w "\n%{http_code}" -X POST "$url" \
    -H "apikey: ${TEAM_BRAIN_SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${TEAM_BRAIN_SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d "$body")
  http=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')
  if [ "$http" -lt 200 ] || [ "$http" -ge 300 ]; then
    echo "$body" >&2
    die "RPC $fn failed (HTTP $http)"
  fi
  echo "$body"
}

save_credentials() {
  local json="$1"
  mkdir -p "$TEAM_DIR"
  jq '{
    api_key: .api_key,
    team_id: .team_id,
    member_id: .member_id,
    display_name: .display_name,
    role: .role,
    team_name: .team_name,
    invite_code: .invite_code
  }' <<<"$json" >"$CRED_FILE"
  chmod 600 "$CRED_FILE" 2>/dev/null || true
  echo "Wrote credentials → $CRED_FILE" >&2
  echo "Invite code: $(jq -r .invite_code <<<"$json")" >&2
  echo "API key saved (keep private)." >&2
}

ensure_initiative_md() {
  local key="$1"
  local title="${2:-$key}"
  local status="${3:-active}"
  local url="${4:-}"
  local path="$TEAM_DIR/initiatives/${key}.md"
  mkdir -p "$TEAM_DIR/initiatives"
  if [ ! -f "$path" ]; then
    cat >"$path" <<EOF
# ${key}: ${title}

**Tracker:** ${url:-https://jira/browse/${key}}  
**Status:** ${status}  
**Owners:**  
**Attached:**

---

## Goal

(Fill in — or update via team-brain capture / sync)

---

## Decisions

| Date | Decision | Why | Decided by |
|------|----------|-----|------------|
| | | | |

---

## Research & findings

---

## Open questions

- [ ]

---

## Links

- PRs:
- Docs / ADRs:

---

## Capture log

(Synced from Supabase via \`team-brain-api.sh mirror\` / \`sync\`)

EOF
  fi
}

mirror_captures_to_md() {
  local key="$1"
  local payload="$2"
  local path="$TEAM_DIR/initiatives/${key}.md"
  ensure_initiative_md "$key" \
    "$(jq -r '.initiative.title // empty' <<<"$payload")" \
    "$(jq -r '.initiative.status // "active"' <<<"$payload")" \
    "$(jq -r '.initiative.jira_url // empty' <<<"$payload")"

  local title status url
  title=$(jq -r '.initiative.title // empty' <<<"$payload")
  status=$(jq -r '.initiative.status // "active"' <<<"$payload")
  url=$(jq -r '.initiative.jira_url // empty' <<<"$payload")

  # Refresh header fields if present
  if [ -n "$title" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "1s|^# .*|# ${key}: ${title}|" "$path" 2>/dev/null || true
    else
      sed -i "1s|^# .*|# ${key}: ${title}|" "$path" 2>/dev/null || true
    fi
  fi

  local tmp block
  tmp=$(mktemp)
  # Keep everything before Capture log, then rewrite log from Supabase
  if grep -q '^## Capture log' "$path"; then
    sed '/^## Capture log/,$d' "$path" >"$tmp"
  else
    cat "$path" >"$tmp"
    echo "" >>"$tmp"
  fi

  {
    echo "## Capture log"
    echo ""
    echo "(Synced from Supabase — $(date -u +%Y-%m-%dT%H:%M:%SZ))"
    echo ""
    jq -r '
      .captures // [] | .[] |
      "- `\(.created_at[:10])` [@\(.author_name)] **\(.kind)**: \(.body | gsub("\n"; " "))"
    ' <<<"$payload"
    echo ""
  } >>"$tmp"

  # Append decisions from capture kind=decision into a simple note under Research if needed — keep Capture log as SoT
  mv "$tmp" "$path"
  echo "Mirrored captures → $path" >&2
}

cmd_register() {
  local name="${1:-}"
  local display="${2:-${USER:-engineer}}"
  [ -n "$name" ] || die "usage: register <team-name> [display-name]"
  local out
  out=$(rpc register_team "$(jq -n --arg n "$name" --arg d "$display" '{p_name:$n, p_display_name:$d}')")
  save_credentials "$out"
  # Seed local TEAM.md / team.yaml hints
  mkdir -p "$TEAM_DIR/initiatives"
  if [ ! -f "$TEAM_DIR/TEAM.md" ] && [ -f "$SCRIPT_DIR/../team/TEAM.md" ]; then
    cp "$SCRIPT_DIR/../team/TEAM.md" "$TEAM_DIR/TEAM.md"
  fi
  if [ ! -f "$CONFIG_YAML" ]; then
    cat >"$CONFIG_YAML" <<EOF
version: 1
team:
  name: $(jq -r .team_name <<<"$out")
sync:
  backend: supabase
  supabase_url: ${TEAM_BRAIN_SUPABASE_URL}
  supabase_anon_key: ${TEAM_BRAIN_SUPABASE_ANON_KEY}
jira:
  site: https://redhat.atlassian.net
initiatives: []
EOF
    echo "Wrote $CONFIG_YAML" >&2
  fi
  echo "$out" | jq .
}

cmd_join() {
  local invite="${1:-}"
  local display="${2:-${USER:-engineer}}"
  [ -n "$invite" ] || die "usage: join <invite-code> [display-name]"
  seed_team_yaml_from_public
  local out
  out=$(rpc join_team "$(jq -n --arg c "$invite" --arg d "$display" '{p_invite_code:$c, p_display_name:$d}')")
  save_credentials "$out"
  # Refresh team name in yaml if present
  if [ -f "$CONFIG_YAML" ]; then
    local tname
    tname=$(jq -r .team_name <<<"$out")
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|^  name: .*|  name: \"$tname\"|" "$CONFIG_YAML" 2>/dev/null || true
    else
      sed -i "s|^  name: .*|  name: \"$tname\"|" "$CONFIG_YAML" 2>/dev/null || true
    fi
  fi
  mkdir -p "$TEAM_DIR/initiatives"
  echo "$out" | jq .
}

# One-command teammate onboarding: invite + name + optional Jira key
cmd_onboard() {
  local invite="${1:-}"
  local display="${2:-}"
  local jira_key="${3:-}"
  [ -n "$invite" ] && [ -n "$display" ] || die "usage: onboard <invite-code> \"Your Name\" [JIRA-KEY]"

  echo "→ Seeding config from public project + joining team…" >&2
  cmd_join "$invite" "$display" >/dev/null
  # Reload api key after join
  TEAM_BRAIN_API_KEY=$(jq -r .api_key "$CRED_FILE")
  export TEAM_BRAIN_API_KEY

  echo "→ whoami" >&2
  cmd_whoami

  if [ -n "$jira_key" ]; then
    jira_key=$(echo "$jira_key" | tr '[:lower:]' '[:upper:]')
    load_public_env
    local site="${TEAM_BRAIN_JIRA_SITE:-https://redhat.atlassian.net}"
    local url="${site%/}/browse/${jira_key}"
    echo "→ attach + sync $jira_key" >&2
    # Prefer existing initiative title from server if sync works after soft attach
    if ! cmd_attach "$jira_key" "$jira_key" "active" "$url" >/dev/null; then
      die "attach failed for $jira_key"
    fi
    echo "→ synced captures:" >&2
    cmd_sync "$jira_key" | jq '{initiative: .initiative, capture_count: (.captures|length), authors: [.captures[].author_name] | unique}'
    echo "" >&2
    echo "Onboard complete. Initiative file: $TEAM_DIR/initiatives/${jira_key}.md" >&2
  else
    echo "" >&2
    echo "Onboard complete (no Jira key). Next: bash $0 sync <JIRA-KEY>" >&2
  fi
}

cmd_whoami() {
  require_api_key
  rpc tb_whoami "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" '{p_api_key:$k}')" | jq .
}

cmd_attach() {
  require_api_key
  local key="${1:-}"
  local title="${2:-$key}"
  local status="${3:-active}"
  local url="${4:-}"
  [ -n "$key" ] || die "usage: attach <JIRA-KEY> [title] [status] [jira-url]"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local body out
  body=$(jq -n \
    --arg k "$TEAM_BRAIN_API_KEY" \
    --arg j "$key" \
    --arg t "$title" \
    --arg s "$status" \
    --arg u "$url" \
    '{p_api_key:$k, p_jira_key:$j, p_title:$t, p_status:$s, p_jira_url:(if $u=="" then null else $u end), p_meta:{}}')
  out=$(rpc upsert_initiative "$body")
  ensure_initiative_md "$key" "$title" "$status" "$url"
  # Update team.yaml initiatives list if file exists
  if [ -f "$CONFIG_YAML" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$CONFIG_YAML" "$key" "$title" <<'PY' || true
import sys, pathlib
path, key, title = sys.argv[1], sys.argv[2], sys.argv[3]
text = pathlib.Path(path).read_text()
entry = f"  - id: {key}\n    title: \"{title}\"\n    status: active\n    file: initiatives/{key}.md\n"
if f"id: {key}" not in text:
    if "initiatives:" in text:
        # append after initiatives:
        lines = text.splitlines()
        out = []
        inserted = False
        for i, line in enumerate(lines):
            out.append(line)
            if line.strip() == "initiatives:" and not inserted:
                # if next lines are empty list marker, still append entry
                out.append(entry.rstrip())
                inserted = True
        if not inserted:
            out.append("initiatives:")
            out.append(entry.rstrip())
        pathlib.Path(path).write_text("\n".join(out) + "\n")
    else:
        pathlib.Path(path).write_text(text.rstrip() + "\n\ninitiatives:\n" + entry)
PY
  fi
  echo "$out" | jq .
}

cmd_capture() {
  require_api_key
  local key="${1:-}"
  local kind="${2:-note}"
  shift 2 || true
  local body_text="${*:-}"
  [ -n "$key" ] || die "usage: capture <JIRA-KEY> <research|decision|note> <body...>"
  [ -n "$body_text" ] || die "capture body required"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local out sync_payload
  out=$(rpc add_capture "$(jq -n \
    --arg k "$TEAM_BRAIN_API_KEY" \
    --arg j "$key" \
    --arg kind "$kind" \
    --arg b "$body_text" \
    '{p_api_key:$k, p_jira_key:$j, p_kind:$kind, p_body:$b}')")
  sync_payload=$(rpc list_captures "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" --arg j "$key" '{p_api_key:$k, p_jira_key:$j, p_limit:50}')")
  mirror_captures_to_md "$key" "$sync_payload"
  echo "$out" | jq .
}

cmd_sync() {
  require_api_key
  local key="${1:-}"
  [ -n "$key" ] || die "usage: sync <JIRA-KEY>"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local out
  out=$(rpc list_captures "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" --arg j "$key" '{p_api_key:$k, p_jira_key:$j, p_limit:50}')")
  mirror_captures_to_md "$key" "$out"
  echo "$out" | jq .
}

cmd_list() {
  require_api_key
  rpc list_initiatives "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" '{p_api_key:$k}')" | jq .
}

cmd_mirror() {
  cmd_sync "$@"
}

cmd_status() {
  load_config
  echo "TEAM_DIR=$TEAM_DIR"
  echo "CONFIG=$CONFIG_YAML $([ -f "$CONFIG_YAML" ] && echo OK || echo missing)"
  echo "CREDENTIALS=$CRED_FILE $([ -f "$CRED_FILE" ] && echo OK || echo missing)"
  echo "SUPABASE_URL=${TEAM_BRAIN_SUPABASE_URL:-unset}"
  echo "ANON_KEY=$([ -n "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" ] && echo set || echo unset)"
  echo "API_KEY=$([ -n "${TEAM_BRAIN_API_KEY:-}" ] && echo set || echo unset)"
  if [ -n "${TEAM_BRAIN_API_KEY:-}" ] && [ -n "${TEAM_BRAIN_SUPABASE_URL:-}" ]; then
    cmd_whoami || true
  fi
}

usage() {
  cat <<EOF
Team Brain Supabase client

  onboard <invite-code> "Your Name" [JIRA-KEY]
      New teammate path — uses supabase/project.public.env (no dashboard)

  register <team-name> [display-name]   # admin creates team (once)
  join <invite-code> [display-name]
  whoami
  attach <JIRA-KEY> [title] [status] [jira-url]
  capture <JIRA-KEY> <research|decision|note> <body...>
  sync <JIRA-KEY>          # pull captures + mirror to initiatives/<KEY>.md
  list                     # list initiatives
  status

Public project config (committed): supabase/project.public.env
Personal credentials (gitignored): .team-brain/credentials.json
EOF
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    onboard) cmd_onboard "$@" ;;
    register) cmd_register "$@" ;;
    join) cmd_join "$@" ;;
    whoami) cmd_whoami "$@" ;;
    attach) cmd_attach "$@" ;;
    capture) cmd_capture "$@" ;;
    sync|mirror) cmd_sync "$@" ;;
    list) cmd_list "$@" ;;
    status) cmd_status "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
