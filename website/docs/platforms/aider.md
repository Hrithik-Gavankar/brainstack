---
sidebar_position: 5
---

# Aider

Brainstack integrates with Aider via `CONVENTIONS.md`.

## Files installed

- `CONVENTIONS.md` — Aider conventions file
- `.engineer-brain/BRAIN.md` — Your living profile
- `.engineer-brain/COMMANDS.md` — Command definitions
- `.engineer-brain/scripts/scan.sh` — Git scanner

## Installation

```bash
bash install.sh aider ~/my-workspace
```

## Configuration

Add to your `.aider.conf.yml`:

```yaml
read:
  - CONVENTIONS.md
  - .engineer-brain/BRAIN.md
  - .engineer-brain/COMMANDS.md
```

## Usage

In any Aider session, use natural language:

```
engineer-brain sync
engineer-brain update
```
