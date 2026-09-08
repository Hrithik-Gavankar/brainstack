#!/usr/bin/env bash
# Shared helpers — mask secrets in terminal output; write full share bundle locally only.
# Source from team-brain-bootstrap.sh / team-brain-admin-setup.sh / team-brain-api.sh

tb_mask_secret() {
  local s="${1:-}"
  local n=${#s}
  if [ -z "$s" ]; then
    echo "(empty)"
    return 0
  fi
  if [ "$n" -le 8 ]; then
    echo "(redacted, ${n} chars)"
    return 0
  fi
  printf '%s…%s (%s chars)\n' "${s:0:4}" "${s:n-4:4}" "$n"
}

tb_share_bundle_path() {
  local team_dir="${TEAM_BRAIN_DIR:-${TB_SHARE_BUNDLE_DIR:-}}"
  if [ -z "$team_dir" ]; then
    team_dir="$(pwd)/.team-brain"
  fi
  printf '%s/share-bundle.txt' "$team_dir"
}

tb_write_share_bundle_file() {
  local path content
  path=$(tb_share_bundle_path)
  content="$1"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" >"$path"
  chmod 600 "$path" 2>/dev/null || true
  echo "$path"
}

tb_print_no_paste_warning() {
  cat <<'EOF'

⚠  SECRETS — DO NOT paste this terminal output into git commits, PRs, Slack threads,
   or screen recordings. Full values are in .team-brain/share-bundle.txt (gitignored, chmod 600).
   Share URL + anon + invite with joiners via DM only.

EOF
}
