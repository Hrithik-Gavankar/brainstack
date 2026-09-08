#!/usr/bin/env bash
# Team Brain — one-shot ADMIN setup
#
# Fill ONE file, then run (no flags required):
#   cp supabase/admin.setup.env.example supabase/admin.setup.env
#   bash core/scripts/team-brain-admin-setup.sh
#
# After success (auto-written — gitignored unless noted):
#   supabase/project.public.env     runtime URL/anon for team-brain-api.sh
#   .team-brain/credentials.json  your api_key + invite
#   .team-brain/share-bundle.txt    DM to members
#   .team-brain/project.json        commit-safe pin
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP="$SCRIPT_DIR/team-brain-bootstrap.sh"
API="$SCRIPT_DIR/team-brain-api.sh"
ADMIN_SETUP_ENV="${TEAM_BRAIN_ADMIN_SETUP_ENV:-$REPO_ROOT/supabase/admin.setup.env}"
ADMIN_SETUP_EXAMPLE="$REPO_ROOT/supabase/admin.setup.env.example"
PUBLIC_ENV="${TEAM_BRAIN_PUBLIC_ENV:-$REPO_ROOT/supabase/project.public.env}"

# shellcheck source=team-brain-secret-utils.sh
source "$SCRIPT_DIR/team-brain-secret-utils.sh"

ADMIN_NAME=""
TEAM_NAME=""
JIRA_KEY=""
JIRA_TITLE=""
JIRA_SITE=""
SUPABASE_URL=""
ANON_KEY=""
DB_URL=""
USE_LOCAL=0
SKIP_MIGRATIONS=0
SKIP_START=0
DRY_RUN=0
CONFIG_PATH="$ADMIN_SETUP_ENV"
BOOTSTRAP_ARGS=()

die() { echo "error: $*" >&2; exit 1; }
info() { echo "→ $*" >&2; }
ok() { echo "✓ $*" >&2; }
warn() { echo "⚠ $*" >&2; }

strip_env_value() {
  local v="${1:-}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

is_truthy() {
  case "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
  esac
  return 1
}

is_placeholder_url() {
  case "${1:-}" in
    ""|*YOUR_PROJECT*|*YOUR_REF*|*your-project*|*example.supabase*) return 0 ;;
  esac
  return 1
}

is_placeholder_anon() {
  case "${1:-}" in
    ""|your-anon-key|YOUR_ANON*|replace-me*|changeme*) return 0 ;;
  esac
  return 1
}

is_placeholder_name() {
  case "${1:-}" in
    ""|"Your Name"|YOUR_NAME|CHANGEME|changeme) return 0 ;;
  esac
  return 1
}

is_placeholder_team() {
  case "${1:-}" in
    ""|"Your Crew"|YOUR_CREW|CHANGEME|changeme) return 0 ;;
  esac
  return 1
}

is_placeholder_jira() {
  case "${1:-}" in
    ""|YOUR-EPIC|YOUR_EPIC|JIRA-KEY|YOU_JIRA_TICKET_HERE) return 0 ;;
  esac
  return 1
}

set_var_from_env_line() {
  local key="$1" raw="$2"
  local val
  val=$(strip_env_value "$raw")
  case "$key" in
    TEAM_BRAIN_ADMIN_NAME) ADMIN_NAME="$val" ;;
    TEAM_BRAIN_TEAM_NAME) TEAM_NAME="$val" ;;
    TEAM_BRAIN_JIRA_KEY) JIRA_KEY="$val" ;;
    TEAM_BRAIN_JIRA_TITLE) JIRA_TITLE="$val" ;;
    TEAM_BRAIN_JIRA_SITE) JIRA_SITE="$val" ;;
    TEAM_BRAIN_SUPABASE_URL) SUPABASE_URL="$val" ;;
    TEAM_BRAIN_SUPABASE_ANON_KEY) ANON_KEY="$val" ;;
    TEAM_BRAIN_DB_URL) DB_URL="$val" ;;
    TEAM_BRAIN_USE_LOCAL)
      if is_truthy "$val"; then USE_LOCAL=1; fi
      ;;
    TEAM_BRAIN_SKIP_MIGRATIONS)
      if is_truthy "$val"; then SKIP_MIGRATIONS=1; fi
      ;;
    TEAM_BRAIN_SKIP_START)
      if is_truthy "$val"; then SKIP_START=1; fi
      ;;
  esac
}

