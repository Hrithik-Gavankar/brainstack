---
sidebar_position: 6
---

# Continue.dev

Brainstack integrates with Continue.dev via `.continue/rules.md`.

## Files installed

- `.continue/rules.md` — Continue.dev rules file
- `.engineer-brain/BRAIN.md` — Your living profile
- `.engineer-brain/COMMANDS.md` — Command definitions
- `.engineer-brain/scripts/scan.sh` — Git scanner

## Installation

```bash
bash install.sh continue-dev ~/my-workspace
```

## Usage

In any Continue.dev session:

```
engineer-brain sync
engineer-brain update
```

Continue.dev loads rules from `.continue/rules.md` automatically.
