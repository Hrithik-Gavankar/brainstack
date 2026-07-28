---
name: team-brain
description: >-
  Team / initiative scope of Brain — shared context for spikes, epics, and
  crews. Register a team, attach Jira initiatives, capture findings to
  Supabase, and mirror into per-initiative markdown. Invoke for "team brain",
  "team-brain", "register team", "join team", "attach initiative", "capture
  for the team", "team sync", "initiative breakdown", or shared spike context
  (not personal standups).
argument-hint: >-
  <command> — onboard | register | join | whoami | init | attach | sync |
  capture | breakdown | status | detach
tools: Read, Write, Shell, Glob, Grep
---

# Team Brain — Shared Initiative Context

Part of the **Brain** product umbrella:

| Skill | Scope | Living docs |
|-------|--------|-------------|
| `engineer-brain` | Personal identity, standups, growth | `BRAIN.md` |
| `team-brain` | Team + initiatives | `TEAM.md` + **one `initiatives/<JIRA-KEY>.md` per initiative** |

Personal `BRAIN.md` is never uploaded to Supabase.

## Sync model (hybrid)

| Layer | Role |
|-------|------|
| **Jira** | Initiative identity (key, title, status, URL) |
| **Supabase** | Team membership + shared captures (multi-engineer sync) |
| **Local `.team-brain/`** | `TEAM.md` + per-initiative `.md` mirrors for demo/git export |

Prefer Supabase when `sync.backend: supabase` and credentials exist.
Fall back to local files only when backend is `local` or API is unset.

Client script (from engineer-brain repo or skill scripts):

```bash
bash "${SKILL_DIR}/scripts/team-brain-api.sh" <command> ...
# or
bash "<repo>/core/scripts/team-brain-api.sh" <command> ...
```

Setup: see `supabase/README.md`.

---

## Commands

### `onboard <invite-code> "Name" [JIRA-KEY]` (preferred for new joiners)

One command — uses committed `supabase/project.public.env` (no dashboard, no copying keys).

```bash
bash …/team-brain-api.sh onboard 9F7AC910 "Ada Engineer" AAP-81423
```

Seeds `.team-brain/`, joins the team, attaches + syncs the initiative.

### `register <team-name> [display-name]`

Create a team in Supabase (admin, once). Uses `project.public.env` or `team.yaml`.

```bash
bash …/team-brain-api.sh register "DevTools Spike Crew" "Hrithik"
```

Saves `.team-brain/credentials.json` (gitignored). Share only the **invite_code**.

### `join <invite-code> [display-name]`

Join an existing team; saves credentials for this engineer.

### `whoami`

Show current member + team via Supabase.

### `init`

Scaffold local layout only (no cloud):

```bash
bash "${SKILL_DIR}/scripts/team-init.sh" "$HOME/path/to/workspace"
```

Still useful for `TEAM.md` templates; for sync demos prefer `register`.

### `attach <JIRA-KEY>`

1. **Jira (required for hybrid):** fetch issue via Atlassian MCP / tools  
   (`getJiraIssue` or equivalent) — collect `key`, `summary`, `status`, browse URL.  
   If Jira is unavailable, ask the user for title/status and continue with a warning.
2. **Supabase:**  
   `team-brain-api.sh attach <KEY> "<summary>" "<status>" "<jira_url>"`  
   Creates/updates the initiative row and ensures `initiatives/<KEY>.md`.
3. **Local brief:** read `TEAM.md` + that initiative md; summarize goal, decisions, latest captures.
4. Never mix personal `BRAIN.md` into the initiative file.

### `capture <JIRA-KEY> [research|decision|note]`

1. Confirm body with the user (or summarize from the conversation if they ask).
2. If Supabase configured:  
   `team-brain-api.sh capture <KEY> <kind> <body>`  
   (auto-mirrors Capture log into `initiatives/<KEY>.md`).
3. Else append to the local initiative markdown only.
4. Never copy personal career/growth notes from `BRAIN.md`.

### `sync <JIRA-KEY>`

1. If Supabase: `team-brain-api.sh sync <KEY>` (pull + mirror md).
2. Present team status: new captures, open questions, suggested next captures.
3. This is **not** a personal standup (`/engineer-brain sync`).

### `breakdown <JIRA-KEY>`

Draft stories/spikes + AC from initiative md + latest synced captures. Flag gaps.

### `status`

Run `team-brain-api.sh status` when available; also summarize `team.yaml` (backend, initiatives, jira site).

### `detach`

Clear active initiative focus from the session; keep team credentials.

---

## Hard rules

- Never commit / push without explicit permission
- Never commit `credentials.json` or service-role keys
- Never publish personal `BRAIN.md` to Supabase
- Prefer concise captures over chat dumps
- One markdown file **per initiative** (`initiatives/<JIRA-KEY>.md`)

---

## Related

- Engineer skill: `/engineer-brain`
- Supabase setup: `supabase/README.md`
- Commands detail: `core/team/TEAM_COMMANDS.md`
- Client: `core/scripts/team-brain-api.sh`
