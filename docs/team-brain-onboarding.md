# Team Brain — beginner onboarding

**Who this is for:** a junior engineer joining a crew that already uses Team Brain.  
**Time:** about 10 minutes.  
**You do not need:** your own Supabase account, a `service_role` key, or Docker.  
**You do need from your admin:** invite code, Jira key, and the crew’s Supabase **project URL + anon key** (placeholders ship in the repo — not a live project).

---

## What is Team Brain? (30 seconds)

You and your teammates work on the **same Jira ticket** (for example `AAP-81423`).

Without Team Brain, each person’s AI starts cold and re-researches the same things.

With Team Brain, the intended loop is:

1. **You trigger once** — `start <JIRA-KEY>` (enter **sync mode**)  
2. **Crew memory loads** — cache fills; your AI summarizes, *then* digs into code  
3. **While sync is active** — background pull stays merge-safe; AI `remember`s findings  
4. **Idle ~1h** — sync goes to **sleep** (you’ll be prompted); `wake` to resume  
5. **Planning** — `breakdown` turns shared memory into story drafts  

Your personal career notes (`BRAIN.md` / engineer-brain) stay **private**. Team Brain only shares work on the initiative.

### Context-first (what you should feel)

| Moment | What should happen |
|--------|--------------------|
| You start team work on a ticket | You run **`start`** once → memory loads + sync mode on |
| You (or AI) learn something durable | AI **saves immediately** (`remember` + `source_ref`) |
| Same topic, updated finding | **Updates** that memory (no duplicate / no clobber of other refs) |
| You correct bad research | AI **`correct`s** the same `source_ref` (+ optional `learning`) |
| Teammate saved something | Background sync merges into your `cache/` |
| You step away ~1h | Sync **sleeps** — AI should ask you to `wake` |

Enforced strongest in **Cursor** (`team-brain.mdc` + skill + optional MCP).

---

## Before you start — checklist

Ask a teammate (crew admin) for **three things** (Slack/chat is fine):

| Ask for | Example | Notes |
|---------|---------|--------|
| **Invite code** | 16 hex chars | From admin’s `register` — not in the public repo |
| **Jira key** | `AAP-81423` | The ticket you will work on |
| **Supabase URL + anon key** | `https://….supabase.co` + anon JWT | Crew’s project — put in local `supabase/project.public.env` or `.team-brain/team.yaml` |

Also make sure you have:

- [ ] This repo cloned (`engineer-brain`)
- [ ] A terminal (macOS Terminal, iTerm, VS Code/Cursor terminal)
- [ ] `curl` and `jq` installed (`brew install jq` if needed)
- [ ] Placeholders in `supabase/project.public.env` replaced with the crew’s URL + anon (or set env / `team.yaml`)

You do **not** need your own Supabase account or the dashboard.

---

## Path A — Join an existing team (most juniors)

### Step 1 — Open a terminal in the right place

```bash
cd /path/to/engineer-brain
```

Use the real path on your machine (where you cloned the repo).

### Step 1b — Point at the crew’s Supabase project

Edit `supabase/project.public.env` (or export env / fill `.team-brain/team.yaml`) with the URL + anon key your admin shared. Leave placeholders → onboard will fail with a clear error.

### Step 2 — Run one onboard command

Replace the three placeholders with **your** values:

```bash
bash core/scripts/team-brain-api.sh onboard INVITE_CODE "Your Name" JIRA-KEY
```

**Real example:**

```bash
bash core/scripts/team-brain-api.sh onboard 9F7AC910 "Ada Junior" AAP-81423
```

Tips:

- Keep your name in quotes if it has a space: `"Ada Junior"`
- Jira key can be upper or lower case; the tool normalizes it
- Use a **display name that nobody else on the team already used** (duplicates are rejected)

### Step 3 — Check that it worked

```bash
bash core/scripts/team-brain-api.sh whoami
```

You should see JSON with your `display_name`, `team_name`, and `role` (usually `member`).

