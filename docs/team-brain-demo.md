# Team Brain — Demo & Office Hours

**One-pager for AT-AT, Office Hours, and social sharing.**

---

## What is Team Brain?

**Team Brain** is collaborative AI memory for engineering crews working on the same Jira ticket.

Without Team Brain, each engineer's AI starts cold — re-researching the same things, missing context from teammates, and duplicating work.

With Team Brain, knowledge compounds:

```
┌─────────────────────────────────────────────────────────────┐
│   Alice (AI)              Bob (AI)              Carol (AI)  │
│      ↓                       ↓                      ↓       │
│   remember ──────────────────┼──────────────────────┘       │
│      │                       │                              │
│      └──────────> Shared Memory <───────── recall ─────────┘│
│                  (Supabase)                                 │
└─────────────────────────────────────────────────────────────┘
```

## The Demo Flow (3 minutes)

### 1. Start sync (one manual trigger)

```bash
# In Cursor chat:
"I'm starting on AAP-81423 — start Team Brain sync."
```

What happens:
- Loads crew memories into local cache
- Background sync keeps you in sync with teammates
- AI summarizes existing knowledge before diving in

### 2. AI researches → remembers

```bash
# AI finds something useful:
bash core/scripts/team-brain-api.sh remember AAP-81423 research \
  --source-ref "AAP-81423#cli-entrypoint" \
  "CLI entrypoint is in pkg/scaffold — start here for EE schema."
```

- Findings persist for the whole crew
- Merge-safe: same `source_ref` updates (no duplicates)

### 3. Teammate recalls

```bash
# Bob's AI pulls the knowledge:
bash core/scripts/team-brain-api.sh recall AAP-81423 "scaffold"
```

Result:
```json
{
  "total": 1,
  "memories": [{
    "author": "Alice",
    "body": "CLI entrypoint is in pkg/scaffold — start here for EE schema.",
    "source_ref": "AAP-81423#cli-entrypoint"
  }]
}
```

### 4. Breakdown into stories

```bash
bash core/scripts/team-brain-api.sh breakdown AAP-81423
```

Generates a draft epic breakdown from shared memory — stories, spikes, implementation hints.

---

## Key Features

| Feature | What it does |
|---------|--------------|
| **Sync mode** | One trigger → live shared context |
| **Merge-safe writes** | Same `source_ref` = update, not duplicate |
| **Idle sleep + wake** | Conserves resources; prompts to resume |
| **Peer push** | Signal broadcast when teammates `remember` |
| **Roles** | Admin / member (write) / viewer (read-only) |
| **Correction loop** | Fix bad research → learning memory |
| **History / rollback** | Soft restore prior findings |
| **MCP tools** | Native AI tool access (Cursor, Claude Code) |

---

## Who It's For

| Role | Benefit |
|------|---------|
| **Junior engineer** | Onboard in 10 minutes; instant context from seniors |
| **Senior engineer** | Never re-explain the same finding twice |
| **Tech lead** | `breakdown` turns research into stories |
| **AI agent** | Recall before research; remember after findings |

---

## Security Highlights

- API keys hashed (SHA-256) — never plaintext
- No anon SELECT on memory content
- Rate-limited register/join (default 5 reg/h, 15 join/h)
- Role-based write gates (viewers = read-only)
- Invite codes 16 hex chars; admin-only rotate

---

## Quick Start

**Admin (once per crew):**
```bash
bash core/scripts/team-brain-api.sh bootstrap \
  --team "Spike Crew" --admin "Alice" \
  --url "https://….supabase.co" --anon "eyJ…" \
  --db-url "postgresql://…" --jira AAP-81423 --write-env
```

**Teammate:**
```bash
bash core/scripts/team-brain-api.sh onboard <INVITE> "Bob" AAP-81423
```

**Work session:**
```
I'm starting on AAP-81423 — start Team Brain sync.
```

---

## Demo Assets

### Terminal Demo Script

```bash
# Demo: Team Brain in 60 seconds

# 1. Alice remembers
bash core/scripts/team-brain-api.sh remember DEMO-1 research \
  --source-ref "DEMO-1#api-auth" \
  "API uses bearer tokens from /auth/token endpoint."

# 2. Bob recalls
bash core/scripts/team-brain-api.sh recall DEMO-1 "auth"

# 3. Carol joins and gets context
bash core/scripts/team-brain-api.sh onboard ABC123 "Carol" DEMO-1
bash core/scripts/team-brain-api.sh start DEMO-1
# → AI summarizes: "Auth uses bearer tokens from /auth/token..."

# 4. Breakdown
bash core/scripts/team-brain-api.sh breakdown DEMO-1
```

### Cursor Chat Demo

```
User: I'm starting on AAP-81423 — start Team Brain sync.

AI: ✓ Loaded 3 crew memories for AAP-81423.

Summary:
• CLI entrypoint in pkg/scaffold (Alice)
• EE schema validation via ansible-language-server (Bob)
• Watch for deprecated executionEnvironment fields (Alice, corrected)

Ready to dig in. What would you like to work on?
```

### Screenshot Sequence (for GIF)

1. **Start** — Chat shows "start Team Brain sync"
2. **Memory loads** — AI summarizes 2-3 bullet points
3. **Remember** — AI saves a finding with `source_ref`
4. **Peer recall** — Second terminal shows teammate's finding
5. **Breakdown** — Story draft markdown generated

> **Note:** GIF asset to be recorded and added to `docs/assets/team-brain-demo.gif`.  
> Placeholder: run the terminal demo script above for live demos.

---

## Links

- [Beginner onboarding](team-brain-onboarding.md)
- [Tutorial walkthrough](team-brain-tutorial.md)
- [Memory architecture](team-brain-memory.md)
- [Supabase setup](../supabase/README.md)
- [MCP server](../mcp/team-brain/README.md)
- [Example fixture](../examples/team-spike-crew/)

---

## Office Hours Talking Points

1. **Why not just Confluence / Notion?**
   - Those are for humans. Team Brain is for AI agents.
   - Structured memories, not prose documents.

2. **Why not just share BRAIN.md?**
   - `BRAIN.md` is personal (career, growth).
   - Team Brain is initiative-scoped (AAP-81423 work only).

3. **What about privacy?**
   - Each crew runs their own Supabase project.
   - No anon access to memory content — even the realtime push body travels app-layer encrypted (per-team key), never plaintext, never decrypted by the DB.
   - Role-based: viewers can read but not write.

4. **Does it work with Claude Code / VS Code?**
   - MCP server works with any MCP-compatible client.
   - CLI works everywhere (`bash`, `zsh`, any terminal).

5. **How do I try it?**
   - Local Docker: `bootstrap --local`
   - Hosted: free Supabase tier is enough

---

*Built for the Ansible DevTools team. MIT licensed.*
