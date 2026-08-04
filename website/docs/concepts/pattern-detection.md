---
sidebar_position: 3
---

# Pattern Detection

Brainstack doesn't just collect data — it detects patterns and surfaces insights you might miss yourself.

## Detection Rules

| Pattern | Trigger | Action |
|---------|---------|--------|
| Fix-heavy mode | >60% of commits are `fix:` | Flags in reflection |
| Cooling repository | Active repo with 30+ days no commits | Alerts engineer |
| Velocity drop | >30% decrease week-over-week | Flags for attention |
| Stale growth goal | Unchecked for 30+ days | Escalates in reflection |
| New expertise signal | First commits in a new area | Celebrates in reflection |

## Expertise Classification

Based on commit frequency in a specific area:

- **Strong** (10+ commits or 3+ PRs) — Can teach others
- **Growing** (2-9 commits or 1-2 PRs) — Actively developing
- **Exposure** (0-1 commits, repo cloned) — Aware but unproven

## How it helps

Pattern detection turns raw git data into career coaching:

- "You haven't touched the frontend repo in 45 days"
- "Your fix-to-feature ratio suggests you're stuck in maintenance mode"
- "Performance optimization is on your growth list but you have zero `perf:` commits"
- "First architecture commit this quarter — nice!"
