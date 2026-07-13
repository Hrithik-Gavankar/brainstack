---
sidebar_position: 2
---

# Platform Adapters

Platform adapters translate your universal BRAIN.md into the native context format each AI tool expects.

## How it works

Each AI coding assistant has its own mechanism for loading persistent context:

| Platform | Native Format | File Location |
|----------|---------------|---------------|
| Cursor | `.mdc` rules + `SKILL.md` | `.cursor/rules/` + `.cursor/skills/` |
| Claude Code | `CLAUDE.md` | Workspace root |
| GitHub Copilot | `copilot-instructions.md` | `.github/` |
| Windsurf | `.windsurfrules` | Workspace root |
| Aider | `CONVENTIONS.md` | Workspace root |
| Continue.dev | `rules.md` | `.continue/` |

## What each adapter contains

1. **Context summary** — Condensed identity, skills, workspace info
2. **Behavior instructions** — How AI should use the context
3. **Command reference** — Platform-specific invocation syntax
4. **Brain reference** — Path to full BRAIN.md

## Adding a new platform

1. Create `platforms/<name>/` directory
2. Add context file in native format
3. Add `README.md` with setup instructions
4. Add install case to `install.sh`
