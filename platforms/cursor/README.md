# Brainstack — Cursor IDE Setup

## Installation

### Option 1: Auto-install (recommended)

```bash
cd /path/to/your/workspace
bash /path/to/brainstack/install.sh cursor
```

### Option 2: Manual install

1. Copy the `.cursor` folder structure into your workspace root:

```bash
cp -r platforms/cursor/rules /path/to/your/workspace/.cursor/rules
# includes engineer-brain.mdc + team-brain.mdc (mandatory recall/remember loop)
cp -r platforms/cursor/skills /path/to/your/workspace/.cursor/skills
cp core/scripts/scan.sh /path/to/your/workspace/.cursor/skills/engineer-brain/scripts/
cp core/scripts/doctor.sh /path/to/your/workspace/.cursor/skills/engineer-brain/scripts/
cp core/BRAIN.md /path/to/your/workspace/.cursor/skills/engineer-brain/BRAIN.md
mkdir -p /path/to/your/workspace/.cursor/skills/team-brain/scripts
cp core/scripts/team-init.sh /path/to/your/workspace/.cursor/skills/team-brain/scripts/
cp core/scripts/team-brain-api.sh /path/to/your/workspace/.cursor/skills/team-brain/scripts/
cp core/team/TEAM_COMMANDS.md /path/to/your/workspace/.cursor/skills/team-brain/
```

2. Edit `.cursor/rules/engineer-brain.mdc` — fill in your career details.

3. Edit `.cursor/skills/engineer-brain/scripts/scan.sh` — configure:
   - `WORKSPACE` default / author `AUTHOR_PATTERN`
   - `PERSONAL_REPOS` — side projects to exclude from team standup metrics
   - `GH_OWNERS` — org names used to filter review results (optional)
   - `RELEASE_REPOS` — `owner/name` repos to check for recent releases (optional)

4. Run `/engineer-brain update` in Cursor to auto-populate BRAIN.md.

5. (Optional team demo) `bash .cursor/skills/team-brain/scripts/team-init.sh .` or copy `examples/team-spike-crew/` → `.team-brain/`.

**Note:** Your installed `.cursor/skills/` copy is independent of this
repo. Upstream improvements land here; re-copy skills (or re-run
`install.sh`) when you want them in your live workspace. Keep personal `BRAIN.md`
local — never commit it back to this repository.

## Usage

| Command | What You Get |
|---------|-------------|
| `/engineer-brain sync` | Ready-to-paste standup notes |
| `/engineer-brain update` | Refreshes BRAIN.md with latest data |
| `/engineer-brain quarterly` | Quarterly review content |
| `/engineer-brain reflect` | Pattern analysis & recommendations |
| `/engineer-brain scan [days]` | Raw git scan output |
| `/team-brain onboard` / `register` / `join` | Invite join or create team |
| `/team-brain attach <JIRA-KEY>` | Jira identity + pull memories → cache |
| `/team-brain remember` / `recall` / `sync` | Shared memories (Supabase → cache) |
| `/team-brain breakdown <KEY>` | Draft stories from recalled memories |
| `/team-brain watch` / `metrics` | Near-realtime poll; local reuse stats |
| `/team-brain init` | Local scaffold only |

### Team Brain sync mode (always-on)

`team-brain.mdc` is installed with Cursor rules. **One chat line to start:**

```text
I'm starting on AAP-81423 — start Team Brain sync.
```

```text
I'm starting on AAP-81423 — start Team Brain sync, summarize crew memory, then help me.
```

```text
/team-brain start AAP-81423
```

| Later | Say |
|-------|-----|
| After idle sleep | `Wake Team Brain sync for AAP-81423 and continue.` |
| Done | `Stop Team Brain sync for AAP-81423.` |

While active the agent should summarize cache, `touch` each turn, and `remember` findings (`source_ref`).

Beginner path: [docs/team-brain-onboarding.md](../../docs/team-brain-onboarding.md).

### Team Brain MCP (optional)

Agent tools without shelling out manually — see [`mcp/team-brain/README.md`](../../mcp/team-brain/README.md).

```bash
cd /path/to/brainstack/mcp/team-brain
python3 -m venv .venv && source .venv/bin/activate && pip install -e .
```

Wire Cursor — add under `mcpServers` in `~/.cursor/mcp.json`:

```json
"team-brain": {
  "command": "<brainstack>/mcp/team-brain/.venv/bin/python",
  "args": ["<brainstack>/mcp/team-brain/server.py"],
  "env": {
    "TEAM_BRAIN_DIR": "<workspace>/.team-brain"
  }
}
```

Reload MCP servers in Cursor after editing.

## How It Works

- **`engineer-brain.mdc`** — loaded on every AI interaction (always-on personal context)
- **`team-brain.mdc`** — always-on collaborative memory loop (recall / remember)
- **`engineer-brain` skill** — personal commands + `BRAIN.md`
- **`team-brain` skill** — team/initiative commands + `.team-brain/`
- **`scan.sh`** — multi-repo git scanner (personal metrics)
- **Optional MCP** — `mcp/team-brain/` tools for the same verbs without shelling out
- Scopes: [docs/scopes.md](../../docs/scopes.md)
