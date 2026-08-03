#!/usr/bin/env bash
# Team Brain — Supabase RPC client
# Usage:
#   export TEAM_BRAIN_SUPABASE_URL=https://xxxx.supabase.co
#   export TEAM_BRAIN_SUPABASE_ANON_KEY=eyJ...
#   export TEAM_BRAIN_API_KEY=tb_...   # after register/join (or use credentials file)
#   bash team-brain-api.sh <command> [args...]
#
# Commands: onboard | register | join | whoami | attach | start | stop | wake |
#           bootstrap | pin | remember | correct | history | restore | recall | capture |
#           sync | watch | breakdown | metrics | aggregate | compliance | list | mirror | status |
#           sync-status | touch | broadcast-topic | rotate-invite | set-role
# Plan: docs/team-brain-memory.md — memories are SoT; md is optional export.
# Realtime (#31): signal Broadcast + poll fallback — see migration …_realtime_broadcast.sql
# Pin (#39): commit-safe .team-brain/project.json — never secrets.
# Roles (#40): admin | member (write) | viewer (read-only).
# Aggregate (#35): metrics --team / aggregate — coverage + reuse; no BRAIN.md.

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
PIN_FILE="${TEAM_BRAIN_PIN:-$TEAM_DIR/project.json}"

die() { echo "error: $*" >&2; exit 1; }

# Commit-safe pin (#39). Never put anon / api_key / invite here.
pin_path() { echo "$PIN_FILE"; }

load_pin() {
  local path
  path=$(pin_path)
  [ -f "$path" ] || { echo "{}"; return 1; }
  if ! jq -e 'type == "object"' "$path" >/dev/null 2>&1; then
    die "invalid pin file: $path (must be a JSON object)"
  fi
  # Soft-reject secrets if someone mistakenly committed them
  if jq -e '
      (.api_key // .anon_key // .supabase_anon_key // .invite_code // .invite // "")
      | tostring | length > 0
    ' "$path" >/dev/null 2>&1; then
    die "pin file must not contain secrets (api_key / anon / invite). Remove them from $path"
  fi
  cat "$path"
}

pinned_jira_key() {
  local pin key
  pin=$(load_pin 2>/dev/null) || return 1
  key=$(jq -r '
    .default_jira_key // .jira_key //
    (if (.jira_keys|type)=="array" and (.jira_keys|length)>0 then .jira_keys[0] else empty end) //
    empty
  ' <<<"$pin")
  [ -n "$key" ] && [ "$key" != "null" ] || return 1
  echo "$key" | tr '[:lower:]' '[:upper:]'
}

resolve_jira_key() {
  # Prefer explicit arg; else pin default.
  local key="${1:-}"
  if [ -n "$key" ]; then
    echo "$key" | tr '[:lower:]' '[:upper:]'
    return 0
  fi
  if key=$(pinned_jira_key); then
    echo "→ Using pinned Jira key from $(pin_path): $key" >&2
    echo "$key"
    return 0
  fi
  return 1
}

rpc_forbidden_hint() {
  local err="${1:-}"
  if echo "$err" | grep -qi 'viewer role is read-only\|forbidden: viewer'; then
    echo "→ Your role is viewer (read-only). Ask an admin for member/write access." >&2
  elif echo "$err" | grep -qi 'forbidden: admin only'; then
    echo "→ Admin only — ask a crew admin (rotate-invite / set-role)." >&2
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

need_cmd curl
need_cmd jq

load_public_env() {
  [ -f "$PUBLIC_ENV" ] || return 0
  # Only fill keys that are unset — never clobber env / team.yaml values already loaded
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      TEAM_BRAIN_SUPABASE_URL=*)
        [ -n "${TEAM_BRAIN_SUPABASE_URL:-}" ] || export TEAM_BRAIN_SUPABASE_URL="${line#TEAM_BRAIN_SUPABASE_URL=}"
        ;;
      TEAM_BRAIN_SUPABASE_ANON_KEY=*)
        [ -n "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" ] || export TEAM_BRAIN_SUPABASE_ANON_KEY="${line#TEAM_BRAIN_SUPABASE_ANON_KEY=}"
        ;;
      TEAM_BRAIN_JIRA_SITE=*)
        [ -n "${TEAM_BRAIN_JIRA_SITE:-}" ] || export TEAM_BRAIN_JIRA_SITE="${line#TEAM_BRAIN_JIRA_SITE=}"
        ;;
    esac
  done <"$PUBLIC_ENV"
}

supabase_config_is_placeholder() {
  case "${TEAM_BRAIN_SUPABASE_URL:-}" in
    ""|*YOUR_PROJECT*|*your-project*|*example.supabase*) return 0 ;;
  esac
  case "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" in
    ""|your-anon-key|YOUR_ANON*|replace-me*|changeme*) return 0 ;;
  esac
  return 1
}

seed_team_yaml_from_public() {
  # Same resolution as require_supabase: env → team.yaml → project.public.env
  load_config
  [ -n "${TEAM_BRAIN_SUPABASE_URL:-}" ] || die "missing TEAM_BRAIN_SUPABASE_URL (set env, $CONFIG_YAML, or $PUBLIC_ENV)"
  [ -n "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" ] || die "missing TEAM_BRAIN_SUPABASE_ANON_KEY (set env, $CONFIG_YAML, or $PUBLIC_ENV)"
  if supabase_config_is_placeholder; then
    die "Supabase URL/anon are still placeholders. Set real values in env, $CONFIG_YAML, or $PUBLIC_ENV. Ask your crew admin for the project URL + anon key, or see supabase/README.md if you are the admin."
  fi
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
  site: ${TEAM_BRAIN_JIRA_SITE:-https://your-org.atlassian.net}
initiatives: []
EOF
    chmod 600 "$CONFIG_YAML" 2>/dev/null || true
    echo "Seeded $CONFIG_YAML with crew Supabase config" >&2
  fi
}

yaml_get() {
  # Read a dotted key from team.yaml. Prefer yq; fallback supports flat single-line values only.
  local key="$1"
  local file="$2"
  local val=""
  if command -v yq >/dev/null 2>&1; then
    val=$(yq -r ".$key // \"\"" "$file" 2>/dev/null || true)
    if [ "$val" = "null" ]; then val=""; fi
    printf '%s' "$val"
    return 0
  fi
  local leaf="${key##*.}"
  grep -E "^[[:space:]]*${leaf}:" "$file" 2>/dev/null | head -1 \
    | sed "s/.*${leaf}:[[:space:]]*//" | tr -d '"' | tr -d "'" || true
}

load_config() {
  # Prefer env → team.yaml → committed public project config
  # Constraint without yq: sync.* values must be flat, unquoted, single-line.
  if [ -z "${TEAM_BRAIN_SUPABASE_URL:-}" ] || [ -z "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" ]; then
    if [ -f "$CONFIG_YAML" ]; then
      TEAM_BRAIN_SUPABASE_URL=${TEAM_BRAIN_SUPABASE_URL:-$(yaml_get sync.supabase_url "$CONFIG_YAML")}
      TEAM_BRAIN_SUPABASE_ANON_KEY=${TEAM_BRAIN_SUPABASE_ANON_KEY:-$(yaml_get sync.supabase_anon_key "$CONFIG_YAML")}
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
  if supabase_config_is_placeholder; then
    die "Supabase URL/anon are still placeholders. Crew admin: create a project, apply supabase/migrations, set TEAM_BRAIN_SUPABASE_URL + TEAM_BRAIN_SUPABASE_ANON_KEY (or edit $PUBLIC_ENV / $CONFIG_YAML). See supabase/README.md"
  fi
}

require_api_key() {
  load_config
  [ -n "${TEAM_BRAIN_API_KEY:-}" ] || die "set TEAM_BRAIN_API_KEY or run register/join (credentials at $CRED_FILE)"
}

# Soft RPC: prints resp body on success (0); error on stderr and returns 1 (no exit).
# Use this inside $( … || … ) fallbacks — die/exit would abort the whole subshell.
rpc_try() {
  local fn="$1"
  local payload="$2"
  require_supabase
  local url="${TEAM_BRAIN_SUPABASE_URL%/}/rest/v1/rpc/${fn}"
  local resp http resp_body
  resp=$(curl -sS -w "\n%{http_code}" -X POST "$url" \
    -H "apikey: ${TEAM_BRAIN_SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${TEAM_BRAIN_SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload")
  http=$(echo "$resp" | tail -n1)
  resp_body=$(echo "$resp" | sed '$d')
  if [ "$http" -lt 200 ] || [ "$http" -ge 300 ]; then
    echo "$resp_body" >&2
    rpc_forbidden_hint "$resp_body"
    echo "RPC $fn failed (HTTP $http)" >&2
    return 1
  fi
  echo "$resp_body"
  return 0
}

rpc() {
  local out
  if ! out=$(rpc_try "$1" "$2"); then
    die "RPC $1 failed"
  fi
  echo "$out"
}

# ---------------------------------------------------------------------------
# Embeddings (P2) — optional; TEAM_BRAIN_EMBED_PROVIDER=openai|ollama|none
# Vectors are 768-d (OpenAI text-embedding-3-small dimensions=768, or nomic-embed-text).
# ---------------------------------------------------------------------------

embed_dims() {
  echo "${TEAM_BRAIN_EMBED_DIMS:-768}"
}

# Prints JSON array of floats on stdout; returns 1 if provider unset/unavailable.
embed_text() {
  local text="$1"
  local provider="${TEAM_BRAIN_EMBED_PROVIDER:-none}"
  local dims
  dims=$(embed_dims)
  case "$provider" in
    none|""|off)
      return 1
      ;;
    openai)
      local key="${TEAM_BRAIN_EMBED_API_KEY:-${OPENAI_API_KEY:-}}"
      local model="${TEAM_BRAIN_EMBED_MODEL:-text-embedding-3-small}"
      local base="${TEAM_BRAIN_EMBED_BASE_URL:-https://api.openai.com/v1}"
      [ -n "$key" ] || { echo "embed: set TEAM_BRAIN_EMBED_API_KEY or OPENAI_API_KEY" >&2; return 1; }
      local resp
      resp=$(curl -sS "${base%/}/embeddings" \
        -H "Authorization: Bearer ${key}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg m "$model" --arg i "$text" --argjson d "$dims" \
          '{model:$m, input:$i, dimensions:$d}')") || return 1
      if ! jq -e '.data[0].embedding | type == "array"' >/dev/null 2>&1 <<<"$resp"; then
        echo "embed openai failed: $(jq -c '.' <<<"$resp" 2>/dev/null || echo "$resp")" >&2
        return 1
      fi
      jq -c '.data[0].embedding' <<<"$resp"
      ;;
    ollama)
      local model="${TEAM_BRAIN_EMBED_MODEL:-nomic-embed-text}"
      local base="${TEAM_BRAIN_EMBED_BASE_URL:-http://127.0.0.1:11434}"
      local resp
      resp=$(curl -sS "${base%/}/api/embeddings" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg m "$model" --arg i "$text" '{model:$m, prompt:$i}')") || return 1
      if ! jq -e '.embedding | type == "array"' >/dev/null 2>&1 <<<"$resp"; then
        echo "embed ollama failed: $(jq -c '.' <<<"$resp" 2>/dev/null || echo "$resp")" >&2
        return 1
      fi
      # Truncate/pad to expected dims if model differs slightly
      jq -c --argjson d "$dims" '
        .embedding as $e |
        if ($e|length) == $d then $e
        elif ($e|length) > $d then $e[0:$d]
        else $e + [range($d - ($e|length)) | 0]
        end
      ' <<<"$resp"
      ;;
    *)
      echo "embed: unknown TEAM_BRAIN_EMBED_PROVIDER=$provider (use openai|ollama|none)" >&2
      return 1
      ;;
  esac
}

# Pull memories: prefer list_recent (P0); fall back to list_captures (v1).
fetch_memories() {
  local key="$1"
  local since="${2:-}"
  local body out
  if [ -n "$since" ]; then
    body=$(jq -n --arg k "$TEAM_BRAIN_API_KEY" --arg j "$key" --arg s "$since" \
      '{p_api_key:$k, p_jira_key:$j, p_since:$s, p_limit:50}')
  else
    body=$(jq -n --arg k "$TEAM_BRAIN_API_KEY" --arg j "$key" \
      '{p_api_key:$k, p_jira_key:$j, p_limit:50}')
  fi
  if out=$(rpc_try list_recent "$body" 2>/dev/null); then
    echo "$out"
    return 0
  fi
  rpc list_captures "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" --arg j "$key" \
    '{p_api_key:$k, p_jira_key:$j, p_limit:50}')"
}

