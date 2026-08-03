#!/usr/bin/env bash
# Engineer Brain — PR Watch
# Scans GitHub repos for open PRs and generates a prioritized digest
# Usage: bash watch.sh [workspace_path] [--repos owner/repo,...] [--stale-days N] [--loop N]
#
# Requires: gh CLI (authenticated), python3

set -uo pipefail

WORKSPACE="${1:-$(pwd)}"
[ "${WORKSPACE}" = "--repos" ] || [ "${WORKSPACE}" = "--stale-days" ] || [ "${WORKSPACE}" = "--loop" ] && WORKSPACE="$(pwd)"
shift 2>/dev/null || true

REPOS=""
STALE_DAYS=14
LOOP_MINUTES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repos)      REPOS="$2"; shift 2 ;;
    --stale-days) STALE_DAYS="$2"; shift 2 ;;
    --loop)       LOOP_MINUTES="$2"; shift 2 ;;
    *)            shift ;;
  esac
done

if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI not found."
  echo ""
  echo "Install from https://cli.github.com/ and run 'gh auth login'"
  exit 1
fi

if ! gh auth status &>/dev/null 2>&1; then
  echo "ERROR: gh CLI is not authenticated."
  echo ""
  echo "Run 'gh auth login' to authenticate."
  exit 1
fi

GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")

# Resolve team memberships so team review requests count as "needs your review"
GH_TEAMS=""
if [ -n "$GH_USER" ]; then
  GH_TEAMS=$(gh api user/memberships/orgs --jq '.[].organization.login' 2>/dev/null | while read -r org; do
    gh api "orgs/$org/teams" --jq '.[].slug' 2>/dev/null | while read -r team; do
      # Check if user is a member of this team
      if gh api "orgs/$org/teams/$team/members" --jq '.[].login' 2>/dev/null | grep -qx "$GH_USER"; then
        echo "$org/$team"
      fi
    done
  done 2>/dev/null || echo "")
fi

discover_repos() {
  for dir in "$WORKSPACE"/*/; do
    [ -d "$dir/.git" ] || [ -f "$dir/.git" ] || continue
    local remote
    remote=$(git -C "$dir" remote get-url upstream 2>/dev/null \
          || git -C "$dir" remote get-url origin 2>/dev/null \
          || echo "")
    local slug=""
    slug=$(echo "$remote" | sed -n 's|.*github\.com[:/]\([^/]*/[^/]*\)\.git$|\1|p')
    if [ -z "$slug" ]; then
      slug=$(echo "$remote" | sed -n 's|.*github\.com[:/]\([^/]*/[^/]*\)$|\1|p')
    fi
    if [ -n "$slug" ]; then
      echo "$slug"
    fi
  done | sort -u
}

if [ -n "$REPOS" ]; then
  REPO_LIST=$(echo "$REPOS" | tr ',' '\n')
else
  REPO_LIST=$(discover_repos)
fi

if [ -z "$REPO_LIST" ]; then
  echo "ERROR: No GitHub repos found."
  echo ""
  echo "Either specify repos with --repos owner/repo,owner/repo2"
  echo "or run from a workspace directory containing git repos with GitHub remotes."
  exit 1
fi

REPO_COUNT=$(echo "$REPO_LIST" | wc -l | tr -d ' ')