Then:

```bash
bash core/scripts/team-brain-api.sh status
```

You should see something like:

- `TEAM_DIR=.../.team-brain`
- `CREDENTIALS=... OK`
- `API_KEY=set`

### Step 4 — Find your local files

Team Brain created a folder next to your work (often the parent workspace), for example:

```text
.team-brain/
├── credentials.json    ← YOUR secret — never commit or paste in Slack
├── team.yaml
├── cache/
│   └── AAP-81423.json  ← what agents should read
└── initiatives/
    └── AAP-81423.md    ← optional human-readable export
```

**Safety rule:** never commit `credentials.json`. Never share your `api_key`. Sharing the **invite code** with a new teammate is OK.

---

## Your first day — sync mode

Use the **same Jira key** your crew is on.

### 1) Start sync (the only manual step before work)

```bash
bash core/scripts/team-brain-api.sh start AAP-81423
```

This:

- Loads crew memories into `.team-brain/cache/AAP-81423.json`
- Starts **background sync** (merge-safe pull)
- Stays awake while you/`touch`/`remember`/`recall` stay active
- **Sleeps after 1 hour** of no local activity (warning ~5 min before)

Check:

```bash
bash core/scripts/team-brain-api.sh sync-status AAP-81423
```

Optional topic search anytime:

```bash
bash core/scripts/team-brain-api.sh recall AAP-81423 "scaffold"
```

### 2) Save something useful you learned

Keep it short and professional (a teammate’s AI will see this). Prefer a stable `--source-ref`:

```bash
bash core/scripts/team-brain-api.sh remember AAP-81423 research --source-ref "AAP-81423#cli-entrypoint" "Found CLI entrypoint in pkg/scaffold — start there for EE schema."
```

| Kind | When to use |
|------|-------------|
| `research` | What you discovered in the code/docs |
| `decision` | What the team agreed |
| `note` | Small reminder / link / open question |

Merge rules:

- Same text again → no-op (`deduped`)
- Same `source_ref`, **new** text → **update** that memory (`updated`)
- New `source_ref` → insert

### 3) Draft stories / stop when done

```bash
bash core/scripts/team-brain-api.sh breakdown AAP-81423
bash core/scripts/team-brain-api.sh stop AAP-81423
```

If sync slept: `wake AAP-81423` (or `start` again).

---

## Path B — You are creating the team (admin, once)

Only one person does this for a new crew. **You need a Supabase account** (free tier is fine). Joiners do not.

### Preferred — one-command bootstrap (~10 minutes)

