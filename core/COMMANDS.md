# engineer-brain — Command Reference

A living system that learns how you work, what you focus on, where
you're growing, and where you should push further. Produces actionable output
for daily syncs and quarterly reviews.

## Data Sources

1. **Git history** across repos in your workspace
2. **GitHub activity** via `gh` (authored PRs, reviews, releases/tags) — often more
   accurate than local commits alone
3. **BRAIN.md** — the living document (located in the platform-specific directory or `core/BRAIN.md`)
4. **Session/conversation history** (platform-specific: Cursor transcripts, Claude projects, etc.)
5. **Jira / Linear / project tracker** (if integration available)

**Critical:** Standup-relevant work is frequently *not* in authored git commits.
Reviews, releases, demos, meetup/office-hours prep, and design-feedback work must
be pulled from GitHub/tracker/transcripts/BRAIN — not inferred from `git log --author` alone.

---

## Commands

These commands can be invoked differently depending on your platform:
- **Cursor**: `/engineer-brain <command>`
- **Claude Code**: `engineer-brain <command>` or natural language (e.g., "run my daily sync")
- **VS Code Copilot**: `@workspace engineer-brain <command>` or natural language
- **Windsurf**: `/engineer-brain <command>` or natural language
- **Any platform**: natural language triggers like "daily sync", "update brain", "quarterly review"

---

### `sync` (daily standup helper)

Generate today's standup notes.

**Scope: Current team and current role only.**
Only include work from team repos / team activities in this workspace.
Never reference past roles or personal/side projects — this is for your team's standup thread.
Repos listed in `PERSONAL_REPOS` inside `scan.sh` are excluded from team standup scope.

**Schedule: Workdays only (Monday–Friday).**
If today is Monday, "yesterday" means last Friday. If today is a
weekend, skip — standups don't happen on weekends.

1. Determine the lookback window based on the day of week:
   - **Monday**: scan last 3 days (covers Friday–Sunday)
   - **Tuesday–Friday**: scan last 1 day
   - **Saturday/Sunday**: tell the user "No standup today — it's the weekend." and stop.
   ```bash
   bash <path-to-scripts>/scan.sh "$HOME/path/to/workspace" [1 or 3]
   ```

2. **Also gather non-commit signals** (`scan.sh` emits these when `gh` is authenticated
   and `GH_OWNERS` / `RELEASE_REPOS` are configured):
   - Authored PRs updated in the window
   - Reviews given in the window
   - Recent releases on configured repos
   - Tracker issues in the open sprint + BRAIN.md upcoming events

3. Read `BRAIN.md` for sprint context, active tickets, and scheduled team events.

4. Generate standup notes as **concise prose bullets**, not a dump of every commit hash:
   ```
   1. What I worked on yesterday:
   - [Group related work into 1–3 readable bullets: reviews, features/tickets, releases, demos]
   - [Prefer impact language: "released X upstream", "got TICKET ready for review"]

   2. What I plan on working on today:
   - [Carry-forward from open PRs + tracker In Progress/Review + BRAIN events]
   - [Include release follow-ups, meetup/demo prep, active review queue when relevant]

   3. Blockers:
   - None
   ```

5. If the user **corrects** a sync (pastes their real standup, etc.), treat that as
   ground truth: update BRAIN.md sprint context, note missed signal types, and improve
   scanner config when the gap is systemic. Do not argue with the correction.

### `update` (refresh the brain)

Re-scan everything and update BRAIN.md.

1. Run the full scan for the last 30 days:
   ```bash
   bash <path-to-scripts>/scan.sh "$HOME/path/to/workspace" 30
   ```

2. Read the current `BRAIN.md`.

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
   bash <path-to-scripts>/scan.sh "$HOME/path/to/workspace" 90
   ```

2. Read `BRAIN.md` for context.

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

### `jira` (assigned tasks from Jira)

Fetch your assigned Jira issues, grouped by status.

**Usage:** `jira [filter] [days]`

**Filters:**
- `all` (default) — all open issues assigned to you
- `active` — only "In Progress" issues
- `backlog` — only "Backlog" issues
- `review` — only issues in "Review" status
- `sprint` — issues in the current open sprint
- `done [days]` — issues completed in the last N days (default 7)
- `weekly` — issues completed in the last 7 days
- `quarterly` — issues completed since the start of the current quarter

1. Run:
   ```bash
   bash <path-to-scripts>/jira.sh [filter] [days]
   ```
2. Display the output directly.

**Required env vars:** `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`

**Integration with other commands:**
- When running `sync`, also run `jira done 1` (or `jira done 3` on Monday) to include recently closed Jira tasks in standup notes.
- When running `quarterly`, also run `jira quarterly` to include all closed Jira tasks for the quarter in the review content.
- When running `reflect`, check `jira all` for stale assigned issues that haven't been updated recently.

### `scan` (raw data refresh)

Just run the scanner and display results.

1. Parse optional `[days]` argument (default: 7).
2. Run:
   ```bash
   bash <path-to-scripts>/scan.sh "$HOME/path/to/workspace" [days]
   ```
3. Display the output directly.

### `doctor` (brain health check)

Check the health and completeness of your engineering brain.

1. Run the doctor script:
   ```bash
   bash <path-to-scripts>/doctor.sh "$HOME/path/to/workspace"
   ```
2. Display the output directly to the user. Do not modify, summarize, or reformat the report.
3. If the overall score is below 80%, suggest the user run `engineer-brain update` to improve data freshness.

### `watch` (PR digest across repos)

Scan GitHub repos for open PRs and generate a prioritized digest.

**Scope: All GitHub repos in the workspace (or specified repos).**
Requires the `gh` CLI to be installed and authenticated (`gh auth login`).

**Usage:** `watch [--repos owner/repo,...] [--stale-days N] [--loop N]`

**Flags:**
- `--repos` : comma-separated `owner/repo` slugs (default: auto-discover from workspace git remotes)
- `--stale-days` : days of inactivity before a PR is classified as stale (default: 14)
- `--loop` : re-run every N minutes (default: run once and exit)

1. Run:
   ```bash
   bash <path-to-scripts>/watch.sh "$HOME/path/to/workspace" [--repos ...] [--stale-days N] [--loop N]
   ```
2. Display the output directly.

The script classifies each PR into buckets:
- **Needs Your Review** : you (or a team you belong to) are a requested reviewer, PR is not a draft. Sorted oldest-first, smallest-first.
- **Your Open PRs** : PRs you authored that are still open. Stale own PRs go to the Stale bucket instead.
- **Contributor PRs** : human-authored PRs from other contributors. Bot PRs and drafts are excluded.
- **Stale** : no updates in `--stale-days` days (default 14), including your own stale PRs. Sorted by idle time.

Output includes PR size labels (S/M/L/XL based on lines changed), age, idle time, author, and labels.

**Integration with other commands:**
- When running `sync`, mention the count from `watch` (e.g., "3 PRs waiting for your review") in section 2 (planned work).
- When running `reflect`, flag if your review queue is growing or if you have stale PRs of your own.

---

## Hard Rules

- **NEVER commit** code without the user's explicit permission.
- **NEVER push** to any remote without the user's explicit permission.
- **NEVER force-push** under any circumstance unless the user explicitly says to.
- If a workflow suggests committing or pushing, always stop and ask first.

---

## Jira/Tracker Comment Formats

When asked to write a comment for a ticket tracker, use one of two formats:

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
- **Jira integration**: Run `jira` command to pull assigned tasks, completed work, and sprint data
- **Session analyzer**: If session analytics are available, pull AI usage stats
