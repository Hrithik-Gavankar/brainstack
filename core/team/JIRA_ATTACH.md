# Attach flow — Jira → Supabase → markdown

Used by the `team-brain` skill when running `/team-brain attach <JIRA-KEY>`.

## Steps for the agent

1. **Resolve Jira** (preferred: Atlassian MCP `getJiraIssue` with cloudId + key):
   - `key` (e.g. `AAP-81423`)
   - `fields.summary`
   - `fields.status.name`
   - Browse URL: `{jira.site}/browse/{key}` from `.team-brain/team.yaml`

2. If Jira fails, ask the user for title + status; set URL to `{site}/browse/{key}` anyway.

3. **Upsert Supabase + create md:**

```bash
bash core/scripts/team-brain-api.sh attach "$KEY" "$SUMMARY" "$STATUS" "$URL"
```

This writes/updates:
- Supabase `initiatives` row
- Local `initiatives/<KEY>.md` (one file per initiative)

4. **Brief the user** from `TEAM.md` + that md file (goal, decisions, capture log).

5. Remind: personal `/engineer-brain` context stays separate; do not upload `BRAIN.md`.
