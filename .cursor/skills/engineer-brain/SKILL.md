---
name: engineer-brain
description: >-
  Your self-updating engineering brain — tracks work patterns, expertise,
  habits, progress gaps, and generates daily sync-up notes and quarterly
  review content. Invoke when you say "engineer brain", "update brain",
  "daily sync", "standup", "sync up", "quarterly connections", "what did I
  work on", "my progress", "where am I lacking", "what should I focus on",
  "update my brain", "brain scan", "engineering context", or ask about
  your own work patterns.
argument-hint: <command> — sync | update | quarterly | reflect | scan [days]
tools: Read, Write, Shell, Glob, Grep
---

# Engineer Brain — Self-Updating Engineering Context

A living system that learns how you work, what you focus on, where
you're growing, and where you should push further. Produces actionable output
for daily syncs and quarterly reviews.

## Data Sources

1. **Git history** across all repos in your workspace
2. **BRAIN.md** at `${SKILL_DIR}/BRAIN.md` (the living document)
3. **Agent transcripts** in the Cursor projects folder
4. **Jira** via `jira-integration` skill (if available)

---

## Commands

Parse the user's request to determine which command to run:

### `sync` (daily standup helper)

Generate today's standup notes.

**Scope: Current team and current role only.**
Only include work from repos in this workspace.
Never reference past roles or personal projects — this is for your team's standup thread.

**Schedule: Workdays only (Monday–Friday).**
If today is Monday, "yesterday" means last Friday. If today is a
weekend, skip — standups don't happen on weekends.

1. Determine the lookback window based on the day of week:
   - **Monday**: scan last 3 days (covers Friday–Sunday)
   - **Tuesday–Friday**: scan last 1 day
   - **Saturday/Sunday**: tell the user "No standup today — it's the weekend."
     and stop.
   ```bash
   bash "${SKILL_DIR}/scripts/scan.sh" "$HOME/path/to/workspace" [1 or 3]
   ```

2. Read `${SKILL_DIR}/BRAIN.md` for current sprint context and active branches.

3. Generate standup notes in your team's thread format:
   ```
   1. What I worked on yesterday:
   - [list each commit/PR from yesterday with repo name and concise description]
   - [include any reviews done, Jira tickets referenced]

   2. What I plan on working on today:
   - [infer from active branches what's in progress]
   - [check for any open PR reviews needed]
   - [suggest next logical task based on patterns and BRAIN.md sprint context]

   3. Blockers:
   - [any branches with merge conflicts]
   - [any CI failures on active branches]
   - [any stale branches > 5 days old]
   - None (if no blockers)
   ```

4. If the `jira-integration` MCP tool is available, also check for assigned
   Jira issues in the current sprint and include them in section 2.

### `update` (refresh the brain)

Re-scan everything and update BRAIN.md.

1. Run the full scan for the last 30 days:
   ```bash
   bash "${SKILL_DIR}/scripts/scan.sh" "$HOME/path/to/workspace" 30
   ```

2. Read the current `${SKILL_DIR}/BRAIN.md`.

3. For each section in BRAIN.md, update with fresh data:
   - **Active Repositories**: re-count commits, update last-active dates
   - **Expertise Map**: reclassify based on new commits and file patterns
   - **Work Patterns**: recalculate commit type distribution and velocity
   - **Current Sprint Context**: update active branches and recent achievements
   - **Growth Areas**: check if any previous gaps have been addressed
   - **Learning Log**: add entries for new technologies or patterns encountered
   - **Quarterly Template**: append new accomplishments

4. Write the updated BRAIN.md back.

5. Print a summary of what changed:
   ```
   ## Brain Updated — [DATE]
   - X new commits since last update
   - New expertise signal: [if any new repo or tech area]
   - Velocity trend: [up/down/stable]
   - Growth checklist: X/Y items addressed
   ```

### `quarterly` (performance review prep)

Generate quarterly performance review content.

**Scope: Current quarter only (last 3 months), current team only.**
Only include work done in repos in this workspace.
Do NOT reference past roles, past teams, or personal/side projects.

