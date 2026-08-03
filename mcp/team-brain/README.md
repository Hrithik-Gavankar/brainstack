# Team Brain MCP

Agent-native tools for collaborative initiative memory. Wraps [`team-brain-api.sh`](../../core/scripts/team-brain-api.sh) — no embeddings required (FTS recall by default).

## Tools

| Tool | Purpose |
|------|---------|
| `start` | **Enter sync mode** — load crew memory + background pull |
| `stop` / `wake` / `touch` | Leave / resume / keep awake |
| `sync_status` | `active` \| `sleep` \| `stopped` + embedded `compliance` |
| `compliance` | Soft MCP-first gate (`research_ok`, `agent_action`) |
| `prepare_research` | Recall/list + compliance — call before deep research |
| `broadcast_topic` | Realtime signal topic for a Jira key (#31) |
| `peer_notify` | Latest push notify file (`.team-brain/notify/<KEY>.json`) |
| `pin_show` | Commit-safe repo pin (`project.json`) (#39) |
| `rotate_invite` / `set_role` | Admin-only invite rotate / role change (#40) |
| `whoami` | Current member / team |
| `attach` | Upsert Jira initiative + pull recent memories |
| `remember` | Write memory (`source_ref`; update on overlap; kinds include `learning`) |
| `correct` | Human correction — update `source_ref` + optional learning |
| `history` | List archived revisions + current body for a `source_ref` |
| `restore` | Soft-rollback to revision N (archives current first) |
| `recall` | Search (query) or list recent (no query); includes `compliance` |
| `list_recent` | Sync / list with optional `since` cursor |
| `list_initiatives` | Team initiative index |
| `breakdown` | Recall → draft stories/spikes (`*-breakdown.md`) |
| `metrics` | Local reuse stats, or `metrics("--team")` for crew aggregation (#35) |
| `aggregate` | Crew coverage + reuse (#35); no memory bodies / no BRAIN.md |
| `status` | Client config |

## MCP-first compliance (#36)

**Decision:** stronger prompts + soft session gate (`policy=stronger_prompts`). Not a hard CLI block — offline humans keep working; agents must follow `agent_action`.

| Signal | Meaning |
|--------|---------|
| `research_ok` | Crew context loaded this session (`start` or `recall` / `prepare_research`) |
| `agent_action` | Next required agent step (start / wake / recall / remember) — do not ignore |
| Soft vs hard | CLI commands still run; compliance is agent-visible guidance |

`start` stamps context load. `recall` / `remember` update session stamps. `sync_status` embeds the same `compliance` object. Never requires uploading personal `BRAIN.md`.

## Install

```bash
cd mcp/team-brain
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
# Uses mcp SDK 1.x (FastMCP). mcp 2.x is not supported yet.
```

Requires an onboarded `.team-brain/` (credentials + `team.yaml`) in the workspace you open in the IDE, or set:

```bash
export TEAM_BRAIN_DIR=/path/to/.team-brain
export TEAM_BRAIN_API_SCRIPT=/path/to/brainstack/core/scripts/team-brain-api.sh
```

## Cursor (`mcp.json`)

```json
{
  "mcpServers": {
    "team-brain": {
      "command": "/path/to/brainstack/mcp/team-brain/.venv/bin/python",
      "args": ["/path/to/brainstack/mcp/team-brain/server.py"],
      "env": {
        "TEAM_BRAIN_DIR": "/path/to/your/workspace/.team-brain"
      }
    }
  }
}
```

## Claude Code

Add the same command/args/env under MCP servers in your Claude config.

## Sync mode (product loop)

```text
USER: start team work on KEY
  → start(KEY)     # one entry — load memory + background pull (research_ok)
  → summarize cache, then research

WHILE active
  → touch(KEY) each turn
  → if compliance.agent_action set → follow it
  → prepare_research(KEY[, query]) before deep dives when unsure
  → after long research / ~every 8–10 turns → quiet recall (do not spam every turn)
  → optional once-per-spike CLI: `watch KEY &` (poll or --push); not a wake substitute
  → remember(KEY, body, source_ref) after findings
      identical → no-op | same source_ref + new body → update
  → on human correction: correct(KEY, source_ref, corrected_body[, was_wrong, learning])
      or re-remember same source_ref (never fork a second row)

IDLE ~1h
  → mode=sleep; prompt user → wake(KEY) or start again (watch ≠ wake)
```

Memory bodies: natural-language prefer/avoid guidance — not TODO/NO-TODO dumps.  
Apply migration `20260802000001_team_brain_learning_kind.sql` for the `learning` kind.  
Apply `20260803000001_team_brain_memory_history.sql` for revision archive + `history` / `restore`.  
Apply `20260804000001_team_brain_realtime_broadcast.sql` for peer push signals (`start` / `watch --push`; poll remains fallback).  
Apply `20260805000001_team_brain_roles_and_invites.sql` for `viewer` + admin invite rotate.  
Commit `.team-brain/project.json` for repo pin (#39); `start`/`attach` accept an empty key when pinned.

### Chat examples (Cursor)

```text
I'm starting on AAP-81423 — start Team Brain sync.
I'm starting on AAP-81423 — start Team Brain sync, summarize crew memory, then help me.
Wake Team Brain sync for AAP-81423 and continue.
Stop Team Brain sync for AAP-81423.
Breakdown AAP-81423 from Team Brain memory.
```

Cursor ships always-on rule `platforms/cursor/rules/team-brain.mdc` + skill.

See [docs/team-brain-onboarding.md](../../docs/team-brain-onboarding.md).
