#!/usr/bin/env bash
# Team Brain — one-command crew bootstrap (admin, ~10 minutes)
# Issue: https://github.com/Hrithik-Gavankar/brainstack/issues/41
#
# Collapses: configure Supabase → apply migrations → register → print share bundle.
# Never commits live keys. Joiners still use onboard (no Supabase account).
#
# Usage:
#   bash core/scripts/team-brain-bootstrap.sh --team "Spike Crew" --admin "Alice" [options]
#   bash core/scripts/team-brain-api.sh bootstrap --team "Spike Crew" --admin "Alice" ...
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
API="${TEAM_BRAIN_API_SCRIPT:-$SCRIPT_DIR/team-brain-api.sh}"
PUBLIC_ENV="${TEAM_BRAIN_PUBLIC_ENV:-$REPO_ROOT/supabase/project.public.env}"
MIGRATIONS_DIR="$REPO_ROOT/supabase/migrations"
SUPABASE_DIR="$REPO_ROOT/supabase"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "→ $*" >&2; }
ok() { echo "✓ $*" >&2; }
warn() { echo "⚠ $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1 — install it and retry"
}

usage() {
  cat <<EOF
Team Brain crew bootstrap (admin once)

  bash core/scripts/team-brain-bootstrap.sh --team NAME --admin "Display Name" [options]

Required:
  --team NAME               Crew / team name for register
  --admin "Display Name"    Your display name (admin)

Config (any of env / flags / existing project.public.env):
  --url URL                 Supabase Project URL
  --anon KEY                Supabase anon key
  --jira-site URL           Jira site (default from env / your-org placeholder)
  --jira KEY                Optional: attach this Jira key after register
  --jira-title TITLE        Optional title for attach
  --db-url URL              Postgres URI to apply migrations (psql). Or set TEAM_BRAIN_DB_URL.
                            Never uses ambient DATABASE_URL. Never written to project.public.env.
  --local                   Docker local stack: supabase start + status keys + migrate
  --skip-migrations         Migrations already applied
  --skip-register           Only configure (+ migrate); do not register
  --write-env               Persist URL/anon/jira-site into supabase/project.public.env (never commit live keys)
  --dry-run                 Print plan; no mutations
  -h, --help                This help

Migration strategy (first match wins):
  1. --local                   → supabase start (CLI applies supabase/migrations)
  2. --db-url / TEAM_BRAIN_DB_URL → psql applies each migration in timestamp order
  3. linked CLI                → supabase db push (must match --url project)
  4. otherwise                 → combined SQL + SQL Editor steps; re-run with --skip-migrations

Examples:
  # Hosted project you already filled in project.public.env + linked CLI:
  bash core/scripts/team-brain-bootstrap.sh --team "Spike Crew" --admin "Alice" --jira AAP-81423

  # Pass URL/anon + DB URL for migrations:
  bash core/scripts/team-brain-bootstrap.sh --team "Spike Crew" --admin "Alice" \\
    --url "https://xxxx.supabase.co" --anon "eyJ..." --db-url "postgresql://postgres:...@db.xxxx.supabase.co:5432/postgres"

  # Local Docker demo:
  bash core/scripts/team-brain-bootstrap.sh --team "Local Crew" --admin "Alice" --local --jira DEMO-1
EOF
}

TEAM_NAME=""
ADMIN_NAME=""
SUPABASE_URL="${TEAM_BRAIN_SUPABASE_URL:-}"
ANON_KEY="${TEAM_BRAIN_SUPABASE_ANON_KEY:-}"
JIRA_SITE="${TEAM_BRAIN_JIRA_SITE:-}"
JIRA_KEY=""
JIRA_TITLE=""
# Only explicit --db-url or TEAM_BRAIN_DB_URL (never ambient DATABASE_URL — wrong DB risk)
DB_URL="${TEAM_BRAIN_DB_URL:-}"
USE_LOCAL=0
SKIP_MIGRATIONS=0
SKIP_REGISTER=0
WRITE_ENV=0
DRY_RUN=0
MIGRATION_BLOCKED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAM_NAME="${2:-}"; shift 2 ;;
    --admin) ADMIN_NAME="${2:-}"; shift 2 ;;
    --url) SUPABASE_URL="${2:-}"; shift 2 ;;
    --anon) ANON_KEY="${2:-}"; shift 2 ;;
    --jira-site) JIRA_SITE="${2:-}"; shift 2 ;;
    --jira) JIRA_KEY="${2:-}"; shift 2 ;;
    --jira-title) JIRA_TITLE="${2:-}"; shift 2 ;;
    --db-url) DB_URL="${2:-}"; shift 2 ;;
    --local) USE_LOCAL=1; shift ;;
    --skip-migrations) SKIP_MIGRATIONS=1; shift ;;
    --skip-register) SKIP_REGISTER=1; shift ;;
    --write-env) WRITE_ENV=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) die "unknown arg: $1 (see --help)" ;;
  esac
