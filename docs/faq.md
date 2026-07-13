# Frequently Asked Questions

---

## General

### What is Engineer Brain?

Engineer Brain is a persistent engineering context layer for AI coding assistants. It creates a living, versioned profile of you as an engineer — your skills, work patterns, active projects, and growth trajectory — and feeds it into every AI tool you use.

### Is this another AI coding tool?

No. Engineer Brain doesn't write code, debug, or autocomplete. It provides *context* to tools that do those things. Think of it as the memory layer that makes every AI tool better at helping you specifically.

### How is this different from just writing a system prompt?

Three key differences:

1. **Self-updating** — BRAIN.md refreshes from your actual git history. System prompts go stale immediately.
2. **Portable** — Same brain works across Cursor, Claude Code, Copilot, Windsurf, Aider, and Continue.dev. System prompts are tool-locked.
3. **Intelligent** — Pattern detection flags blind spots, growth opportunities, and anomalies. Static prompts just sit there.

### Does it work if I use multiple AI tools?

Yes — that's a primary design goal. Install once, and every AI tool gets the same deep context about you. Switch tools freely without losing personalization.

---

## Privacy & Security

### Does Engineer Brain send my data anywhere?

No. Everything is local:
- The scanner reads only your local git history
- BRAIN.md lives in your workspace
- Context files live in your workspace
- Nothing is transmitted to any server, ever

### What data does the scanner collect?

The scanner reads git metadata only:
- Commit messages, authors, and dates
- Branch names and status
- Uncommitted change summaries (file names, not contents)

It does NOT read file contents, secrets, environment variables, or credentials.

### Can my team see my BRAIN.md?

Only if you commit it to a shared repository. You can:
- Add it to `.gitignore` to keep it private
- Commit it for team visibility (useful for onboarding)
- Share specific sections selectively

### Is it safe to put my career history in a file?

BRAIN.md contains only information you choose to include. It's no more sensitive than a LinkedIn profile or resume — and it stays on your machine unless you push it.

---

## Installation & Setup

### How long does setup take?

5-10 minutes:
1. Clone the repo (30 seconds)
2. Run the installer (10 seconds)
3. Fill in your identity section (2-3 minutes)
4. Configure the scanner (1 minute)
5. Run `engineer-brain update` (1-2 minutes depending on git history)

### Do I need to fill in everything manually?

No. Fill in the Identity section (name, role, goal) and configure the scanner. Then run `engineer-brain update` — it auto-populates the rest from your git history.

### Can I use it with a monorepo?

Yes. The scanner traverses all git repositories in your workspace path. A monorepo counts as one repository with all its commits scanned.

### What if I have repos in multiple locations?

Configure your workspace path to a common parent directory, or run the scanner multiple times with different paths. The update command aggregates all scan data.

---

## Usage

### How often should I run each command?

| Command | Recommended Frequency |
|---------|----------------------|
| `sync` | Daily, before standup |
| `update` | Monthly, or after major project changes |
| `quarterly` | Once per quarter, before reviews |
| `reflect` | Weekly (Fridays work well) |

### Do I need to run commands manually?

Yes, for now. Commands are triggered by typing them into your AI assistant. Future versions may support scheduled automation.

### Can I customize the standup format?

Yes. Edit the standup template in `core/COMMANDS.md` under the `sync` command to match your team's Slack/Teams format.

### What if a command gives inaccurate output?

The output quality depends on:
1. How well your BRAIN.md is configured (especially the Identity and Sprint Context sections)
2. Whether your scanner config has the correct author pattern
3. Whether your commits follow conventional commit format (`fix:`, `feat:`, etc.)

If output is inaccurate, run `engineer-brain update` to refresh the brain with latest data.

---

## Platforms

### Which AI tools are supported?

Currently: Cursor, Claude Code, GitHub Copilot (VS Code), Windsurf, Aider, and Continue.dev.

### Can I request support for a new platform?

Yes! Open an issue with:
- Platform name and link
- How it loads persistent context (file format, location)
- Any documentation links for its context/rules system

Or submit a PR — adding a new platform adapter is straightforward (see [architecture docs](architecture.md#adding-a-new-platform)).

### If I switch AI tools, do I lose my brain?

No. Your BRAIN.md stays in your workspace. Just run the installer for your new platform and it creates the appropriate context file that references the same brain.

---

## Contributing

### How can I contribute?

See [CONTRIBUTING.md](../CONTRIBUTING.md). Quick options:
- Add a new platform adapter
- Improve pattern detection heuristics
- Create example profiles for different engineering roles
- Improve documentation
- Report bugs or suggest features

### I have an idea for a new command. How do I propose it?

Open a GitHub issue with:
- Command name and description
- What data sources it needs
- Expected output format
- Use case / when you'd run it

### Can I use this at my company?

Yes. MIT license means you can use it commercially, modify it, and distribute it. No restrictions.