load_admin_setup_env() {
  local file="$1" line key raw
  [ -f "$file" ] || return 1
  [ -r "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    case "$line" in
      *=*)
        key="${line%%=*}"
        raw="${line#*=}"
        set_var_from_env_line "$key" "$raw"
        ;;
    esac
  done <"$file"
  return 0
}

usage() {
  cat <<EOF
Team Brain — one-shot ADMIN setup

  cp supabase/admin.setup.env.example supabase/admin.setup.env
  # edit all values in admin.setup.env
  bash core/scripts/team-brain-admin-setup.sh

Options (override admin.setup.env):
  --config PATH           default: supabase/admin.setup.env
  --init                  copy example → admin.setup.env and exit
  --dry-run               print plan only
  -h, --help              this help

CLI overrides (optional — prefer editing admin.setup.env):
  --admin, --team, --jira, --jira-site, --jira-title
  --url, --anon, --db-url, --local, --skip-migrations, --skip-start

After success, share .team-brain/share-bundle.txt with members (DM only).
See: docs/team-brain-onboarding.md
EOF
}

print_setup_guide() {
  cat >&2 <<EOF

Team Brain admin onboarding — one file:

  1. cp supabase/admin.setup.env.example supabase/admin.setup.env
  2. Edit every value in supabase/admin.setup.env
  3. bash core/scripts/team-brain-admin-setup.sh

Quick init:
  bash core/scripts/team-brain-admin-setup.sh --init

EOF
}

validate_admin_config() {
  local missing=()

  is_placeholder_name "$ADMIN_NAME" && missing+=("TEAM_BRAIN_ADMIN_NAME")
  is_placeholder_team "$TEAM_NAME" && missing+=("TEAM_BRAIN_TEAM_NAME")
  is_placeholder_jira "$JIRA_KEY" && missing+=("TEAM_BRAIN_JIRA_KEY")
  [ -z "$JIRA_TITLE" ] && missing+=("TEAM_BRAIN_JIRA_TITLE")
  [ -z "$JIRA_SITE" ] && missing+=("TEAM_BRAIN_JIRA_SITE")

  if [ "$USE_LOCAL" -eq 0 ]; then
    is_placeholder_url "$SUPABASE_URL" && missing+=("TEAM_BRAIN_SUPABASE_URL")
    is_placeholder_anon "$ANON_KEY" && missing+=("TEAM_BRAIN_SUPABASE_ANON_KEY")
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    warn "Still placeholders or empty in $CONFIG_PATH:"
    local field
    for field in "${missing[@]}"; do
      echo "  • $field" >&2
    done
    print_setup_guide
    die "Fill admin.setup.env, then re-run."
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG_PATH="${2:-}"; shift 2 ;;
    --init)
      cp "$ADMIN_SETUP_EXAMPLE" "$ADMIN_SETUP_ENV"
      chmod 600 "$ADMIN_SETUP_ENV" 2>/dev/null || true
      ok "Created $ADMIN_SETUP_ENV"
      echo "Edit every value, then run: bash core/scripts/team-brain-admin-setup.sh" >&2
      exit 0
      ;;
    --admin|-a) ADMIN_NAME="${2:-}"; shift 2 ;;
    --team) TEAM_NAME="${2:-}"; shift 2 ;;
    --jira) JIRA_KEY="${2:-}"; shift 2 ;;
    --jira-site) JIRA_SITE="${2:-}"; shift 2 ;;
    --jira-title) JIRA_TITLE="${2:-}"; shift 2 ;;
    --url) SUPABASE_URL="${2:-}"; shift 2 ;;
    --anon) ANON_KEY="${2:-}"; shift 2 ;;
    --db-url) DB_URL="${2:-}"; shift 2 ;;
    --local) USE_LOCAL=1; shift ;;
    --skip-migrations) SKIP_MIGRATIONS=1; shift ;;
    --skip-start) SKIP_START=1; shift ;;
    --dry-run) DRY_RUN=1; BOOTSTRAP_ARGS+=(--dry-run); shift ;;
    --help-credentials) print_setup_guide; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *)
      die "unknown option: $1 (try --help)"
      ;;
  esac
done

[ -f "$BOOTSTRAP" ] || die "bootstrap script not found: $BOOTSTRAP"

if [ ! -f "$CONFIG_PATH" ]; then
  print_setup_guide
  die "Missing $CONFIG_PATH — run: bash core/scripts/team-brain-admin-setup.sh --init"
fi

load_admin_setup_env "$CONFIG_PATH" || die "could not load $CONFIG_PATH (missing or not readable)"
ok "Loaded admin config from $CONFIG_PATH"