done

[ -n "$TEAM_NAME" ] || die "--team NAME is required (see --help)"
[ -n "$ADMIN_NAME" ] || die "--admin \"Display Name\" is required (see --help)"
[ -f "$API" ] || die "team-brain-api.sh not found at $API"
need_cmd jq
need_cmd curl

is_placeholder_url() {
  case "${1:-}" in
    ""|*YOUR_PROJECT*|*your-project*|*example.supabase*) return 0 ;;
  esac
  return 1
}

is_placeholder_anon() {
  case "${1:-}" in
    ""|your-anon-key|YOUR_ANON*|replace-me*|changeme*) return 0 ;;
  esac
  return 1
}

load_public_env_soft() {
  [ -f "$PUBLIC_ENV" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    case "$line" in
      TEAM_BRAIN_SUPABASE_URL=*)
        [ -n "$SUPABASE_URL" ] || SUPABASE_URL="${line#TEAM_BRAIN_SUPABASE_URL=}"
        ;;
      TEAM_BRAIN_SUPABASE_ANON_KEY=*)
        [ -n "$ANON_KEY" ] || ANON_KEY="${line#TEAM_BRAIN_SUPABASE_ANON_KEY=}"
        ;;
      TEAM_BRAIN_JIRA_SITE=*)
        [ -n "$JIRA_SITE" ] || JIRA_SITE="${line#TEAM_BRAIN_JIRA_SITE=}"
        ;;
    esac
  done <"$PUBLIC_ENV"
}

write_public_env() {
  local url="$1" anon="$2" site="$3"
  cat >"$PUBLIC_ENV" <<EOF
# Team Brain project config — LOCAL CREW VALUES (do not commit live keys to a public fork).
# Generated by team-brain-bootstrap.sh — keep this file local / use env / team.yaml instead if preferred.

TEAM_BRAIN_SUPABASE_URL=${url}
TEAM_BRAIN_SUPABASE_ANON_KEY=${anon}
TEAM_BRAIN_JIRA_SITE=${site:-https://your-org.atlassian.net}
EOF
  ok "Wrote $PUBLIC_ENV (do not commit live keys)"
}

list_migration_files() {
  ls -1 "$MIGRATIONS_DIR"/[0-9]*.sql 2>/dev/null | sort
}

supabase_linked() {
  command -v supabase >/dev/null 2>&1 || return 1
  # Linked projects usually have .temp/project-ref or config under supabase/
  if [ -f "$SUPABASE_DIR/.temp/project-ref" ] || [ -f "$REPO_ROOT/.supabase/project-ref" ]; then
    return 0
  fi
  # supabase status against linked remote is expensive; treat --db-url / --local as preferred
  return 1
}

apply_migrations_psql() {
  local db="$1"
  need_cmd psql
  local f count=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    info "Applying $(basename "$f")"
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  [dry-run] psql … -f $f"
    else
      PSQLRC=/dev/null psql "$db" -v ON_ERROR_STOP=1 -f "$f" >/dev/null
    fi
    count=$((count + 1))
  done < <(list_migration_files)
  [ "$count" -gt 0 ] || die "no migrations found in $MIGRATIONS_DIR"
  ok "Applied $count migrations via psql"
}

apply_migrations_supabase_push() {
  need_cmd supabase
  info "Running supabase db push (linked project)"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] (cd supabase && supabase db push)"
    return 0
  fi
  (
    cd "$SUPABASE_DIR"
    supabase db push
  ) || die "supabase db push failed — login/link the project (supabase login && supabase link) or pass --db-url"
  ok "Migrations applied via supabase db push"
}

write_combined_sql() {
  local out="${1:-$REPO_ROOT/supabase/.bootstrap-migrations.combined.sql}"
  if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] would write combined SQL → $out"
    echo "$out"
    return 0
  fi
  mkdir -p "$(dirname "$out")"
  {
    echo "-- Team Brain combined migrations (generated by bootstrap)"
    echo "-- Apply in Supabase SQL Editor if CLI/psql unavailable. Do not commit live secrets."
    echo ""
    local f
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      echo "-- >>> $(basename "$f")"
      cat "$f"
      echo ""
      echo "-- <<< $(basename "$f")"
      echo ""
    done < <(list_migration_files)
  } >"$out"
  echo "$out"
}

