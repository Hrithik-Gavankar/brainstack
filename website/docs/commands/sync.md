---
sidebar_position: 1
---

# sync

Generate paste-ready standup notes from git history, GitHub activity, and BRAIN.md context.

## Usage

```
engineer-brain sync
```

## What it does

1. Determines lookback window (1 day, or 3 days on Monday)
2. Runs `scan.sh` for commits, branches, and (when `gh` is authenticated) PRs / reviews / releases (prefer text mode for sync; use `scan.sh --json` for tooling/CI)
3. Reads BRAIN.md for sprint context and upcoming events
4. Generates concise prose standup notes (not a commit dump)

Authored git commits alone are not enough — reviews, releases, demos, and
design-feedback work often only show up via `gh`, your tracker, or BRAIN.md.

## Output format

```
1. What I worked on yesterday:
- [1–3 impact-focused bullets: reviews, tickets, releases, demos]

2. What I plan on working on today:
- [open PRs + tracker In Progress/Review + BRAIN events]

3. Blockers:
- None
```

## Scanner config (optional)

In `scan.sh`:

| Variable | Purpose |
|----------|---------|
| `PERSONAL_REPOS` | Side-project basenames to exclude from team standup metrics |
| `GH_OWNERS` | Org names used to filter review results |
| `RELEASE_REPOS` | `owner/name` repos to check for recent releases |

## Intelligence

- **Monday-aware**: Looks back 3 days on Mondays
- **Weekend-aware**: Tells you to take the day off on weekends
- **Correction loop**: If you paste a real standup that the sync missed, treat it as ground truth and update BRAIN.md
- **Blocker detection**: Flags merge conflicts, CI failures, stale branches when present
