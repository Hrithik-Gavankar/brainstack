---
sidebar_position: 2
---

# update

Refresh BRAIN.md with latest git data, patterns, and metrics.

## Usage

```
engineer-brain update
```

## What it does

1. Scans all repos for the last 30 days
2. Reads current BRAIN.md
3. Updates every section with fresh data
4. Writes the updated BRAIN.md
5. Prints a change summary

## Sections updated

- Active Repositories (commit counts, last-active dates)
- Expertise Map (reclassified from commit patterns)
- Work Patterns (commit type distribution, velocity)
- Current Sprint Context (active branches, achievements)
- Growth Areas (progress check)

## Recommended frequency

Monthly, or after major project changes.
