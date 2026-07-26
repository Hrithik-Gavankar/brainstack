# Team Brain

Shared, opt-in context for crews working the same spike, epic, or initiative.

Part of the **Brain** product alongside [engineer-brain](scopes.md) (personal scope).
Tracked originally in [#2](https://github.com/Hrithik-Gavankar/engineer-brain/issues/2).

## Why

Without Team Brain, 2–3 engineers on the same initiative each re-explain the same paths to their AI — duplicate tokens, contradictory decisions, slow handoffs.

With Team Brain, research and decisions land once in an initiative file; others **attach** and build.

## How teammates stay in sync

```
.team-brain/
├── team.yaml
├── TEAM.md
└── initiatives/
    └── TICKET-123.md
```

| Step | What happens |
|------|----------------|
| 1 | Crew shares the same `.team-brain/` in git (or a shared checkout) |
| 2 | Engineer A runs `/team-brain capture` → updates `initiatives/…md` → commits / opens PR |
| 3 | Engineers B and C `git pull` → `/team-brain attach <id>` loads the new context |

No separate sync server is required for this product version — **git is the sync fabric**.

Scaffold:

```bash
bash core/scripts/team-init.sh /path/to/workspace
# or copy examples/team-spike-crew/ → .team-brain/
```

Cursor: install installs the `team-brain` skill beside `engineer-brain`.

## Privacy

- Personal `BRAIN.md` never syncs through Team Brain
- `share_scopes` in `team.yaml` gate what members opt into
- Public hosts must not receive personal brains (same rule as the dashboard)

## Commands

Full reference: [core/team/TEAM_COMMANDS.md](../core/team/TEAM_COMMANDS.md)