JIRA_KEY=$(echo "$JIRA_KEY" | tr '[:lower:]' '[:upper:]')

if [ "$DRY_RUN" -eq 0 ]; then
  validate_admin_config
else
  info "Dry run — skipping validation"
fi

cd "$REPO_ROOT"
export TEAM_BRAIN_DIR="${TEAM_BRAIN_DIR:-$REPO_ROOT/.team-brain}"

BOOTSTRAP_ARGS+=(--team "$TEAM_NAME" --admin "$ADMIN_NAME" --jira "$JIRA_KEY")
BOOTSTRAP_ARGS+=(--jira-title "$JIRA_TITLE" --jira-site "$JIRA_SITE" --write-env)

if [ "$USE_LOCAL" -eq 1 ]; then
  BOOTSTRAP_ARGS+=(--local)
elif [ -n "$SUPABASE_URL" ] && [ -n "$ANON_KEY" ]; then
  BOOTSTRAP_ARGS+=(--url "$SUPABASE_URL" --anon "$ANON_KEY")
fi

[ -n "$DB_URL" ] && BOOTSTRAP_ARGS+=(--db-url "$DB_URL")
[ "$SKIP_MIGRATIONS" -eq 1 ] && BOOTSTRAP_ARGS+=(--skip-migrations)

set +e
bash "$BOOTSTRAP" ${BOOTSTRAP_ARGS[@]+"${BOOTSTRAP_ARGS[@]}"}
bootstrap_rc=$?
set -e

if [ "$bootstrap_rc" -eq 2 ]; then
  echo "" >&2
  echo "═══════════════════════════════════════════════════════════════" >&2
  echo " One-time pause — apply migrations in Supabase SQL Editor" >&2
  echo "═══════════════════════════════════════════════════════════════" >&2
  echo " 1. Supabase Dashboard → SQL Editor" >&2
  echo " 2. Paste and run:" >&2
  echo "    $REPO_ROOT/supabase/.bootstrap-migrations.combined.sql" >&2
  echo " 3. Re-run the SAME command (no config changes):" >&2
  echo "    bash core/scripts/team-brain-admin-setup.sh" >&2
  echo "═══════════════════════════════════════════════════════════════" >&2
  exit 2
fi

[ "$bootstrap_rc" -eq 0 ] || die "bootstrap failed (exit $bootstrap_rc)"

if [ "$DRY_RUN" -eq 1 ]; then
  info "Dry run — would run pin set, doctor, start $JIRA_KEY"
  exit 0
fi

info "Setting commit-safe pin"
bash "$API" pin set --jira "$JIRA_KEY" --team-name "$TEAM_NAME" | jq '{pinned, default_jira_key, team_name, path}' 2>/dev/null \
  || bash "$API" pin set --jira "$JIRA_KEY" --team-name "$TEAM_NAME"

info "Doctor check"
bash "$API" doctor || warn "doctor reported issues — fix migrations before going live"

if [ "$SKIP_START" -eq 0 ]; then
  info "Starting sync mode ($JIRA_KEY)"
  bash "$API" start "$JIRA_KEY"
  bash "$API" sync-status "$JIRA_KEY" | jq '{jira_key, mode}' 2>/dev/null \
    || bash "$API" sync-status "$JIRA_KEY"
fi

invite=""
invite=$(bash "$API" whoami 2>/dev/null | jq -r '.invite_code // empty' || true)

invite_mask=""
if [ -n "$invite" ]; then
  invite_mask=$(tb_mask_secret "$invite")
fi
bundle_path=$(tb_share_bundle_path)

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " Admin setup complete"
echo "═══════════════════════════════════════════════════════════════"
echo " Config:   $CONFIG_PATH"
echo " Role:     admin"
echo " Epic:     $JIRA_KEY — $JIRA_TITLE"
if [ -n "$invite" ]; then
  echo " Invite:   $invite_mask"
  echo " Full invite + anon: $bundle_path (gitignored — share via DM only)"
else
  echo " Invite:   (run: bash core/scripts/team-brain-api.sh whoami)"
fi
echo ""
echo " Auto-written:"
echo "   $PUBLIC_ENV"
echo "   $TEAM_BRAIN_DIR/credentials.json"
echo "   $bundle_path  ← DM to members"
echo "   $TEAM_BRAIN_DIR/project.json  (commit-safe pin)"
echo ""
echo " Members:"
echo "   bash core/scripts/team-brain-member-setup.sh --invite <INVITE> --name \"Bob\" --role member"
echo "═══════════════════════════════════════════════════════════════"
tb_print_no_paste_warning
