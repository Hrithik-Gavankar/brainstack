# BRAIN.md Specification

**Version:** 1.0.0-draft
**Status:** Draft
**Authors:** Hrithik Gavankar

---

## Abstract

This document defines `BRAIN.md` — a structured Markdown file format for documenting an individual engineer's professional identity, expertise, work patterns, and growth trajectory. It is designed to be consumed by AI coding assistants, enabling personalized, context-aware interactions across any tool that supports it.

`BRAIN.md` is to engineers what `README.md` is to projects.

---

## Motivation

### The precedent for structured project documentation

The software ecosystem has converged on standard files that describe projects:

| File | Documents | Consumed By |
|------|-----------|-------------|
| `README.md` | What a project does | Humans, GitHub, package registries |
| `package.json` | Node.js application metadata | npm, bundlers, CI systems |
| `pyproject.toml` | Python project configuration | pip, build tools, IDEs |
| `Cargo.toml` | Rust crate metadata | cargo, crates.io |
| `Dockerfile` | Runtime environment | Docker, Kubernetes, CI |

Each of these files answers the question: *"What is this project, and how should tools interact with it?"*

### The missing standard: documenting engineers

There is no equivalent standard that answers: *"Who is this engineer, and how should AI tools interact with them?"*

Today, every AI coding assistant starts from zero. Engineers re-explain their expertise, their workspace layout, their team conventions, and their goals — session after session, tool after tool.

**`BRAIN.md` fills this gap.**

| File | Documents | Consumed By |
|------|-----------|-------------|
| `BRAIN.md` | The engineer | AI coding assistants |

---

## Design Principles

1. **Markdown-native** — Human-readable, git-friendly, universally supported
2. **Self-updating** — Designed to be refreshed programmatically from git history
3. **Platform-agnostic** — Not tied to any specific AI tool or vendor
4. **Privacy-first** — Lives locally, never transmitted unless the engineer chooses to share
5. **Progressive** — Useful even when partially filled; more powerful when complete
6. **Versioned** — Can be tracked in git, diffed over time, and reviewed for growth

---

## Specification

### File Location

`BRAIN.md` SHOULD be located in one of:
- The workspace root (for platform-agnostic setups)
- A platform-specific directory (e.g., `.cursor/skills/engineer-brain/BRAIN.md`)
- A dedicated directory (e.g., `.engineer-brain/BRAIN.md`)

### File Format

`BRAIN.md` is a valid Markdown file using ATX headings (`#`, `##`, `###`) to define sections. Tables use GitHub Flavored Markdown pipe syntax.

### Required Sections

#### 1. Header

```markdown
# [Full Name] — Engineering Brain

> Last updated: [ISO 8601 date]
> Auto-generated baseline. Updates itself via `engineer-brain update`.
```

The header MUST include the engineer's name and a last-updated timestamp.

#### 2. Identity

```markdown
## Identity

- **Name:** [Full name]
- **Role:** [Role title, team, company]
- **Total experience:** [Years]
- **Workspace:** [Path to primary workspace]
- **Primary tools:** [IDE, CLI tools, frameworks]
- **Career goal:** [Next career milestone]
```

Purpose: Establishes who the engineer is. AI assistants use this to calibrate response complexity, domain assumptions, and career-aware suggestions.

#### 3. Career History

```markdown
## Career History

### [Company] — [Role]
**[Start] – [End or Present]**

[1-2 sentence summary]

- Primary codebase: [repo or package]
- Key technologies: [stack]
- Key achievements: [measurable impacts]
```

Purpose: Provides longitudinal context. AI can reference past experience when suggesting approaches the engineer has proven skills in but hasn't applied in their current role.

#### 4. Skills Inventory

```markdown
## Full Skills Inventory

### [Category]
| Skill | Proficiency | Where Proven | Last Used |
|-------|------------|--------------|-----------|
| [skill] | Strong/Growing/Exposure | [context] | [date] |
```

Categories SHOULD include: Backend, Frontend, Infrastructure & DevOps, and optionally domain-specific categories.

**Proficiency levels:**
- **Strong** — 10+ commits in the area, or 3+ PRs merged in the subsystem. Can teach others.
- **Growing** — 2-9 commits, or 1-2 PRs. Actively building competence.
- **Exposure** — Repo cloned, files read, limited hands-on work. Aware but not proven.

Purpose: Enables AI to match suggestions to the engineer's actual skill level rather than assuming expertise or ignorance.

#### 5. Active Repositories

