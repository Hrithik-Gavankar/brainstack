#!/usr/bin/env bash
# Engineer Brain — Jira Integration
# Fetches assigned issues from Jira Cloud (API v3)
# Usage: bash jira.sh [filter] [days]
#   filter: all (default) | active | backlog | review | sprint | done [days] | weekly | quarterly
#
# Required env vars: JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN

set -uo pipefail

FILTER="${1:-all}"
DAYS="${2:-7}"

if [ -z "${JIRA_URL:-}" ] || [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ]; then
  echo "ERROR: Missing env vars. Set JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN."
  echo ""
  echo "Setup:"
  echo "  1. Go to https://id.atlassian.com/manage-profile/security/api-tokens"
  echo "  2. Create a new API token"
  echo "  3. Add to your shell profile:"
  echo "     export JIRA_URL=\"https://your-org.atlassian.net\""
  echo "     export JIRA_EMAIL=\"you@company.com\""
  echo "     export JIRA_API_TOKEN=\"your-token\""
  exit 1
fi

case "$FILTER" in
  active)
    JQL="assignee=currentUser() AND statusCategory = \"In Progress\" ORDER BY updated DESC"
    ;;
  backlog)
    JQL="assignee=currentUser() AND status = Backlog ORDER BY updated DESC"
    ;;
  review)
    JQL="assignee=currentUser() AND status = Review ORDER BY updated DESC"
    ;;
  sprint)
    JQL="assignee=currentUser() AND sprint in openSprints() AND statusCategory != Done ORDER BY rank ASC"
    ;;
  done)
    SINCE=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%d 2>/dev/null)
    JQL="assignee=currentUser() AND statusCategory = Done AND resolutiondate >= \"$SINCE\" ORDER BY resolutiondate DESC"
    ;;
  weekly)
    SINCE=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d 2>/dev/null)
    JQL="assignee=currentUser() AND statusCategory = Done AND resolutiondate >= \"$SINCE\" ORDER BY resolutiondate DESC"
    ;;
  quarterly)
    QUARTER_MONTH=$(( ( $(date +%-m) - 1 ) / 3 * 3 + 1 ))
    QUARTER_START=$(printf "%s-%02d-01" "$(date +%Y)" "$QUARTER_MONTH")
    JQL="assignee=currentUser() AND statusCategory = Done AND resolutiondate >= \"$QUARTER_START\" ORDER BY resolutiondate DESC"
    ;;
  all)
    JQL="assignee=currentUser() AND statusCategory != Done ORDER BY updated DESC"
    ;;
  *)
    echo "Unknown filter: $FILTER"
    echo "Usage: jira.sh [all|active|backlog|review|sprint|done|weekly|quarterly] [days]"
    exit 1
    ;;
esac

echo "=== JIRA TASKS ==="
echo "User: $JIRA_EMAIL"
echo "Filter: $FILTER"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

JSON_BODY=$(python3 -c "
import json, sys
jql = sys.argv[1]
print(json.dumps({
    'jql': jql,
    'maxResults': 50,
    'fields': ['summary','status','priority','issuetype','project','updated','duedate','resolutiondate','resolution','sprint']
}))
" "$JQL")

RESPONSE=$(curl -s -w "\n%{http_code}" -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -X POST "$JIRA_URL/rest/api/3/search/jql" \
  -H "Content-Type: application/json" \
  -d "$JSON_BODY" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: Jira API returned HTTP $HTTP_CODE"
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
  exit 1
fi

echo "$BODY" | python3 -c "
import json, sys

data = json.load(sys.stdin)
issues = data.get('issues', [])

if not issues:
    print('No issues found.')
    sys.exit(0)

print(f'Found {len(issues)} issue(s):')
print()

by_status = {}
for issue in issues:
    f = issue['fields']
    status = f['status']['name']
    by_status.setdefault(status, []).append(issue)

jira_url = '${JIRA_URL}'

for status, items in by_status.items():
    print(f'### {status} ({len(items)})')
    print()
    for issue in items:
        f = issue['fields']
        key = issue['key']
        summary = f['summary']
        priority = f['priority']['name']
        itype = f['issuetype']['name']
        project = f['project']['key']
        updated = f['updated'][:10]
        due = f.get('duedate') or '—'
        resolved = (f.get('resolutiondate') or '')[:10]
        resolution = (f.get('resolution') or {})
        resolution_name = resolution.get('name', '') if isinstance(resolution, dict) else ''
        url = jira_url + '/browse/' + key
        print(f'  [{key}]({url}) — {summary}')
        detail = f'    Type: {itype} | Priority: {priority} | Project: {project}'
        print(detail)
        detail2 = f'    Updated: {updated} | Due: {due}'
        if resolved:
            detail2 += f' | Resolved: {resolved}'
        if resolution_name:
            detail2 += f' ({resolution_name})'
        print(detail2)
        print()
" 2>&1

echo "=== END ==="