bootstrap_local() {
  need_cmd supabase
  need_cmd docker
  info "Starting local Supabase (Docker) — migrations from supabase/migrations apply on start"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] supabase start"
    SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
    ANON_KEY="${ANON_KEY:-local-anon-dry-run}"
    return 0
  fi
  (
    cd "$REPO_ROOT"
    supabase start
  ) || die "supabase start failed — is Docker running? Install: https://supabase.com/docs/guides/cli"
  # Parse status env
  local status_env
  status_env=$(cd "$REPO_ROOT" && supabase status -o env 2>/dev/null) \
    || die "supabase status failed after start"
  local api_url anon
  api_url=$(echo "$status_env" | sed -n 's/^API_URL=//p' | tr -d '"' | head -1)
  anon=$(echo "$status_env" | sed -n 's/^ANON_KEY=//p' | tr -d '"' | head -1)
  [ -n "$api_url" ] && [ -n "$anon" ] || die "could not read API_URL/ANON_KEY from supabase status -o env"
  SUPABASE_URL="$api_url"
  ANON_KEY="$anon"
  SKIP_MIGRATIONS=1
  WRITE_ENV=1
  ok "Local Supabase ready at $SUPABASE_URL"
}

print_plan() {
  cat >&2 <<EOF

======== Team Brain bootstrap plan ========
  Team:              $TEAM_NAME
  Admin:             $ADMIN_NAME
  Supabase URL:      ${SUPABASE_URL:-"(unset)"}
  Anon key:          $([ -n "$ANON_KEY" ] && echo "(set)" || echo "(unset)")
  Jira site:         ${JIRA_SITE:-https://your-org.atlassian.net}
  Jira attach:       ${JIRA_KEY:-"(none)"}
  Local Docker:      $USE_LOCAL
  Skip migrations:   $SKIP_MIGRATIONS
  Skip register:     $SKIP_REGISTER
  Write public env:  $WRITE_ENV
  DB URL for psql:   $([ -n "$DB_URL" ] && echo "(set — not printed)" || echo "(unset)")
  Dry run:           $DRY_RUN
===========================================

EOF
}

print_share_bundle() {
  local invite="$1"
  local team="$2"
  local url="$3"
  local anon="$4"
  local jira="$5"
  local site="${6:-https://your-org.atlassian.net}"

  cat <<EOF

╔══════════════════════════════════════════════════════════════════╗
║  Team Brain — share bundle (admin → crew)                        ║
╚══════════════════════════════════════════════════════════════════╝

Team:     ${team}
Invite:   ${invite}
URL:      ${url}
Anon:     ${anon}
Jira key: ${jira:-"(give teammates the ticket key)"}
Jira:     ${site}

Joiner checklist (no Supabase account needed):
  1. Clone brainstack (or use installed skills)
  2. Put URL + anon in local supabase/project.public.env (or .team-brain/team.yaml / env)
  3. Run:
       bash core/scripts/team-brain-api.sh onboard ${invite} "Their Name" ${jira:-JIRA-KEY}
  4. Start sync:
       bash core/scripts/team-brain-api.sh start ${jira:-JIRA-KEY}

Do NOT commit live URL/anon/invite to a public fork.
Do NOT share service_role or member api_key in chat logs that get committed.

Admin credentials saved under .team-brain/credentials.json (gitignored).
EOF
}

# ----- main -----
load_public_env_soft
[ -n "$JIRA_SITE" ] || JIRA_SITE="https://your-org.atlassian.net"

if [ "$USE_LOCAL" -eq 1 ]; then
  bootstrap_local
fi

print_plan

if [ "$USE_LOCAL" -eq 0 ]; then
  if is_placeholder_url "$SUPABASE_URL" || is_placeholder_anon "$ANON_KEY"; then
    die "Supabase URL/anon missing or still placeholders.
  Fix one of:
    • Pass --url and --anon
    • Export TEAM_BRAIN_SUPABASE_URL / TEAM_BRAIN_SUPABASE_ANON_KEY
    • Edit $PUBLIC_ENV then re-run
    • Use --local for Docker
  Create a project: https://supabase.com → Project Settings → API"
  fi
fi

if [ "$WRITE_ENV" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] would write $PUBLIC_ENV"
  else
    write_public_env "$SUPABASE_URL" "$ANON_KEY" "$JIRA_SITE"
  fi
fi

export TEAM_BRAIN_SUPABASE_URL="$SUPABASE_URL"
export TEAM_BRAIN_SUPABASE_ANON_KEY="$ANON_KEY"
export TEAM_BRAIN_JIRA_SITE="$JIRA_SITE"

# Migrations
if [ "$SKIP_MIGRATIONS" -eq 0 ]; then
  if [ "$USE_LOCAL" -eq 1 ]; then
    ok "Local mode: migrations applied by supabase start"
  elif [ -n "$DB_URL" ]; then
    # Prefer explicit DB URL over linked CLI so --url/--anon/--db-url stay consistent
    apply_migrations_psql "$DB_URL"
  elif supabase_linked; then
    if [ -n "$SUPABASE_URL" ] && ! is_placeholder_url "$SUPABASE_URL"; then
      warn "Using linked supabase CLI project for db push (ensure it matches --url $SUPABASE_URL)"
    fi
    apply_migrations_supabase_push
  elif command -v supabase >/dev/null 2>&1; then
    warn "Supabase CLI found but project not linked."
    info "Option A: supabase login && cd supabase && supabase link --project-ref <ref> && re-run bootstrap"
    info "Option B: pass --db-url 'postgresql://postgres:<DB_PASSWORD>@db.<ref>.supabase.co:5432/postgres'"
    combined=$(write_combined_sql "$SUPABASE_DIR/.bootstrap-migrations.combined.sql")
    info "Option C: open Supabase SQL Editor and run: $combined"
    MIGRATION_BLOCKED=1
    if [ "$DRY_RUN" -eq 1 ]; then
      warn "[dry-run] would stop here until migrations are applied (A/B/C)"
    else
      die "migrations not applied — pick A/B/C then re-run with --skip-migrations (or link/--db-url)"
    fi
  else
    combined=$(write_combined_sql "$SUPABASE_DIR/.bootstrap-migrations.combined.sql")
    cat >&2 <<EOF
error: cannot auto-apply migrations (no linked supabase CLI / --db-url).

Actionable next steps:
  1. Open Supabase Dashboard → SQL Editor
  2. Paste and run the combined file:
       $combined
     (or apply each file in supabase/migrations/ in timestamp order)
  3. Re-run bootstrap with --skip-migrations:
       bash core/scripts/team-brain-bootstrap.sh --team "$TEAM_NAME" --admin "$ADMIN_NAME" \\
         --url "$SUPABASE_URL" --anon "<anon>" --skip-migrations ${JIRA_KEY:+--jira $JIRA_KEY}

Install CLI (optional): https://supabase.com/docs/guides/cli
EOF
    MIGRATION_BLOCKED=1
    if [ "$DRY_RUN" -eq 1 ]; then
      warn "[dry-run] would stop here until migrations are applied"
    else
      exit 1
    fi
  fi
else
  info "Skipping migrations (--skip-migrations or local already applied)"
fi

if [ "$MIGRATION_BLOCKED" -eq 1 ]; then
  warn "Bootstrap incomplete — apply migrations, then re-run (add --skip-migrations after SQL Editor)."
  exit 2
fi

if [ "$SKIP_REGISTER" -eq 1 ]; then
  ok "Skip register — config/migrations done"
  exit 0
fi

info "Registering team via team-brain-api.sh register"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  [dry-run] bash $API register \"$TEAM_NAME\" \"$ADMIN_NAME\""
  invite="DRYRUN_INVITE"
  reg_json='{"invite_code":"DRYRUN_INVITE","team_name":"'"$TEAM_NAME"'"}'
else
  reg_json=$(bash "$API" register "$TEAM_NAME" "$ADMIN_NAME") \
    || die "register failed — confirm migrations applied and URL/anon are correct (HTTP errors often mean RPCs missing)"
  invite=$(jq -r '.invite_code // empty' <<<"$reg_json")
  [ -n "$invite" ] || die "register succeeded but invite_code missing in response: $reg_json"
  ok "Registered team; invite code captured"
fi

if [ -n "$JIRA_KEY" ]; then
  local_title="${JIRA_TITLE:-$JIRA_KEY}"
  local_url="${JIRA_SITE%/}/browse/${JIRA_KEY}"
  info "Attaching initiative $JIRA_KEY"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] bash $API attach $JIRA_KEY \"$local_title\" active \"$local_url\""
  else
    bash "$API" attach "$JIRA_KEY" "$local_title" "active" "$local_url" >/dev/null \
      || warn "attach failed — you can attach later: bash $API attach $JIRA_KEY"
  fi
fi

print_share_bundle "$invite" "$TEAM_NAME" "$SUPABASE_URL" "$ANON_KEY" "$JIRA_KEY" "$JIRA_SITE"

if [ "$DRY_RUN" -eq 0 ]; then
  echo "$reg_json" | jq '{team_name, invite_code, role, display_name, jira_key: $j}' --arg j "${JIRA_KEY:-}"
fi

ok "Bootstrap complete — share the bundle above with joiners"