1. Create a project at [supabase.com](https://supabase.com) (skip if using `--local` Docker).
2. From the repo root:

```bash
cd /path/to/engineer-brain
bash core/scripts/team-brain-api.sh bootstrap \
  --team "Team Name" --admin "Your Name" \
  --url "https://YOUR_REF.supabase.co" \
  --anon "eyJ..." \
  --db-url "postgresql://postgres:YOUR_DB_PASSWORD@db.YOUR_REF.supabase.co:5432/postgres" \
  --jira AAP-81423 \
  --write-env
```

3. Copy the printed **share bundle** to Slack (invite + URL + anon + Jira key).  
4. Tell juniors to use **Path A**.

Details / other modes (`--local`, linked CLI, `--skip-migrations`): [supabase/README.md](../supabase/README.md) · `bash core/scripts/team-brain-bootstrap.sh --help`.

**Do not commit** live URL/anon/DB password.

### Manual path (same outcome)

1. Create a project at [supabase.com](https://supabase.com).
2. Copy **Project URL** + **anon** key into local `supabase/project.public.env` (replace placeholders). Set `TEAM_BRAIN_JIRA_SITE`.
3. Apply migrations in timestamp order — see [supabase/README.md](../supabase/README.md) and [migrations/README.md](../supabase/migrations/README.md).
4. Register and share:

```bash
bash core/scripts/team-brain-api.sh register "Team Name" "Your Name"
bash core/scripts/team-brain-api.sh attach AAP-81423 "Short title" "active" "https://your-org.atlassian.net/browse/AAP-81423"
```

> **Note:** New teams get 16-character invite codes. Only admins see the invite via `register` / `whoami` / bootstrap share bundle — joiners’ `credentials.json` does not store it.

---

## How sync actually works (read this)

**Goal:** one trigger → live merge-safe shared AI context for the ticket → sleep when idle.

| Behavior | Status |
|----------|--------|
| **`start`** — one manual entry; load memory + background pull | ✅ |
| **Merge-safe writes** — dedupe identical; update same `source_ref` | ✅ (apply sync-mode migration) |
| **Cache merge** — no blind wipe of other memories on pull | ✅ |
| **Idle sleep + warn** — default 1h; `wake` to resume | ✅ |
| **Agent prompts on sleep** | ✅ Cursor rule/skill |
| **Peer push while sync/`watch` active** | ✅ Signal Broadcast (#31) + poll fallback; needs `start` or `watch` once |
| **Push into open chat with zero `start`** | ❌ Still needs you (or the agent) to enter sync mode once |

**Cursor:** say *“I’m starting on AAP-81423 — start Team Brain sync.”*  
The always-on rule expects `start` → summarize cache → work → `remember` / `touch`.

## Daily habits (keep it simple)

| When | What happens |
|------|----------------|
| **Starting work on the ticket** | `start JIRA-KEY` (once) |
| You / AI learned something durable | `remember` with `source_ref` |
| AI got research wrong — you correct it | `correct` (or re-`remember` same `source_ref`) |
| Keep sync awake | automatic via recall/remember; or `touch` |
| Sync slept | Prompt → `wake JIRA-KEY` |
| Done for the day | `stop JIRA-KEY` |
| Planning stories / spikes | `breakdown JIRA-KEY` |
| “Am I connected?” | `whoami` / `sync-status` |

### Correcting bad research (important)

Agents can be wrong. When you paste a correction, the AI should **update** the matching memory (same `source_ref`) — not leave a stale row and not invent a second topic slug.

```bash
bash core/scripts/team-brain-api.sh correct AAP-81423 --source-ref "AAP-81423#cli-schema" \
  --was "Claimed schema lived in tox-ansible" \
  "EE schema path lives in packages/ansible-language-server."
```

Optional `--learning "Was wrong: … Prefer: …"` writes a `learning` row at `source_ref/learning`.  
Memory bodies should be natural prefer/avoid guidance — not TODO/NO-TODO lists.

Each `source_ref` update **archives** the prior body. Inspect or soft-rollback:

```bash
bash core/scripts/team-brain-api.sh history AAP-81423 --source-ref "AAP-81423#cli-schema"
bash core/scripts/team-brain-api.sh restore AAP-81423 --source-ref "AAP-81423#cli-schema" --revision 1
```

`restore` keeps the audit trail (current body is archived before rollback).

In Cursor you can say:

```text
Correct Team Brain for AAP-81423#cli-schema — the schema is in packages/ansible-language-server, not tox-ansible.
```

```text
Show Team Brain history for AAP-81423#cli-schema and restore revision 1 if needed.
```

Apply once on the crew Supabase project:

- `20260802000001_team_brain_learning_kind.sql` — `learning` kind  
- `20260803000001_team_brain_memory_history.sql` — revisions + history/restore

---

## Using Cursor (recommended for the context-first loop)

Install into your workspace once:

```bash
bash install.sh cursor /path/to/your/workspace
```

That installs:

- `team-brain.mdc` — always-on: **recall before research**, **remember after findings**, soft `compliance` gate
- `team-brain` skill — chat commands (+ `compliance` / MCP `prepare_research`)

### Start-of-ticket (do this every time)

Paste into Cursor chat / Composer (pick one):

```text
I'm starting on AAP-81423 — start Team Brain sync.
```

```text
I'm starting on AAP-81423 — start Team Brain sync, summarize crew memory, then help me.
```

```text
/team-brain start AAP-81423
```

Other useful lines:

| When | Say this |
|------|----------|
| Keep working after a break | `Wake Team Brain sync for AAP-81423 and continue.` |
| Done for the day | `Stop Team Brain sync for AAP-81423.` |
| Check state | `What's my Team Brain sync-status for AAP-81423?` |
| Compliance | `What's Team Brain compliance for AAP-81423?` |
| Plan stories | `Breakdown AAP-81423 from Team Brain memory.` |
| Fix bad research | `Correct Team Brain for AAP-81423#<slug> — …` |

Then work. After findings the AI should `remember` (and `touch`) without you asking.  
If `compliance.agent_action` is set, the agent should follow it before deep research.  
If you correct it, it should `correct` / re-`remember` the same `source_ref`.  
If sync sleeps, it should ask before continuing.  
Personal `BRAIN.md` stays private — never upload it to Team Brain.

### MCP tools (advanced)

If your team wired the `team-brain` MCP server, your agent can call `attach` / `remember` / `recall` / `breakdown` as tools.  
Setup: [mcp/team-brain/README.md](../mcp/team-brain/README.md).  
Juniors can ignore MCP and use the bash commands or Cursor skill.

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| `missing dependency: jq` | `brew install jq` (macOS) |
| `unauthorized` / RPC failed | Re-run `whoami`. If still broken, ask admin for a fresh invite and `onboard` again with a **new display name** |
| `member already exists` | Pick a different `"Your Name"` (must be unique on the team) |
| `initiative not found — attach first` | `attach JIRA-KEY` or include the key in `onboard … KEY` |
| `TEAM_DIR` points somewhere weird | `export TEAM_BRAIN_DIR="$PWD/.team-brain"` from your workspace, then retry |
| Nothing in `recall` | Nobody has `remember`’d yet — add the first finding yourself |
| Afraid you committed secrets | Check `git status` — `credentials.json` must stay untracked. If it was committed, tell a senior immediately |

---

## What not to do

- Do not paste your `api_key` or `credentials.json` into Slack, PRs, or screenshots
- Do not put personal career / performance notes into Team Brain
- Do not treat the markdown file as the source of truth — **Supabase + `cache/`** are; md is a convenience export
- Do not invent an epic breakdown without running `recall` / `breakdown` first

---

## Quick command cheat sheet

```bash
# Join
bash core/scripts/team-brain-api.sh onboard <INVITE> "Your Name" <JIRA-KEY>

# Check
bash core/scripts/team-brain-api.sh whoami
bash core/scripts/team-brain-api.sh status

# Work session (CLI)
bash core/scripts/team-brain-api.sh start <JIRA-KEY>
bash core/scripts/team-brain-api.sh sync-status <JIRA-KEY>
bash core/scripts/team-brain-api.sh remember <JIRA-KEY> research --source-ref "<KEY>#slug" "Finding…"
bash core/scripts/team-brain-api.sh breakdown <JIRA-KEY>
bash core/scripts/team-brain-api.sh stop <JIRA-KEY>

# Sleep / wake
bash core/scripts/team-brain-api.sh wake <JIRA-KEY>
bash core/scripts/team-brain-api.sh touch <JIRA-KEY>
bash core/scripts/team-brain-api.sh metrics <JIRA-KEY>

# Or in Cursor chat:
#   I'm starting on AAP-81423 — start Team Brain sync.
#   Wake Team Brain sync for AAP-81423 and continue.
#   Stop Team Brain sync for AAP-81423.
```

---

## Next reading (when you are ready)

- [team-brain.md](team-brain.md) — how sync layers fit together  
- [team-brain-memory.md](team-brain-memory.md) — full product plan  
- [supabase/README.md](../supabase/README.md) — admin / new project setup  
