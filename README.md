# engineer-brain

A self-updating engineering context system that tracks your work patterns, expertise, habits, and growth — then generates daily standups and quarterly review content automatically.

Works with **any AI coding assistant**: Cursor, Claude Code, VS Code Copilot, Windsurf, Aider, Continue.dev, and more.

Think of it as a **second brain for your engineering career**, powered by your git history and living inside your IDE.

---

## What It Does

| Command | What You Get |
|---------|-------------|
| `engineer-brain sync` | Ready-to-paste standup notes (scans git, detects blockers, suggests today's work) |
| `engineer-brain update` | Refreshes your BRAIN.md with latest commit data, velocity trends, expertise shifts |
| `engineer-brain quarterly` | Generates structured quarterly review content with impact metrics |
| `engineer-brain reflect` | Pattern analysis: blind spots, habit observations, actionable recommendations |
| `engineer-brain scan [days]` | Raw git scan output across all your repos |

---

## Supported Platforms

| Platform | Context File | Installation |
|----------|-------------|--------------|
| [Cursor](https://cursor.sh) | `.cursor/rules/engineer-brain.mdc` + `SKILL.md` | `bash install.sh cursor` |
| [Claude Code](https://claude.ai/code) | `CLAUDE.md` | `bash install.sh claude-code` |
| [VS Code Copilot](https://github.com/features/copilot) | `.github/copilot-instructions.md` | `bash install.sh vscode-copilot` |
| [Windsurf](https://codeium.com/windsurf) | `.windsurfrules` | `bash install.sh windsurf` |
| [Aider](https://aider.chat) | `CONVENTIONS.md` | `bash install.sh aider` |
| [Continue.dev](https://continue.dev) | `.continue/rules.md` | `bash install.sh continue-dev` |

Each platform gets the same core brain — just with its native context file format.

---

## Features

### Always-On Context
- Your AI loads your engineering profile **on every interaction** — no need to explain your stack, repos, or goals repeatedly
- AI knows your strengths, growth areas, workspace layout, and preferred work style
- Custom instructions shape how the AI assists you (push toward architecture, flag security issues, reference your test patterns, etc.)

### Self-Updating Brain (`BRAIN.md`)
- Living document that evolves as you work
- Tracks: career history, skills inventory, active repos, expertise map, work patterns, sprint context, growth roadmap
- Auto-classifies expertise levels (Strong / Growing / Exposure) based on commit frequency
- Detects patterns: fix-to-feature ratio, velocity trends, cooling repos, stale goals

### Multi-Repo Git Scanner (`scan.sh`)
- Scans **all git repos** in your workspace in one pass
- Outputs: recent commits, active branches, uncommitted changes, commit type breakdown, files touched, velocity metrics
- Works with any number of repos (monorepos, polyrepos, whatever)
- Cross-platform (macOS + Linux)

### Smart Standup Generation
- Knows your team's standup format and generates paste-ready notes
- Monday-aware: looks back 3 days on Mondays (covers the weekend)
- Weekend-aware: tells you to take the day off
- Detects blockers automatically (merge conflicts, CI failures, stale branches)
- Integrates with Jira/Linear if available

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

## Quick Start

### 1. Install for your platform

```bash
git clone https://github.com/Hrithik-Gavankar/engineer-brain.git
cd engineer-brain

# Pick your platform:
bash install.sh cursor ~/my-workspace
bash install.sh claude-code ~/my-workspace
bash install.sh vscode-copilot ~/my-workspace
bash install.sh windsurf ~/my-workspace
bash install.sh aider ~/my-workspace
bash install.sh continue-dev ~/my-workspace
```

### 2. Configure

Edit the context file that was installed (the main one for your platform) and fill in:
- `[YOUR NAME]`, `[YOUR ROLE]`, `[YOUR COMPANY]`
- Career history, skills inventory, workspace layout
- Custom "When Helping Me" instructions

### 3. Configure the scanner

Edit `.engineer-brain/scripts/scan.sh` (or `.cursor/skills/engineer-brain/scripts/scan.sh` for Cursor):

```bash
WORKSPACE="${1:-$HOME/path/to/your/workspace}"
AUTHOR_PATTERN="your-name\|your-username\|your-email"
```

### 4. Go

Open your AI assistant and say: **"engineer-brain update"**

It will scan your git history and auto-populate BRAIN.md. From then on, run `sync` before standups, `reflect` on Fridays, and `quarterly` before reviews.

---

## Project Structure

```
engineer-brain/
├── core/                              # Platform-agnostic core
│   ├── BRAIN.md                       # Living document template
│   ├── COMMANDS.md                    # Full command reference & logic
│   ├── CONTEXT.md                     # Context rule template (generic)
│   └── scripts/
│       └── scan.sh                    # Multi-repo git scanner
├── platforms/                         # Platform-specific adapters
│   ├── cursor/                        # Cursor IDE
│   │   ├── rules/engineer-brain.mdc
│   │   ├── skills/engineer-brain/SKILL.md
│   │   └── README.md
│   ├── claude-code/                   # Claude Code
│   │   ├── CLAUDE.md
│   │   └── README.md
│   ├── vscode-copilot/               # VS Code + GitHub Copilot
│   │   ├── .github/copilot-instructions.md
│   │   └── README.md
│   ├── windsurf/                      # Windsurf (Codeium)
│   │   ├── .windsurfrules
│   │   └── README.md
│   ├── aider/                         # Aider
│   │   ├── CONVENTIONS.md
│   │   └── README.md
│   └── continue-dev/                  # Continue.dev
│       ├── .continue/rules.md
│       └── README.md
├── install.sh                         # Universal installer
├── .gitignore
├── LICENSE
└── README.md                          # This file
```

### How the pieces work together:

| Component | Purpose | Used By |
|-----------|---------|---------|
| `core/BRAIN.md` | Your living engineering profile | All platforms |
| `core/COMMANDS.md` | Command definitions & logic | Non-Cursor platforms |
| `core/scripts/scan.sh` | Git data collection | All commands |
| `platforms/<name>/` | Platform-specific context file | Your chosen AI assistant |
| `install.sh` | Sets up everything for a platform | You, once |

---

## Customization

### Add Your Own Commands

Edit `core/COMMANDS.md` (or `SKILL.md` for Cursor) and add a new section following the existing pattern.

### Change Standup Format

Edit the standup template in `core/COMMANDS.md` under the `sync` command to match your team's Slack/Teams format.

### Add More Data Sources

The system is designed to be extensible:
- **Jira integration**: Pull sprint data automatically
- **Linear integration**: Pull issue assignments and cycle data
- **Session analytics**: Include AI usage stats
- **Custom scripts**: Add more scripts to `scripts/` and reference them in COMMANDS.md

### Tune Pattern Detection Thresholds

In `core/COMMANDS.md` under "Auto-Learning Rules", adjust:
- Expertise classification commit thresholds
- Fix-to-feature ratio warning threshold (default: 60%)
- Repo cooling period (default: 30 days)
- Growth goal escalation period (default: 30 days)

---

## Example Output

### `engineer-brain sync` (Monday morning)

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

### `engineer-brain reflect`

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

- Any AI coding assistant (see [Supported Platforms](#supported-platforms))
- Git repositories in your workspace
- Bash (macOS or Linux)

---

## Adding a New Platform

Want to add support for another AI tool? It's simple:

1. Create `platforms/<platform-name>/`
2. Add the context file in whatever format the tool expects
3. Add a `README.md` with setup instructions
4. Add an install case in `install.sh`
5. Submit a PR!

The core content (`BRAIN.md`, `COMMANDS.md`, `scan.sh`) stays the same — you're just creating a new context file adapter.

---

## Contributing

PRs welcome! Ideas for improvement:

- [ ] Support for GitLab/Bitbucket alongside GitHub
- [ ] Integration with more project management tools (Linear, Shortcut, etc.)
- [ ] Weekly email digest mode
- [ ] Team-level brain (aggregate patterns across a team)
- [ ] Web UI dashboard for visualizing patterns and progress
- [ ] Zed editor support
- [ ] JetBrains AI Assistant support
- [ ] Neovim + AI plugin support

---

## License

MIT — use it, fork it, make it yours.

---

## Credits

Built by [Hrithik Gavankar](https://github.com/hrithikgavankar) while working on Ansible DevTools at Red Hat. Born out of the need to stop re-explaining context to AI tools and start getting personalized, career-aware assistance.
