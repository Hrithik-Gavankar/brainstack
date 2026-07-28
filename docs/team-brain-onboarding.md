# Team Brain — beginner onboarding

**Who this is for:** a junior engineer joining a crew that already uses Team Brain.  
**Time:** about 10 minutes.  
**You do not need:** a Supabase account, API keys from a dashboard, or Docker.

---

## What is Team Brain? (30 seconds)

You and your teammates work on the **same Jira ticket** (for example `AAP-81423`).

Without Team Brain, each person’s AI starts cold and re-researches the same things.

With Team Brain:

1. Someone saves a finding once (`remember`)
2. Everyone else can load it (`recall`)
3. You can turn findings into a story draft (`breakdown`)

Your personal career notes (`BRAIN.md` / engineer-brain) stay **private**. Team Brain only shares work on the initiative.

---

## Before you start — checklist

Ask a teammate for **two things** (Slack/chat is fine):

| Ask for | Example | Notes |
|---------|---------|--------|
| **Invite code** | `9F7AC910` or longer | Not a password for the whole company — just your crew |
| **Jira key** | `AAP-81423` | The ticket you will work on |

Also make sure you have:

- [ ] This repo cloned (`engineer-brain`)
- [ ] A terminal (macOS Terminal, iTerm, VS Code/Cursor terminal)
- [ ] `curl` and `jq` installed (`brew install jq` if needed)

You do **not** need the Supabase dashboard.

---

## Path A — Join an existing team (most juniors)

### Step 1 — Open a terminal in the right place

```bash
cd /path/to/engineer-brain
```

Use the real path on your machine (where you cloned the repo).

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

## Your first day — three commands

Use the **same Jira key** your crew is on.

### 1) Load what the team already knows

```bash
bash core/scripts/team-brain-api.sh recall AAP-81423
```

Optional — search for a topic:

```bash
bash core/scripts/team-brain-api.sh recall AAP-81423 "scaffold"
```

### 2) Save something useful you learned

Keep it short and professional (a teammate’s AI will see this):

```bash
bash core/scripts/team-brain-api.sh remember AAP-81423 research "Found CLI entrypoint in pkg/scaffold — start there for EE schema."
```

Kinds you can use:

| Kind | When to use |
|------|-------------|
| `research` | What you discovered in the code/docs |
| `decision` | What the team agreed |
| `note` | Small reminder / link / open question |

Optional — avoid duplicates if you might save the same thing twice:

```bash
bash core/scripts/team-brain-api.sh remember AAP-81423 research --source-ref "AAP-81423#cli-entrypoint" "Found CLI entrypoint in pkg/scaffold."
```

### 3) Draft stories from team memory (optional)

```bash
bash core/scripts/team-brain-api.sh breakdown AAP-81423
```

Open the file it prints, usually:

` .team-brain/initiatives/AAP-81423-breakdown.md `

Edit with the crew before filing real Jira stories.

---

## Path B — You are creating the team (admin, once)

Only one person does this for a new crew.

```bash
cd /path/to/engineer-brain
bash core/scripts/team-brain-api.sh register "Team Name" "Your Name"
```

The command prints an **invite code**. Copy that into Slack for teammates.

Then attach the Jira work:

```bash
bash core/scripts/team-brain-api.sh attach AAP-81423 "Short title" "active" "https://your-org.atlassian.net/browse/AAP-81423"
```

Tell juniors to use **Path A** with your invite code + Jira key.

> **Note:** New teams get longer invite codes (16 characters). Older demo codes may still be shorter — both are fine if your admin shared them.

---

## How sync actually works (read this)

Team Brain is **not** magic chat sync. Shared memory appears when:

1. Someone (or their AI) runs **`remember`** after a finding  
2. Someone else (or their AI) runs **`recall`** before researching  

If both of you forget, you will duplicate work — same as unused Slack notes.

**Good news:** with Cursor, Team Brain installs an **always-on rule** + skill that tells the AI:

- **Before researching** a Jira key → `recall` (sync crew memory first)  
- **After a finding** → `remember` immediately (direct save, don’t wait for you)

So you should not have to babysit every command — but if the AI skips a step, run the CLI yourself.

## Daily habits (keep it simple)

| When | What happens |
|------|----------------|
| Starting work on the ticket | AI should `recall` first (or you run it) |
| You / AI learned something durable | AI should `remember` immediately |
| Teammate saved a finding | Your next `recall` (or AI loop) picks it up |
| Planning stories / spikes | `breakdown JIRA-KEY` |
| “Am I connected?” | `whoami` or `status` |

Optional while collaborating live (second terminal) — refreshes cache as others save:

```bash
bash core/scripts/team-brain-api.sh watch AAP-81423 5
```

Stop with `Ctrl+C`.

---

## Using Cursor (optional)

### Skill (chat)

If Team Brain is installed in your workspace (via `install.sh cursor`):

- `/team-brain attach AAP-81423`
- `/team-brain remember …`
- `/team-brain recall …`
- `/team-brain breakdown …`

### MCP tools (advanced)

If your team wired the `team-brain` MCP server, your agent can call `attach` / `remember` / `recall` / `breakdown` as tools.  
Setup details: [mcp/team-brain/README.md](../mcp/team-brain/README.md).  
Juniors can ignore MCP and use the bash commands above.

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

# Work
bash core/scripts/team-brain-api.sh recall <JIRA-KEY>
bash core/scripts/team-brain-api.sh remember <JIRA-KEY> research "Finding…"
bash core/scripts/team-brain-api.sh breakdown <JIRA-KEY>

# Optional
bash core/scripts/team-brain-api.sh watch <JIRA-KEY> 5
bash core/scripts/team-brain-api.sh metrics <JIRA-KEY>
```

---

## Next reading (when you are ready)

- [team-brain.md](team-brain.md) — how sync layers fit together  
- [team-brain-memory.md](team-brain-memory.md) — full product plan  
- [supabase/README.md](../supabase/README.md) — admin / new project setup  
