---
sidebar_position: 1
---

# Cursor

Engineer Brain integrates with Cursor via its native rules and skills system.

## Files installed

- `.cursor/rules/engineer-brain.mdc` — Always-on personal context
- `.cursor/rules/team-brain.mdc` — Always-on Team Brain agent loop (recall / remember)
- `.cursor/skills/engineer-brain/SKILL.md` — Personal commands + `BRAIN.md`
- `.cursor/skills/team-brain/SKILL.md` — Team / initiative commands
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

/team-brain onboard <invite> Name KEY
/team-brain attach AAP-81423
/team-brain remember / recall
/team-brain breakdown AAP-81423
```

Personal context loads automatically. On initiative work, the Team Brain rule requires **recall before research** and **remember after durable findings**.

Optional MCP: see [mcp/team-brain](https://github.com/Hrithik-Gavankar/engineer-brain/blob/main/mcp/team-brain/README.md).