save_credentials() {
  local json="$1"
  mkdir -p "$TEAM_DIR"
  # Persist invite_code only for admins (defense in depth if DB not yet on invite_hygiene)
  jq '{
    api_key: .api_key,
    team_id: .team_id,
    member_id: .member_id,
    display_name: .display_name,
    role: .role,
    team_name: .team_name
  } + (if .role == "admin" and (.invite_code // null) != null and .invite_code != "" then {invite_code: .invite_code} else {} end)' \
    <<<"$json" >"$CRED_FILE"
  chmod 600 "$CRED_FILE" 2>/dev/null || true
  echo "Wrote credentials → $CRED_FILE" >&2
  if jq -e '.role == "admin" and (.invite_code // null) != null and .invite_code != ""' >/dev/null 2>&1 <<<"$json"; then
    echo "Invite code (share with teammates; keep private from the public internet): $(jq -r .invite_code <<<"$json")" >&2
  fi
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

ensure_team_gitignore() {
  mkdir -p "$TEAM_DIR"
  if [ ! -f "$TEAM_DIR/.gitignore" ]; then
    printf '%s\n' 'credentials.json' 'cache/' 'metrics.json' 'sync/' 'notify/' >"$TEAM_DIR/.gitignore"
    return
  fi
  for entry in cache/ metrics.json sync/ notify/; do
    grep -qx "$entry" "$TEAM_DIR/.gitignore" 2>/dev/null || echo "$entry" >>"$TEAM_DIR/.gitignore"
  done
}

# Agent-facing SoT cache (P0). Markdown export remains optional.
write_memory_cache() {
  local key="$1"
  local payload="$2"
  local cache_dir="$TEAM_DIR/cache"
  local path="$cache_dir/${key}.json"
  mkdir -p "$cache_dir"
  ensure_team_gitignore
  jq --arg synced "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg key "$key" '
    {
      jira_key: (.initiative.jira_key // $key),
      synced_at: $synced,
      initiative: .initiative,
      memories: (.memories // .captures // [])
    }
  ' <<<"$payload" >"$path"
  echo "Memory cache → $path" >&2
}

# ---------------------------------------------------------------------------
# Sync mode — one manual start; background pull; merge-safe; idle sleep
# State: .team-brain/sync/<KEY>.json  pid/log alongside
# ---------------------------------------------------------------------------

SYNC_DIR() { echo "$TEAM_DIR/sync"; }
NOTIFY_DIR() { echo "$TEAM_DIR/notify"; }
sync_state_path() { echo "$(SYNC_DIR)/${1}.json"; }
sync_pid_path() { echo "$(SYNC_DIR)/${1}.pid"; }
sync_log_path() { echo "$(SYNC_DIR)/${1}.log"; }
realtime_pid_path() { echo "$(SYNC_DIR)/${1}.realtime.pid"; }
realtime_log_path() { echo "$(SYNC_DIR)/${1}.realtime.log"; }
REALTIME_SCRIPT() { echo "$SCRIPT_DIR/team-brain-realtime.py"; }

# TEAM_BRAIN_REALTIME=auto|on|off — push sidecar for sync mode / watch --push
realtime_mode() {
  local m
  m=$(echo "${TEAM_BRAIN_REALTIME:-auto}" | tr '[:upper:]' '[:lower:]')
  case "$m" in
    on|1|true|yes) echo on ;;
    off|0|false|no) echo off ;;
    *) echo auto ;;
  esac
}

stop_realtime_daemon() {
  local key="$1"
  local pidfile
  pidfile=$(realtime_pid_path "$key")
  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 0.2
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile"
  fi
}

# Best-effort Broadcast sidecar. Never fails start/watch — poll remains SoT fallback.
start_realtime_daemon() {
  local key="$1"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local mode
  mode=$(realtime_mode)
  if [ "$mode" = "off" ]; then
    echo "→ Realtime push off (TEAM_BRAIN_REALTIME=off) — poll/watch only" >&2
    return 0
  fi
  need_cmd python3
  if [ ! -f "$(REALTIME_SCRIPT)" ]; then
    echo "→ Realtime script missing — poll fallback" >&2
    return 0
  fi
  if ! python3 -c 'import websockets' 2>/dev/null; then
    if [ "$mode" = "on" ]; then
      echo "→ Realtime requested but websockets missing — pip install websockets (poll continues)" >&2
    else
      echo "→ Realtime auto-skip (pip install websockets for push; poll continues)" >&2
    fi
    return 0
  fi
  # Probe topic RPC (migration applied?)
  if ! rpc_try memory_broadcast_topic "$(jq -n \
    --arg k "$TEAM_BRAIN_API_KEY" --arg j "$key" \
    '{p_api_key:$k, p_jira_key:$j}')" >/dev/null 2>&1; then
    if [ "$mode" = "on" ]; then
      echo "→ Realtime on but memory_broadcast_topic failed — apply …_realtime_broadcast.sql (poll continues)" >&2
    else
      echo "→ Realtime auto-skip (broadcast migration not applied; poll continues)" >&2
    fi
    return 0
  fi
  stop_realtime_daemon "$key"
  mkdir -p "$(SYNC_DIR)"
  local logfile pidfile
  logfile=$(realtime_log_path "$key")
  pidfile=$(realtime_pid_path "$key")
  nohup python3 "$(REALTIME_SCRIPT)" "$key" >>"$logfile" 2>&1 &
  echo $! >"$pidfile"
  echo "→ Realtime push listener pid $(cat "$pidfile") (log: $logfile)" >&2
}

# Client-side signal if DB trigger unavailable (best-effort; never fails remember).
maybe_client_broadcast() {
  local key="$1"
  local out_json="${2:-}"
  [ -n "$key" ] || return 0
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  load_config
  [ -n "${TEAM_BRAIN_SUPABASE_URL:-}" ] && [ -n "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" ] || return 0
  supabase_config_is_placeholder && return 0
  local team_id=""
  if [ -f "$CRED_FILE" ]; then
    team_id=$(jq -r '.team_id // empty' "$CRED_FILE")
  fi
  [ -n "$team_id" ] || return 0
  if jq -e '.deduped == true' >/dev/null 2>&1 <<<"$out_json"; then
    return 0
  fi
  local topic payload mem_json
  topic="team-brain:${team_id}:${key}"
  mem_json=$(jq -c '{
      capture_id:(.id // .capture_id // null),
      source_ref:(.source_ref // null),
      kind:(.kind // null),
      updated_at:(.updated_at // null),
      op:(if .updated==true then "UPDATE" else "INSERT" end)
    }' <<<"$out_json" 2>/dev/null || echo '{}')
  payload=$(jq -n \
    --arg tid "$team_id" \
    --arg jk "$key" \
    --argjson mem "$mem_json" \
    '{
      team_id: $tid,
      jira_key: $jk,
      capture_id: $mem.capture_id,
      source_ref: $mem.source_ref,
      kind: $mem.kind,
      updated_at: $mem.updated_at,
      op: $mem.op,
      via: "client_broadcast"
    }')
  # Topic may contain ':' — encode path segments safely via batch endpoint
  local url="${TEAM_BRAIN_SUPABASE_URL%/}/realtime/v1/api/broadcast"
  curl -sS -o /dev/null -X POST "$url" \
    -H "apikey: ${TEAM_BRAIN_SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${TEAM_BRAIN_SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg t "$topic" --argjson p "$payload" \
      '{messages:[{topic:$t, event:"memory_changed", payload:$p}]}')" \
    2>/dev/null || true
}

# Authenticated cache refresh after a push signal (merge-safe; used by realtime listener).
cmd_pull_signal() {
  require_api_key
  local key="${1:-}"
  [ -n "$key" ] || die "usage: _pull_signal <JIRA-KEY>"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local since="" delta payload new_count
  if [ -f "$(sync_state_path "$key")" ]; then
    since=$(jq -r '.cursor // empty' "$(sync_state_path "$key")")
  fi
  if [ -n "$since" ]; then
    delta=$(fetch_memories "$key" "$since" 2>/dev/null || echo '{}')
  else
    delta=$(fetch_memories "$key" 2>/dev/null || echo '{}')
  fi
  new_count=$(jq '((.memories // .captures) // []) | length' <<<"$delta" 2>/dev/null || echo 0)
  payload=$(fetch_memories "$key" 2>/dev/null || true)
  if [ -n "${payload:-}" ]; then
    merge_memory_cache "$key" "$payload"
    mirror_captures_to_md "$key" "$payload" >/dev/null 2>&1 || true
    since=$(jq -r '[((.memories // .captures) // [])[] | (.updated_at // .created_at)] | max // empty' <<<"$payload")
  fi
  mkdir -p "$(NOTIFY_DIR)"
  ensure_team_gitignore
  local notify_path
  notify_path="$(NOTIFY_DIR)/${key}.json"
  jq -n \
    --arg key "$key" \
    --arg now "$(iso_now)" \
    --argjson n "${new_count:-0}" \
    --arg cur "${since:-}" \
    --argjson delta "$(jq -c '((.memories // .captures) // [])[:10] | map({id, kind, source_ref, updated_at, author_name})' <<<"${delta:-{}}" 2>/dev/null || echo '[]')" \
    '{
      jira_key: $key,
      notified_at: $now,
      pull_count: $n,
      cursor: (if $cur=="" then null else $cur end),
      source: "realtime_broadcast",
      memories: $delta,
      agent_hint: "Peer memory landed — summarize notify/cache before continuing deep research."
    }' >"$notify_path"
  if [ -f "$(sync_state_path "$key")" ]; then
    local tmp
    tmp=$(mktemp)
    jq --arg now "$(iso_now)" --arg cur "${since:-}" --argjson n "${new_count:-0}" '
      .last_pull_at = $now
      | .last_push_at = $now
      | .cursor = (if $cur == "" then .cursor else $cur end)
      | .last_pull_count = $n
      | .push = ((.push // {}) + {last_signal_at: $now, last_pull_count: $n})
    ' "$(sync_state_path "$key")" >"$tmp" && mv "$tmp" "$(sync_state_path "$key")"
  fi
  echo "→ push pull ${key}: +${new_count:-0} (notify: $notify_path)" >&2
  jq . "$notify_path"
}

cmd_broadcast_topic() {
  require_api_key
  local key="${1:-}"
  [ -n "$key" ] || die "usage: broadcast-topic <JIRA-KEY>"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  rpc memory_broadcast_topic "$(jq -n \
    --arg k "$TEAM_BRAIN_API_KEY" --arg j "$key" \
    '{p_api_key:$k, p_jira_key:$j}')" | jq .
}

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
epoch_now() { date -u +%s; }

# Merge incoming memories into cache by id (prefer newer updated_at/created_at).
# Never drops local rows that server didn't send in a partial delta.
merge_memory_cache() {
  local key="$1"
  local incoming="$2"
  local path="$TEAM_DIR/cache/${key}.json"
  mkdir -p "$TEAM_DIR/cache"
  ensure_team_gitignore
  local synced
  synced=$(iso_now)
  if [ ! -f "$path" ]; then
    write_memory_cache "$key" "$incoming"
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  jq -n --slurpfile old "$path" --argjson inc "$incoming" --arg synced "$synced" --arg key "$key" '
    def ts($m): ($m.updated_at // $m.created_at // "");
    ($old[0].memories // []) as $a |
    ($inc.memories // $inc.captures // []) as $b |
    (reduce $a[] as $m ({}; . + {($m.id|tostring): $m})) as $base |
    (reduce $b[] as $m ($base;
      ($m.id|tostring) as $id |
      if .[$id] == null then .[$id] = $m
      elif (ts($m) >= ts(.[$id])) then .[$id] = $m
      else .
      end
    )) as $map |
    {
      jira_key: ($inc.initiative.jira_key // $old[0].jira_key // $key),
      synced_at: $synced,
      initiative: ($inc.initiative // $old[0].initiative),
      memories: ([ $map[] ] | sort_by(.created_at // "") | reverse)
    }
  ' >"$tmp" && mv "$tmp" "$path"
  echo "Memory cache merged → $path" >&2
}

read_sync_state() {
  local key="$1"
  local path
  path=$(sync_state_path "$key")
  [ -f "$path" ] || { echo "{}"; return 1; }
  cat "$path"
}

write_sync_state() {
  local key="$1"
  local json="$2"
  mkdir -p "$(SYNC_DIR)"
  ensure_team_gitignore
  local path
  path=$(sync_state_path "$key")
  echo "$json" | jq . >"$path"
}

touch_sync_activity() {
  local key="${1:-}"
  [ -n "$key" ] || return 0
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local path
  path=$(sync_state_path "$key")
  [ -f "$path" ] || return 0
  local mode
  mode=$(jq -r '.mode // "stopped"' "$path")
  [ "$mode" = "active" ] || [ "$mode" = "sleep" ] || return 0
  local now
  now=$(iso_now)
  local tmp
  tmp=$(mktemp)
  jq --arg now "$now" '
    .last_activity_at = $now
    | if .mode == "sleep" then . else . end
  ' "$path" >"$tmp" && mv "$tmp" "$path"
}

# Soft MCP-first compliance (#36): track recall/remember on sync session (not a hard CLI gate).
# research_ok = sync active/sleep AND crew context loaded this session (start or recall).
mark_compliance() {
  local key="${1:-}"
  local event="${2:-}"
  [ -n "$key" ] && [ -n "$event" ] || return 0
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local path
  path=$(sync_state_path "$key")
  [ -f "$path" ] || return 0
  local now
  now=$(iso_now)
  local tmp
  tmp=$(mktemp)
  case "$event" in
    recall|context)
      jq --arg now "$now" '
        .last_recall_at = $now
        | .compliance = ((.compliance // {}) + {
            policy: "stronger_prompts",
            last_recall_at: $now,
            research_ok: true
          })
      ' "$path" >"$tmp" && mv "$tmp" "$path"
      ;;
    remember)
      jq --arg now "$now" '
        .last_remember_at = $now
        | .compliance = ((.compliance // {}) + {
            policy: "stronger_prompts",
            last_remember_at: $now
          })
      ' "$path" >"$tmp" && mv "$tmp" "$path"
      ;;
    *) return 0 ;;
  esac
}

compliance_payload() {
  local key="$1"
  local path mode last_recall last_remember research_ok agent_action
  path=$(sync_state_path "$key")
  if [ ! -f "$path" ]; then
    jq -n --arg k "$key" '{
      jira_key: $k,
      policy: "stronger_prompts",
      mode: "none",
      research_ok: false,
      last_recall_at: null,
      last_remember_at: null,
      agent_action: "Call start(jira_key) then summarize crew memory before deep research.",
      note: "Soft gate — CLI humans may still run commands; agents must follow agent_action."
    }'
    return 0
  fi
  mode=$(jq -r '.mode // "stopped"' "$path")
  last_recall=$(jq -r '.last_recall_at // .compliance.last_recall_at // empty' "$path")
  last_remember=$(jq -r '.last_remember_at // .compliance.last_remember_at // empty' "$path")
  research_ok=false
  agent_action=""
  if [ "$mode" = "sleep" ]; then
    agent_action="Sync is sleep — ask user to wake(jira_key) or start before deep research."
  elif [ "$mode" != "active" ]; then
    agent_action="Call start(jira_key) (loads crew memory) before deep research."
  elif [ -z "$last_recall" ]; then
    agent_action="Call recall(jira_key) before deep research (sync is active but no context load recorded)."
  else
    research_ok=true
    if [ -z "$last_remember" ]; then
      agent_action="After durable findings, call remember(jira_key, body, source_ref) before ending the turn."
    else
      agent_action=""
    fi
  fi
  jq -n \
    --arg k "$key" \
    --arg mode "$mode" \
    --arg lr "${last_recall}" \
    --arg lm "${last_remember}" \
    --argjson ok "$research_ok" \
    --arg action "$agent_action" \
    '{
      jira_key: $k,
      policy: "stronger_prompts",
      mode: $mode,
      research_ok: $ok,
      last_recall_at: (if $lr=="" then null else $lr end),
      last_remember_at: (if $lm=="" then null else $lm end),
      agent_action: (if $action=="" then null else $action end),
      note: "Soft gate — CLI humans may still run commands; agents must follow agent_action when present."
    }'
}

stop_sync_daemon() {
  local key="$1"
  local pidfile
  pidfile=$(sync_pid_path "$key")
  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      # give it a moment; then force
      sleep 0.2
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile"
  fi
  stop_realtime_daemon "$key"
}

# Background pull loop — invoked as: team-brain-api.sh _sync_loop <KEY>
cmd_sync_loop() {
  require_api_key
  local key="${1:-}"
  [ -n "$key" ] || die "usage: _sync_loop <JIRA-KEY>"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local state_path interval idle_sec warn_sec
  state_path=$(sync_state_path "$key")
  [ -f "$state_path" ] || die "no sync session for $key — run start first"

  echo "── sync loop $key started $(iso_now) ──" >&2
  local warned=0
  while true; do
    [ -f "$state_path" ] || exit 0
    local mode
    mode=$(jq -r '.mode // "stopped"' "$state_path")
    [ "$mode" = "active" ] || { echo "── sync loop exit (mode=$mode) ──" >&2; exit 0; }

    interval=$(jq -r '.poll_interval_sec // 5' "$state_path")
    idle_sec=$(jq -r '.idle_timeout_sec // 3600' "$state_path")
    warn_sec=$(jq -r '.warn_before_sleep_sec // 300' "$state_path")
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=5
    [ "$interval" -ge 2 ] || interval=2

    sleep "$interval"

    local last_act now_e last_e idle_for
    last_act=$(jq -r '.last_activity_at // .started_at // empty' "$state_path")
    now_e=$(epoch_now)
    if [ -n "$last_act" ]; then
      # macOS/BSD date and GNU date
      last_e=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_act" +%s 2>/dev/null \
        || date -u -d "$last_act" +%s 2>/dev/null \
        || echo "$now_e")
    else
      last_e=$now_e
    fi
    idle_for=$((now_e - last_e))

    if [ "$idle_for" -ge "$idle_sec" ]; then
      echo "" >&2
      echo "⚠ Sync mode SLEEP for $key — no local activity for ${idle_sec}s ($(iso_now))" >&2
      echo "  Run: bash team-brain-api.sh wake $key   (or start again)" >&2
      local tmp
      tmp=$(mktemp)
      jq --arg now "$(iso_now)" --argjson idle "$idle_for" '
        .mode = "sleep"
        | .slept_at = $now
        | .idle_for_sec = $idle
        | .message = "Sync sleeping after idle timeout. Run wake or start to resume."
      ' "$state_path" >"$tmp" && mv "$tmp" "$state_path"
      rm -f "$(sync_pid_path "$key")"
      exit 0
    fi

    if [ "$idle_for" -ge $((idle_sec - warn_sec)) ] && [ "$warned" -eq 0 ]; then
      local left=$((idle_sec - idle_for))
      echo "⚠ Sync mode for $key going to sleep in ~${left}s without activity. Run touch / recall / remember to stay awake." >&2
      warned=1
      tmp=$(mktemp)
      jq --arg now "$(iso_now)" --argjson left "$left" '
        .sleep_warning_at = $now
        | .seconds_until_sleep = $left
      ' "$state_path" >"$tmp" && mv "$tmp" "$state_path"
    fi
    if [ "$idle_for" -lt $((idle_sec - warn_sec)) ]; then
      warned=0
    fi

    local since cursor_payload delta new_count
    since=$(jq -r '.cursor // empty' "$state_path")
    if [ -n "$since" ]; then
      delta=$(fetch_memories "$key" "$since" 2>/dev/null || echo '{}')
    else
      delta=$(fetch_memories "$key" 2>/dev/null || echo '{}')
    fi
    new_count=$(jq '((.memories // .captures) // []) | length' <<<"$delta" 2>/dev/null || echo 0)
    if [ "${new_count:-0}" -gt 0 ]; then
      echo "── $(iso_now) +${new_count} memory(ies) for $key ──" >&2
      jq -r '
        ((.memories // .captures) // []) | .[] |
        "[\(.updated_at // .created_at)] @\(.author_name) \(.kind)\(if .source_ref then " ("+.source_ref+")" else "" end): \(.body | gsub("\n"; " "))"
      ' <<<"$delta" 2>/dev/null || true
      merge_memory_cache "$key" "$delta"
      # Full refresh keeps export + initiative metadata perfect
      cursor_payload=$(fetch_memories "$key" 2>/dev/null || true)
      if [ -n "${cursor_payload:-}" ]; then
        merge_memory_cache "$key" "$cursor_payload"
        mirror_captures_to_md "$key" "$cursor_payload" >/dev/null 2>&1 || true
        since=$(jq -r '[((.memories // .captures) // [])[] | (.updated_at // .created_at)] | max // empty' <<<"$cursor_payload")
      fi
      tmp=$(mktemp)
      jq --arg now "$(iso_now)" --arg cur "${since:-}" --argjson n "$new_count" '
        .last_pull_at = $now
        | .cursor = (if $cur == "" then .cursor else $cur end)
        | .last_pull_count = $n
      ' "$state_path" >"$tmp" && mv "$tmp" "$state_path"
    else
      tmp=$(mktemp)
      jq --arg now "$(iso_now)" '.last_pull_at = $now | .last_pull_count = 0' \
        "$state_path" >"$tmp" && mv "$tmp" "$state_path"
    fi
  done
}

cmd_start() {
  require_api_key
  local key=""
  local interval=5
  local idle_hours=1
  local foreground=0
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --foreground|-f) foreground=1; shift ;;
      --interval) interval="${2:-5}"; shift 2 ;;
      --idle-hours) idle_hours="${2:-1}"; shift 2 ;;
      -h|--help) die "usage: start [JIRA-KEY] [interval-sec] [idle-hours] [--foreground]  (JIRA-KEY optional if project.json pin set)" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  if [ ${#positional[@]} -ge 1 ]; then key="${positional[0]}"; fi
  if [ ${#positional[@]} -ge 2 ]; then interval="${positional[1]}"; fi
  if [ ${#positional[@]} -ge 3 ]; then idle_hours="${positional[2]}"; fi

  if ! key=$(resolve_jira_key "$key"); then
    die "usage: start [JIRA-KEY] … — pass a key or commit .team-brain/project.json with default_jira_key"
  fi
  [[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -ge 2 ] || die "interval must be integer >= 2"
  local idle_sec
  idle_sec=$(awk -v h="$idle_hours" 'BEGIN{printf "%d", (h+0)*3600}')
  [ "$idle_sec" -ge 60 ] || die "idle-hours must yield at least 60s"

  echo "→ Starting Team Brain sync mode for $key" >&2
  # Ensure initiative exists (lightweight attach if missing)
  if ! fetch_memories "$key" >/dev/null 2>&1; then
    echo "→ Initiative missing — attaching $key" >&2
    cmd_attach "$key" "$key" "active" >/dev/null
  fi

  stop_sync_daemon "$key"

  local payload summary_n now
  payload=$(fetch_memories "$key")
  merge_memory_cache "$key" "$payload"
  mirror_captures_to_md "$key" "$payload" >/dev/null 2>&1 || true
  summary_n=$(jq '((.memories // .captures) // []) | length' <<<"$payload")
  now=$(iso_now)
  local cursor
  cursor=$(jq -r '[((.memories // .captures) // [])[] | (.updated_at // .created_at)] | max // empty' <<<"$payload")

  write_sync_state "$key" "$(jq -n \
    --arg key "$key" \
    --arg now "$now" \
    --arg cur "${cursor:-}" \
    --argjson iv "$interval" \
    --argjson idle "$idle_sec" \
    --argjson n "$summary_n" \
    '{
      jira_key: $key,
      mode: "active",
      started_at: $now,
      last_activity_at: $now,
      last_pull_at: $now,
      last_recall_at: $now,
      cursor: (if $cur=="" then null else $cur end),
      poll_interval_sec: $iv,
      idle_timeout_sec: $idle,
      warn_before_sleep_sec: 300,
      initial_memory_count: $n,
      message: "Sync mode active. Crew memory loaded; background pull running.",
      compliance: {
        policy: "stronger_prompts",
        last_recall_at: $now,
        research_ok: true
      }
    }')"

  echo "" >&2
  echo "══════════════════════════════════════════════" >&2
  echo "  SYNC MODE ACTIVE — $key" >&2
  echo "  Loaded ${summary_n} crew memories into cache" >&2
  echo "  Poll every ${interval}s · sleep after ${idle_hours}h idle" >&2
  echo "  Cache: $TEAM_DIR/cache/${key}.json" >&2
  echo "  Push:  Realtime Broadcast signal (TEAM_BRAIN_REALTIME=$(realtime_mode); poll = fallback)" >&2
  echo "══════════════════════════════════════════════" >&2
  if [ "$summary_n" -gt 0 ]; then
    echo "Crew memory (latest):" >&2
    jq -r '((.memories // .captures) // [])[:5][] |
      "- [\(.kind)] \(.body | gsub("\n"; " ") | .[0:120])"' <<<"$payload" >&2
  else
    echo "No memories yet — your first remember starts the shared brain." >&2
  fi
  echo "" >&2

  if [ "$foreground" -eq 1 ]; then
    echo "→ Foreground sync loop (Ctrl+C stops). Use touch/recall/remember to stay awake." >&2
    start_realtime_daemon "$key" || true
    cmd_sync_loop "$key"
    stop_realtime_daemon "$key"
    return 0
  fi

  mkdir -p "$(SYNC_DIR)"
  local logfile pidfile
  logfile=$(sync_log_path "$key")
  pidfile=$(sync_pid_path "$key")
  nohup bash "$SCRIPT_DIR/team-brain-api.sh" _sync_loop "$key" >>"$logfile" 2>&1 &
  echo $! >"$pidfile"
  start_realtime_daemon "$key" || true
  local tmp rpid
  rpid=""
  [ -f "$(realtime_pid_path "$key")" ] && rpid=$(cat "$(realtime_pid_path "$key")")
  tmp=$(mktemp)
  jq --argjson pid "$(cat "$pidfile")" --arg rpid "${rpid:-}" '
    .pid = $pid
    | .realtime_pid = (if $rpid=="" then null else ($rpid|tonumber) end)
    | .push = ((.push // {}) + {policy: "signal_broadcast", mode: (if $rpid=="" then "poll_only" else "broadcast+poll" end)})
  ' "$(sync_state_path "$key")" >"$tmp" \
    && mv "$tmp" "$(sync_state_path "$key")"
  echo "Background sync pid $(cat "$pidfile") (log: $logfile)" >&2
  echo "Stop:  bash team-brain-api.sh stop $key" >&2
  echo "Wake:  bash team-brain-api.sh wake $key" >&2
  jq . "$(sync_state_path "$key")"
}

cmd_stop() {
  local key="${1:-}"
  if [ -z "$key" ]; then
    # stop all active sessions
    local f base
    for f in "$(SYNC_DIR)"/*.json; do
      [ -f "$f" ] || continue
      base=$(basename "$f" .json)
      cmd_stop "$base"
    done
    return 0
  fi
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  stop_sync_daemon "$key"
  if [ -f "$(sync_state_path "$key")" ]; then
    local tmp
    tmp=$(mktemp)
    jq --arg now "$(iso_now)" '
      .mode = "stopped"
      | .stopped_at = $now
      | .message = "Sync stopped by user."
      | del(.pid)
    ' "$(sync_state_path "$key")" >"$tmp" && mv "$tmp" "$(sync_state_path "$key")"
    echo "Sync mode STOPPED for $key" >&2
    jq . "$(sync_state_path "$key")"
  else
    echo "No sync session for $key" >&2
  fi
}

cmd_wake() {
  require_api_key
  local key="${1:-}"
  [ -n "$key" ] || die "usage: wake <JIRA-KEY>"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local path
  path=$(sync_state_path "$key")
  if [ ! -f "$path" ]; then
    echo "No prior session — starting fresh" >&2
    cmd_start "$key"
    return 0
  fi
  local interval idle_hours
  interval=$(jq -r '.poll_interval_sec // 5' "$path")
  idle_hours=$(jq -r '(.idle_timeout_sec // 3600) / 3600' "$path")
  cmd_start "$key" "$interval" "$idle_hours"
}

cmd_touch() {
  local key="${1:-}"
  [ -n "$key" ] || die "usage: touch <JIRA-KEY>"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local path
  path=$(sync_state_path "$key")
  [ -f "$path" ] || die "no sync session for $key — run start first"
  local mode
  mode=$(jq -r '.mode // "stopped"' "$path")
  if [ "$mode" = "sleep" ]; then
    echo "Sync was sleeping — waking $key" >&2
    cmd_wake "$key" >/dev/null
    return 0
  fi
  if [ "$mode" != "active" ]; then
    die "sync mode is $mode — run start $key"
  fi
  touch_sync_activity "$key"
  echo "Activity touched for $key @ $(iso_now)" >&2
  jq '{jira_key, mode, last_activity_at, idle_timeout_sec, message}' "$(sync_state_path "$key")"
}

_sync_status_one() {
  local key="$1"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  if [ ! -f "$(sync_state_path "$key")" ]; then
    jq -n --argjson c "$(compliance_payload "$key")" \
      --arg k "$key" \
      '{jira_key:$k, mode:"none", message:"No sync session. Run start <KEY>.", compliance:$c}'
    return 0
  fi
  local pid mode daemon
  pid=$(jq -r '.pid // empty' "$(sync_state_path "$key")")
  mode=$(jq -r '.mode // "stopped"' "$(sync_state_path "$key")")
  daemon="stopped"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    daemon="running"
  elif [ "$mode" = "active" ]; then
    daemon="dead"
  fi
  local rpid rdaemon
  rpid=$(jq -r '.realtime_pid // empty' "$(sync_state_path "$key")")
  if [ -z "$rpid" ] && [ -f "$(realtime_pid_path "$key")" ]; then
    rpid=$(cat "$(realtime_pid_path "$key")" 2>/dev/null || true)
  fi
  rdaemon="stopped"
  if [ -n "$rpid" ] && kill -0 "$rpid" 2>/dev/null; then
    rdaemon="running"
  elif [ -n "$rpid" ]; then
    rdaemon="dead"
  fi
  jq --arg d "$daemon" --arg rd "$rdaemon" --argjson c "$(compliance_payload "$key")" \
    '. + {daemon: $d, realtime_daemon: $rd, compliance: $c}' "$(sync_state_path "$key")"
}

cmd_sync_status() {
  load_config
  local key="${1:-}"
  mkdir -p "$(SYNC_DIR)" 2>/dev/null || true
  if [ -n "$key" ]; then
    _sync_status_one "$key"
    return 0
  fi
  local f
  local acc="[]"
  for f in "$(SYNC_DIR)"/*.json; do
    [ -f "$f" ] || continue
    acc=$(jq -n --argjson a "$acc" --argjson o "$(_sync_status_one "$(basename "$f" .json)")" '$a + [$o]')
  done
  echo "$acc" | jq .
}

# compliance — agent-visible soft gate status (MCP-first loop)
cmd_compliance() {
  load_config
  local key="${1:-}"
  [ -n "$key" ] || die "usage: compliance <JIRA-KEY>"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local out
  out=$(compliance_payload "$key")
  if jq -e '.agent_action != null' >/dev/null 2>&1 <<<"$out"; then
    echo "→ compliance: $(jq -r '.agent_action' <<<"$out")" >&2
  elif jq -e '.research_ok == true' >/dev/null 2>&1 <<<"$out"; then
    echo "→ compliance: research_ok (recall/context loaded this session)" >&2
  fi
  echo "$out" | jq .
}

# Local reuse metrics (P4) — .team-brain/metrics.json (gitignored)
METRICS_FILE() { echo "$TEAM_DIR/metrics.json"; }

bump_metric() {
  local key="$1"
  local field="$2"
  local add_reused="${3:-0}"
  local path
  path="$(METRICS_FILE)"
  ensure_team_gitignore
  mkdir -p "$TEAM_DIR"
  [ -f "$path" ] || echo '{"version":1,"initiatives":{}}' >"$path"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local tmp
  tmp=$(mktemp)
  jq --arg k "$key" --arg f "$field" --arg now "$now" --argjson n "$add_reused" '
    .initiatives[$k] = (.initiatives[$k] // {
      recall_hits: 0,
      remember_writes: 0,
      breakdown_runs: 0,
      memories_reused_total: 0
    })
    | .initiatives[$k][$f] = ((.initiatives[$k][$f] // 0) + 1)
    | .initiatives[$k].memories_reused_total =
        ((.initiatives[$k].memories_reused_total // 0) + $n)
    | .initiatives[$k].updated_at = $now
    | if $f == "recall_hits" then .initiatives[$k].last_recall_at = $now else . end
    | if $f == "breakdown_runs" then .initiatives[$k].last_breakdown_at = $now else . end
  ' "$path" >"$tmp" && mv "$tmp" "$path"
}

mirror_captures_to_md() {
  local key="$1"
  local payload="$2"
  local path="$TEAM_DIR/initiatives/${key}.md"
  ensure_initiative_md "$key" \
    "$(jq -r '.initiative.title // empty' <<<"$payload")" \
    "$(jq -r '.initiative.status // "active"' <<<"$payload")" \
    "$(jq -r '.initiative.jira_url // empty' <<<"$payload")"

  local title
  title=$(jq -r '.initiative.title // empty' <<<"$payload")

  # Refresh header fields if present
  if [ -n "$title" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "1s|^# .*|# ${key}: ${title}|" "$path" 2>/dev/null || true
    else
      sed -i "1s|^# .*|# ${key}: ${title}|" "$path" 2>/dev/null || true
    fi
  fi

  local tmp
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
    echo "(Export of team memories — $(date -u +%Y-%m-%dT%H:%M:%SZ); SoT is Supabase / cache/)"
    echo ""
    jq -r '
      (.memories // .captures // []) | .[] |
      "- `\(.created_at[:10])` [@\(.author_name)] **\(.kind)**: \(.body | gsub("\n"; " "))"
    ' <<<"$payload"
    echo ""
  } >>"$tmp"

  mv "$tmp" "$path"
  echo "Mirrored export → $path" >&2
  write_memory_cache "$key" "$payload"
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
  site: https://your-org.atlassian.net
initiatives: []
EOF
    echo "Wrote $CONFIG_YAML" >&2
  fi
  echo "$out" | jq .
}

cmd_join() {
  local invite=""
  local display="${USER:-engineer}"
  local role="member"
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --role) role="${2:-member}"; shift 2 ;;
      -h|--help) die "usage: join <invite-code> [display-name] [--role member|viewer]" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  if [ ${#positional[@]} -ge 1 ]; then invite="${positional[0]}"; fi
  if [ ${#positional[@]} -ge 2 ]; then display="${positional[1]}"; fi
  [ -n "$invite" ] || die "usage: join <invite-code> [display-name] [--role member|viewer]"
  role=$(echo "$role" | tr '[:upper:]' '[:lower:]')
  case "$role" in
    member|viewer) ;;
    *) die "role must be member or viewer (admin comes from register)" ;;
  esac
  seed_team_yaml_from_public
  local out
  out=$(rpc join_team "$(jq -n \
    --arg c "$invite" --arg d "$display" --arg r "$role" \
    '{p_invite_code:$c, p_display_name:$d, p_role:$r}')")
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
  if [ "$role" = "viewer" ]; then
    echo "→ Joined as viewer (read-only). recall/list/breakdown OK; remember/correct forbidden." >&2
  fi
  echo "$out" | jq .
}

# One-command teammate onboarding: invite + name + optional Jira key (or pin)
cmd_onboard() {
  local invite=""
  local display=""
  local jira_key=""
  local role="member"
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --role) role="${2:-member}"; shift 2 ;;
      -h|--help)
        die "usage: onboard <invite-code> \"Your Name\" [JIRA-KEY] [--role member|viewer]"
        ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  if [ ${#positional[@]} -ge 1 ]; then invite="${positional[0]}"; fi
  if [ ${#positional[@]} -ge 2 ]; then display="${positional[1]}"; fi
  if [ ${#positional[@]} -ge 3 ]; then jira_key="${positional[2]}"; fi
  [ -n "$invite" ] && [ -n "$display" ] || \
    die "usage: onboard <invite-code> \"Your Name\" [JIRA-KEY] [--role member|viewer]"

  echo "→ Seeding config from public project + joining team…" >&2
  cmd_join "$invite" "$display" --role "$role" >/dev/null
  # Reload api key after join
  TEAM_BRAIN_API_KEY=$(jq -r .api_key "$CRED_FILE")
  export TEAM_BRAIN_API_KEY

  echo "→ whoami" >&2
  cmd_whoami

  if [ -z "$jira_key" ]; then
    jira_key=$(pinned_jira_key 2>/dev/null || true)
    [ -n "$jira_key" ] && echo "→ Using pinned Jira key: $jira_key" >&2
  fi

  if [ -n "$jira_key" ]; then
    jira_key=$(echo "$jira_key" | tr '[:lower:]' '[:upper:]')
    load_public_env
    local site="${TEAM_BRAIN_JIRA_SITE:-https://your-org.atlassian.net}"
    local url="${site%/}/browse/${jira_key}"
    echo "→ attach + recall recent memories for $jira_key" >&2
    if [ "$role" = "viewer" ]; then
      # Viewers cannot upsert_initiative — pull if already attached by a writer
      if ! cmd_sync "$jira_key" >/dev/null 2>&1; then
        echo "→ Viewer cannot attach a new initiative. Ask a writer/admin to attach $jira_key first, then: recall $jira_key" >&2
      else
        echo "→ memories:" >&2
        cmd_sync "$jira_key" | jq '{initiative: .initiative, memory_count: ((.memories // .captures)//[] | length), authors: [((.memories // .captures)//[])[].author_name] | unique}'
      fi
    else
      if ! cmd_attach "$jira_key" "$jira_key" "active" "$url" >/dev/null; then
        die "attach failed for $jira_key"
      fi
      echo "→ memories:" >&2
      cmd_sync "$jira_key" | jq '{initiative: .initiative, memory_count: ((.memories // .captures)//[] | length), authors: [((.memories // .captures)//[])[].author_name] | unique}'
      echo "" >&2
      echo "Onboard complete. Cache: $TEAM_DIR/cache/${jira_key}.json  Export: $TEAM_DIR/initiatives/${jira_key}.md" >&2
    fi
  else
    echo "" >&2
    echo "Onboard complete (no Jira key). Next: bash \$0 attach <JIRA-KEY> && bash \$0 sync <JIRA-KEY>" >&2
    echo "Or commit .team-brain/project.json with default_jira_key and re-run onboard / start." >&2
  fi
}

cmd_pin() {
  local sub="${1:-show}"
  shift || true
  case "$sub" in
    show|get|"")
      if [ ! -f "$(pin_path)" ]; then
        echo "No pin at $(pin_path). Create with: pin set --jira KEY [--team-name NAME] [--project-ref REF]" >&2
        jq -n '{pinned:false, path:"'"$(pin_path)"'", hint:"Commit project.json (non-secret). Keep credentials.json gitignored."}'
        return 0
      fi
      load_pin | jq --arg p "$(pin_path)" '. + {path:$p, pinned:true}'
      ;;
    set|init|write)
      local jira="" team_name="" project_ref="" keys_json="[]"
      while [ $# -gt 0 ]; do
        case "$1" in
          --jira|--jira-key) jira="${2:-}"; shift 2 ;;
          --team-name|--team) team_name="${2:-}"; shift 2 ;;
          --project-ref|--ref) project_ref="${2:-}"; shift 2 ;;
          --jira-keys)
            keys_json=$(jq -c --arg s "${2:-}" '$s | split(",") | map(ascii_upcase|gsub("^\\s+|\\s+$";"")) | map(select(length>0))' 2>/dev/null || echo '[]')
            shift 2
            ;;
          -h|--help)
            die "usage: pin set --jira KEY [--team-name NAME] [--project-ref REF] [--jira-keys K1,K2]"
            ;;
          *) die "unknown pin set option: $1" ;;
        esac
      done
      [ -n "$jira" ] || die "usage: pin set --jira KEY [--team-name NAME] [--project-ref REF]"
      jira=$(echo "$jira" | tr '[:lower:]' '[:upper:]')
      mkdir -p "$TEAM_DIR"
      ensure_team_gitignore
      local existing="{}"
      [ -f "$(pin_path)" ] && existing=$(load_pin)
      if [ -z "$team_name" ]; then
        team_name=$(jq -r '.team_name // empty' <<<"$existing")
        [ -z "$team_name" ] && [ -f "$CRED_FILE" ] && team_name=$(jq -r '.team_name // empty' "$CRED_FILE")
      fi
      if [ -z "$project_ref" ]; then
        project_ref=$(jq -r '.supabase_project_ref // empty' <<<"$existing")
      fi
      if [ "$keys_json" = "[]" ]; then
        keys_json=$(jq -c --arg j "$jira" '.jira_keys // [$j]' <<<"$existing" 2>/dev/null || jq -n --arg j "$jira" '[$j]')
      fi
      jq -n \
        --arg j "$jira" \
        --arg tn "${team_name:-}" \
        --arg pr "${project_ref:-}" \
        --argjson keys "$keys_json" \
        '{
          version: 1,
          team_name: (if $tn=="" then null else $tn end),
          default_jira_key: $j,
          jira_keys: (($keys + [$j]) | unique),
          supabase_project_ref: (if $pr=="" then null else $pr end),
          notes: "Commit-safe crew pin. NEVER put anon key, api_key, or invite_code here. Secrets stay in env / credentials.json (gitignored)."
        }' >"$(pin_path)"
      chmod 644 "$(pin_path)" 2>/dev/null || true
      echo "→ Wrote commit-safe pin → $(pin_path)" >&2
      echo "  Commit this file. Do NOT commit credentials.json or anon keys." >&2
      jq . "$(pin_path)"
      ;;
    *)
      die "usage: pin show | pin set --jira KEY [--team-name NAME] [--project-ref REF]"
      ;;
  esac
}

cmd_rotate_invite() {
  require_api_key
  rpc rotate_invite "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" '{p_api_key:$k}')" | jq .
}

cmd_set_role() {
  require_api_key
  local name=""
  local role=""
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --role) role="${2:-}"; shift 2 ;;
      -h|--help) die "usage: set-role \"Display Name\" --role admin|member|viewer" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  if [ ${#positional[@]} -ge 1 ]; then name="${positional[0]}"; fi
  if [ ${#positional[@]} -ge 2 ] && [ -z "$role" ]; then role="${positional[1]}"; fi
  [ -n "$name" ] && [ -n "$role" ] || die "usage: set-role \"Display Name\" --role admin|member|viewer"
  role=$(echo "$role" | tr '[:upper:]' '[:lower:]')
  rpc set_member_role "$(jq -n \
    --arg k "$TEAM_BRAIN_API_KEY" --arg d "$name" --arg r "$role" \
    '{p_api_key:$k, p_display_name:$d, p_role:$r}')" | jq .
}

cmd_whoami() {
  require_api_key
  rpc tb_whoami "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" '{p_api_key:$k}')" | jq .
}

cmd_attach() {
  require_api_key
  local key="${1:-}"
  local title="${2:-}"
  local status="${3:-active}"
  local url="${4:-}"
  if ! key=$(resolve_jira_key "$key"); then
    die "usage: attach [JIRA-KEY] [title] [status] [jira-url] — or set project.json pin"
  fi
  title="${title:-$key}"
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
  # Session attach always pulls recent memories into cache (P0 periodic sync)
  cmd_sync "$key" >/dev/null || true
  echo "$out" | jq .
}

# remember — collaborative memory write (preferred). capture is a compat alias.
# Body: positional args, or "-" (stdin), or --body-file PATH (preferred for MCP / special chars).
# Kinds: research | decision | note | learning
cmd_remember() {
  require_api_key
  local key="${1:-}"
  local kind="${2:-note}"
  shift 2 || true
  local source_ref="${TEAM_BRAIN_SOURCE_REF:-}"
  local body_file=""
  local from_stdin=0
  local args=()
  local usage='usage: remember <JIRA-KEY> <research|decision|note|learning> [--source-ref REF] [--body-file PATH | - | <body...>]'
  while [ $# -gt 0 ]; do
    case "$1" in
      --source-ref)
        source_ref="${2:-}"
        shift 2 || die "$usage"
        ;;
      --body-file)
        body_file="${2:-}"
        shift 2 || die "$usage"
        ;;
      -)
        from_stdin=1
        shift
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  local body_text=""
  if [ -n "$body_file" ]; then
    [ -f "$body_file" ] || die "body file not found: $body_file"
    body_text=$(cat "$body_file")
  elif [ "$from_stdin" -eq 1 ]; then
    body_text=$(cat)
  elif [ ${#args[@]} -gt 0 ]; then
    body_text="${args[*]}"
  fi
  [ -n "$key" ] || die "$usage"
  [ -n "$body_text" ] || die "memory body required ($usage)"
  kind=$(echo "$kind" | tr '[:upper:]' '[:lower:]')
  case "$kind" in
    research|decision|note|learning) ;;
    *) die "kind must be research, decision, note, or learning (got: $kind)" ;;
  esac
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local out sync_payload payload emb
  emb=""
  if emb=$(embed_text "$body_text" 2>/dev/null); then
    echo "→ embedding via ${TEAM_BRAIN_EMBED_PROVIDER} ($(embed_dims)-d)" >&2
    payload=$(jq -n \
      --arg k "$TEAM_BRAIN_API_KEY" \
      --arg j "$key" \
      --arg kind "$kind" \
      --arg b "$body_text" \
      --arg r "$source_ref" \
      --argjson e "$emb" \
      '{p_api_key:$k, p_jira_key:$j, p_kind:$kind, p_body:$b, p_source_ref:(if $r=="" then null else $r end), p_embedding:$e}')
  else
    payload=$(jq -n \
      --arg k "$TEAM_BRAIN_API_KEY" \
      --arg j "$key" \
      --arg kind "$kind" \
      --arg b "$body_text" \
      --arg r "$source_ref" \
      '{p_api_key:$k, p_jira_key:$j, p_kind:$kind, p_body:$b, p_source_ref:(if $r=="" then null else $r end), p_embedding:null}')
  fi
  if ! out=$(rpc_try remember "$payload" 2>/dev/null); then
    # Older remember without p_embedding, or pre-P0
    payload=$(jq -n \
      --arg k "$TEAM_BRAIN_API_KEY" \
      --arg j "$key" \
      --arg kind "$kind" \
      --arg b "$body_text" \
      --arg r "$source_ref" \
      '{p_api_key:$k, p_jira_key:$j, p_kind:$kind, p_body:$b, p_source_ref:(if $r=="" then null else $r end)}')
    if ! out=$(rpc_try remember "$payload" 2>/dev/null); then
      if [ "$kind" = "learning" ]; then
        die "remember(learning) failed — apply migration 20260802000001_team_brain_learning_kind.sql"
      fi
      out=$(rpc add_capture "$(jq -n \
        --arg k "$TEAM_BRAIN_API_KEY" \
        --arg j "$key" \
        --arg kind "$kind" \
        --arg b "$body_text" \
        '{p_api_key:$k, p_jira_key:$j, p_kind:$kind, p_body:$b}')")
    fi
  fi
  sync_payload=$(fetch_memories "$key")
  merge_memory_cache "$key" "$sync_payload"
  mirror_captures_to_md "$key" "$sync_payload"
  # Count non-deduped writes as remember_writes; still bump on dedupe (retry reuse)
  bump_metric "$key" "remember_writes" 0
  touch_sync_activity "$key"
  mark_compliance "$key" remember
  # Surface merge result for agents
  if jq -e '.updated == true' >/dev/null 2>&1 <<<"$out"; then
    local archived
    archived=$(jq -r '.archived_revision // empty' <<<"$out")
    if [ -n "$archived" ]; then
      echo "→ memory UPDATED (same source_ref, new body; prior archived as revision $archived)" >&2
    else
      echo "→ memory UPDATED (same source_ref, new body)" >&2
    fi
  elif jq -e '.deduped == true' >/dev/null 2>&1 <<<"$out"; then
    echo "→ memory unchanged (deduped — identical content)" >&2
  fi
  # Best-effort peer signal (DB trigger preferred; client covers pre-migration projects)
  maybe_client_broadcast "$key" "$out"
  echo "$out" | jq .
}

cmd_capture() {
  # Compat alias for remember (no source_ref)
  cmd_remember "$@"
}

# correct — human correction loop: update memory at source_ref + optional learning.
# Prefer natural-language guidance in bodies (avoid / prefer) — never TODO/NO-TODO dumps.
cmd_correct() {
  require_api_key
  local key="${1:-}"
  shift || true
  local source_ref="${TEAM_BRAIN_SOURCE_REF:-}"
  local kind="research"
  local learning_text=""
  local was_wrong=""
  local body_file=""
  local from_stdin=0
  local args=()
  local usage='usage: correct <JIRA-KEY> --source-ref REF [--kind research|decision|note] [--was TEXT] [--learning TEXT] [--body-file PATH | - | <corrected body...>]'
  while [ $# -gt 0 ]; do
    case "$1" in
      --source-ref)
        source_ref="${2:-}"
        shift 2 || die "$usage"
        ;;
      --kind)
        kind="${2:-}"
        shift 2 || die "$usage"
        ;;
      --was|--was-wrong)
        was_wrong="${2:-}"
        shift 2 || die "$usage"
        ;;
      --learning)
        learning_text="${2:-}"
        shift 2 || die "$usage"
        ;;
      --body-file)
        body_file="${2:-}"
        shift 2 || die "$usage"
        ;;
      -)
        from_stdin=1
        shift
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  local body_text=""
  if [ -n "$body_file" ]; then
    [ -f "$body_file" ] || die "body file not found: $body_file"
    body_text=$(cat "$body_file")
  elif [ "$from_stdin" -eq 1 ]; then
    body_text=$(cat)
  elif [ ${#args[@]} -gt 0 ]; then
    body_text="${args[*]}"
  fi
  [ -n "$key" ] || die "$usage"
  [ -n "$source_ref" ] || die "correct requires --source-ref (stable topic slug). $usage"
  [ -n "$body_text" ] || die "corrected body required ($usage)"
  kind=$(echo "$kind" | tr '[:upper:]' '[:lower:]')
  case "$kind" in
    research|decision|note) ;;
    learning) die "correct --kind must be research|decision|note (use --learning for the learning row)" ;;
    *) die "kind must be research, decision, or note (got: $kind)" ;;
  esac
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')

  echo "→ correcting memory at source_ref=$source_ref" >&2
  local corrected_out learning_out learning_ref learning_body tmp_body tmp_learn tmp_err
  local got_ref learning_error
  tmp_body=$(mktemp)
  tmp_learn=""
  tmp_err=""
  trap 'rm -f "$tmp_body" "$tmp_learn" "$tmp_err"' RETURN
  printf '%s' "$body_text" >"$tmp_body"
  corrected_out=$(cmd_remember "$key" "$kind" --source-ref "$source_ref" --body-file "$tmp_body")

  # Soft content-hash dedupe / old add_capture can return a different (or null) source_ref.
  # Never report ok unless the intended topic slug was actually bound.
  got_ref=$(jq -r '.source_ref // empty' <<<"$corrected_out")
  if [ "$got_ref" != "$source_ref" ]; then
    die "correct did not bind source_ref=$source_ref (got: ${got_ref:-none}). Apply sync-mode migration; avoid identical body already stored under a different ref."
  fi

  learning_out="null"
  learning_error=""
  if [ -n "$learning_text" ] || [ -n "$was_wrong" ]; then
    learning_ref="${source_ref}/learning"
    if [ -n "$learning_text" ]; then
      learning_body="$learning_text"
    else
      learning_body=$(printf 'Was wrong: %s\nPrefer: %s\nTreat %s as ground truth; avoid repeating the incorrect claim.' \
        "$was_wrong" "$body_text" "$source_ref")
    fi
    echo "→ recording learning at source_ref=$learning_ref" >&2
    tmp_learn=$(mktemp)
    tmp_err=$(mktemp)
    printf '%s' "$learning_body" >"$tmp_learn"
    # Correction already saved — learning failure must not abort the command (set -e safe via if).
    if learning_out=$(cmd_remember "$key" learning --source-ref "$learning_ref" --body-file "$tmp_learn" 2>"$tmp_err"); then
      :
    else
      learning_error=$(tr '\n' ' ' <"$tmp_err" | sed 's/[[:space:]]*$//')
      [ -n "$learning_error" ] || learning_error="learning remember failed — apply 20260802000001_team_brain_learning_kind.sql"
      echo "⚠ correction saved but learning write failed: $learning_error" >&2
      learning_out="null"
    fi
  fi

  jq -n \
    --argjson corrected "$corrected_out" \
    --argjson learning "$learning_out" \
    --arg ref "$source_ref" \
    --arg learning_error "$learning_error" \
    '{
      ok: true,
      source_ref: $ref,
      corrected: $corrected,
      learning: (if $learning == null then null else $learning end),
      learning_error: (if $learning_error == "" then null else $learning_error end)
    }'
}

# history — list archived revisions + current body for a source_ref
cmd_history() {
  require_api_key
  local key="${1:-}"
  shift || true
  local source_ref="${TEAM_BRAIN_SOURCE_REF:-}"
  local usage='usage: history <JIRA-KEY> --source-ref REF'
  while [ $# -gt 0 ]; do
    case "$1" in
      --source-ref)
        source_ref="${2:-}"
        shift 2 || die "$usage"
        ;;
      *)
        die "$usage"
        ;;
    esac
  done
  [ -n "$key" ] || die "$usage"
  [ -n "$source_ref" ] || die "history requires --source-ref. $usage"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local payload out err tmp_err
  payload=$(jq -n \
    --arg k "$TEAM_BRAIN_API_KEY" \
    --arg j "$key" \
    --arg r "$source_ref" \
    '{p_api_key:$k, p_jira_key:$j, p_source_ref:$r}')
  tmp_err=$(mktemp)
  if ! out=$(rpc_try list_memory_history "$payload" 2>"$tmp_err"); then
    err=$(tr '\n' ' ' <"$tmp_err" | sed 's/[[:space:]]*$//')
    rm -f "$tmp_err"
    if echo "$err" | grep -Eqi 'Could not find the function|PGRST202|404|does not exist'; then
      die "list_memory_history unavailable — apply migration 20260803000001_team_brain_memory_history.sql"
    fi
    die "list_memory_history failed: ${err:-unknown error}"
  fi
  rm -f "$tmp_err"
  touch_sync_activity "$key"
  echo "$out" | jq .
}

# restore — soft-rollback source_ref to an archived revision (archives current first)
cmd_restore() {
  require_api_key
  local key="${1:-}"
  shift || true
  local source_ref="${TEAM_BRAIN_SOURCE_REF:-}"
  local revision=""
  local usage='usage: restore <JIRA-KEY> --source-ref REF --revision N'
  while [ $# -gt 0 ]; do
    case "$1" in
      --source-ref)
        source_ref="${2:-}"
        shift 2 || die "$usage"
        ;;
      --revision)
        revision="${2:-}"
        shift 2 || die "$usage"
        ;;
      *)
        die "$usage"
        ;;
    esac
  done
  [ -n "$key" ] || die "$usage"
  [ -n "$source_ref" ] || die "restore requires --source-ref. $usage"
  [[ "$revision" =~ ^[1-9][0-9]*$ ]] || die "restore requires --revision N (positive integer). $usage"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local payload out sync_payload err tmp_err
  payload=$(jq -n \
    --arg k "$TEAM_BRAIN_API_KEY" \
    --arg j "$key" \
    --arg r "$source_ref" \
    --argjson rev "$revision" \
    '{p_api_key:$k, p_jira_key:$j, p_source_ref:$r, p_revision:$rev}')
  tmp_err=$(mktemp)
  if ! out=$(rpc_try restore_memory "$payload" 2>"$tmp_err"); then
    err=$(tr '\n' ' ' <"$tmp_err" | sed 's/[[:space:]]*$//')
    rm -f "$tmp_err"
    if echo "$err" | grep -Eqi 'Could not find the function|PGRST202|404|does not exist'; then
      die "restore_memory unavailable — apply migration 20260803000001_team_brain_memory_history.sql"
    fi
    die "restore_memory failed: ${err:-unknown error}"
  fi
  rm -f "$tmp_err"
  sync_payload=$(fetch_memories "$key")
  merge_memory_cache "$key" "$sync_payload"
  mirror_captures_to_md "$key" "$sync_payload"
  touch_sync_activity "$key"
  if jq -e '.restored == true' >/dev/null 2>&1 <<<"$out"; then
    echo "→ restored $source_ref from revision $revision (current archived)" >&2
  elif jq -e '.deduped == true' >/dev/null 2>&1 <<<"$out"; then
    echo "→ already at revision $revision (no change)" >&2
  fi
  echo "$out" | jq .
}

# recall — semantic (vector) when embed provider set; else FTS. No query → sync.
cmd_recall() {
  require_api_key
  local key="${1:-}"
  shift || true
  [ -n "$key" ] || die "usage: recall <JIRA-KEY> [search query...]"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local query="${*:-}"
  local out emb payload hit_n
  if [ -n "$query" ]; then
    emb=""
    if emb=$(embed_text "$query" 2>/dev/null); then
      echo "→ recall mode: vector (${TEAM_BRAIN_EMBED_PROVIDER})" >&2
      payload=$(jq -n \
        --arg k "$TEAM_BRAIN_API_KEY" \
        --arg j "$key" \
        --arg q "$query" \
        --argjson e "$emb" \
        '{p_api_key:$k, p_jira_key:$j, p_query:$q, p_limit:10, p_embedding:$e}')
    else
      echo "→ recall mode: fts (set TEAM_BRAIN_EMBED_PROVIDER for semantic)" >&2
      payload=$(jq -n \
        --arg k "$TEAM_BRAIN_API_KEY" \
        --arg j "$key" \
        --arg q "$query" \
        '{p_api_key:$k, p_jira_key:$j, p_query:$q, p_limit:10, p_embedding:null}')
    fi
    if ! out=$(rpc_try search_memories "$payload" 2>/dev/null); then
      # Pre-P2 signature (no p_embedding)
      if ! out=$(rpc_try search_memories "$(jq -n \
        --arg k "$TEAM_BRAIN_API_KEY" \
        --arg j "$key" \
        --arg q "$query" \
        '{p_api_key:$k, p_jira_key:$j, p_query:$q, p_limit:10}')" 2>/dev/null); then
        die "search_memories unavailable — apply memory + embeddings migrations"
      fi
    fi
    merge_memory_cache "$key" "$(jq '{initiative, memories: (.memories // []), captures: (.memories // [])}' <<<"$out")"
    local hit_n
    hit_n=$(jq '((.memories // []) | length)' <<<"$out")
    bump_metric "$key" "recall_hits" "$hit_n"
    touch_sync_activity "$key"
    mark_compliance "$key" recall
    echo "$out" | jq .
  else
    out=$(fetch_memories "$key")
    merge_memory_cache "$key" "$out"
    mirror_captures_to_md "$key" "$out"
    hit_n=$(jq '((.memories // .captures) // []) | length' <<<"$out")
    bump_metric "$key" "recall_hits" "$hit_n"
    touch_sync_activity "$key"
    mark_compliance "$key" recall
    echo "$out" | jq .
  fi
}

# reembed — backfill embeddings for recent memories missing vectors
cmd_reembed() {
  require_api_key
  local key="${1:-}"
  local limit="${2:-20}"
  [ -n "$key" ] || die "usage: reembed <JIRA-KEY> [limit]"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  [ "${TEAM_BRAIN_EMBED_PROVIDER:-none}" != "none" ] && [ -n "${TEAM_BRAIN_EMBED_PROVIDER:-}" ] \
    || die "set TEAM_BRAIN_EMBED_PROVIDER=openai|ollama first"

  local payload mem_id body emb n=0
  payload=$(fetch_memories "$key")
  while IFS=$'\t' read -r mem_id body; do
    [ -n "$mem_id" ] || continue
    emb=$(embed_text "$body") || die "embed failed for $mem_id"
    rpc set_memory_embedding "$(jq -n \
      --arg k "$TEAM_BRAIN_API_KEY" \
      --arg id "$mem_id" \
      --argjson e "$emb" \
      '{p_api_key:$k, p_memory_id:$id, p_embedding:$e}')" >/dev/null
    echo "embedded $mem_id" >&2
    n=$((n + 1))
    [ "$n" -ge "$limit" ] && break
  done < <(jq -r --argjson lim "$limit" '
    ((.memories // .captures) // [])[:$lim][]
    | [.id, .body] | @tsv
  ' <<<"$payload")
  echo "reembed complete ($n memories)" >&2
}

cmd_sync() {
  require_api_key
  local key="${1:-}"
  local since="${2:-}"
  [ -n "$key" ] || die "usage: sync <JIRA-KEY> [since-ISO8601]"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  local out
  out=$(fetch_memories "$key" "$since")
  merge_memory_cache "$key" "$out"
  mirror_captures_to_md "$key" "$out"
  touch_sync_activity "$key"
  echo "$out" | jq .
}

# Near-realtime watch: authenticated poll (default) + optional Broadcast push (#31).
# postgres_changes CDC is intentionally NOT used — would require anon SELECT on captures.
# See docs/team-brain-memory.md P1 + Realtime push section.
cmd_watch() {
  require_api_key
  local key=""
  local interval=5
  local mode="auto" # auto|push|poll
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --push) mode="push"; shift ;;
      --poll) mode="poll"; shift ;;
      --interval) interval="${2:-5}"; shift 2 ;;
      -h|--help)
        die "usage: watch <JIRA-KEY> [interval-seconds] [--push|--poll]"
        ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  if [ ${#positional[@]} -ge 1 ]; then key="${positional[0]}"; fi
  if [ ${#positional[@]} -ge 2 ]; then interval="${positional[1]}"; fi
  [ -n "$key" ] || die "usage: watch <JIRA-KEY> [interval-seconds] [--push|--poll]"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  [[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -ge 2 ] || die "interval must be an integer >= 2"

  echo "→ Initial sync for $key" >&2
  local payload since new_count
  payload=$(fetch_memories "$key")
  mirror_captures_to_md "$key" "$payload" >/dev/null
  # Cursor must track updated_at (source_ref merges) — same as cmd_sync_loop
  since=$(jq -r '[((.memories // .captures) // [])[] | (.updated_at // .created_at)] | max // empty' <<<"$payload")
  new_count=$(jq '((.memories // .captures) // []) | length' <<<"$payload")

  if [ "$mode" = "push" ] || [ "$mode" = "auto" ]; then
    # Foreground push listener; poll still runs as safety net unless --push-only later
    if [ "$mode" = "push" ]; then
      export TEAM_BRAIN_REALTIME=on
    fi
    start_realtime_daemon "$key" || true
  fi

  echo "Watching $key every ${interval}s (${new_count} memories; mode=${mode}). Ctrl+C to stop." >&2
  echo "Cursor: ${since:-none}" >&2
  echo "Fallback poll always on — push is additive when Realtime is available." >&2

  trap 'stop_realtime_daemon "'"$key"'"; exit 0' INT TERM

  while true; do
    sleep "$interval"
    local delta
    if [ -n "$since" ]; then
      delta=$(fetch_memories "$key" "$since")
    else
      delta=$(fetch_memories "$key")
    fi
    new_count=$(jq '((.memories // .captures) // []) | length' <<<"$delta")
    if [ "$new_count" -gt 0 ]; then
      echo "" >&2
      echo "── $(date -u +%Y-%m-%dT%H:%M:%SZ) +${new_count} memory(ies) ──" >&2
      jq -r '
        ((.memories // .captures) // []) | .[] |
        "[\(.updated_at // .created_at)] @\(.author_name) \(.kind): \(.body | gsub("\n"; " "))"
      ' <<<"$delta"
      payload=$(fetch_memories "$key")
      mirror_captures_to_md "$key" "$payload" >/dev/null
      since=$(jq -r '[((.memories // .captures) // [])[] | (.updated_at // .created_at)] | max // empty' <<<"$payload")
    fi
  done
}

cmd_list() {
  require_api_key
  rpc list_initiatives "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" '{p_api_key:$k}')" | jq .
}

cmd_mirror() {
  cmd_sync "$@"
}

# breakdown — consume recalled memories → draft stories/spikes/AC (P4)
cmd_breakdown() {
  require_api_key
  need_cmd python3
  local key="${1:-}"
  shift || true
  local query="${*:-}"
  [ -n "$key" ] || die "usage: breakdown <JIRA-KEY> [optional recall query]"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')

  echo "→ Recalling memories for breakdown ($key)" >&2
  local payload
  if [ -n "$query" ]; then
    if ! payload=$(rpc_try search_memories "$(jq -n \
      --arg k "$TEAM_BRAIN_API_KEY" \
      --arg j "$key" \
      --arg q "$query" \
      '{p_api_key:$k, p_jira_key:$j, p_query:$q, p_limit:30, p_embedding:null}')" 2>/dev/null); then
      payload=$(rpc search_memories "$(jq -n \
        --arg k "$TEAM_BRAIN_API_KEY" \
        --arg j "$key" \
        --arg q "$query" \
        '{p_api_key:$k, p_jira_key:$j, p_query:$q, p_limit:30}')")
    fi
  else
    payload=$(fetch_memories "$key")
  fi
  [ -n "$payload" ] || die "no memories returned — attach + remember first"

  write_memory_cache "$key" "$payload"
  local mem_n
  mem_n=$(jq '((.memories // .captures) // []) | length' <<<"$payload")
  bump_metric "$key" "recall_hits" "$mem_n"

  local out_path title written
  out_path="$TEAM_DIR/initiatives/${key}-breakdown.md"
  title=$(jq -r '.initiative.title // empty' <<<"$payload")
  [ -n "$title" ] || title="$key"
  mkdir -p "$TEAM_DIR/initiatives"

  local payload_file
  payload_file=$(mktemp)
  printf '%s' "$payload" >"$payload_file"
  written=$(PAYLOAD_FILE="$payload_file" OUT_PATH="$out_path" KEY="$key" TITLE="$title" python3 <<'PY'
import json, os, datetime
from pathlib import Path

data = json.loads(Path(os.environ["PAYLOAD_FILE"]).read_text(encoding="utf-8"))
out_path = Path(os.environ["OUT_PATH"])
key = os.environ["KEY"]
title = os.environ["TITLE"]
memories = data.get("memories") or data.get("captures") or []
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

by = {"decision": [], "research": [], "note": []}
for m in memories:
    k = (m.get("kind") or "note").lower()
    by.setdefault(k, []).append(m)

lines = [
    f"# Breakdown: {key} — {title}",
    "",
    f"_Generated from **{len(memories)}** team memories at `{now}` (Team Brain P4)._",
    "",
    "## Memory inputs",
    "",
]
if not memories:
    lines.append("_No memories yet — run `remember` / `recall` before breakdown._")
else:
    for m in memories:
        day = (m.get("created_at") or "")[:10]
        author = m.get("author_name") or "?"
        kind = m.get("kind") or "note"
        body = (m.get("body") or "").replace("\n", " ")
        ref = m.get("source_ref") or ""
        ref_s = f" (`{ref}`)" if ref else ""
        lines.append(f"- `{day}` [@{author}] **{kind}**{ref_s}: {body}")

lines += ["", "## Proposed stories / spikes", ""]
n = 1
for m in by.get("decision") or []:
    body = (m.get("body") or "").strip().replace("\n", " ")
    lines += [
        f"### Story {n}: Implement — {body[:80]}",
        "",
        f"**Context:** Decision from @{m.get('author_name', '?')}",
        "",
        "**Acceptance criteria (draft)**",
        f"- [ ] Behavior matches: {body}",
        "- [ ] Tests / docs updated",
        "- [ ] No regression on related paths noted in research",
        "",
    ]
    n += 1

for m in by.get("research") or []:
    body = (m.get("body") or "").strip().replace("\n", " ")
    lines += [
        f"### Spike {n}: Validate — {body[:80]}",
        "",
        f"**Context:** Research from @{m.get('author_name', '?')}",
        "",
        "**Exit criteria (draft)**",
        f"- [ ] Confirm or refute: {body}",
        "- [ ] Capture outcome with `remember … decision`",
        "",
    ]
    n += 1

notes = by.get("note") or []
if notes:
    lines += ["### Follow-ups from notes", ""]
    for m in notes:
        body = (m.get("body") or "").strip().replace("\n", " ")
        lines.append(f"- [ ] {body}")
    lines.append("")

if n == 1 and not notes:
    lines += [
        "_Insufficient structured memories to draft stories. Add `research` / `decision` memories and re-run._",
        "",
    ]

lines += ["## Gaps", ""]
if not by.get("decision"):
    lines.append("- [ ] No **decision** memories — sequencing may be unclear")
if not by.get("research"):
    lines.append("- [ ] No **research** memories — technical paths may be missing")
if len(memories) < 2:
    lines.append("- [ ] Thin memory set — consider a crew `sync` / more `remember` before planning")
if by.get("decision") and by.get("research"):
    lines.append("- [ ] Review story/spike split with the crew; trim duplicates")
lines += [
    "",
    "## Next",
    "",
    "1. Edit this draft with the crew",
    "2. File Jira stories/spikes from the sections above",
    "3. `remember` new decisions as planning settles",
    "",
]
out_path.write_text("\n".join(lines), encoding="utf-8")
print(out_path)
PY
)
  rm -f "$payload_file"

  bump_metric "$key" "breakdown_runs" 0
  # Persist last memory count on breakdown
  local path
  path="$(METRICS_FILE)"
  jq --arg k "$key" --argjson n "$mem_n" \
    '.initiatives[$k].memories_at_last_breakdown = $n' "$path" >"${path}.tmp" && mv "${path}.tmp" "$path"

  echo "Breakdown draft → $written" >&2
  jq -n \
    --arg key "$key" \
    --arg path "$written" \
    --argjson memories "$mem_n" \
    --arg title "$title" \
    '{jira_key:$key, title:$title, memory_count:$memories, breakdown_path:$path}'
}

# Local reuse overlay for team aggregation (#35) — never uploads metrics.json.
_local_reuse_overlay() {
  local path
  path="$(METRICS_FILE)"
  if [ ! -f "$path" ]; then
    echo '{"available":false,"note":"no local metrics.json yet — recall/remember/breakdown on this machine first"}'
    return 0
  fi
  jq '{
    available: true,
    source: "local metrics.json (this machine only — not uploaded)",
    initiatives: .initiatives,
    totals: {
      recall_hits: ([.initiatives[].recall_hits] | add // 0),
      remember_writes: ([.initiatives[].remember_writes] | add // 0),
      breakdown_runs: ([.initiatives[].breakdown_runs] | add // 0),
      memories_reused_total: ([.initiatives[].memories_reused_total] | add // 0)
    }
  }' "$path"
}

# Client-side fallback when team_aggregate_metrics RPC is not applied yet.
_aggregate_client_fallback() {
  local initiatives payload key mems
  initiatives=$(rpc list_initiatives "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" '{p_api_key:$k}')")
  mems='[]'
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    payload=$(rpc list_recent "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" --arg j "$key" \
      '{p_api_key:$k, p_jira_key:$j, p_limit:200}')") || continue
    mems=$(jq -n -c --argjson acc "$mems" --argjson p "$payload" '
      $acc + (
        ($p.memories // $p.captures // []) | map({
          jira_key: ($p.initiative.jira_key // ""),
          title: ($p.initiative.title // ""),
          status: ($p.initiative.status // ""),
          kind,
          author_name,
          created_at,
          updated_at: (.updated_at // .created_at // null)
        })
      )
    ')
  done < <(jq -r '.[].jira_key // empty' <<<"$initiatives")

  jq -n --argjson memories "$mems" --argjson initiatives "$initiatives" '
    {
      version: 1,
      source: "client_fallback",
      note: "Apply migration 20260807000001_team_brain_aggregate_metrics.sql for server RPC (faster, no bodies).",
      team: { name: null, id: null },
      totals: {
        members: ([$memories[].author_name] | unique | length),
        initiatives: ($initiatives | length),
        memories: ($memories | length)
      },
      coverage: {
        by_member_kind: (
          [$memories[] | {author_name, kind}]
          | group_by(.author_name + "|" + .kind)
          | map({author_name: .[0].author_name, kind: .[0].kind, count: length})
          | sort_by(-.count)
        ),
        by_member_initiative: (
          [$memories[] | {author_name, jira_key}]
          | group_by(.author_name + "|" + .jira_key)
          | map({author_name: .[0].author_name, jira_key: .[0].jira_key, count: length})
          | sort_by(-.count)
        ),
        matrix: (
          [$memories[] | {author_name, kind}]
          | group_by(.author_name)
          | map({
              key: .[0].author_name,
              value: (group_by(.kind) | map({key: .[0].kind, value: length}) | from_entries)
            })
          | from_entries
        ),
        note: "Derived from Team Brain remember activity. Not personal BRAIN.md. Bodies discarded client-side."
      },
      reuse: {
        per_initiative: (
          $initiatives | map(. as $i | {
            jira_key: $i.jira_key,
            title: ($i.title // ""),
            status: ($i.status // ""),
            memory_count: ([$memories[] | select(.jira_key == $i.jira_key)] | length),
            unique_authors: ([$memories[] | select(.jira_key == $i.jira_key) | .author_name] | unique | length)
          })
        ),
        per_week: (
          [$memories[] | select((.updated_at // .created_at) != null) | {
            week: ((.updated_at // .created_at)[0:7]),
            jira_key
          }]
          | group_by(.week + "|" + .jira_key)
          | map({week: .[0].week, jira_key: .[0].jira_key, memories: length})
          | sort_by(.week) | reverse
        ),
        note: "Fallback buckets by YYYY-MM from list_recent samples (limit 200/key). Server RPC preferred for ISO weeks."
      },
      privacy: {
        includes: ["member display_name", "memory kind counts", "initiative keys"],
        excludes: ["memory bodies (stripped)", "personal BRAIN.md", "api keys", "GitHub review graph"],
        scope: "crew members with a valid team api_key"
      },
      out_of_scope_v1: ["collaboration_graph_from_github", "workload_heatmap_from_calendar", "personal_BRAIN_md_skills"]
    }
  '
}

cmd_aggregate() {
  load_config
  require_api_key
  ensure_team_gitignore
  local remote local_overlay merged
  local_overlay=$(_local_reuse_overlay)
  if remote=$(rpc_try team_aggregate_metrics "$(jq -n --arg k "$TEAM_BRAIN_API_KEY" '{p_api_key:$k}')" 2>/dev/null); then
    if echo "$remote" | jq -e 'type == "object" and (.coverage != null or .reuse != null)' >/dev/null 2>&1; then
      jq -n --argjson remote "$remote" --argjson local "$local_overlay" \
        '$remote + {local_reuse: $local, source: ($remote.source // "server")}'
      return 0
    fi
  fi
  echo "→ team_aggregate_metrics RPC unavailable — client fallback (apply …_aggregate_metrics.sql)" >&2
  merged=$(_aggregate_client_fallback)
  jq -n --argjson remote "$merged" --argjson local "$local_overlay" \
    '$remote + {local_reuse: $local}'
}

cmd_metrics() {
  load_config
  ensure_team_gitignore
  local path key="${1:-}"
  case "$key" in
    --team|team|--aggregate|aggregate)
      cmd_aggregate
      return 0
      ;;
  esac
  path="$(METRICS_FILE)"
  if [ ! -f "$path" ]; then
    echo '{"version":1,"initiatives":{},"note":"no metrics yet — recall/remember/breakdown first"}'
    return 0
  fi
  if [ -n "$key" ]; then
    key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
    jq --arg k "$key" '{
      jira_key: $k,
      metrics: (.initiatives[$k] // {}),
      reuse_hint: (
        if (.initiatives[$k].recall_hits // 0) > 0 and (.initiatives[$k].memories_reused_total // 0) > 0
        then "Crew context is being reused (recall hits + memories loaded)."
        else "Run recall/breakdown on this key to start tracking reuse."
        end
      )
    }' "$path"
  else
    jq '{
      version,
      initiatives,
      totals: {
        recall_hits: ([.initiatives[].recall_hits] | add // 0),
        remember_writes: ([.initiatives[].remember_writes] | add // 0),
        breakdown_runs: ([.initiatives[].breakdown_runs] | add // 0),
        memories_reused_total: ([.initiatives[].memories_reused_total] | add // 0)
      },
      team_hint: "Run metrics --team (or aggregate) for crew coverage + reuse (#35)"
    }' "$path"
  fi
}

cmd_status() {
  load_config
  echo "TEAM_DIR=$TEAM_DIR"
  echo "CONFIG=$CONFIG_YAML $([ -f "$CONFIG_YAML" ] && echo OK || echo missing)"
  echo "CREDENTIALS=$CRED_FILE $([ -f "$CRED_FILE" ] && echo OK || echo missing)"
  echo "SUPABASE_URL=${TEAM_BRAIN_SUPABASE_URL:-unset}"
  echo "ANON_KEY=$([ -n "${TEAM_BRAIN_SUPABASE_ANON_KEY:-}" ] && echo set || echo unset)"
  echo "API_KEY=$([ -n "${TEAM_BRAIN_API_KEY:-}" ] && echo set || echo unset)"
  echo "EMBED_PROVIDER=${TEAM_BRAIN_EMBED_PROVIDER:-none} dims=$(embed_dims)"
  echo "METRICS=$(METRICS_FILE) $([ -f "$(METRICS_FILE)" ] && echo OK || echo missing)"
  echo "SYNC_DIR=$(SYNC_DIR) $([ -d "$(SYNC_DIR)" ] && echo OK || echo missing)"
  if [ -d "$(SYNC_DIR)" ]; then
    echo "SYNC_SESSIONS:"
    cmd_sync_status 2>/dev/null | jq -c '.[]? // .' 2>/dev/null || true
  fi
  if [ -n "${TEAM_BRAIN_API_KEY:-}" ] && [ -n "${TEAM_BRAIN_SUPABASE_URL:-}" ]; then
    cmd_whoami || true
  fi
}

usage() {
  cat <<EOF
Team Brain — collaborative memory client (Supabase)

  bootstrap --team NAME --admin "Name" [options…]
      Admin one-shot: configure → migrate → register → print joiner share bundle.
      See: bash core/scripts/team-brain-bootstrap.sh --help
  onboard <invite-code> "Your Name" [JIRA-KEY] [--role member|viewer]
  register <team-name> [display-name]
  join <invite-code> [display-name] [--role member|viewer]
  whoami
  pin show | pin set --jira KEY [--team-name NAME] [--project-ref REF]
      Commit-safe .team-brain/project.json (#39). Never secrets (anon/api_key/invite).
  rotate-invite              Admin-only: rotate invite code (#40)
  set-role "Name" --role admin|member|viewer
      Admin-only: change a teammate's role (#40)
  attach [JIRA-KEY] [title] [status] [jira-url]
      Upsert initiative (writers only). Jira key optional if project.json pin set.

  start [JIRA-KEY] [interval-sec] [idle-hours] [--foreground]
      ONE manual step: load crew memory + enter sync mode (background pull).
      Jira key optional when .team-brain/project.json has default_jira_key.
      Merge-safe: new inserts; identical → no-op; same source_ref + new body → update.
      Sleeps after idle-hours (default 1h) with warning; wake/start to resume.
  stop [JIRA-KEY]           Leave sync mode (all sessions if no key)
  wake <JIRA-KEY>           Resume from sleep
  touch <JIRA-KEY>          Mark activity (keeps sync awake); wakes if sleeping
  sync-status [JIRA-KEY]    Sync mode + MCP compliance (research_ok, agent_action)
  compliance [JIRA-KEY]     MCP-first soft gate status (issue #36)

  remember <JIRA-KEY> <research|decision|note|learning> [--source-ref REF] [--body-file PATH | - | <body...>]
      Write shared memory (admin/member only; viewers forbidden). Dedupes / source_ref merge.
  correct <JIRA-KEY> --source-ref REF [--kind research|decision|note] [--was TEXT] [--learning TEXT] [--body-file PATH | - | <body...>]
      Human correction: UPDATE memory at source_ref; optional learning row at REF/learning.
      Bodies: natural-language prefer/avoid guidance — not TODO/NO-TODO dumps.
  history <JIRA-KEY> --source-ref REF
      List archived revisions + current body (apply memory-history migration).
  restore <JIRA-KEY> --source-ref REF --revision N
      Soft-rollback to revision N; archives current body first (audit preserved).
  capture …                 Compat alias for remember

  recall <JIRA-KEY> [query…]
      With query: FTS search. Without: same as sync (list recent).
  sync <JIRA-KEY> [since]   Pull memories → cache/<KEY>.json (+ md export)
  watch <JIRA-KEY> [secs] [--push|--poll]
      Near-realtime: authenticated poll (always) + optional Broadcast push (#31).
      --push prefers Realtime listener; --poll disables it. Default: auto.
  broadcast-topic <JIRA-KEY>
      Show signal Broadcast topic (apply …_realtime_broadcast.sql).
  breakdown <JIRA-KEY> [q]  Recall memories → initiatives/<KEY>-breakdown.md (stories/spikes)
  metrics [JIRA-KEY]        Local reuse stats (recall hits, remembers, breakdowns)
  metrics --team | aggregate
      Crew aggregation (#35): coverage matrix + reuse/activity by initiative/week.
      Prefers team_aggregate_metrics RPC; falls back to list_recent (bodies stripped).
      Overlays local metrics.json recall hits (this machine only — never uploaded).
  reembed <JIRA-KEY> [n]    Backfill embeddings (requires TEAM_BRAIN_EMBED_PROVIDER)
  list
  status

Embeddings (optional semantic recall):
  export TEAM_BRAIN_EMBED_PROVIDER=openai   # or ollama
  export TEAM_BRAIN_EMBED_API_KEY=sk-...    # openai
  export TEAM_BRAIN_EMBED_MODEL=text-embedding-3-small
  # ollama: TEAM_BRAIN_EMBED_BASE_URL=http://127.0.0.1:11434 MODEL=nomic-embed-text
  Vectors are 768-d. Without a provider, recall uses FTS.

Realtime push (#31 — signal Broadcast; poll always remains fallback):
  export TEAM_BRAIN_REALTIME=auto           # auto | on | off
  pip install websockets                   # required for push listener
  Apply migration 20260804000001_team_brain_realtime_broadcast.sql

Roles / invites (#40):
  Apply migration 20260805000001_team_brain_roles_and_invites.sql
  Roles: admin | member (write) | viewer (read-only)
  Admin: rotate-invite · set-role

Repo pin (#39):
  Commit .team-brain/project.json (non-secret). Keep credentials.json gitignored.

Team aggregation (#35):
  Apply migration 20260807000001_team_brain_aggregate_metrics.sql
  bash core/scripts/team-brain-api.sh metrics --team
  Privacy: counts + display_name only — never memory bodies / BRAIN.md

SoT: Supabase memories + .team-brain/cache/<KEY>.json
Sync state: .team-brain/sync/<KEY>.json
Push notify: .team-brain/notify/<KEY>.json
Pin: .team-brain/project.json (commit-safe)
Export: .team-brain/initiatives/<KEY>.md (optional)
Plan: docs/team-brain-memory.md
EOF
}

cmd_bootstrap() {
  local boot="${SCRIPT_DIR}/team-brain-bootstrap.sh"
  [ -f "$boot" ] || die "team-brain-bootstrap.sh missing at $boot"
  bash "$boot" "$@"
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    bootstrap) cmd_bootstrap "$@" ;;
    onboard) cmd_onboard "$@" ;;
    register) cmd_register "$@" ;;
    join) cmd_join "$@" ;;
    whoami) cmd_whoami "$@" ;;
    pin) cmd_pin "$@" ;;
    rotate-invite|rotate_invite) cmd_rotate_invite "$@" ;;
    set-role|set_role) cmd_set_role "$@" ;;
    attach) cmd_attach "$@" ;;
    start) cmd_start "$@" ;;
    stop) cmd_stop "$@" ;;
    wake) cmd_wake "$@" ;;
    touch) cmd_touch "$@" ;;
    sync-status|sync_status) cmd_sync_status "$@" ;;
    compliance|compliance-status|compliance_status) cmd_compliance "$@" ;;
    _sync_loop) cmd_sync_loop "$@" ;;
    remember) cmd_remember "$@" ;;
    correct) cmd_correct "$@" ;;
    history) cmd_history "$@" ;;
    restore) cmd_restore "$@" ;;
    capture) cmd_capture "$@" ;;
    recall) cmd_recall "$@" ;;
    reembed) cmd_reembed "$@" ;;
    breakdown) cmd_breakdown "$@" ;;
    metrics) cmd_metrics "$@" ;;
    aggregate|team-metrics|team_metrics) cmd_aggregate "$@" ;;
    sync|mirror) cmd_sync "$@" ;;
    watch) cmd_watch "$@" ;;
    broadcast-topic|broadcast_topic) cmd_broadcast_topic "$@" ;;
    _pull_signal) cmd_pull_signal "$@" ;;
    list) cmd_list "$@" ;;
    status) cmd_status "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
