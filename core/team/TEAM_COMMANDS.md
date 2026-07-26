# Team Brain — Command Reference

Team Brain is the **team / initiative scope** of the Brain product.
Personal identity stays in engineer-brain (`BRAIN.md`). Team Brain never replaces it.

**v1 sync backend:** local files (`.team-brain/` or a shared git checkout).  
**Future:** optional HiveShare for realtime multi-agent memory — do not reimplement that layer here.

---

## Data layout

```
.team-brain/                    # or shared team repo root
├── team.yaml                   # members, repos, initiative index
├── TEAM.md                     # team identity + norms
└── initiatives/
    └── TICKET-123.md           # initiative living context
```

Load path for a session:

`personal BRAIN.md` + `TEAM.md` + `initiatives/<id>.md` (when attached)

---

## Commands

### `init`

Scaffold Team Brain in the workspace.

```bash
bash <path-to-scripts>/team-init.sh "$HOME/path/to/workspace"
```

Or manually copy `core/team/*` into `.team-brain/`.

Fill `team.yaml` + `TEAM.md` before using other commands.

### `attach <initiative-id>`

Load initiative context into the current session:

1. Resolve `id` via `team.yaml` → initiative file
2. Read `TEAM.md` + that initiative file
3. Summarize goal, decisions, open questions, latest findings for the user
4. Remind: personal BRAIN.md stays local; do not paste growth notes into the initiative

### `sync [initiative-id]`

Compose a team/initiative status update (not a personal standup).

1. If `initiative-id` given — sync that initiative; else all `active` ones
2. Read initiative files + optional git activity on configured `repos`
3. Output:
   - What the team learned / decided recently
   - Open questions
   - Suggested next captures
4. Backend `local`: file + git only. Backend `hiveshare` (future): also search/pull hives

### `capture <initiative-id> [note]`

Append a research/decision note to the initiative file.

1. Require explicit user content (or summarize from the current conversation if they ask)
2. Append under **Research & findings** or **Capture log** with date + author
3. If it is a decision, also add a row to the **Decisions** table
4. Never write personal career/growth content from BRAIN.md

### `breakdown <initiative-id>`

Draft epic/story breakdown from initiative context.

1. Read initiative goal, decisions, findings, open questions
2. Propose ordered stories/spikes with acceptance criteria
3. Flag gaps that need more `/team-brain capture` before committing the plan

### `status`

Show team.yaml summary: members, active initiatives, sync backend, missing files.

### `detach`

Clear the active initiative from session guidance; keep TEAM.md norms if useful.

---

## Hard rules

- Never commit or push without explicit user permission
- Never sync or publish personal `BRAIN.md`
- Opt-in only — respect `share_scopes` in `team.yaml`
- Prefer impactful captures over dumping chat logs
