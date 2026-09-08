---
sidebar_position: 1
---

# Cursor

Brainstack integrates with Cursor via its native rules and skills system.

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
/team-brain start YOU_JIRA_TICKET_HERE
/team-brain remember / recall
/team-brain breakdown YOU_JIRA_TICKET_HERE
```

**Start crew work (natural language):**

```text
I'm starting on YOU_JIRA_TICKET_HERE — start Team Brain sync.
I'm starting on YOU_JIRA_TICKET_HERE — start Team Brain sync, summarize crew memory, then help me.
Wake Team Brain sync for YOU_JIRA_TICKET_HERE and continue.
Stop Team Brain sync for YOU_JIRA_TICKET_HERE.
```

Personal context loads automatically. Team Brain sync mode loads crew memory first, then the agent remembers durable findings.

Optional MCP: see [mcp/team-brain](https://github.com/Hrithik-Gavankar/brainstack/blob/main/mcp/team-brain/README.md).
