#!/usr/bin/env bash
# Team Brain — Supabase RPC client
# Usage:
#   export TEAM_BRAIN_SUPABASE_URL=https://xxxx.supabase.co
#   export TEAM_BRAIN_SUPABASE_ANON_KEY=eyJ...
#   export TEAM_BRAIN_API_KEY=tb_...   # after register/join (or use credentials file)
#   bash team-brain-api.sh <command> [args...]
#
# Commands: onboard | register | join | whoami | attach | remember | recall |
#           capture | sync | watch | breakdown | metrics | list | mirror | status
# Plan: docs/team-brain-memory.md — memories are SoT; md is optional export.

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
  site: ${TEAM_BRAIN_JIRA_SITE:-https://your-org.atlassian.net}
initiatives: []
EOF
    echo "Seeded $CONFIG_YAML from $PUBLIC_ENV" >&2
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
    echo "RPC $fn failed (HTTP $http)" >&2
    return 1
  fi
  echo "$resp_body"
  return 0
}

rpc() {
  local out
  out=$(rpc_try "$1" "$2") || die "RPC $1 failed"
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

ensure_team_gitignore() {
  mkdir -p "$TEAM_DIR"
  if [ ! -f "$TEAM_DIR/.gitignore" ]; then
    printf '%s\n' 'credentials.json' 'cache/' 'metrics.json' >"$TEAM_DIR/.gitignore"
    return
  fi
  for entry in cache/ metrics.json; do
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
    local site="${TEAM_BRAIN_JIRA_SITE:-https://your-org.atlassian.net}"
    local url="${site%/}/browse/${jira_key}"
    echo "→ attach + recall recent memories for $jira_key" >&2
    if ! cmd_attach "$jira_key" "$jira_key" "active" "$url" >/dev/null; then
      die "attach failed for $jira_key"
    fi
    echo "→ memories:" >&2
    cmd_sync "$jira_key" | jq '{initiative: .initiative, memory_count: ((.memories // .captures)//[] | length), authors: [((.memories // .captures)//[])[].author_name] | unique}'
    echo "" >&2
    echo "Onboard complete. Cache: $TEAM_DIR/cache/${jira_key}.json  Export: $TEAM_DIR/initiatives/${jira_key}.md" >&2
  else
    echo "" >&2
    echo "Onboard complete (no Jira key). Next: bash $0 attach <JIRA-KEY> && bash $0 sync <JIRA-KEY>" >&2
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
  # Session attach always pulls recent memories into cache (P0 periodic sync)
  cmd_sync "$key" >/dev/null || true
  echo "$out" | jq .
}

# remember — collaborative memory write (preferred). capture is a compat alias.
cmd_remember() {
  require_api_key
  local key="${1:-}"
  local kind="${2:-note}"
  shift 2 || true
  local source_ref="${TEAM_BRAIN_SOURCE_REF:-}"
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --source-ref)
        source_ref="${2:-}"
        shift 2 || die "usage: remember <JIRA-KEY> <kind> [--source-ref REF] <body...>"
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  local body_text=""
  if [ ${#args[@]} -gt 0 ]; then
    body_text="${args[*]}"
  fi
  [ -n "$key" ] || die "usage: remember <JIRA-KEY> <research|decision|note> [--source-ref REF] <body...>"
  [ -n "$body_text" ] || die "memory body required"
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
      out=$(rpc add_capture "$(jq -n \
        --arg k "$TEAM_BRAIN_API_KEY" \
        --arg j "$key" \
        --arg kind "$kind" \
        --arg b "$body_text" \
        '{p_api_key:$k, p_jira_key:$j, p_kind:$kind, p_body:$b}')")
    fi
  fi
  sync_payload=$(fetch_memories "$key")
  mirror_captures_to_md "$key" "$sync_payload"
  # Count non-deduped writes as remember_writes; still bump on dedupe (retry reuse)
  bump_metric "$key" "remember_writes" 0
  echo "$out" | jq .
}

cmd_capture() {
  # Compat alias for remember (no source_ref)
  cmd_remember "$@"
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
    write_memory_cache "$key" "$(jq '{initiative, memories, captures: .memories, mode}' <<<"$out")"
    local hit_n
    hit_n=$(jq '((.memories // []) | length)' <<<"$out")
    bump_metric "$key" "recall_hits" "$hit_n"
    echo "$out" | jq .
  else
    out=$(fetch_memories "$key")
    mirror_captures_to_md "$key" "$out"
    hit_n=$(jq '((.memories // .captures) // []) | length' <<<"$out")
    bump_metric "$key" "recall_hits" "$hit_n"
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
  mirror_captures_to_md "$key" "$out"
  echo "$out" | jq .
}

# Near-realtime watch: poll list_recent with a cursor (member api_key auth).
# True postgres_changes Realtime cannot use our custom api_key RLS model safely
# with the anon JWT — see docs/team-brain-memory.md P1.
cmd_watch() {
  require_api_key
  local key="${1:-}"
  local interval="${2:-5}"
  [ -n "$key" ] || die "usage: watch <JIRA-KEY> [interval-seconds]"
  key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
  [[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -ge 2 ] || die "interval must be an integer >= 2"

  echo "→ Initial sync for $key" >&2
  local payload since new_count
  payload=$(fetch_memories "$key")
  mirror_captures_to_md "$key" "$payload" >/dev/null
  since=$(jq -r '[((.memories // .captures) // [])[].created_at] | max // empty' <<<"$payload")
  new_count=$(jq '((.memories // .captures) // []) | length' <<<"$payload")
  echo "Watching $key every ${interval}s (${new_count} memories). Ctrl+C to stop." >&2
  echo "Cursor: ${since:-none}" >&2

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
        "[\(.created_at)] @\(.author_name) \(.kind): \(.body | gsub("\n"; " "))"
      ' <<<"$delta"
      payload=$(fetch_memories "$key")
      mirror_captures_to_md "$key" "$payload" >/dev/null
      since=$(jq -r '[((.memories // .captures) // [])[].created_at] | max // empty' <<<"$payload")
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

cmd_metrics() {
  load_config
  ensure_team_gitignore
  local path key="${1:-}"
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
      }
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
  if [ -n "${TEAM_BRAIN_API_KEY:-}" ] && [ -n "${TEAM_BRAIN_SUPABASE_URL:-}" ]; then
    cmd_whoami || true
  fi
}

usage() {
  cat <<EOF
Team Brain — collaborative memory client (Supabase)

  onboard <invite-code> "Your Name" [JIRA-KEY]
  register <team-name> [display-name]
  join <invite-code> [display-name]
  whoami
  attach <JIRA-KEY> [title] [status] [jira-url]
      Upsert initiative, then pull recent memories into cache/

  remember <JIRA-KEY> <research|decision|note> [--source-ref REF] <body...>
      Write shared memory (preferred). Dedupes by source_ref / content hash.
  capture …                 Compat alias for remember

  recall <JIRA-KEY> [query…]
      With query: FTS search. Without: same as sync (list recent).
  sync <JIRA-KEY> [since]   Pull memories → cache/<KEY>.json (+ md export)
  watch <JIRA-KEY> [secs]   Near-realtime poll (default 5s); updates cache on new memories
  breakdown <JIRA-KEY> [q]  Recall memories → initiatives/<KEY>-breakdown.md (stories/spikes)
  metrics [JIRA-KEY]        Reuse stats (recall hits, remembers, breakdowns)
  reembed <JIRA-KEY> [n]    Backfill embeddings (requires TEAM_BRAIN_EMBED_PROVIDER)
  list
  status

Embeddings (optional semantic recall):
  export TEAM_BRAIN_EMBED_PROVIDER=openai   # or ollama
  export TEAM_BRAIN_EMBED_API_KEY=sk-...    # openai
  export TEAM_BRAIN_EMBED_MODEL=text-embedding-3-small
  # ollama: TEAM_BRAIN_EMBED_BASE_URL=http://127.0.0.1:11434 MODEL=nomic-embed-text
  Vectors are 768-d. Without a provider, recall uses FTS.

SoT: Supabase memories + .team-brain/cache/<KEY>.json
Export: .team-brain/initiatives/<KEY>.md (optional)
Plan: docs/team-brain-memory.md
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
    remember) cmd_remember "$@" ;;
    capture) cmd_capture "$@" ;;
    recall) cmd_recall "$@" ;;
    reembed) cmd_reembed "$@" ;;
    breakdown) cmd_breakdown "$@" ;;
    metrics) cmd_metrics "$@" ;;
    sync|mirror) cmd_sync "$@" ;;
    watch) cmd_watch "$@" ;;
    list) cmd_list "$@" ;;
    status) cmd_status "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
