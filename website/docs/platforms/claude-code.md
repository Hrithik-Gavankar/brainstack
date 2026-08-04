---
sidebar_position: 2
---

# Claude Code

Brainstack integrates with Claude Code via `CLAUDE.md`.

## Files installed

- `CLAUDE.md` — Context file loaded by Claude Code
- `.engineer-brain/BRAIN.md` — Your living profile
- `.engineer-brain/COMMANDS.md` — Command definitions
- `.engineer-brain/scripts/scan.sh` — Git scanner

## Installation

```bash
bash install.sh claude-code ~/my-workspace
```

## Usage

In any Claude Code session:

```
engineer-brain sync
engineer-brain update
engineer-brain quarterly
engineer-brain reflect
```

Claude Code automatically reads `CLAUDE.md` from your workspace root.
