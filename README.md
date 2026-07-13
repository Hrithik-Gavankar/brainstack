# cursor-engineer-brain

A self-updating engineering context system for [Cursor IDE](https://cursor.sh) that tracks your work patterns, expertise, habits, and growth — then generates daily standups and quarterly review content automatically.

Think of it as a **second brain for your engineering career**, powered by your git history and living inside your IDE.

---

## What It Does

| Command | What You Get |
|---------|-------------|
| `/engineer-brain sync` | Ready-to-paste standup notes (scans git, detects blockers, suggests today's work) |
| `/engineer-brain update` | Refreshes your BRAIN.md with latest commit data, velocity trends, expertise shifts |
| `/engineer-brain quarterly` | Generates structured quarterly review content with impact metrics |
| `/engineer-brain reflect` | Pattern analysis: blind spots, habit observations, actionable recommendations |
| `/engineer-brain scan [days]` | Raw git scan output across all your repos |

---

## Features

### Always-On Context (`.cursor/rules/engineer-brain.mdc`)
- Cursor loads your engineering profile **on every message** — no need to explain your stack, your repos, or your goals repeatedly
- AI knows your strengths, growing areas, workspace layout, and preferred work style
- Custom instructions shape how the AI assists you (push toward architecture, flag security issues, reference your test patterns, etc.)

### Self-Updating Brain (`.cursor/skills/engineer-brain/BRAIN.md`)
- Living document that evolves as you work
- Tracks: career history, skills inventory, active repos, expertise map, work patterns, sprint context, growth roadmap
- Auto-classifies expertise levels (Strong / Growing / Exposure) based on commit frequency
- Detects patterns: fix-to-feature ratio, velocity trends, cooling repos, stale goals

### Multi-Repo Git Scanner (`scripts/scan.sh`)
- Scans **all git repos** in your workspace in one pass
- Outputs: recent commits, active branches, uncommitted changes, commit type breakdown, files touched, velocity metrics
- Works with any number of repos (monorepos, polyrepos, whatever)
- Cross-platform (macOS + Linux)

### Smart Standup Generation
- Knows your team's standup format and generates paste-ready notes
- Monday-aware: looks back 3 days on Mondays (covers the weekend)
- Weekend-aware: tells you to take the day off
- Detects blockers automatically (merge conflicts, CI failures, stale branches)
- Integrates with Jira if available

### Quarterly Review Automation
- Generates structured performance review content from your actual git history
- Groups accomplishments by impact theme (Security, Quality, DevEx, Features)
- Includes hard numbers: PRs merged, lines changed, test coverage added
- Scoped to current team only — won't leak past-role context

### Pattern Detection & Growth Tracking
- Flags when you're stuck in "fix-only" mode (>60% fix commits)
- Alerts on cooling repos (active before, dormant now)
- Escalates stale growth goals (unchecked >30 days)
- Celebrates new milestones (first `feat:` commit, new repo contributed to)

### Safety Guardrails
- **Never commits** without your explicit permission
- **Never pushes** without your explicit permission
- **Never force-pushes** unless you explicitly say to
- Always asks before any destructive git operation

---

## Installation

1. **Copy the `.cursor` folder** into your workspace root:

```bash
cp -r .cursor /path/to/your/workspace/
```

2. **Configure the scanner** — edit `.cursor/skills/engineer-brain/scripts/scan.sh`:

```bash
# Set your workspace path
WORKSPACE="${1:-$HOME/path/to/your/workspace}"

# Set your git author pattern (matches across all repos)
AUTHOR_PATTERN="your-name\|your-username\|your-email"
```

3. **Fill in the rule** — edit `.cursor/rules/engineer-brain.mdc`:
   - Replace `[YOUR NAME]`, `[YOUR ROLE]`, etc. with your info
   - Customize the "When Helping Me" instructions to match your preferences

4. **Fill in BRAIN.md** — edit `.cursor/skills/engineer-brain/BRAIN.md`:
   - Add your career history, skills, active repos
   - Or just run `/engineer-brain update` and let it auto-populate from git history

5. **Optional**: Add your resume as `RESUME.md` or a PDF in the skill folder for richer context.

---

## File Structure

```
.cursor/
├── rules/
│   └── engineer-brain.mdc          # Always-on context rule (loaded every message)
└── skills/
    └── engineer-brain/
        ├── SKILL.md                 # Skill definition (commands, logic, prompts)
        ├── BRAIN.md                 # Living document (your data, auto-updated)
        ├── RESUME.md                # (Optional) Your resume for richer context
        └── scripts/
            └── scan.sh              # Multi-repo git scanner
```

### How the pieces work together:

| File | Purpose | When It's Used |
|------|---------|----------------|
| `rules/engineer-brain.mdc` | Always-on AI context | Every single AI interaction |
| `skills/.../SKILL.md` | Command definitions & logic | When you invoke `/engineer-brain` |
| `skills/.../BRAIN.md` | Your living engineering profile | Referenced by sync/update/quarterly |
| `scripts/scan.sh` | Git data collection | Called by sync/update/quarterly/scan |

---

## Customization

### Add Your Own Commands

Edit `SKILL.md` and add a new `### command-name` section following the existing pattern.

### Change Standup Format

Edit the standup template in `SKILL.md` under the `sync` command to match your team's Slack/Teams format.

### Add More Data Sources

The system is designed to be extensible. You can add:
- **Jira integration**: If you have a `jira-integration` MCP tool, the brain will pull sprint data automatically
- **Session analytics**: If you have a `session-analyzer` tool, it'll include AI usage stats
- **Custom scripts**: Add more scripts to the `scripts/` folder and reference them in SKILL.md

### Tune Pattern Detection Thresholds

In `SKILL.md` under "Auto-Learning Rules", adjust:
- Expertise classification commit thresholds
- Fix-to-feature ratio warning threshold (default: 60%)
- Repo cooling period (default: 30 days)
- Growth goal escalation period (default: 30 days)

---

## Example Output

### `/engineer-brain sync` (Monday morning)

```
1. What I worked on Friday:
- api-server: fixed rate limiting edge case on concurrent requests (PR #142)
- dashboard: added loading states to analytics charts (#89)

2. What I plan on working on today:
- api-server: continue auth refactor (branch: refactor/auth-middleware)
- review: PR #145 from @teammate (caching layer)

3. Blockers:
- api-server: refactor/auth-middleware has merge conflict with main
```

### `/engineer-brain reflect`

```
## Reflection — 2026-07-13

### What You're Doing Well
- Consistent daily commits (avg 2.3/day)
- Strong test coverage habit (every fix includes tests)

### Blind Spots
- Haven't touched frontend-app repo in 45 days (was active before)
- No `perf:` commits detected — performance work is a growth goal

### Recommendations
1. Pick up one frontend-app issue this week to keep that repo warm
2. Profile the API response times — you have the skills from past roles
```

---

## Requirements

- [Cursor IDE](https://cursor.sh) (with Skills support)
- Git repositories in your workspace
- Bash (macOS or Linux)

---

## Contributing

PRs welcome! Ideas for improvement:

- [ ] Support for GitLab/Bitbucket alongside GitHub
- [ ] Integration with more project management tools (Linear, Shortcut, etc.)
- [ ] Weekly email digest mode
- [ ] Team-level brain (aggregate patterns across a team)
- [ ] VS Code extension wrapper (for non-Cursor users)

---

## License

MIT — use it, fork it, make it yours.

---

## Credits

Built by [Hrithik Gavankar](https://github.com/hrithikgavankar) while working on Ansible DevTools at Red Hat. Born out of the need to stop re-explaining context to AI tools and start getting personalized, career-aware assistance.
