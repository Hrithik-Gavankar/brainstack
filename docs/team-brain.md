# Team Brain

Shared, opt-in context for crews working the same spike, epic, or initiative.

Tracked originally in [#2](https://github.com/Hrithik-Gavankar/engineer-brain/issues/2).

## Why

Without Team Brain, 2–3 engineers on the same initiative each re-explain the same paths to their AI — duplicate tokens, contradictory decisions, slow handoffs.

With Team Brain, research and decisions land once in an initiative file; others **attach** and build.

## v1 (demo) — local / git sync

```
.team-brain/
├── team.yaml
├── TEAM.md
└── initiatives/
    └── TICKET-123.md
```

| Mechanism | How teammates stay aligned |
|-----------|----------------------------|
| Shared git repo / PR | Commit initiative captures; others pull |
| Shared checkout | Same `.team-brain/` on a team drive (optional) |
| Commands | `attach`, `sync`, `capture`, `breakdown` |

Scaffold:

```bash
bash core/scripts/team-init.sh /path/to/workspace
# or copy examples/team-spike-crew/ → .team-brain/
```

Cursor: install installs the `team-brain` skill beside `engineer-brain`.

## Future — HiveShare adapter

[HiveShare](https://github.com/KB-perByte/hiveshare) already provides collaborative AI memory (MCP `add_hive` / `search_hives`, invites, SSE). Team Brain will **not** reimplement that.

Planned later (`sync.backend: hiveshare` in `team.yaml`):

- Map initiative id → hiveshare id
- `capture` / `sync` optionally read/write hives
- Keep `TEAM.md` + decision tables as human-readable structure

See the HiveShare integration issue on this repo.

## Privacy

- Personal `BRAIN.md` never syncs through Team Brain
- `share_scopes` in `team.yaml` gate what members opt into
- Public hosts must not receive personal brains (same rule as the dashboard)

## Commands

Full reference: [core/team/TEAM_COMMANDS.md](../core/team/TEAM_COMMANDS.md)