```markdown
## Active Repositories

| Repo | Role | Contribution Level | Last Active | Focus Area |
|------|------|--------------------|-------------|------------|
| [name] | [role] | Heavy/Moderate/Light | [date] | [area] |
```

Purpose: Tells the AI which codebases are relevant to current work, preventing suggestions that reference inactive or irrelevant repos.

#### 6. Expertise Map

```markdown
## Expertise Map

### Strong (proven at current and past roles)
- [Area]: [evidence]

### Growing (actively building)
- [Area]: [current activity]

### Proven but dormant (reactivation targets)
- [Area]: [where proven, when last used]
```

Purpose: Higher-level view than the skills table. Identifies areas where the engineer can be pushed toward growth or reminded of underused capabilities.

#### 7. Work Patterns

```markdown
## Work Patterns

### Commit Type Distribution
fix: X%
feat: X%
refactor: X%
test: X%
chore: X%

### Velocity Trend
[Month]: X commits

### Work Schedule
- Peak hours: [time range]
- Active days: [days]

### Implementation Style
1. [Pattern description]
2. [Pattern description]
```

Purpose: Enables AI to detect anomalies (velocity drops, fix-heavy periods) and tailor workflow suggestions to the engineer's natural rhythm.

#### 8. Current Sprint Context

```markdown
## Current Sprint Context

### Active Branches
| Repo | Branch | Status |
|------|--------|--------|
| [repo] | [branch] | In progress / Merged / Stale |

### Recent Achievements
1. [Achievement with reference]
```

Purpose: Immediate context for daily interactions. AI can reference in-progress work without the engineer needing to re-state it.

#### 9. Growth Areas

```markdown
## Growth Areas & Feedback Loop

### Strengths to Leverage
- [Strength with evidence]

### Growth Roadmap
#### [Category]
- [ ] [Goal]
- [x] [Completed goal]

### Learning Log
| Date | What Learned | Source |
|------|-------------|--------|
| [date] | [topic] | [source] |
```

Purpose: Enables coaching-aware AI behavior. The AI can nudge the engineer toward growth goals rather than only optimizing for immediate task completion.

### Optional Sections

#### Quarterly Template

Pre-structured template for performance review generation.

#### Daily Sync Helper

Team-specific standup format and preferences.

---

## How AI Assistants Should Consume BRAIN.md

### Loading

AI assistants SHOULD load BRAIN.md at the start of every session or conversation. The file SHOULD be included in the system context (rules, instructions, or equivalent mechanism).

### Interpretation

AI assistants SHOULD use BRAIN.md to:

1. **Calibrate complexity** — Don't over-explain concepts the engineer has "Strong" proficiency in
2. **Reference past experience** — Suggest approaches proven in previous roles
3. **Respect work patterns** — Align suggestions with the engineer's implementation style
4. **Push growth** — Nudge toward growth goals when opportunities arise naturally
5. **Maintain sprint awareness** — Reference active branches and current work
6. **Flag anomalies** — Note when patterns deviate (velocity drops, repo cooling, etc.)

### Updating

AI assistants SHOULD offer to update BRAIN.md when:
- Significant new work is detected (new repo, new technology, major PR)
- Periodic refresh is triggered (monthly cadence recommended)
- The engineer explicitly requests it

Updates SHOULD be generated from git history and session data, not fabricated.

---

## Toward an Open Standard

### Why BRAIN.md should be universal

The AI coding assistant market is fragmenting. Engineers use multiple tools — often switching between them within a single day. Context should not be locked inside any single vendor's format.

`BRAIN.md` proposes a universal, vendor-neutral format that:
- Any AI tool can read (it's just Markdown)
- Any tool can write updates to (structured sections with predictable headings)
- Engineers own and control (lives in their workspace, versioned in git)
- Evolves with the ecosystem (new sections can be added without breaking existing consumers)

### Adoption path

1. **Individual adoption** — Engineers maintain their own BRAIN.md
2. **Tool integration** — AI assistants natively recognize and consume BRAIN.md
3. **Ecosystem tooling** — Validators, importers (from LinkedIn, GitHub profile), exporters
4. **Community standard** — RFC process for adding new sections or proficiency levels

---

## Compatibility

BRAIN.md is designed to be forward-compatible:
- Unknown sections SHOULD be ignored by consumers that don't recognize them
- Missing optional sections SHOULD NOT cause errors
- Custom sections (prefixed with `x-`) are allowed for experimental features

---

## References

- [Engineer Brain Repository](https://github.com/Hrithik-Gavankar/engineer-brain)
- [Architecture Documentation](architecture.md)
- [Vision Document](vision.md)
