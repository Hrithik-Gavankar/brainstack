---
sidebar_position: 1
slug: /introduction
---

# Introduction

**Engineer Brain** is a persistent engineering context layer for AI coding assistants.

## The Problem

AI coding assistants understand code. They don't understand *engineers*.

Every session starts from zero. Your AI doesn't know your expertise, your active projects, your team conventions, or your career trajectory. You re-explain context dozens of times a day across multiple tools.

## The Solution

Engineer Brain creates a **versioned engineering profile** — stored as a simple Markdown file called `BRAIN.md` — that follows you across every AI coding assistant you use.

It's not another AI tool. It's a **context layer** that makes every AI tool better.

**Team Brain** (opt-in) adds collaborative AI memory for a crew on the same Jira initiative — Supabase as source of truth, local cache for agents, MCP + Cursor agent loop.

## Key Principles

- **Portable** — Same brain across 6+ platforms
- **Self-updating** — Refreshes from your git history
- **Private by default** — Personal `BRAIN.md` stays local; Team Brain is explicit opt-in
- **Open** — MIT licensed, community-driven

## What You Get

| Command | Output |
|---------|--------|
| `engineer-brain sync` | Paste-ready standup notes |
| `engineer-brain update` | Refreshed BRAIN.md with latest data |
| `engineer-brain quarterly` | Structured quarterly review |
| `engineer-brain reflect` | Pattern analysis and recommendations |
| `team-brain onboard` / `remember` / `recall` | Join crew + shared initiative memory |
| `team-brain breakdown` | Story/spike draft from recalled memories |

## Next Steps

- [Quick Start](./quick-start.md) — Install in 5 minutes
- [Brain scopes](./scopes.md) — Personal vs team
- [BRAIN.md Spec](./concepts/brain-spec.md) — Understand the format
- [Architecture](./architecture.md) — How it works under the hood
