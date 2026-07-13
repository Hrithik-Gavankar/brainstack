---
sidebar_position: 1
---

# Cursor

Engineer Brain integrates with Cursor via its native rules and skills system.

## Files installed

- `.cursor/rules/engineer-brain.mdc` — Always-on context rule
- `.cursor/skills/engineer-brain/SKILL.md` — Command definitions
- `.cursor/skills/engineer-brain/BRAIN.md` — Your living profile
- `.cursor/skills/engineer-brain/scripts/scan.sh` — Git scanner

## Installation

```bash
bash install.sh cursor ~/my-workspace
```

## Usage

In any Cursor chat or Composer session:

```
/engineer-brain sync
/engineer-brain update
/engineer-brain quarterly
/engineer-brain reflect
```

The context rule loads automatically on every interaction, giving Cursor deep awareness of your engineering profile.
