# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added
- Scanner **`--json` output** (#3): `scan.sh` collect-once → text or JSON emitters; stable schema for dashboard/CI/`jq`; smoke test `tests/scan/smoke_json.sh`
- Team Brain **launch readiness** (#32 / #38 / #42): rate-limit `register_team`/`join_team` (DB sliding window, default 5 reg/h, 15 join/h); demo & Office Hours one-pager (`docs/team-brain-demo.md`); hands-on tutorial with verification checklist (`docs/team-brain-tutorial.md`)
- Migration `20260806000001_team_brain_rate_limits.sql` — fingerprint-based sliding window; `tb_rate_limit_stats` monitoring view
- Team Brain **repo pin + access roles** (#39 / #40): commit-safe `.team-brain/project.json`; `start`/`attach`/`onboard` honor pin; roles `admin`\|`member`\|`viewer`; `rotate-invite` / `set-role`; join `--role viewer`
- Migration `20260805000001_team_brain_roles_and_invites.sql` — write gates for viewers; admin invite rotate
- Team Brain **Realtime signal push** (#31): DB `realtime.send` trigger + `team-brain-realtime.py` listener; `watch --push`; `notify/<KEY>.json`; poll/`watch` remain fallback; no anon SELECT on captures
- Migration `20260804000001_team_brain_realtime_broadcast.sql` — `memory_broadcast_topic` + capture broadcast trigger
- Team Brain **MCP-first compliance** (#36): soft session gate (`compliance` / `prepare_research`); `sync-status` embeds `research_ok` + `agent_action`; Cursor rule/skill + MCP instructions use `stronger_prompts` (CLI not hard-blocked)
- Team Brain **crew bootstrap** (#41): `bootstrap` / `team-brain-bootstrap.sh` — migrate + register + share bundle for admins
- Team Brain **memory version history / soft rollback** (#34): `capture_revisions`; `history` / `restore` CLI + MCP
- Migration `20260803000001_team_brain_memory_history.sql` — archive prior body on `source_ref` update
- Team Brain **correction / learning loop** (#30): `correct` CLI + MCP; `learning` kind; skill/onboarding guidance
- Migration `20260802000001_team_brain_learning_kind.sql` — `captures.kind` includes `learning`
- `engineer-brain doctor` command — brain health check with weighted scoring, cooling repo detection, and growth suggestions
- `core/scripts/doctor.sh` — portable health check script (macOS + Linux)
- Dashboard data port (`loadDashboardData`) with sample adapter + BRAIN.md stub (#26)
- Dashboard CI job (`npm ci` / build / lint), favicon, and wired Refresh control
- Scanner GitHub activity section (`gh`): authored PRs, reviews, optional release checks
- Configurable `PERSONAL_REPOS`, `GH_OWNERS`, and `RELEASE_REPOS` in `core/scripts/scan.sh`
- Sync guidance for non-commit signals, prose standup style, and correction → learn feedback loop
- **Brain scopes** — `engineer-brain` + `team-brain` skills ([docs/scopes.md](docs/scopes.md))
- Team Brain v1: `core/team/` templates, `team-init.sh`, Cursor `team-brain` skill, `examples/team-spike-crew/`
- Team Brain docs ([docs/team-brain.md](docs/team-brain.md)) — hybrid Jira + Supabase sync
- Supabase schema + RPCs (`supabase/migrations`) for teams, members, initiatives, captures
- `core/scripts/team-brain-api.sh` — register/join/attach/capture/sync + md mirror
- Team Brain collaborative memory plan ([docs/team-brain-memory.md](docs/team-brain-memory.md))
- P0 memory migration: `source_ref`, FTS, `remember` / `search_memories` / `list_recent`
- CLI `remember` / `recall` + `.team-brain/cache/<KEY>.json` (md remains optional export)
- CLI `watch <JIRA-KEY>` — near-realtime authenticated poll; updates memory cache
- P2 semantic recall: pgvector(768), optional OpenAI/Ollama embed on `remember`/`recall`, `reembed` backfill
- P3 Team Brain MCP server (`mcp/team-brain/`) — attach / remember / recall / list_recent for agents
- Team-brain skill agent defaults: recall on attach, remember after durable research
- P4 `breakdown` — recalls memories → `initiatives/<KEY>-breakdown.md` (stories/spikes/AC)
- P4 `metrics` — local reuse stats (`.team-brain/metrics.json`); MCP tools `breakdown` / `metrics`
- Security follow-up: unique member names, 16-char invites, `updated_at` trigger (`…_security.sql`)
- Mandatory Team Brain **agent loop**: always-on `team-brain.mdc` + skill — recall before research, remember after findings
- Team Brain beginner onboarding guide ([docs/team-brain-onboarding.md](docs/team-brain-onboarding.md))
- CLI `onboard` — join + optional attach + recall in one command
- **Sync mode** — `start` / `stop` / `wake` / `touch` / `sync-status`: one manual entry, background merge-safe pull, idle sleep (~1h) with warning
- Migration `…_sync_mode.sql` — `remember` updates same `source_ref` when body changes; `list_recent` includes updated rows
- MCP + Cursor rule/skill wired for sync mode lifecycle

### Changed
- Team Brain `remember` accepts `learning` kind; memory body guidance prefers natural prefer/avoid (no TODO dumps)
- engineer-brain standup correction feedback mirrors Team Brain absorb-and-learn pattern
- Jira site defaults use `https://your-org.atlassian.net` (no hardcoded company host)
- `supabase/project.public.env` ships **placeholders only** (no live URL/anon in git); each crew brings their own project
- `join_team` omits `invite_code`; `whoami` returns invite only for admin (`…_invite_hygiene.sql`)
- `watch` cursor uses `updated_at` so source_ref merges are visible
- MCP `remember` passes body on stdin (avoids shell arg mangling)
- `.gitignore` scopes Team Brain credentials to `.team-brain/` only
- `team-brain-api.sh`: yq-aware YAML load; RPC `payload`/`resp_body` naming
- Dashboard expertise taxonomy aligned with brain-spec (**Strong / Growing / Exposure**); chart colors moved to UI layer
- Documented `dashboard/` vs `website/`, privacy/hosting rules (public deploy = sample only)
- `platforms/cursor/skills/engineer-brain/SKILL.md` and `core/COMMANDS.md` sync flow no longer rely on authored git commits alone
- Cursor platform README documents scanner config knobs and install vs live-copy drift
- Architecture / README / roadmap / FAQ / website docs aligned with collaborative memory + agent loop
- Team Brain: Supabase memories as SoT; local `cache/<KEY>.json` for agents; md optional export

---

## [1.0.0] — 2026-07-14

### Added
- Core engine: BRAIN.md template, COMMANDS.md, multi-repo scanner
- Platform adapters: Cursor, Claude Code, GitHub Copilot, Windsurf, Aider, Continue.dev
- Universal installer (`install.sh`) with support for all 6 platforms
- Commands: sync, update, quarterly, reflect, scan
- Pattern detection: fix-heavy mode, cooling repos, velocity tracking, stale goals
- Auto-expertise classification (Strong / Growing / Exposure)
- Monday-aware standup generation with blocker detection
- BRAIN.md specification (docs/brain-spec.md)
- Architecture documentation with Mermaid diagrams
- Vision document outlining long-term philosophy
- Example BRAIN.md profiles for 5 engineering roles
- Contributing guidelines, Code of Conduct
- GitHub issue and PR templates
- Roadmap and FAQ documentation

### Security
- All data stays local — no external transmission
- Scanner reads only git metadata, never file contents
- No credentials or secrets stored in BRAIN.md
