# Frequently Asked Questions

---

## General

### What is Brainstack?

Brainstack is a persistent context layer for AI coding assistants — with two scopes:

| Scope | What it does |
|-------|--------------|
| **`engineer-brain`** | Your personal profile — skills, patterns, career trajectory |
| **Team Brain** | Shared crew memory on a Jira initiative — realtime sync across agents |

Together, they give AI deep context about *you* and *your team's work*.

### What's the difference between `engineer-brain` and Team Brain?

**`engineer-brain`** = personal. Your `BRAIN.md` stays local, tracks your growth, generates standups and quarterly reviews. Never uploaded.

**Team Brain** = crew collaboration. When three engineers spike the same Jira initiative, their agents share memory via Supabase. Engineer A learns something → Engineer B's agent knows it instantly.

You can use Brainstack with `engineer-brain` alone. Team Brain is opt-in for crews who want shared AI context.

### Is this another AI coding tool?

No. Brainstack doesn't write code, debug, or autocomplete. It provides *context* to tools that do those things. Think of it as the memory layer that makes every AI tool better at helping you specifically.

### How is this different from just writing a system prompt?

Three key differences:

1. **Self-updating** — BRAIN.md refreshes from your actual git history. System prompts go stale immediately.
2. **Portable** — Same brain works across Cursor, Claude Code, Copilot, Windsurf, Aider, and Continue.dev. System prompts are tool-locked.
3. **Intelligent** — Pattern detection flags blind spots, growth opportunities, and anomalies. Static prompts just sit there.

### Does it work if I use multiple AI tools?

Yes — that's a primary design goal. Install once, and every AI tool gets the same deep context about you. Switch tools freely without losing personalization.

---

## Privacy & Security

### Does Brainstack send my data anywhere?

| Scope | Data location | What syncs |
|-------|---------------|------------|
| **`engineer-brain`** | 100% local | Nothing — git history, `BRAIN.md`, context files stay on your machine |
| **Team Brain** | Your Supabase project | Initiative memories + membership (you own the project) |

**Personal `BRAIN.md` is never uploaded to Team Brain.** Team Brain syncs only crew findings on a Jira key — research decisions, architectural choices, spike learnings.

See [team-brain.md](team-brain.md) and [supabase/README.md](../supabase/README.md).

### What data does the scanner collect?

The scanner reads git metadata only:
- Commit messages, authors, and dates
- Branch names and status
- Uncommitted change summaries (file names, not contents)
- Optional GitHub activity via `gh` (authored PRs, reviews, configured releases)

It does NOT read file contents, secrets, environment variables, or credentials.

### Can I get machine-readable scan output?

Yes. Pass `--json` (requires `python3`):

```bash
bash core/scripts/scan.sh ~/workspace 7 --json | jq '.type_breakdown'
```

Default output stays human/AI-readable text. JSON is the stable contract for the
dashboard data port, CI jobs, and future weekly brain-update automation.

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

## Team Brain

### What is Team Brain?

The **team / initiative scope** of Brain. Crews share collaborative AI memory on a Jira key (Supabase + local cache). It is not a second personal `BRAIN.md`.

### How does a crew admin set up Team Brain quickly?

Use **bootstrap** (configure → migrations → register → share bundle):

```bash
bash core/scripts/team-brain-api.sh bootstrap --team "Crew" --admin "Alice" --url … --anon … --db-url … --jira AAP-81423
```

See [supabase/README.md](../supabase/README.md). Joiners still use `onboard` and do **not** need a Supabase account.

### How do I join a crew?

Ask your admin for an **invite code**, **Jira key**, and the crew’s **Supabase URL + anon key**. Put URL/anon in local `supabase/project.public.env` (or `team.yaml` / env), then:

```bash
bash core/scripts/team-brain-api.sh onboard <INVITE> "Your Name" AAP-81423
```

You do **not** need your own Supabase account. Step-by-step: [team-brain-onboarding.md](team-brain-onboarding.md). Admin setup: [supabase/README.md](../supabase/README.md).

### Do agents sync automatically?

Not by chat alone. Shared memory requires `remember`, then `recall` (or MCP / optional `watch`). With Realtime push (#31) enabled, peers get a signal + cache refresh while sync/`watch` is running; poll remains the fallback. In Cursor, the always-on Team Brain rule requires recall-before-research and remember-after-findings.

### How do I correct bad research in Team Brain?

Paste the correction in chat (or run CLI). The agent should **`correct`** (or re-`remember`) the **same** `source_ref` so the row updates — never a second topic slug. Optional `learning` kind records “was wrong → prefer …”. See [team-brain-onboarding.md](team-brain-onboarding.md) and example in `examples/team-spike-crew/`.

### Can I undo a memory update?

Yes — after the history migration, each `source_ref` update archives the prior body. Use `history <KEY> --source-ref REF` then `restore <KEY> --source-ref REF --revision N`. Restore archives the current body first so the audit trail stays intact.

### Is semantic search required?

No. Default recall is full-text search. Optional embeddings (OpenAI/Ollama) are documented in [team-brain-memory.md](team-brain-memory.md).

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
