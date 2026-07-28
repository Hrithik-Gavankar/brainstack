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

## Agent habits

1. **Start of work on a key** → `attach` or `list_recent` / `recall` (no query)
2. **After durable research** → `remember` with a stable `source_ref`
3. **Before breakdown** → `recall` with a short query or list recent

See [docs/team-brain-memory.md](../../docs/team-brain-memory.md).
