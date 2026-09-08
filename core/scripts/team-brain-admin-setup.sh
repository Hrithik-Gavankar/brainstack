#!/usr/bin/env bash
# Team Brain — one-shot ADMIN setup
#
# Creates the crew (register → admin role). Colleagues use team-brain-member-setup.sh.
#
# DEMO DEFAULTS (Brainstack Day 0 workshop only — change for your crew):
#   Epic: KAN-4 · Crew: Workshop Crew
#   Override: --jira YOUR-EPIC --team "Your Crew" --jira-site https://your-org.atlassian.net
#   Or env: TEAM_BRAIN_DEMO_JIRA_KEY, TEAM_BRAIN_DEMO_TEAM_NAME, TEAM_BRAIN_DEMO_JIRA_SITE
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP="$SCRIPT_DIR/team-brain-bootstrap.sh"
API="$SCRIPT_DIR/team-brain-api.sh"

# shellcheck source=team-brain-secret-utils.sh
source "$SCRIPT_DIR/team-brain-secret-utils.sh"

# --- demo defaults (override for production crews) ---
DEFAULT_JIRA_KEY="${TEAM_BRAIN_DEMO_JIRA_KEY:-KAN-4}"
DEFAULT_JIRA_TITLE="${TEAM_BRAIN_DEMO_JIRA_TITLE:-Brainstack context layer — workshop spike}"
DEFAULT_JIRA_SITE="${TEAM_BRAIN_DEMO_JIRA_SITE:-https://brainstack-org.atlassian.net}"
DEFAULT_TEAM_NAME="${TEAM_BRAIN_DEMO_TEAM_NAME:-Workshop Crew}"

ADMIN_NAME="${TEAM_BRAIN_ADMIN_NAME:-}"
TEAM_NAME="$DEFAULT_TEAM_NAME"
JIRA_KEY="$DEFAULT_JIRA_KEY"
JIRA_TITLE="$DEFAULT_JIRA_TITLE"
JIRA_SITE="$DEFAULT_JIRA_SITE"
SKIP_START=0
DRY_RUN=0
BOOTSTRAP_ARGS=()

die() { echo "error: $*" >&2; exit 1; }
info() { echo "→ $*" >&2; }
ok() { echo "✓ $*" >&2; }
warn() { echo "⚠ $*" >&2; }

print_demo_notice() {
  cat >&2 <<EOF

──────────────────────────────────────────────────────────────────
 Demo defaults (workshop): epic ${JIRA_KEY} · crew "${TEAM_NAME}"
 For your own crew, pass --jira YOUR-EPIC --team "Your Crew"
 (and --jira-site if not brainstack-org). See docs/workshop-brainstack-day0.md
──────────────────────────────────────────────────────────────────

EOF
}

usage() {
  cat <<EOF
Team Brain — one-shot ADMIN setup

  bash core/scripts/team-brain-admin-setup.sh --admin "Your Name" [options]

Required:
  --admin, -a "Name"        Admin display name (creates crew + admin role)

Demo defaults (override for your epic):
  --jira KEY                Default: $DEFAULT_JIRA_KEY (demo only)
  --team NAME               Default: $DEFAULT_TEAM_NAME (demo only)
  --jira-site URL           Default: $DEFAULT_JIRA_SITE

Bootstrap options (passed through):
  --url URL  --anon KEY  --db-url URL  --local  --skip-migrations  --dry-run

Colleagues then run:
  bash core/scripts/team-brain-member-setup.sh --invite <CODE> --name "Bob" --role member

See: docs/workshop-brainstack-day0.md
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --admin|-a) ADMIN_NAME="${2:-}"; shift 2 ;;
    --team) TEAM_NAME="${2:-}"; shift 2 ;;
    --jira) JIRA_KEY="${2:-}"; shift 2 ;;
    --jira-site) JIRA_SITE="${2:-}"; shift 2 ;;
    --jira-title) JIRA_TITLE="${2:-}"; shift 2 ;;
    --skip-start) SKIP_START=1; shift ;;
    --dry-run) DRY_RUN=1; BOOTSTRAP_ARGS+=(--dry-run); shift ;;
    --help|-h) usage; exit 0 ;;
    --url|--anon|--db-url)
      [ $# -ge 2 ] || die "$1 requires a value"
      BOOTSTRAP_ARGS+=("$1" "$2"); shift 2 ;;
    --local|--skip-migrations)
      BOOTSTRAP_ARGS+=("$1"); shift ;;
    *)
      die "unknown option: $1 (colleagues use team-brain-member-setup.sh)"
      ;;
  esac
done

[ -n "$ADMIN_NAME" ] || die "--admin \"Your Name\" is required (see --help)"
[ -f "$BOOTSTRAP" ] || die "bootstrap script not found: $BOOTSTRAP"

JIRA_KEY=$(echo "$JIRA_KEY" | tr '[:lower:]' '[:upper:]')
print_demo_notice

cd "$REPO_ROOT"
export TEAM_BRAIN_DIR="${TEAM_BRAIN_DIR:-$REPO_ROOT/.team-brain}"

bash "$BOOTSTRAP" \
  --team "$TEAM_NAME" \
  --admin "$ADMIN_NAME" \
  --jira "$JIRA_KEY" \
  --jira-title "$JIRA_TITLE" \
  --jira-site "$JIRA_SITE" \
  --write-env \
  "${BOOTSTRAP_ARGS[@]}"

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
echo " Role:     admin"
echo " Epic:     $JIRA_KEY — $JIRA_TITLE"
if [ -n "$invite" ]; then
  echo " Invite:   $invite_mask"
  echo " Full invite + anon: $bundle_path (gitignored — share via DM only)"
else
  echo " Invite:   (run: bash core/scripts/team-brain-api.sh whoami)"
  echo " Full bundle: $bundle_path (if bootstrap wrote it)"
fi
echo ""
echo " Colleague (member) — use invite from $bundle_path or credentials.json:"
echo "   bash core/scripts/team-brain-member-setup.sh --invite <INVITE> --name \"Bob\" --role member"
echo ""
echo " Do NOT paste invite/anon into git, PRs, or public Slack."
echo " (Demo used KAN-4 / Workshop Crew — pass --jira / --team for your epic.)"
echo "═══════════════════════════════════════════════════════════════"
tb_print_no_paste_warning
