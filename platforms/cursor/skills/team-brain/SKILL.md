---
name: team-brain
description: >-
  Team / initiative shared AI memory. MUST run before research on a Jira key
  (recall/sync crew memory) and after findings (remember for teammates).
  Invoke for team-brain, shared spike, initiative context, Jira crew work,
  "what does the team know", remember, recall, breakdown, or when exploring
  code for an attached ticket (not personal standups).
argument-hint: >-
  <command> — onboard | register | join | whoami | init | attach | remember |
  recall | capture | sync | watch | breakdown | status | detach
tools: Read, Write, Shell, Glob, Grep
---

# Team Brain — Shared AI Memory (agent loop)

Part of **Brain**: personal=`engineer-brain`, crew=`team-brain`.

| Prefer | Fallback |
|--------|----------|
| MCP tools `team-brain_*` / `recall` / `remember` | `bash …/team-brain-api.sh …` |

Scripts:

```bash
API="${SKILL_DIR}/scripts/team-brain-api.sh"
# or: <engineer-brain-repo>/core/scripts/team-brain-api.sh
```

---

## THE AGENT LOOP (non-negotiable)

This is the product. Manual CLI is the escape hatch — **agents must run this loop**.

### 1) BEFORE researching (sync memory)

When the user starts work on a Jira key, asks you to explore/implement for an initiative, or you are about to search the codebase for that work:

1. Resolve the active key (from user, `.team-brain/team.yaml`, or ask once).
2. **Sync first** — do not explore yet:

```bash
bash "$API" recall <JIRA-KEY>
# If they named a topic, also:
bash "$API" recall <JIRA-KEY> "<topic keywords>"
```

3. Read `.team-brain/cache/<JIRA-KEY>.json` if present.
4. Tell the user in 2–5 bullets: what the crew already knows / decided / left open.
5. **Only then** dig into the repo. Reuse paths and decisions from memory.

If `recall` fails (not onboarded), say so and offer `onboard` / `attach` — do not silently skip.

### 2) AFTER researching (direct save)

As soon as you have a durable finding (entrypoint, constraint, decision, “start here”, failed approach):

1. **Save immediately** — do not wait for “please remember this”:

```bash
bash "$API" remember <JIRA-KEY> research --source-ref "<JIRA-KEY>#<short-slug>" "<one or two sentence finding>"
# decisions:
bash "$API" remember <JIRA-KEY> decision --source-ref "<JIRA-KEY>#dec-<slug>" "<what we decided and why>"
```

2. Use a stable `source_ref` so Ada and Bob do not double-write the same crunch.
3. Confirm briefly: “Saved to Team Brain for the crew.”

Save **during** the turn you learned it — not in a later cleanup pass.

### 3) Planning / breakdown

```bash
bash "$API" breakdown <JIRA-KEY>
```

Never invent an epic breakdown without recalled memories.

---

## Parallel laptops (why this exists)

| Without the loop | With the loop |
|------------------|---------------|
| Both engineers re-research; nothing shared | First finding is `remember`’d; second agent `recall`s before digging |
| Chat-only context dies with the session | Supabase + cache survive across machines |

`watch` (optional second terminal) keeps cache fresh; the **loop** is still required inside the agent.

---

## Commands (human / fallback)

| Command | Purpose |
|---------|---------|
| `onboard` / `register` / `join` | Membership |
| `attach` | Bind Jira key (also pulls recent memories) |
| `recall` | **Sync before research** |
| `remember` | **Save after research** |
| `breakdown` | Stories from memories |
| `watch` / `metrics` / `status` | Live poll / stats / config |

Beginner guide: `docs/team-brain-onboarding.md`

---

## Hard rules

- **Recall before research** on a known Jira key
- **Remember after findings** with `source_ref`
- Never commit `credentials.json` or publish personal `BRAIN.md`
- Concise professional memories only
- Cache/JSON is agent SoT; markdown is export

## Related

- Always-on rule: `platforms/cursor/rules/team-brain.mdc`
- Plan: `docs/team-brain-memory.md`
- MCP: `mcp/team-brain/README.md`