run_watch() {
  echo "=== PR WATCH ==="
  echo "User: ${GH_USER:-unknown}"
  echo "Repos: ${REPO_COUNT}"
  echo "Stale threshold: ${STALE_DAYS} days"
  echo "Scan time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  ALL_PRS=""
  FAILED_REPOS=""

  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    pr_json=$(gh pr list --repo "$repo" --state open --limit 100 \
      --json number,title,author,createdAt,updatedAt,isDraft,reviewRequests,url,additions,deletions,headRefName,reviewDecision,labels \
      2>/dev/null) || {
      FAILED_REPOS="${FAILED_REPOS}${repo}\n"
      continue
    }

    if [ "$pr_json" = "[]" ] || [ -z "$pr_json" ]; then
      continue
    fi

    tagged=$(echo "$pr_json" | python3 -c "
import json, sys
prs = json.load(sys.stdin)
repo = sys.argv[1]
for pr in prs:
    pr['repo'] = repo
json.dump(prs, sys.stdout)
" "$repo" 2>/dev/null || echo "[]")

    if [ "$tagged" != "[]" ]; then
      ALL_PRS="${ALL_PRS}${tagged}"
    fi
  done <<< "$REPO_LIST"

  if [ -n "$FAILED_REPOS" ]; then
    echo "## SKIPPED REPOS (no gh access)"
    echo ""
    echo -e "$FAILED_REPOS" | while IFS= read -r r; do
      [ -n "$r" ] && echo "- $r"
    done
    echo ""
  fi

  if [ -z "$ALL_PRS" ]; then
    echo "No open PRs found across ${REPO_COUNT} repo(s)."
    echo ""
    echo "=== END ==="
    return
  fi

  echo "$ALL_PRS" | python3 -c "
import json, sys, datetime

gh_user = sys.argv[1]
stale_days = int(sys.argv[2])
gh_teams = sys.argv[3].strip().split('\n') if sys.argv[3].strip() else []
now = datetime.datetime.now(datetime.timezone.utc)

raw = sys.stdin.read()
try:
    all_prs = json.loads('[' + raw.replace('][', '],[') + ']')
    prs = []
    for item in all_prs:
        if isinstance(item, list):
            prs.extend(item)
        else:
            prs.append(item)
except json.JSONDecodeError as e:
    print(f'ERROR: Failed to parse PR data: {e}', file=sys.stderr)
    prs = []

if not prs:
    print('No open PRs found.')
    sys.exit(0)

def parse_date(s):
    try:
        return datetime.datetime.fromisoformat(s.replace('Z', '+00:00'))
    except Exception:
        return now

def pr_size(pr):
    total = pr.get('additions', 0) + pr.get('deletions', 0)
    if total <= 50: return 'S'
    if total <= 200: return 'M'
    if total <= 500: return 'L'
    return 'XL'

def pr_age_days(pr):
    return (now - parse_date(pr.get('createdAt', ''))).days

def pr_idle_days(pr):
    return (now - parse_date(pr.get('updatedAt', ''))).days

def is_bot_author(author):
    if author.startswith('app/'):
        return True
    bot_suffixes = ['[bot]', '-bot']
    for suffix in bot_suffixes:
        if author.endswith(suffix):
            return True
    return False

needs_review = []
your_prs = []
contributor_prs = []
bot_prs = []
drafts = []
stale = []

for pr in prs:
    age = pr_age_days(pr)
    idle = pr_idle_days(pr)
    is_draft = pr.get('isDraft', False)
    author = (pr.get('author', {}) or {}).get('login', '')
    review_requests = pr.get('reviewRequests', []) or []

    requested_logins = []
    requested_teams = []
    for rr in review_requests:
        if isinstance(rr, dict):
            typename = rr.get('__typename', '')
            if typename == 'Team':
                slug = rr.get('slug', '')
                if slug:
                    requested_teams.append(slug)
            else:
                login = rr.get('login', '')
                if login:
                    requested_logins.append(login)

    is_requested = False
    if gh_user:
        if gh_user in requested_logins:
            is_requested = True
        else:
            for team_slug in requested_teams:
                if team_slug in gh_teams:
                    is_requested = True
                    break

    is_own = gh_user and author == gh_user
    is_bot = is_bot_author(author)

    pr['_age'] = age
    pr['_idle'] = idle
    pr['_size'] = pr_size(pr)
    pr['_is_own'] = is_own
    pr['_is_requested'] = is_requested
    pr['_is_bot'] = is_bot

    if is_own and idle >= stale_days:
        stale.append(pr)
    elif is_requested and not is_draft:
        needs_review.append(pr)
    elif is_own:
        your_prs.append(pr)
    elif is_draft:
        drafts.append(pr)
    elif is_bot:
        bot_prs.append(pr)
    elif idle >= stale_days:
        stale.append(pr)
    else:
        contributor_prs.append(pr)

size_rank = {'S': 0, 'M': 1, 'L': 2, 'XL': 3}
needs_review.sort(key=lambda p: (-p['_age'], size_rank.get(p['_size'], 9)))
your_prs.sort(key=lambda p: -p['_age'])
contributor_prs.sort(key=lambda p: -p['_age'])
stale.sort(key=lambda p: -p['_idle'])

def fmt_pr(pr):
    repo = pr.get('repo', '')
    num = pr.get('number', 0)
    title = pr.get('title', '')
    author = (pr.get('author', {}) or {}).get('login', '')
    url = pr.get('url', '')
    size = pr['_size']
    age = pr['_age']
    idle = pr['_idle']
    adds = pr.get('additions', 0)
    dels = pr.get('deletions', 0)
    draft = ' [DRAFT]' if pr.get('isDraft', False) else ''
    own = ' (yours)' if pr.get('_is_own', False) else ''
    requested = ' [review requested]' if pr.get('_is_requested', False) else ''
    labels = pr.get('labels', []) or []
    label_str = ''
    if labels:
        label_names = [l.get('name', '') for l in labels if isinstance(l, dict)]
        if label_names:
            label_str = ' {' + ', '.join(label_names) + '}'

    line = f'  {repo}#{num} -- {title}{draft}{own}{requested}{label_str}'
    detail = f'    {url}'
    detail2 = f'    @{author} | {age}d old | idle {idle}d | {size} (+{adds}/-{dels})'
    return line + '\n' + detail + '\n' + detail2

total = len(prs)
repo_count = len(set(p['repo'] for p in prs))
print(f'Found {total} open PR(s) across {repo_count} repo(s).')
print()

if needs_review:
    print(f'## NEEDS YOUR REVIEW ({len(needs_review)})')
    print()
    for pr in needs_review:
        print(fmt_pr(pr))
        print()

if your_prs:
    print(f'## YOUR OPEN PRS ({len(your_prs)})')
    print()
    for pr in your_prs:
        print(fmt_pr(pr))
        print()

if contributor_prs:
    print(f'## CONTRIBUTOR PRS ({len(contributor_prs)})')
    print()
    for pr in contributor_prs:
        print(fmt_pr(pr))
        print()

if stale:
    print(f'## STALE (>{stale_days}d idle) ({len(stale)})')
    print()
    for pr in stale:
        print(fmt_pr(pr))
        print()

print('## SUMMARY')
print()
print(f'- Needs your review: {len(needs_review)}')
print(f'- Your open PRs: {len(your_prs)}')
print(f'- Contributor PRs: {len(contributor_prs)}')
print(f'- Stale (>{stale_days}d idle): {len(stale)}')
print(f'- Total open: {total} ({len(bot_prs)} bot + {len(drafts)} draft excluded)')
" "$GH_USER" "$STALE_DAYS" "$GH_TEAMS" 2>&1

  echo ""
  echo "=== END ==="
}

if [ "$LOOP_MINUTES" -gt 0 ] 2>/dev/null; then
  while true; do
    clear 2>/dev/null || true
    run_watch
    echo ""
    echo "Next check in ${LOOP_MINUTES} minutes... (Ctrl+C to stop)"
    sleep $((LOOP_MINUTES * 60))
  done
else
  run_watch
fi
