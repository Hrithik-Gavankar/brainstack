---
sidebar_position: 6
---

# doctor

Brain health check with completeness score and growth suggestions.

## Usage

```
engineer-brain doctor
```

## What it does

1. Reads BRAIN.md for section completeness
2. Runs the scanner for the last 30 days
3. Computes a weighted health score across 7 factors
4. Detects cooling repositories
5. Generates data-driven growth suggestions

## Health score factors

| Factor | Weight | Criteria |
|--------|--------|----------|
| Identity completeness | 15% | All fields filled in Identity section |
| Skills freshness | 20% | Skills have recent "Last Used" dates |
| Active repos | 15% | At least 3 repos active in last 30 days |
| Sprint context | 15% | Active branches and recent achievements exist |
| Growth roadmap | 10% | Has unchecked goals (active growth) |
| Velocity consistency | 15% | No >30% drops in commit frequency |
| Commit diversity | 10% | Not >60% single commit type |

## Output format

```
🧠 Engineer Brain Health

Engineering Context:     94%
Repositories Tracked:    18
Active This Week:        6
Skills Updated:          ✓
Standup Ready:           ✓
Quarterly Review Ready:  ✓

Cooling Repositories:
  - inventory-service (32 days)
  - legacy-api (45 days)

Growth Suggestions:
  - No architecture-related commits this month
  - Testing activity decreased 28%
  - GraphQL expertise hasn't been exercised in 90 days

Overall Brain Health
██████████████████░░ 94%
```

## Recommended frequency

Run anytime to check your brain's health. Works well as a first command after installing engineer-brain.
