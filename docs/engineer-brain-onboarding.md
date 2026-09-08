# engineer-brain — onboarding

**Who this is for:** anyone using `engineer-brain sync` for daily standups.  
**Time:** ~15 minutes (one-time setup).  
**You need:** an AI assistant with Brainstack installed, git repos in your workspace, GitHub CLI, and a Jira signal (see below).

---

## What gets configured

| Signal | Required? | Setup |
|--------|-----------|--------|
| Git history | Yes | Clone team repos under your workspace |
| GitHub PRs/reviews | Yes | `gh auth login` |
| **Jira tickets** | **Yes** | **Atlassian MCP** (Cursor) or **`jira.sh`** (other platforms) |
| Google Calendar | Optional | [gcal MCP](https://github.com/Hrithik-Gavankar/brainstack/blob/main/mcp/gcal/README.md) — demos, workshops, meetups |
| `BRAIN.md` | Yes (identity) | Fill name/role/team after `install.sh` |

`sync` **always** pulls Jira. Do not run standup prep without a working Jira signal.

---

## Step 1 — Install engineer-brain

```bash
git clone https://github.com/Hrithik-Gavankar/brainstack.git
cd brainstack
bash install.sh cursor ~/path/to/your-workspace   # or claude-code, vscode-copilot, etc.
```

Verify (Cursor example):

```bash
ls ~/.cursor/skills/engineer-brain/SKILL.md
ls ~/.cursor/skills/engineer-brain/ONBOARDING.md
ls ~/.cursor/rules/engineer-brain.mdc
```

Open `BRAIN.md` in your platform skill directory (or `.engineer-brain/BRAIN.md`) and fill **Identity** + **Current Sprint Context**.

---

## Step 2 — GitHub CLI

```bash
gh auth login
gh auth status
```

Used by `scan.sh` for authored PRs, reviews, and releases.

---

## Step 3 — Jira signal (required)

### Cursor — Atlassian MCP (recommended)

Jira is **not** configured in `~/.cursor/mcp.json`. Use the official **Cursor marketplace plugin** (OAuth — no API token in shell).

#### 3.1 Install the plugin

1. Open **Cursor**.
2. Go to **Settings** → **Plugins** (or open [cursor.com/marketplace/atlassian](https://cursor.com/marketplace/atlassian)).
3. Find **Atlassian** (by Atlassian) and click **Install** / **Enable**.
4. Reload Cursor if prompted.

The plugin registers MCP namespace `plugin-atlassian-atlassian` and points at Atlassian's hosted server (`https://mcp.atlassian.com/v1/mcp/authv2`). You do **not** add a manual `mcpServers` block for Jira.

#### 3.2 Authorize (first use)

1. Start a Cursor chat in your workspace.
2. Ask: *"Who am I on Atlassian?"* or run `/engineer-brain sync`.
3. When the OAuth browser window opens, sign in with your **company Atlassian** account (e.g. `you@company.com` on `your-org.atlassian.net`).
4. Approve the requested Jira/Confluence scopes.

First-time site install may require a user who has access to the Jira projects you use; after that, other crew members can authorize individually.

> **Example (Red Hat):** `you@redhat.com` on `redhat.atlassian.net`, project keys like `AAP-xxxxx`.

#### 3.3 Verify

In chat, the agent should succeed on:

- `atlassianUserInfo` — returns your name and email
- `getAccessibleAtlassianResources` — returns your site cloud id (e.g. `your-org.atlassian.net`)
- `searchJiraIssuesUsingJql` — returns your assigned issues (requires `cloudId` from the previous call)

If the agent reports **no Jira namespace** or **needsAuth**:

| Symptom | Fix |
|---------|-----|
| Plugin not listed in Settings → Plugins | Re-install from marketplace; restart Cursor |
| OAuth never appeared | Retry a Jira tool call; check pop-up blocker |
| `401` / expired session | Re-authenticate via plugin settings or repeat OAuth flow |
| Org blocks Rovo MCP | Ask your Atlassian admin — [control settings](https://support.atlassian.com/security-and-access-policies/docs/control-atlassian-rovo-mcp-server-settings/) |

#### 3.4 What `sync` queries (automatic)

When you run `/engineer-brain sync`, the agent **must**:

1. Resolve `cloudId` via `getAccessibleAtlassianResources`
2. Run JQL for tickets **updated in the standup window** (yesterday, or Friday-only on Mondays)
3. Run JQL for your **active** assignments (`statusCategory = "In Progress"`)
4. Optionally check open sprint (`sprint in openSprints()`) — many teams do not sprint-tag every ticket; the in-progress query is the fallback

**Sample JQL** (replace `CLOUD_ID` with the id from `getAccessibleAtlassianResources`):

```text
# Tuesday–Friday: tickets you touched yesterday
assignee = currentUser() AND updated >= startOfDay(-1) ORDER BY updated DESC

# Monday standup: Friday only
assignee = currentUser() AND updated >= startOfDay(-3) AND updated < startOfDay(-1) ORDER BY updated DESC

# Carry-forward for "today" section
assignee = currentUser() AND statusCategory = "In Progress" ORDER BY updated DESC
```

Tickets surface in standup as `PROJ-12345` (your project key) with impact language, not raw JQL dumps.

### Other platforms — `jira.sh` CLI

Claude Code, Copilot, Windsurf, Aider, and Continue.dev do **not** have the Atlassian Cursor plugin. For `sync` on those platforms, configure the CLI fallback (Step 5) and ensure `install.sh` copied `jira.sh` into your `.engineer-brain/scripts/` (or platform skill `scripts/`).

---

## Step 4 — Optional: Google Calendar

For hackathons, demos, workshops, and meetups that never appear in git:

See [gcal MCP setup](https://github.com/Hrithik-Gavankar/brainstack/blob/main/mcp/gcal/README.md) — one-time OAuth via `gcal.sh authorize`.

---

## Step 5 — Optional: `jira.sh` CLI fallback

For **terminals, non-Cursor platforms, and CI** — not a substitute for Atlassian MCP in Cursor when the plugin is connected.

```bash
export JIRA_URL="https://your-org.atlassian.net"
export JIRA_EMAIL="you@company.com"
export JIRA_API_TOKEN="..."   # https://id.atlassian.com/manage-profile/security/api-tokens
bash .engineer-brain/scripts/jira.sh active
```

Add the exports to `~/.zshrc` if you want shell scripts to work. **Cursor `sync` prefers Atlassian MCP** when the plugin is connected.

---

## Daily use

```
/engineer-brain sync
```

Or: *"Help me with sync up notes for today."*

Expected sources in every run: **git** + **gh** + **Jira** + **BRAIN.md** + **gcal** (if configured).

---

## Related docs

- [core/COMMANDS.md](https://github.com/Hrithik-Gavankar/brainstack/blob/main/core/COMMANDS.md) — full command reference
- [team-brain-onboarding.md](https://github.com/Hrithik-Gavankar/brainstack/blob/main/docs/team-brain-onboarding.md) — crew shared memory (separate from personal standup)
