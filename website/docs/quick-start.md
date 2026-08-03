---
sidebar_position: 2
slug: /quick-start
---

# Quick Start

Get Engineer Brain running in 5 minutes.

## Prerequisites

- Git repositories in your workspace
- Bash (macOS or Linux)
- Any supported AI coding assistant

## Install

```bash
git clone https://github.com/Hrithik-Gavankar/brainstack.git
cd brainstack
bash install.sh <platform> [workspace_path]
```

### Choose your platform

```bash
bash install.sh cursor ~/my-workspace
bash install.sh claude-code ~/my-workspace
bash install.sh vscode-copilot ~/my-workspace
bash install.sh windsurf ~/my-workspace
bash install.sh aider ~/my-workspace
bash install.sh continue-dev ~/my-workspace
```

## Configure

### 1. Fill in your identity

Open the installed context file and fill in:
- Your name and role
- Your skills and career goal
- Your workspace layout

### 2. Auto-populate from git

Open your AI assistant and run:

```
engineer-brain update
```

This scans your git history and auto-populates BRAIN.md with your expertise, patterns, and active repos.

## Use

```
"engineer-brain sync"        → before standup
"engineer-brain reflect"     → Friday afternoons
"engineer-brain update"      → start of each month
"engineer-brain quarterly"   → before performance reviews
```

### Optional — Team Brain

If your crew shared an invite code, Jira key, and Supabase URL + anon (fill local `project.public.env`):

```bash
bash core/scripts/team-brain-api.sh onboard <INVITE> "Your Name" AAP-81423
```

Then in Cursor (one line to start crew work):

```text
I'm starting on AAP-81423 — start Team Brain sync.
```

```text
I'm starting on AAP-81423 — start Team Brain sync, summarize crew memory, then help me.
```

Junior guide: [team-brain-onboarding.md](https://github.com/Hrithik-Gavankar/brainstack/blob/main/docs/team-brain-onboarding.md).

## Verify it works

After running `engineer-brain update`, ask your AI assistant:

> "What are my strongest technical areas?"

It should answer based on your BRAIN.md — referencing your actual skills and commit history, not generic responses.