1. Determine the current quarter boundaries and scan for that period:
   ```bash
   bash "${SKILL_DIR}/scripts/scan.sh" "$HOME/path/to/workspace" 90
   ```

2. Read `${SKILL_DIR}/BRAIN.md` for context.

3. Produce a structured quarterly document:
   ```
   ## Quarterly Review — [QUARTER] [YEAR]
   ### Team: [Your team name]

   ### Key Accomplishments
   [For each merged PR in the quarter, summarize impact in business language]
   [Group by theme: Security, Quality, DevEx, Performance, Features]

   ### Technical Impact (Numbers)
   - PRs merged: X across Y repos
   - Lines of code: +X / -Y
   - Test coverage added: X test files, Y test cases
   - Issues resolved: X

   ### Growth & Learning
   [What new skills were developed this quarter]
   [What areas did you stretch into]
   [Presentations, demos, knowledge sharing events]

   ### Cross-Team Collaboration
   [Repos contributed to beyond primary]
   [Reviews done for other team members]

   ### Goals for Next Quarter
   [Based on gap analysis from BRAIN.md growth roadmap]
   [Aligned with team priorities]
   ```

### `reflect` (pattern analysis and feedback)

Analyze current patterns and provide actionable feedback.

1. Run the scan for the last 30 days.
2. Read BRAIN.md.
3. Analyze and report:

   ```
   ## Reflection — [DATE]

   ### What You're Doing Well
   [Cite specific commits and patterns]

   ### Habit Observations
   - Work hours pattern: [when you're most productive]
   - Commit frequency: [daily average, consistency]
   - PR size tendency: [small/medium/large, recommendation]
   - Fix-to-feature ratio: [current ratio, ideal ratio]

   ### Blind Spots
   [Repos you have cloned but haven't touched]
   [Types of work you consistently skip]
   [Skills on your growth list that haven't progressed]

   ### Recommendations
   1. [Specific, actionable suggestion with reasoning]
   2. [Specific, actionable suggestion with reasoning]
   3. [Specific, actionable suggestion with reasoning]
   ```

### `scan` (raw data refresh)

Just run the scanner and display results.

1. Parse optional `[days]` argument (default: 7).
2. Run:
   ```bash
   bash "${SKILL_DIR}/scripts/scan.sh" "$HOME/path/to/workspace" [days]
   ```
3. Display the output directly.

---

## Hard Rules

- **NEVER commit** code without the user's explicit permission.
- **NEVER push** to any remote without the user's explicit permission.
- **NEVER force-push** under any circumstance unless the user explicitly says to.
- If a workflow suggests committing or pushing, always stop and ask first.

---

## Auto-Learning Rules

When running `update`, apply these heuristics to evolve the brain:

### Expertise Classification
- **Strong**: 10+ commits in an area, or 3+ PRs merged touching the same subsystem
- **Growing**: 2-9 commits, or 1-2 PRs in an area
- **Exposure**: Repo cloned, files read, but no commits

### Pattern Detection
- If > 60% of commits are `fix:`, flag that feature work is underrepresented
- If a repo hasn't been touched in 30+ days but was previously active, flag as "cooling"
- If commit velocity drops > 30% week-over-week, flag for attention
- If a growth-area checkbox stays unchecked for 30+ days, escalate in reflection

### Feedback Loop
After each `update`, compare current state against previous state:
- New repos contributed to → celebrate in reflection
- New commit types (first `feat:` or `perf:`) → note the growth
- Stale growth items → push harder in recommendations
- Changed work hours → note if healthy or concerning

---

## Integration Points

- **Daily sync**: Run `sync` before standup meetings
- **Weekly reflection**: Run `reflect` on Fridays
- **Monthly update**: Run `update` at month start
- **Quarterly prep**: Run `quarterly` before performance reviews
- **Jira context**: If `jira-integration` skill is available, pull sprint data
- **Session analyzer**: If `session-analyzer` skill is available, pull AI usage stats
