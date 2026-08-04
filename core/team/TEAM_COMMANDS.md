# Team Brain — Command Reference

Team Brain is the **team / initiative scope** of Brainstack — collaborative AI memory on a Jira key.  
Personal identity stays in engineer-brain (`BRAIN.md`).

Plan: [docs/team-brain-memory.md](../../docs/team-brain-memory.md)  
Onboarding: [docs/team-brain-onboarding.md](../../docs/team-brain-onboarding.md)

## Layout

```
.team-brain/
├── team.yaml              # sync backend, jira site, initiative index
├── credentials.json       # api_key — gitignored, never commit
├── TEAM.md                # one per team
├── cache/
│   └── AAP-81423.json     # agent SoT (written on start/sync/remember)
├── sync/
│   └── AAP-81423.json     # sync mode session (active | sleep | stopped)
└── initiatives/
    └── AAP-81423.md       # optional human/git export
```

## Sync model

| Backend | Behavior |
|---------|----------|
| `supabase` (default) | Memories in Supabase; local `cache/<KEY>.json` for agents; md export optional |
| `local` | File/git only — no multi-engineer sync |

**Sync mode:** engineer runs `start <KEY>` once → background merge-safe pull → idle sleep → `wake` / `stop`.

Jira = initiative **identity**. Memories = Supabase (+ cache).

## Client

**New teammate:**

```bash
bash core/scripts/team-brain-api.sh onboard INVITECODE "Bob" AAP-81423
```

**Admin (once) — preferred:**

```bash
bash core/scripts/team-brain-api.sh bootstrap \
  --team "Crew" --admin "Alice" \
  --url "https://….supabase.co" --anon "eyJ…" \
  --db-url "postgresql://postgres:…@db….supabase.co:5432/postgres" \
  --jira AAP-81423 --write-env
# prints share bundle (invite + URL + anon + joiner checklist)
```

**Admin (once) — manual:**

```bash
bash core/scripts/team-brain-api.sh register "Crew" "Alice"   # share invite_code
```

**Start of ticket (one manual step):**

In Cursor / any agent chat:

```text
I'm starting on AAP-81423 — start Team Brain sync.
```

```text
/team-brain start AAP-81423
```

CLI:

```bash
bash core/scripts/team-brain-api.sh start AAP-81423
bash core/scripts/team-brain-api.sh sync-status AAP-81423   # includes compliance
bash core/scripts/team-brain-api.sh compliance AAP-81423    # soft MCP-first gate
```

| Chat example | Effect |
|--------------|--------|
| `I'm starting on AAP-81423 — start Team Brain sync.` | Enter sync mode + load crew memory |
| `Wake Team Brain sync for AAP-81423 and continue.` | Resume after idle sleep |
| `Stop Team Brain sync for AAP-81423.` | Leave sync mode |
| `Breakdown AAP-81423 from Team Brain memory.` | Draft stories from recall |

**Day to day (while sync active):**

```bash
bash core/scripts/team-brain-api.sh remember AAP-81423 research --source-ref "AAP-81423#cli" "Finding…"
bash core/scripts/team-brain-api.sh recall AAP-81423 "decision environment"
bash core/scripts/team-brain-api.sh touch AAP-81423    # keep awake
bash core/scripts/team-brain-api.sh stop AAP-81423     # done
bash core/scripts/team-brain-api.sh wake AAP-81423     # after sleep

# Human correction (update same source_ref + optional learning)
bash core/scripts/team-brain-api.sh correct AAP-81423 --source-ref "AAP-81423#cli" \
  --was "Claimed schema was in tox-ansible" \
  --learning "Was wrong: schema in tox-ansible. Prefer: packages/ansible-language-server." \
  "EE schema path lives in packages/ansible-language-server."
```

`capture` / `sync` remain aliases. Project config: `supabase/project.public.env` (placeholders in git — fill with your crew’s project).

## Commands

| Command | Purpose |
|---------|---------|
| `start` | **Enter sync mode** — load memory + background pull |
| `stop` / `wake` / `touch` | Leave / resume / keep awake |
| `sync-status` | Session state: active \| sleep \| stopped (+ `compliance`, realtime daemon) |
| `compliance` | Soft MCP-first gate (`research_ok`, `agent_action`) — agents follow; CLI not blocked |
| `pin` | Commit-safe `project.json` show/set (#39) — never secrets |
| `rotate-invite` | Admin-only invite rotate (#40) |
| `set-role` | Admin-only `admin`\|`member`\|`viewer` (#40) |
| `watch` | Near-realtime poll; `--push` adds Broadcast listener (poll always fallback) |
| `broadcast-topic` | Show signal Broadcast topic for a Jira key (#31) |
| `bootstrap` | **Admin one-shot** — migrate + register + share bundle |
| `onboard` | Join + optional attach + recall |
| `register` / `join` / `whoami` | Membership |
| `attach` | Upsert Jira initiative + pull recent memories |
| `remember` | Write memory (dedupe identical; **update** same `source_ref`; kinds include `learning`) |
| `correct` | Correction loop: update `source_ref` + optional `learning` at `REF/learning` |
| `history` | List archived revisions + current body for a `source_ref` |
| `restore` | Soft-rollback to revision N (archives current first) |
| `recall` | List recent, or vector/FTS search |
| `reembed` | Backfill embeddings for an initiative |
| `watch` | Foreground poll only (prefer `start`) |
| `breakdown` | Recall → draft stories/spikes markdown |
| `metrics` | Reuse stats (recall / remember / breakdown) |
| `sync` | Pull → cache (+ md export) |
| `list` / `status` | Initiatives / config |

## Merge rules

| Case | Result |
|------|--------|
| New `source_ref` / new body | insert |
| Identical body (hash) | no-op (`deduped`) |
| Same `source_ref`, changed body | **update** that row (`updated`) — no second copy |

Human corrections use the same merge path (`correct` or re-`remember`).  
Optional `learning` kind records “was wrong → prefer …” at `source_ref/learning`.  
On `source_ref` update, the prior body is **archived** (`archived_revision`); use `history` / `restore` for soft rollback.  
Memory bodies: natural prefer/avoid prose — not TODO/NO-TODO dumps.

```bash
bash core/scripts/team-brain-api.sh history AAP-81423 --source-ref "AAP-81423#cli"
bash core/scripts/team-brain-api.sh restore AAP-81423 --source-ref "AAP-81423#cli" --revision 1
```

Apply migrations `…_sync_mode.sql`, `…_learning_kind.sql`, and `…_memory_history.sql` on the Supabase project.

## Agent loop (Cursor)

Always-on rule `platforms/cursor/rules/team-brain.mdc`:

1. User/`start` enters sync mode  
2. Summarize cache before research  
3. `remember` after findings; `touch` each turn  
4. If `sleep` → prompt user to `wake`

## Cursor skill / MCP

- Skill: `/team-brain` — `platforms/cursor/skills/team-brain/SKILL.md`
- MCP: `mcp/team-brain/` — `start` / `stop` / `wake` / `touch` / `sync_status` / …
