---
name: team-brain
description: >-
  Team / initiative shared AI memory. User triggers once with start; then
  sync mode pulls crew memory and agents remember findings (merge-safe).
  Invoke for team-brain, start, stop, wake, sync, shared spike, initiative,
  Jira crew work, remember, recall, breakdown (not personal standups).
argument-hint: >-
  <command> — start | stop | wake | touch | sync-status | onboard | register |
  join | whoami | init | attach | remember | recall | capture | sync | watch |
  breakdown | status | detach
tools: Read, Write, Shell, Glob, Grep
---

# Team Brain — Sync Mode

Part of **Brain**: personal=`engineer-brain`, crew=`team-brain`.

| Prefer | Fallback |
|--------|----------|
| MCP `start` / `recall` / `remember` / `touch` | `bash …/team-brain-api.sh …` |

```bash
API="${SKILL_DIR}/scripts/team-brain-api.sh"
# or: <engineer-brain-repo>/core/scripts/team-brain-api.sh
```

---

## Product loop (what the engineer does)

1. **One manual step** — start sync for the ticket  
2. **Automatic while active** — background pull into cache; you summarize + work  
3. **Save findings** — `remember` with `source_ref` (merge-safe)  
4. **Idle sleep** — after ~1h no activity, sync sleeps; prompt user to `wake`

---

## 1) START (when user begins team work)

User will often say things like:

```text
I'm starting on AAP-81423 — start Team Brain sync.
I'm starting on AAP-81423 — start Team Brain sync, summarize crew memory, then help me.
/team-brain start AAP-81423
Wake Team Brain sync for AAP-81423 and continue.
Stop Team Brain sync for AAP-81423.
```

Run:

```bash
bash "$API" start <JIRA-KEY>
bash "$API" sync-status <JIRA-KEY>
```

Then read `.team-brain/cache/<JIRA-KEY>.json`, summarize crew memory, **then** explore.

If already `active`, `touch` and read cache (optional `recall` for a topic).

If `sleep`, tell the user and run `wake` only after they agree (or if they asked to continue).

## 2) WHILE WORKING

Each turn on this key:

```bash
bash "$API" touch <JIRA-KEY>
```

After durable findings:

```bash
bash "$API" remember <JIRA-KEY> research --source-ref "<JIRA-KEY>#<short-slug>" "<finding>"
```

Merge rules (server):

| Case | Result |
|------|--------|
| New finding | insert |
| Same body / hash | `deduped` no-op |
| Same `source_ref`, new body | `updated` (merge — no second row) |

## 3) STOP / SLEEP

```bash
bash "$API" stop <JIRA-KEY>     # leave sync mode
bash "$API" wake <JIRA-KEY>     # resume after sleep
```

When `sync-status` shows `sleep`, **prompt the user** before continuing deep work.

## 4) Breakdown

```bash
bash "$API" breakdown <JIRA-KEY>
```

Never invent stories without recalled memories.

---

## Commands

| Command | Purpose |
|---------|---------|
| `start` | **Enter sync mode** — load memory + background pull |
| `stop` / `wake` / `touch` | Leave / resume / keep awake |
| `sync-status` | active \| sleep \| stopped |
| `onboard` / `register` / `join` | Membership |
| `attach` | Bind Jira key |
| `recall` / `remember` | Search / save |
| `breakdown` / `metrics` / `status` | Plan / stats / config |

Beginner guide: `docs/team-brain-onboarding.md`

## Hard rules

- User’s one step: **`start`** (or ask you to start)
- Context first from cache before research
- `remember` with `source_ref`; never clobber unrelated rows
- Prompt on sleep; never commit `credentials.json`
