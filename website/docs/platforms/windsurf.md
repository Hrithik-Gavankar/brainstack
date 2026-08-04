---
sidebar_position: 4
---

# Windsurf

Brainstack integrates with Windsurf via `.windsurfrules`.

## Files installed

- `.windsurfrules` — Windsurf rules file
- `.engineer-brain/BRAIN.md` — Your living profile
- `.engineer-brain/COMMANDS.md` — Command definitions
- `.engineer-brain/scripts/scan.sh` — Git scanner

## Installation

```bash
bash install.sh windsurf ~/my-workspace
```

## Usage

In any Windsurf session:

```
/engineer-brain sync
/engineer-brain update
```

Windsurf loads `.windsurfrules` automatically from the workspace root.
