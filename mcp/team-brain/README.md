# Team Brain MCP

Agent-native tools for collaborative initiative memory. Wraps [`team-brain-api.sh`](../../core/scripts/team-brain-api.sh) — no embeddings required (FTS recall by default).

## Tools

| Tool | Purpose |
|------|---------|
| `start` | **Enter sync mode** — load crew memory + background pull |
| `stop` / `wake` / `touch` | Leave / resume / keep awake |
| `sync_status` | `active` \| `sleep` \| `stopped` |
| `whoami` | Current member / team |
| `attach` | Upsert Jira initiative + pull recent memories |
| `remember` | Write memory (`source_ref`; update on overlap; kinds include `learning`) |
| `correct` | Human correction — update `source_ref` + optional learning |
| `recall` | Search (query) or list recent (no query) |
| `list_recent` | Sync / list with optional `since` cursor |
| `list_initiatives` | Team initiative index |
| `breakdown` | Recall → draft stories/spikes (`*-breakdown.md`) |
| `metrics` | Local reuse stats (recall / remember / breakdown) |
| `status` | Client config |

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
export TEAM_BRAIN_API_SCRIPT=/path/to/engineer-brain/core/scripts/team-brain-api.sh
```

## Cursor (`mcp.json`)

```json
{
  "mcpServers": {
    "team-brain": {
      "command": "/path/to/engineer-brain/mcp/team-brain/.venv/bin/python",
      "args": ["/path/to/engineer-brain/mcp/team-brain/server.py"],
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
  → start(KEY)     # one entry — load memory + background pull
  → summarize cache, then research

WHILE active
  → touch(KEY) each turn
  → remember(KEY, body, source_ref) after findings
      identical → no-op | same source_ref + new body → update
  → on human correction: correct(KEY, source_ref, corrected_body[, was_wrong, learning])
      or re-remember same source_ref (never fork a second row)

IDLE ~1h
  → mode=sleep; prompt user → wake(KEY) or start again
```

Memory bodies: natural-language prefer/avoid guidance — not TODO/NO-TODO dumps.  
Apply migration `20260802000001_team_brain_learning_kind.sql` for the `learning` kind.

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
