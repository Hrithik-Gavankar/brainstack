---
sidebar_position: 3
---

# Brain scopes

**Brain** is the product umbrella. Two skills = two scopes:

| Skill | For | Living docs |
|-------|-----|-------------|
| `engineer-brain` | You — standups, growth, personal patterns | `BRAIN.md` |
| `team-brain` | Crew — collaborative AI memory on a Jira key | Supabase + `cache/<KEY>.json` (+ optional md) |

Commands (`sync`, `attach`, `remember`, …) are **verbs under a skill**, not separate skills.

## Team Brain (opt-in)

1. Admin: create Supabase project → fill local config → migrations → `register` → share invite + URL + anon  
2. Teammate: put crew URL/anon locally → `onboard <invite> "Name" <JIRA-KEY>`  
3. Agents: **recall before research**, **remember after findings**, **correct on human pushback**, **history/restore when needed**  
4. Optional: MCP tools in `mcp/team-brain/`

Full guides on GitHub:

- [scopes.md](https://github.com/Hrithik-Gavankar/engineer-brain/blob/main/docs/scopes.md)
- [team-brain-onboarding.md](https://github.com/Hrithik-Gavankar/engineer-brain/blob/main/docs/team-brain-onboarding.md)
- [team-brain.md](https://github.com/Hrithik-Gavankar/engineer-brain/blob/main/docs/team-brain.md)
- [architecture.md](https://github.com/Hrithik-Gavankar/engineer-brain/blob/main/docs/architecture.md)
