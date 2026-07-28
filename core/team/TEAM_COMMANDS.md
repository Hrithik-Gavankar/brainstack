# Team Brain — Command Reference

Team Brain is the **team / initiative scope** of the Brain product — collaborative AI memory on a Jira key.  
Personal identity stays in engineer-brain (`BRAIN.md`).

Plan: [docs/team-brain-memory.md](../../docs/team-brain-memory.md)

## Layout

```
.team-brain/
├── team.yaml              # sync backend, jira site, initiative index
├── credentials.json       # api_key — gitignored, never commit
├── TEAM.md                # one per team
├── cache/
│   └── AAP-81423.json     # agent SoT (written on sync/remember)
└── initiatives/
    └── AAP-81423.md       # optional human/git export
```

## Sync model

| Backend | Behavior |
|---------|----------|
| `supabase` (default) | Memories in Supabase; local `cache/<KEY>.json` for agents; md export optional |
| `local` | File/git only — no multi-engineer sync |

Jira = initiative **identity**. Memories = Supabase (+ cache).

## Client

**New teammate:**

```bash
bash core/scripts/team-brain-api.sh onboard INVITECODE "Bob" AAP-81423
```

**Admin (once):**

```bash
bash core/scripts/team-brain-api.sh register "Crew" "Alice"   # share invite_code
```

**Day to day:**

```bash
bash core/scripts/team-brain-api.sh remember AAP-81423 research "Finding…"
bash core/scripts/team-brain-api.sh recall AAP-81423
bash core/scripts/team-brain-api.sh recall AAP-81423 "decision environment"
```

`capture` / `sync` remain aliases. Public config: `supabase/project.public.env`.

## Commands

| Command | Purpose |
|---------|---------|
| `onboard` | Join + optional attach + recall |
| `register` / `join` / `whoami` | Membership |
| `attach` | Upsert Jira initiative + pull recent memories |
| `remember` | Write memory (`--source-ref` for dedup; embeds if provider set) |
| `recall` | List recent, or vector/FTS search |
| `reembed` | Backfill embeddings for an initiative |
| `watch` | Near-realtime poll |
| `breakdown` | Recall → draft stories/spikes markdown |
| `metrics` | Reuse stats (recall / remember / breakdown) |
| `sync` | Pull → cache (+ md export) |
| `list` / `status` | Initiatives / config |

## Agent loop (Cursor)

Always-on rule `platforms/cursor/rules/team-brain.mdc`:

1. `recall` before research on a Jira key  
2. `remember` after durable findings (`source_ref`)

## Cursor skill / MCP

- Skill: `/team-brain` — `platforms/cursor/skills/team-brain/SKILL.md`
- MCP: `mcp/team-brain/` — same verbs for agents without shelling out
- Beginner guide: [docs/team-brain-onboarding.md](../../docs/team-brain-onboarding.md)
