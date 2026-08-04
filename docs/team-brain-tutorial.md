# Team Brain — Hands-On Tutorial

**End-to-end walkthrough: from zero to shared AI memory.**

Time: 15–20 minutes  
Prerequisites: terminal, `curl`, `jq`, and either Docker (local) or a free Supabase account (hosted)

---

## Choose Your Path

| Path | Who | Time | Requirements |
|------|-----|------|--------------|
| **A. Admin (owner)** | Setting up a new crew | 10 min | Supabase account or Docker |
| **B. Joiner (CLI)** | Joining an existing crew | 5 min | Invite from admin |
| **C. MCP-only** | AI-first workflow | 5 min | MCP client (Cursor, Claude Code) |

Pick one path and follow it through. The walkthrough uses a demo Jira key `DEMO-1`.

---

## Path A: Admin — Create a New Crew

### Step 1: Choose your setup

**Option 1: Local Docker (fastest for trying out)**

```bash
cd /path/to/brainstack

# Start local Supabase
supabase start

# Bootstrap with local mode
bash core/scripts/team-brain-api.sh bootstrap \
  --team "Tutorial Crew" --admin "Alice" \
  --local --jira DEMO-1
```

**Option 2: Hosted Supabase (production-like)**

1. Create a project at [supabase.com](https://supabase.com) (free tier works)
2. Get your **Project URL**, **anon key**, and **DB password** from Settings → API

```bash
cd /path/to/brainstack

bash core/scripts/team-brain-api.sh bootstrap \
  --team "Tutorial Crew" --admin "Alice" \
  --url "https://YOUR_REF.supabase.co" \
  --anon "eyJ..." \
  --db-url "postgresql://postgres:YOUR_DB_PASSWORD@db.YOUR_REF.supabase.co:5432/postgres" \
  --jira DEMO-1 \
  --write-env
```

### Step 2: Verify setup

```bash
bash core/scripts/team-brain-api.sh whoami
```

Expected output:
```json
{
  "display_name": "Alice",
  "role": "admin",
  "team_name": "Tutorial Crew",
  "invite_code": "ABC123..."
}
```

### Step 3: Save the share bundle

Bootstrap prints a share bundle. Copy it:

```
=== SHARE BUNDLE (copy to Slack/chat) ===
Team: Tutorial Crew
Invite: ABC123DEF456GH78
URL: https://....supabase.co
Anon: eyJ...
Jira: DEMO-1
```

**Keep this safe** — teammates need the invite + URL + anon to join.

### Step 4: Create a commit-safe pin

```bash
bash core/scripts/team-brain-api.sh pin set --jira DEMO-1 --team-name "Tutorial Crew"
cat .team-brain/project.json
```

This file is safe to commit (no secrets). Teammates can pull it for the Jira key.

### Step 5: Start sync and remember something

```bash
bash core/scripts/team-brain-api.sh start DEMO-1
bash core/scripts/team-brain-api.sh sync-status DEMO-1
```

Now save your first memory:

```bash
bash core/scripts/team-brain-api.sh remember DEMO-1 research \
  --source-ref "DEMO-1#setup" \
  "Tutorial Crew is using Team Brain for DEMO-1. Alice is admin."
```

Expected: `"result": "inserted"` or `"result": "deduped"` if you run it again.

### Step 6: Check it worked

```bash
bash core/scripts/team-brain-api.sh recall DEMO-1
```

You should see your memory in the list.

**Checkpoint A complete.** Skip to [Verification Checklist](#verification-checklist).

---

## Path B: Joiner — Join an Existing Crew

Your admin shared: invite code, Supabase URL + anon key, and Jira key.

### Step 1: Set up environment

```bash
cd /path/to/brainstack

# Option 1: Environment variables
export TEAM_BRAIN_SUPABASE_URL="https://....supabase.co"
export TEAM_BRAIN_SUPABASE_ANON_KEY="eyJ..."

# Option 2: Edit project.public.env
# nano supabase/project.public.env
# → Replace placeholders with URL + anon from admin
```

### Step 2: Onboard

```bash
# Replace with your invite and name
bash core/scripts/team-brain-api.sh onboard ABC123DEF456GH78 "Bob" DEMO-1
```

Expected output includes:
```json
{
  "display_name": "Bob",
  "role": "member",
  "team_name": "Tutorial Crew"
}
```

### Step 3: Verify

```bash
bash core/scripts/team-brain-api.sh whoami
bash core/scripts/team-brain-api.sh status
```

### Step 4: Start sync and recall

```bash
bash core/scripts/team-brain-api.sh start DEMO-1
bash core/scripts/team-brain-api.sh recall DEMO-1
```

You should see memories from your admin (Alice).

### Step 5: Remember something

```bash
bash core/scripts/team-brain-api.sh remember DEMO-1 research \
  --source-ref "DEMO-1#bob-joined" \
  "Bob joined and confirmed Team Brain is working."
```

### Step 6: Breakdown

```bash
bash core/scripts/team-brain-api.sh breakdown DEMO-1
```

This generates a draft epic breakdown from all shared memories.

**Checkpoint B complete.** Skip to [Verification Checklist](#verification-checklist).

---

## Path C: MCP-Only — AI-First Workflow

For Cursor, Claude Code, or other MCP-compatible clients.

### Step 1: Ensure Team Brain MCP is configured

In Cursor, check your MCP settings (`.cursor/mcp.json` or global):

```json
{
  "servers": {
    "team-brain": {
      "command": "python",
      "args": ["/path/to/brainstack/mcp/team-brain/server.py"],
      "env": {
        "TEAM_BRAIN_SUPABASE_URL": "https://....supabase.co",
        "TEAM_BRAIN_SUPABASE_ANON_KEY": "eyJ..."
      }
    }
  }
}
```

### Step 2: Onboard via MCP

In chat, say:

```
Use Team Brain MCP to onboard me with invite ABC123DEF456GH78, name "Carol", on DEMO-1.
```

Or if already onboarded:

```
Use Team Brain MCP to attach DEMO-1.
```

### Step 3: Start sync

```
I'm starting on DEMO-1 — start Team Brain sync.
```

The AI should:
1. Call `start` MCP tool
2. Summarize existing memories
3. Enter sync mode

### Step 4: Let AI remember

Work naturally. When the AI finds something useful, it should call `remember`:

```
Found: the API uses JWT tokens from /auth/login endpoint.
```

AI response:
```
I'll save this to Team Brain.
[Calls remember MCP tool with source_ref "DEMO-1#auth-api"]
```

### Step 5: Recall context

```
What does Team Brain know about DEMO-1?
```

AI calls `recall` and summarizes.

### Step 6: Breakdown

```
Generate a breakdown for DEMO-1 from Team Brain memory.
```

**Checkpoint C complete.** Continue to Verification Checklist.

---

## Verification Checklist

Run through this checklist to confirm everything works.

### Basic connectivity

- [ ] `whoami` returns your display name and role
- [ ] `status` shows `CREDENTIALS=... OK`

```bash
bash core/scripts/team-brain-api.sh whoami
bash core/scripts/team-brain-api.sh status
```

### Sync mode

- [ ] `start DEMO-1` succeeds
- [ ] `sync-status DEMO-1` shows `mode: active`
- [ ] Cache file exists: `.team-brain/cache/DEMO-1.json`

```bash
bash core/scripts/team-brain-api.sh start DEMO-1
bash core/scripts/team-brain-api.sh sync-status DEMO-1
ls -la .team-brain/cache/
```

### Memory operations

- [ ] `remember` inserts a new memory
- [ ] `remember` with same content returns `deduped`
- [ ] `remember` with same `source_ref` but new content returns `updated`
- [ ] `recall` returns memories

```bash
# Insert
bash core/scripts/team-brain-api.sh remember DEMO-1 note \
  --source-ref "DEMO-1#test1" "Test memory 1"

# Dedupe (same content)
bash core/scripts/team-brain-api.sh remember DEMO-1 note \
  --source-ref "DEMO-1#test1" "Test memory 1"

# Update (same source_ref, new content)
bash core/scripts/team-brain-api.sh remember DEMO-1 note \
  --source-ref "DEMO-1#test1" "Updated test memory 1"

# Recall
bash core/scripts/team-brain-api.sh recall DEMO-1 "test"
```

### Cross-user (if you have a teammate)

- [ ] Teammate's `remember` shows up in your `recall`
- [ ] Your `remember` shows up in teammate's `recall`

### Correction / history

- [ ] `correct` updates a memory
- [ ] `history` shows prior versions
- [ ] `restore` recovers an old version

```bash
bash core/scripts/team-brain-api.sh correct DEMO-1 \
  --source-ref "DEMO-1#test1" \
  --was "Old understanding" \
  "Corrected understanding"

bash core/scripts/team-brain-api.sh history DEMO-1 --source-ref "DEMO-1#test1"
```

### Breakdown

- [ ] `breakdown DEMO-1` generates markdown
- [ ] Output file exists: `.team-brain/initiatives/DEMO-1-breakdown.md`

```bash
bash core/scripts/team-brain-api.sh breakdown DEMO-1
cat .team-brain/initiatives/DEMO-1-breakdown.md
```

### Cleanup

- [ ] `stop DEMO-1` stops sync mode

```bash
bash core/scripts/team-brain-api.sh stop DEMO-1
bash core/scripts/team-brain-api.sh sync-status DEMO-1
# → mode: stopped
```

---

## Optional: Watch for Peer Updates

During long sessions, keep sync fresh (same guidance as onboarding + Cursor skill #37):

```bash
# Background watch (poll mode) — once per long spike, not every command
bash core/scripts/team-brain-api.sh watch DEMO-1 &

# Or with push (requires Realtime migration)
bash core/scripts/team-brain-api.sh watch DEMO-1 --push &
```

When teammates `remember`, your cache updates. Agents should also `recall` after long research blocks / ~every 8–10 turns — without nagging every turn. If sync **slept**, `wake` (or `start`); `watch` is not a substitute.

---

## Optional: Roles Demo

### Admin: rotate invite

```bash
bash core/scripts/team-brain-api.sh rotate-invite
# → New invite code printed
```

### Admin: set role

```bash
bash core/scripts/team-brain-api.sh set-role "Bob" --role viewer
# Bob can now only recall, not remember
```

### Viewer: try to remember (should fail)

```bash
# As a viewer:
bash core/scripts/team-brain-api.sh remember DEMO-1 note "Test"
# → Error: forbidden: viewer role is read-only
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `unauthorized` | Re-run `whoami`. If broken, re-onboard with new display name |
| `initiative not found` | Run `attach DEMO-1` first, or include key in onboard |
| `member already exists` | Choose a different display name |
| Empty `recall` | Nobody has `remember`ed yet — add the first memory |
| `rate limit exceeded` | Wait 1 hour or ask admin to check rate limit settings |

---

## Next Steps

- [Beginner onboarding](team-brain-onboarding.md) — detailed setup guide
- [Demo & Office Hours](team-brain-demo.md) — one-pager for presenting
- [Memory architecture](team-brain-memory.md) — how sync + merge work
- [MCP server](../mcp/team-brain/README.md) — AI tool integration
- [Example project](../examples/team-spike-crew/) — fixture for testing

---

## Quick Reference

```bash
# Join
bash core/scripts/team-brain-api.sh onboard <INVITE> "Name" <JIRA-KEY>

# Work session
bash core/scripts/team-brain-api.sh start <JIRA-KEY>
bash core/scripts/team-brain-api.sh remember <JIRA-KEY> research --source-ref "<KEY>#slug" "Finding"
bash core/scripts/team-brain-api.sh recall <JIRA-KEY> "search term"
bash core/scripts/team-brain-api.sh breakdown <JIRA-KEY>
bash core/scripts/team-brain-api.sh stop <JIRA-KEY>

# Check state
bash core/scripts/team-brain-api.sh whoami
bash core/scripts/team-brain-api.sh sync-status <JIRA-KEY>
bash core/scripts/team-brain-api.sh metrics <JIRA-KEY>

# Cursor chat
"I'm starting on AAP-81423 — start Team Brain sync."
"Remember: CLI entrypoint is in pkg/scaffold."
"What does Team Brain know about scaffold?"
"Breakdown AAP-81423 from Team Brain memory."
```

---

*Tutorial complete. You're ready to use Team Brain with your crew.*
