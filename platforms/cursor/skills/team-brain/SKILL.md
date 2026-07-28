---
name: team-brain
description: >-
  Team / initiative scope of Brain — collaborative AI memory for spikes, epics,
  and crews. Register a team, attach Jira initiatives, remember findings to
  Supabase, recall into the session. Invoke for "team brain", "team-brain",
  "register team", "join team", "attach initiative", "remember for the team",
  "recall", "team sync", "initiative breakdown", or shared spike context
  (not personal standups).
argument-hint: >-
  <command> — onboard | register | join | whoami | init | attach | remember |
  recall | capture | sync | watch | breakdown | status | detach
tools: Read, Write, Shell, Glob, Grep
---

# Team Brain — Collaborative AI Memory

Part of the **Brain** product umbrella:

| Skill | Scope | Living docs |
|-------|--------|-------------|
| `engineer-brain` | Personal identity, standups, growth | `BRAIN.md` |
| `team-brain` | Team + initiative **memories** | Supabase SoT + `cache/<KEY>.json` |

Personal `BRAIN.md` is never uploaded to Supabase.

**Plan:** `docs/team-brain-memory.md`  
**MCP (agent tools):** `mcp/team-brain/` — prefer MCP tools when the `team-brain` server is connected; otherwise use the CLI below.

## Agent defaults (P3)

Follow these without waiting for the user to ask:

1. **On attach / starting work on a Jira key** → always `recall` / `list_recent` (or CLI `sync`) and summarize memories into the session brief.
2. **After durable research or a decision** → `remember` with a stable `source_ref` (e.g. `AAP-81423#tox-paths`). Dedup makes retries safe.
3. **Before planning stories** → run `breakdown` (it recalls first). Do not invent an epic breakdown without memories.
4. Prefer **cache** `/.team-brain/cache/<KEY>.json` over re-reading chat history.
5. Never copy personal career/growth notes from `BRAIN.md` into team memory.

## Sync model

| Layer | Role |
|-------|------|
| **Jira** | Initiative identity |
| **Supabase** | Shared memories (SoT) |
| **Local cache** | Agent-facing snapshot |
| **Markdown export** | Optional human/git mirror |

Client (CLI fallback):

```bash
bash "${SKILL_DIR}/scripts/team-brain-api.sh" <command> ...
# or
bash "<repo>/core/scripts/team-brain-api.sh" <command> ...
```

MCP setup: `mcp/team-brain/README.md`.

---

## Commands

### `onboard <invite-code> "Name" [JIRA-KEY]`

```bash
bash …/team-brain-api.sh onboard 9F7AC910 "Ada Engineer" AAP-81423
```

### `register` / `join` / `whoami` / `init`

Membership + local scaffold. Prefer `register` / `onboard` for sync demos.

### `attach <JIRA-KEY>`

1. Fetch Jira via Atlassian MCP when available.
2. MCP `attach` **or** `team-brain-api.sh attach …` (pulls recent memories into cache).
3. **Always** load `cache/<KEY>.json` and summarize for the session.
4. Never mix personal `BRAIN.md` into team memory.

### `remember <JIRA-KEY> [research|decision|note]`

1. Summarize the durable finding; confirm with the user if ambiguous.
2. MCP `remember` **or** CLI with `--source-ref` when the same crunch might repeat.
3. `capture` remains a compat alias.

### `recall <JIRA-KEY> [query…]`

1. MCP `recall` / `list_recent` **or** CLI.
2. With query: FTS (default) or vector if embed provider configured.
3. Without query: recent list / sync.

### `breakdown <JIRA-KEY> [query]`

1. MCP `breakdown` **or** `team-brain-api.sh breakdown <KEY> [query]`.
2. Always recalls team memories first, then writes `initiatives/<KEY>-breakdown.md` (stories from decisions, spikes from research, AC drafts, gaps).
3. Summarize the draft for the user; refine with the crew before filing Jira.
4. Check `metrics <KEY>` for recall/reuse signal.

### `sync` / `watch` / `metrics` / `status` / `detach`

- `sync` — refresh cache  
- `watch` — side-terminal near-realtime poll  
- `metrics` — local reuse stats (gitignored `metrics.json`)  
- `status` / `detach` — config / clear session focus  

---

## Hard rules

- Never commit / push without explicit permission
- Never commit `credentials.json` or service-role keys
- Never publish personal `BRAIN.md` to Supabase
- Prefer concise memories over chat dumps
- Cache/JSON is agent SoT; markdown is export

---

## Related

- Plan: `docs/team-brain-memory.md`
- MCP: `mcp/team-brain/README.md`
- Engineer skill: `/engineer-brain`
- Client: `core/scripts/team-brain-api.sh`
