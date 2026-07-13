---
sidebar_position: 1
---

# sync

Generate paste-ready standup notes from your git history.

## Usage

```
engineer-brain sync
```

## What it does

1. Determines lookback window (1 day, or 3 days on Monday)
2. Scans git history for your commits
3. Reads BRAIN.md for sprint context
4. Generates formatted standup notes

## Output format

```
1. What I worked on yesterday:
- [repo: description, PR/Jira refs]

2. What I plan on working on today:
- [inferred from active branches]

3. Blockers:
- [merge conflicts, CI failures, stale branches]
```

## Intelligence

- **Monday-aware**: Looks back 3 days on Mondays
- **Weekend-aware**: Tells you to take the day off on weekends
- **Blocker detection**: Flags merge conflicts, CI failures, stale branches
