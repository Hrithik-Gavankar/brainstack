# engineer-brain — onboarding

**Who this is for:** anyone using `engineer-brain sync` for daily standups.  
**Time:** ~15 minutes (one-time setup).  
**You need:** Cursor, git repos in your workspace, GitHub CLI, and the **Atlassian** Cursor plugin for Jira.

---

## What gets configured

| Signal | Required? | Setup |
|--------|-----------|--------|
| Git history | Yes | Clone team repos under your workspace |
| GitHub PRs/reviews | Yes | `gh auth login` |
| **Jira tickets** | **Yes** | **Atlassian MCP plugin** (below) |
| Google Calendar | Optional | [gcal MCP](../mcp/gcal/README.md) — demos, workshops, meetups |
| `BRAIN.md` | Yes (identity) | Fill name/role/team after `install.sh` |

`sync` **always** pulls Jira. Do not run standup prep without the Atlassian plugin connected.

---

## Step 1 — Install engineer-brain in Cursor

```bash
git clone https://github.com/Hrithik-Gavankar/brainstack.git
cd brainstack
bash install.sh cursor ~/path/to/your-workspace
```

Verify:

```bash
ls ~/.cursor/skills/engineer-brain/SKILL.md
ls ~/.cursor/rules/engineer-brain.mdc
```

Open `~/.cursor/skills/engineer-brain/BRAIN.md` (or workspace copy) and fill **Identity** + **Current Sprint Context**.

---

## Step 2 — GitHub CLI

```bash
gh auth login
gh auth status
```

Used by `scan.sh` for authored PRs, reviews, and releases.

---

## Step 3 — Atlassian MCP (Jira) — required

Jira is **not** configured in `~/.cursor/mcp.json`. Use the official **Cursor marketplace plugin** (OAuth — no API token in shell).

### 3.1 Install the plugin

1. Open **Cursor**.
2. Go to **Settings** → **Plugins** (or open [cursor.com/marketplace/atlassian](https://cursor.com/marketplace/atlassian)).
3. Find **Atlassian** (by Atlassian) and click **Install** / **Enable**.
4. Reload Cursor if prompted.

The plugin registers MCP namespace `plugin-atlassian-atlassian` and points at Atlassian's hosted server (`https://mcp.atlassian.com/v1/mcp/authv2`). You do **not** add a manual `mcpServers` block for Jira.

### 3.2 Authorize (first use)

1. Start a Cursor chat in your workspace.
2. Ask: *"Who am I on Atlassian?"* or run `/engineer-brain sync`.
3. When the OAuth browser window opens, sign in with your **Red Hat Atlassian** account (e.g. `hgavanka@redhat.com` on `redhat.atlassian.net`).
4. Approve the requested Jira/Confluence scopes.

First-time site install may require a user who has access to the Jira projects you use; after that, other crew members can authorize individually.

### 3.3 Verify

In chat, the agent should succeed on:

- `atlassianUserInfo` — returns your name and email
- `getAccessibleAtlassianResources` — returns `redhat.atlassian.net` cloud id
- `searchJiraIssuesUsingJql` — returns your assigned issues

If the agent reports **no Jira namespace** or **needsAuth**:

| Symptom | Fix |
|---------|-----|
| Plugin not listed in Settings → Plugins | Re-install from marketplace; restart Cursor |
| OAuth never appeared | Retry a Jira tool call; check pop-up blocker |
| `401` / expired session | Re-authenticate via plugin settings or repeat OAuth flow |
| Org blocks Rovo MCP | Ask your Atlassian admin — [control settings](https://support.atlassian.com/security-and-access-policies/docs/control-atlassian-rovo-mcp-server-settings/) |

### 3.4 What `sync` queries (automatic)

When you run `/engineer-brain sync`, the agent **must**:

1. Resolve cloud id via `getAccessibleAtlassianResources`
2. Run JQL for tickets **updated in the standup window** (yesterday, or Friday-only on Mondays)
3. Run JQL for your **In Progress / In Review** assignments
4. Optionally check open sprint (`sprint in openSprints()`) — many Ansible tickets are not sprint-tagged; in-progress query is the fallback

Tickets surface in standup as `AAP-xxxxx` (or your project key) with impact language, not raw JQL dumps.

---

## Step 4 — Optional: Google Calendar

For hackathons, demos, workshops, and meetups that never appear in git:

See [mcp/gcal/README.md](../mcp/gcal/README.md) — one-time OAuth via `gcal.sh authorize`.

---

## Step 5 — Optional: `jira.sh` CLI fallback

For **terminals and CI only** — not a substitute for sync in Cursor.

```bash
export JIRA_URL="https://redhat.atlassian.net"
export JIRA_EMAIL="you@redhat.com"
export JIRA_API_TOKEN="..."   # https://id.atlassian.com/manage-profile/security/api-tokens
bash core/scripts/jira.sh active
```

Add the exports to `~/.zshrc` if you want shell scripts to work. **`sync` prefers Atlassian MCP** when the plugin is connected.

---

## Daily use

```
/engineer-brain sync
```

Or: *"Help me with sync up notes for today."*

Expected sources in every run: **git** + **gh** + **Jira (Atlassian MCP)** + **BRAIN.md** + **gcal** (if configured).

---

## Related docs

- [core/COMMANDS.md](../core/COMMANDS.md) — full command reference
- [workshop-brainstack-day0.md](workshop-brainstack-day0.md) — instructor-led walkthrough
- [team-brain-onboarding.md](team-brain-onboarding.md) — crew shared memory (separate from personal standup)
