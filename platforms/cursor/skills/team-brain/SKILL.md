---
name: team-brain
description: >-
  Team / initiative scope of Brain — shared context for spikes, epics, and
  crews so teammates stop re-researching the same work. Invoke when you say
  "team brain", "team-brain", "attach initiative", "capture for the team",
  "team sync", "initiative breakdown", "shared spike context", or ask about
  team-level context (not personal standups or quarterly reviews).
argument-hint: <command> — init | attach | sync | capture | breakdown | status | detach
tools: Read, Write, Shell, Glob, Grep
---

# Team Brain — Shared Initiative Context

Part of the **Brain** product umbrella:

| Skill | Scope | Living docs |
|-------|--------|-------------|
| `engineer-brain` | Personal identity, standups, growth | `BRAIN.md` |
| `team-brain` | Team norms + initiative context | `TEAM.md` + `initiatives/*.md` |

Personal `BRAIN.md` is never replaced or uploaded by Team Brain.

**Sync (now):** local / git-backed files under `.team-brain/` — teammates share via the same checkout or PRs.

---

## Commands

Parse the user request and run one of:

### `init`

Scaffold Team Brain:

```bash
bash "${SKILL_DIR}/scripts/team-init.sh" "$HOME/path/to/workspace"
```

If `team-init.sh` is not beside this skill, use:

```bash
bash "<repo>/core/scripts/team-init.sh" "$HOME/path/to/workspace"
```

Then help the user fill `TEAM.md` and `team.yaml`.

### `attach <initiative-id>`

1. Find `.team-brain/team.yaml` (or ask for path)
2. Resolve initiative → markdown file
3. Read `TEAM.md` + initiative file
4. Present a short brief: goal, decisions, open questions, latest findings
5. Keep personal engineer-brain context separate

### `sync [initiative-id]`

Compose a **team** status (not a personal standup):

1. Read active initiative file(s)
2. Optionally scan configured repos for recent shared activity
3. Output what was learned/decided, open questions, next captures
### `capture <initiative-id>`

Append user-approved findings/decisions to the initiative file (date + author).
Never copy personal growth notes from `BRAIN.md`.

### `breakdown <initiative-id>`

Draft stories/spikes + AC from the initiative file. Call out context gaps.

### `status`

Summarize team.yaml: members, initiatives, sync backend (`local` / git).

### `detach`

Stop treating an initiative as the active session focus.

---

## Hard rules

- Never commit / push without explicit permission
- Never publish personal `BRAIN.md`
- Prefer concise captures over chat dumps
- Team Brain is part of **this product** alongside engineer-brain — keep the demo story there

---

## Related

- Engineer (personal) skill: `/engineer-brain`
- Templates: `core/team/`
- Commands detail: `core/team/TEAM_COMMANDS.md`
