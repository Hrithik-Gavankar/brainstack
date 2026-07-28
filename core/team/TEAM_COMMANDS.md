# Team Brain — Command Reference

Team Brain is the **team / initiative scope** of the Brain product.
Personal identity stays in engineer-brain (`BRAIN.md`).

## Layout

```
.team-brain/
├── team.yaml              # sync backend, jira site, initiative index
├── credentials.json       # api_key — gitignored, never commit
├── TEAM.md                # one per team
└── initiatives/
    └── AAP-81423.md       # one markdown file PER initiative (Jira key)
```

## Sync model

| Backend | Behavior |
|---------|----------|
| `supabase` (default for demos) | Register/join team; captures sync via Supabase RPCs; mirror into initiative `.md` |
| `local` | File/git only — no multi-machine sync unless you share the folder |

Jira provides initiative **identity** only (key, title, status, URL). Captures live in Supabase.

## Client

**New teammate (invite only):**

```bash
bash core/scripts/team-brain-api.sh onboard INVITECODE "Bob" AAP-81423
```

**Admin (once):**

```bash
bash core/scripts/team-brain-api.sh register "Crew" "Alice"   # share invite_code
```

**Day to day:**

```bash
bash core/scripts/team-brain-api.sh capture AAP-81423 research "Finding…"
bash core/scripts/team-brain-api.sh sync AAP-81423
```

Public project config: `supabase/project.public.env`. See `supabase/README.md`.

## Commands

### `register` / `join` / `whoami`

Cloud team membership. Required before Supabase attach/capture.

### `init`

Local scaffold only (`team-init.sh`).

### `attach <JIRA-KEY>`

Fetch Jira → upsert Supabase initiative → ensure `initiatives/<KEY>.md` → session brief.

### `capture` / `sync`

Write/read captures via Supabase; refresh the initiative markdown Capture log.

### `breakdown` / `status` / `detach`

Story drafting, config summary, clear session focus.

## Hard rules

- Never commit or push without explicit user permission
- Never sync or publish personal `BRAIN.md`
- Never commit `credentials.json`
