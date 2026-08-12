# Architecture

Brainstack is composed of three layers: data collection, intelligence, and delivery —
with two **scopes** (skills): engineer-brain (personal) and team-brain (team/initiative).

See also [scopes.md](scopes.md) and [team-brain.md](team-brain.md).

---

## System Overview

```mermaid
flowchart TD
    subgraph Sources["Data Sources"]
        GIT[Git Repositories]
        JIRA[Jira / Linear / Tracker]
        SESS[Session Analytics]
    end

    subgraph Core["Core Engine"]
        SCAN[Multi-Repo Scanner<br/>scan.sh]
        PATTERN[Pattern Detection]
        BRAIN[BRAIN.md<br/>Personal profile]
        TEAM[TEAM.md + cache/<br/>Team / initiative context]
        API[team-brain-api.sh]
        CMD[Command Engine]
    end

    subgraph Cloud["Team Brain cloud opt-in"]
        SB[(Supabase memories)]
        MCP[mcp/team-brain]
    end

    subgraph Skills["Skills = scopes"]
        EB[engineer-brain<br/>sync update quarterly …]
        TB[team-brain<br/>onboard attach remember recall breakdown]
    end

    subgraph Adapters["Platform Adapters"]
        CUR[Cursor<br/>engineer + team rules + skills]
        CLA[Claude Code<br/>CLAUDE.md]
        COP[GitHub Copilot<br/>copilot-instructions.md]
        WIN[Windsurf<br/>.windsurfrules]
        AID[Aider<br/>CONVENTIONS.md]
        CON[Continue.dev<br/>rules.md]
    end

    subgraph Surfaces["Other Delivery Surfaces"]
        DASH[Web Dashboard<br/>dashboard/ — local + demo viz]
        DOCS[Docs Site<br/>website/ — Docusaurus product docs]
    end

    GIT --> SCAN
    JIRA -->|attach identity| API
    SESS -.->|optional| CMD
    SCAN --> PATTERN
    PATTERN --> BRAIN
    CMD --> BRAIN
    CMD --> TEAM
    EB --> BRAIN
    TB --> API
    API --> SB
    API --> TEAM
    MCP --> API
    BRAIN --> CUR
    TEAM --> CUR
    BRAIN --> CLA
    BRAIN --> COP
    BRAIN --> WIN
    BRAIN --> AID
    BRAIN --> CON
    BRAIN -.->|via data port / future parser| DASH
    BRAIN -.->|documented by| DOCS
```

---

## Layer 1: Data Collection

### Multi-Repo Scanner (`core/scripts/scan.sh`)

The scanner is a bash script that traverses all git repositories in a workspace and extracts:

- **Recent commits** — Subject, author, date, type (fix/feat/refactor/test/chore)
- **Active branches** — Current branch, last commit date, ahead/behind status
- **Uncommitted changes** — Staged and unstaged modifications
- **Commit type breakdown** — Conventional commit prefix distribution
- **Files touched** — Which areas of the codebase are receiving attention
- **Velocity metrics** — Commits per day/week, trend direction
- **GitHub activity** (optional, via `gh`) — authored PRs, reviews given, recent releases
- **Personal-repo filtering** — optional `PERSONAL_REPOS` basenames excluded from team metrics

**Input:** Workspace path, author pattern, lookback period (days); optional `GH_OWNERS` / `RELEASE_REPOS`  
**Output:** One of:

