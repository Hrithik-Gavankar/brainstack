# Attach flow — Jira → Supabase → cache (+ optional md)

Used by the `team-brain` skill when running `/team-brain attach <JIRA-KEY>`.

## Steps for the agent

1. **Resolve Jira** (preferred: Atlassian MCP `getJiraIssue` with cloudId + key):
   - `key` (e.g. `AAP-81423`)
   - `fields.summary`
   - `fields.status.name`
   - Browse URL: `{jira.site}/browse/{key}` from `.team-brain/team.yaml`

2. If Jira fails, ask the user for title + status; set URL to `{site}/browse/{key}` anyway.

3. **Upsert Supabase + refresh local cache:**

```bash
bash core/scripts/team-brain-api.sh attach "$KEY" "$SUMMARY" "$STATUS" "$URL"
```

This writes/updates:

- Supabase `initiatives` row
- Local `.team-brain/cache/<KEY>.json` (recent memories for agents)
- Optional export `initiatives/<KEY>.md` (human/git mirror)

4. **Brief the user** from cache (and `TEAM.md` / md if present): goal, decisions, recent memories.

5. **Agent loop** — before further research on this key, `recall`; after durable findings, `remember` with `source_ref`. See `platforms/cursor/rules/team-brain.mdc`.

6. Remind: personal `/engineer-brain` context stays separate; do not upload `BRAIN.md`.
