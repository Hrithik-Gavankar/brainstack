# Team Brain MCP

Agent-native tools for collaborative initiative memory. Wraps [`team-brain-api.sh`](../../core/scripts/team-brain-api.sh) — no embeddings required (FTS recall by default).

## Tools

| Tool | Purpose |
|------|---------|
| `whoami` | Current member / team |
| `attach` | Upsert Jira initiative + pull recent memories |
| `remember` | Write memory (`source_ref` for dedup) |
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

## Mandatory agent loop

```text
BEFORE research on a Jira key  →  recall (sync)  →  summarize crew memory
AFTER each durable finding     →  remember + source_ref  →  (do not wait for user)
```

1. Start / focus on a key → `attach` or `recall` (no query), plus `recall` with topic words  
2. After each finding → `remember` with `source_ref` like `AAP-81423#cli-schema`  
3. Before planning → `breakdown`

Cursor also ships always-on rule `platforms/cursor/rules/team-brain.mdc` and skill defaults.

See [docs/team-brain-memory.md](../../docs/team-brain-memory.md).