| Mode | Flag | Consumer |
|------|------|----------|
| **Text** (default) | _(none)_ | AI assistants / `engineer-brain sync|update` prompts |
| **JSON** | `--json` | Dashboard data port, CI, `jq`, weekly automation (#3 / #9) |

JSON requires `python3` for safe escaping. Schema (stable keys):

```json
{
  "metadata": { "workspace", "period_days", "since", "scan_time", "author_pattern" },
  "commits": [{ "repo", "hash", "date", "message", "type", "personal" }],
  "branches": [{ "repo", "branch", "ahead_of_main" }],
  "uncommitted": [{ "repo", "files": [] }],
  "type_breakdown": { "feat": 1, "fix": 2 },
  "files_touched": { "repo": ["path"] },
  "velocity": { "total", "period_days", "per_repo", "scope": "team_repos_only" },
  "github": { "available", "authored_prs", "reviews", "releases" }
}
```

Collection is **single-pass**: local git + optional `gh` signals are gathered once, then emitted as text or JSON (no divergent git queries per format).

```mermaid
flowchart LR
    WS[Workspace Directory] --> FIND[Find Git Repos]
    FIND --> R1[Repo 1: git log]
    FIND --> R2[Repo 2: git log]
    FIND --> R3[Repo N: git log]
    R1 --> AGG[Collect once]
    R2 --> AGG
    R3 --> AGG
    AGG --> TEXT[Text emitter]
    AGG --> JSON[JSON emitter]
    TEXT --> OUT1[AI / sync prompts]
    JSON --> OUT2[Dashboard / CI / jq]
```

---

## Layer 2: Intelligence

### Pattern Detection

When processing scan output, the system applies heuristics:

| Pattern | Detection Rule | Action |
|---------|---------------|--------|
| Fix-heavy mode | >60% of commits are `fix:` | Flag in reflection |
| Cooling repo | Previously active repo with 30+ days no commits | Alert engineer |
| Velocity drop | >30% decrease week-over-week | Flag for attention |
| Stale growth goal | Unchecked checkbox for 30+ days | Escalate in reflection |
| New expertise | First commits in a new area | Celebrate in reflection |

### Expertise Classification

```mermaid
flowchart TD
    COMMITS[Commit Count in Area] --> CHECK{How many?}
    CHECK -->|10+ commits or 3+ PRs| STRONG[Strong]
    CHECK -->|2-9 commits or 1-2 PRs| GROWING[Growing]
    CHECK -->|0-1 commits, repo cloned| EXPOSURE[Exposure]
```

### Command Engine

Commands are natural language triggers interpreted by the AI assistant.
**Skills name the scope; commands are verbs** (do not install `sync` as its own skill).

| Skill | Command | Data Flow |
|-------|---------|-----------|
| engineer-brain | `sync` | Scanner (1-3 days) → BRAIN.md sprint context → Standup output |
| engineer-brain | `update` | Scanner (30 days) → Pattern detection → BRAIN.md rewrite |
| engineer-brain | `quarterly` | Scanner (90 days) → BRAIN.md → Structured review document |
| engineer-brain | `reflect` | Scanner (30 days) → Pattern detection → Recommendations |
| engineer-brain | `gcal` | `mcp/gcal` (or `gcal.sh`) → today/upcoming events → merged into `sync` |
| team-brain | `onboard` / `register` / `join` | Invite membership; write `credentials.json` |
| team-brain | `attach` / `recall` | Jira identity + pull memories → cache / session brief |
| team-brain | `remember` | Append shared memory (dedup by `source_ref` / content hash) |
| team-brain | `breakdown` | Recall memories → story/spike draft (`*-breakdown.md`) |
| team-brain | `watch` / `metrics` | Near-realtime poll + signal Broadcast push; local reuse stats |

### Team Brain collaborative memory

```mermaid
flowchart LR
  Jira -->|attach key title status| Init[initiatives]
  EngA -->|remember| SB[(Supabase memories)]
  EngB -->|recall / watch| SB
  SB -->|cache| JSON[".team-brain/cache/KEY.json"]
  SB -->|optional export| MD["initiatives/KEY.md"]
  JSON -->|breakdown| Draft["KEY-breakdown.md"]
  Rule[Cursor team-brain.mdc] -->|recall before / remember after| EngA
  MCP[team-brain MCP] --> EngA
  MCP --> EngB
```

| Layer | Responsibility |
|-------|----------------|
| **Jira** | Initiative identity |
| **Supabase** | Membership + memories (SoT); FTS recall; optional pgvector |
| **Local cache** | Agent-facing snapshot |
| **Markdown** | Optional human/git export |
| **Agent loop** | Always-on Cursor rule + skill: recall before research, remember after findings |
| **MCP** | `mcp/team-brain/` — attach / remember / recall / breakdown / metrics |

Beginner path: [team-brain-onboarding.md](team-brain-onboarding.md).  
Plan and phases: [team-brain-memory.md](team-brain-memory.md). Setup: [supabase/README.md](../supabase/README.md).

### Optional integration: Google Calendar (gcal)

Read-only, generic, and independent of Team Brain / Jira keys — closes the
"sync is calendar-blind" gap (hackathons, demos, meetups, workshops never
appear in git/`gh`). One-time OAuth setup, then `sync` calls `today_sync()` /
`upcoming_sync()` automatically when the `gcal` MCP (or `core/scripts/gcal.sh`) is
configured, falling back to BRAIN.md's `Upcoming Events` table otherwise.

| Layer | Responsibility |
|-------|----------------|
| **`core/scripts/gcal_lib.py`** | Shared OAuth (loopback flow) + Calendar API client — stdlib only, zero third-party deps |
| **`core/scripts/gcal.sh`** | CLI entrypoint for non-MCP platforms (mirrors `jira.sh`) |
| **`mcp/gcal/`** | MCP tools (`status`, `today`, `today_sync`, `upcoming`, `upcoming_sync`, `events_range`, `list_calendars`) |

See [mcp/gcal/README.md](../mcp/gcal/README.md).

---

## Layer 3: Delivery (Platform Adapters)

Each AI coding assistant has its own native format for loading persistent context. Platform adapters translate the universal brain into the tool's expected format.

```mermaid
flowchart TD
    BRAIN[BRAIN.md + TEAM.md + commands] --> ADAPTER{Platform Adapter}
    ADAPTER -->|Cursor| A1[".cursor/rules/engineer-brain.mdc + team-brain.mdc<br/>skills/engineer-brain + skills/team-brain"]
    ADAPTER -->|Claude Code| A2["CLAUDE.md"]
    ADAPTER -->|Copilot| A3[".github/copilot-instructions.md"]
    ADAPTER -->|Windsurf| A4[".windsurfrules"]
    ADAPTER -->|Aider| A5["CONVENTIONS.md"]
    ADAPTER -->|Continue.dev| A6[".continue/rules.md"]
```

### Adapter contents

Each adapter file contains:
1. **Context section** — Condensed version of BRAIN.md identity, skills, and workspace info
2. **Behavior instructions** — How the AI should use the context (calibrate complexity, push growth, flag security)
3. **Command reference** — How to invoke engineer-brain commands in that platform's syntax
4. **Link to full brain** — Path to BRAIN.md for detailed lookups

### Web dashboard (`dashboard/`) vs docs site (`website/`)

| Path | Role | Data |
|------|------|------|
| `dashboard/` | Personal / demo visualization UI (Vite + React) | Consumes brain-shaped data via `loadDashboardData()` — sample fixture today; local `BRAIN.md` parser later |
| `website/` | Public product documentation (Docusaurus) | Static docs only — not a brain viewer |

The dashboard is a Delivery-layer **consumer** of BRAIN.md, not a second source of truth. Keep presentation (chart colors, layout) in the UI layer; keep taxonomy aligned with [brain-spec.md](brain-spec.md) (Strong / Growing / Exposure).

---

## Installation Flow

```mermaid
flowchart TD
    DEV[Developer] -->|"bash install.sh platform workspace"| INST[Install Script]
    INST --> CORE[Install Core Files<br/>BRAIN.md + COMMANDS.md + scan.sh]
    INST --> PLAT[Install Platform Adapter<br/>Native context file]
    CORE --> CONFIG[Configure Scanner<br/>Set workspace + author pattern]
    PLAT --> CONFIG
    CONFIG --> UPDATE["Run: engineer-brain update"]
    UPDATE --> READY[Ready to Use]
```

---

## Update Flow

```mermaid
sequenceDiagram
    participant E as Engineer
    participant AI as AI Assistant
    participant S as Scanner
    participant B as BRAIN.md

    E->>AI: "engineer-brain update"
    AI->>S: Execute scan.sh (30 days)
    S-->>AI: Raw git data
    AI->>AI: Pattern detection
    AI->>B: Read current BRAIN.md
    AI->>B: Write updated BRAIN.md
    AI-->>E: Summary of changes
```

---

## Security & Privacy

- **Personal engineer-brain** stays local — scanner and `BRAIN.md` are not uploaded
- The scanner reads only git metadata (commits, branches), not file contents
- Engineers can `.gitignore` their BRAIN.md if they prefer not to share it
- **Team Brain (opt-in):** membership + initiative memories sync to your Supabase project via RPC + hashed member API keys. Personal `BRAIN.md` is never sent. Do not commit `credentials.json` or `service_role` keys. See [supabase/README.md](../supabase/README.md) security table.
- **Dashboard hosting:** public deploys (Vercel, Pages, etc.) may ship the **sample/demo** dashboard only. Do not upload personal `BRAIN.md` to a public host — use local `npm run dev` / `preview` for real brain data (see [dashboard/README.md](../dashboard/README.md))

---

## Extensibility

### Adding a new platform

1. Create `platforms/<name>/` directory
2. Add the context file in the platform's native format
3. Add a `README.md` with setup instructions
4. Add an install case to `install.sh`

### Adding a new data source

1. Create a new script in `core/scripts/`
2. Reference it from the relevant command in `COMMANDS.md`
3. Define how its output maps to BRAIN.md sections

### Adding a new command

1. Define the command in `core/COMMANDS.md`
2. Specify: trigger, data sources, output format, scope rules
3. For Cursor: also add to `platforms/cursor/skills/engineer-brain/SKILL.md`

### Extending the web dashboard

1. Add or update a data adapter under `dashboard/src/data/` (do not hard-import fixtures from `App.tsx`)
2. Keep `DashboardData` aligned with [brain-spec.md](brain-spec.md)
3. Put chart colors and other presentation details in the UI layer (`colors.ts` / components)
4. Document hosting/privacy constraints in `dashboard/README.md`
