---
sidebar_position: 3
---

# quarterly

Generate structured quarterly performance review content.

## Usage

```
engineer-brain quarterly
```

## What it does

1. Scans the last 90 days of git history
2. Groups accomplishments by impact theme
3. Generates a structured review document

## Output format

```
## Quarterly Review — Q3 2026

### Key Accomplishments
[Grouped by: Security, Quality, DevEx, Performance, Features]

### Technical Impact (Numbers)
- PRs merged: X across Y repos
- Lines of code: +X / -Y
- Test coverage added: X test files

### Growth & Learning
[New skills, stretch work, presentations]

### Goals for Next Quarter
[Based on BRAIN.md growth roadmap]
```

## Scope

Current quarter only. Current team only. Does not reference past roles or personal projects.
