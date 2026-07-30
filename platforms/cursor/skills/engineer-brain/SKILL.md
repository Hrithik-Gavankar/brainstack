---
name: engineer-brain
description: >-
  Your self-updating engineering brain — tracks work patterns, expertise,
  habits, progress gaps, and generates daily sync-up notes and quarterly
  review content. Invoke when you say "engineer brain", "update brain",
  "daily sync", "standup", "sync up", "quarterly connections", "what did I
  work on", "my progress", "where am I lacking", "what should I focus on",
  "update my brain", "brain scan", "engineering context", or ask about
  your own work patterns, "doctor", "health check", "brain health".
argument-hint: <command> — sync | update | quarterly | reflect | scan [days] | doctor
tools: Read, Write, Shell, Glob, Grep
---

# Engineer Brain — Self-Updating Engineering Context

A living system that learns how you work, what you focus on, where
you're growing, and where you should push further. Produces actionable output
for daily syncs and quarterly reviews.

## Data Sources

1. **Git history** across repos in your workspace
2. **GitHub activity** via `gh` (authored PRs, reviews, releases/tags) — often more
   accurate than local commits alone
3. **BRAIN.md** at `${SKILL_DIR}/BRAIN.md` (the living document)
4. **Agent transcripts** in the Cursor projects folder (demos, skill work, non-commit tasks)
5. **Jira / Linear / project tracker** via MCP or integration skill (if available)

**Critical:** Standup-relevant work is frequently *not* in authored git commits.
Reviews, releases, demos, office-hours/meetup prep, cross-team notifications, and
design-feedback incorporation must be pulled from GitHub/Jira/transcripts/BRAIN —
not inferred from `git log --author` alone.

---

## Commands

Parse the user's request to determine which command to run:

### `sync` (daily standup helper)

Generate today's standup notes.

**Scope: Current team and current role only.**
Only include work from team repos / team activities in this workspace.
Never reference past roles or personal/side projects — this is for your
team's standup thread. Repos listed in `PERSONAL_REPOS` inside `scan.sh`
are excluded from team standup scope.

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

2. **Also gather non-commit signals** (require network/`gh` auth; `scan.sh`
   already emits these when configured):
   ```bash
   # Authored PRs updated in window
   gh search prs --author=@me --updated=">=YYYY-MM-DD" --limit 20
   # Reviews given in window
   gh search prs --reviewed-by=@me --updated=">=YYYY-MM-DD" --limit 20
   # Recent releases (configure RELEASE_REPOS in scan.sh)
   gh release list --repo your-org/your-repo --limit 3
   ```
   Plus tracker issues assigned in the open sprint, and BRAIN.md
   "Current Sprint Context" / upcoming events (demos, office hours, meetups).

3. Read `${SKILL_DIR}/BRAIN.md` for sprint context, active tickets, and
   scheduled team events.

4. Generate standup notes as **concise prose bullets**, not a dump of every
   commit hash:
   ```
   1. What I worked on yesterday:
   - [Group related work into 1–3 readable bullets: reviews, features/tickets, releases, demos/skills]
   - [Prefer impact language: "released X upstream", "got TICKET ready for review"]

   2. What I plan on working on today:
   - [Carry-forward from open PRs + tracker In Progress/Review + BRAIN events]
   - [Include release follow-ups, meetup/demo prep, active review queue when relevant]

   3. Blockers:
   - None
   ```

   Prefer the tone of a real standup (what a teammate cares about) over a
   git archaeology report. Example of good output:
   ```
   1. What I worked on yesterday:
   - Reviewed quality-gate PRs, prepared a demo for Office Hours, incorporated feedback for TICKET-123 and got it ready for review, and released my-tool upstream.

   2. What I plan on working on today:
   - Preparing the release notification for the partner team and raising the corresponding dependency bump PR, actively reviewing open PRs, and preparing for the community meetup.

   3. Blockers:
   - None
   ```

5. If the user **corrects** a sync ("actually I also…", pastes their real
   standup, etc.), treat that as ground truth:
   - Absorb into BRAIN.md Current Sprint Context / Recent Achievements
   - Note any signal type the scanner missed (review/release/demo/event)
   - Do **not** argue with the correction — learn from it

### Standup correction feedback (`sync` follow-up)

When the user pastes or describes their real standup after a generated sync:

1. Diff what was missed vs what `scan.sh` + `gh` returned.
2. Update BRAIN.md sprint context immediately.
3. If a systemic gap remains (e.g. releases, demos, cross-team work), improve
   `scripts/scan.sh` config and/or the sync steps above in the same session.

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

### `doctor` (brain health check)

Check the health and completeness of your engineering brain.

1. Run the doctor script:
   ```bash
   bash "${SKILL_DIR}/scripts/doctor.sh" "$HOME/path/to/workspace"
   ```
2. Display the output directly to the user. Do not modify, summarize, or reformat the report.
3. If the overall score is below 80%, suggest the user run `/engineer-brain update` to improve data freshness.

---

## Hard Rules

- **NEVER commit** code without the user's explicit permission.
- **NEVER push** to any remote without the user's explicit permission.
- **NEVER force-push** under any circumstance unless the user explicitly says to.
- If a workflow suggests committing or pushing, always stop and ask first.

---

## Jira Comment Formats

When asked to write a Jira comment, use one of two formats based on the request:

### `short` (default — quick status update)

```
Hi team,

[One-liner update summarizing the status, action taken, or decision made.]

Thank you!
```

### `in-depth` (detailed update with structure)

```
Hi team,

**Updates:**
- [Update point 1]
- [Update point 2]
- [Update point 3]

**Next Steps:**
- [Action item 1]
- [Action item 2]
- [Action item 3]

Thank you!
```

**Rules:**
- If the user says "short" or "quick" or "one-liner" → use the short format
- If the user says "detailed" or "in-depth" or "full update" → use the in-depth format
- If unspecified, ask which format they want
- Always open with "Hi team," and close with "Thank you!"
- Keep bullet points concise and action-oriented
- Use bold headers for sections in the in-depth format

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
