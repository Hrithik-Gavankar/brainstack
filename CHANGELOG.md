# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added
- `engineer-brain doctor` command — brain health check with weighted scoring, cooling repo detection, and growth suggestions
- `core/scripts/doctor.sh` — portable health check script (macOS + Linux)
- Dashboard data port (`loadDashboardData`) with sample adapter + BRAIN.md stub (#26)
- Dashboard CI job (`npm ci` / build / lint), favicon, and wired Refresh control
- Scanner GitHub activity section (`gh`): authored PRs, reviews, optional release checks
- Configurable `PERSONAL_REPOS`, `GH_OWNERS`, and `RELEASE_REPOS` in `core/scripts/scan.sh`
- Sync guidance for non-commit signals, prose standup style, and correction → learn feedback loop

### Changed
- Dashboard expertise taxonomy aligned with brain-spec (**Strong / Growing / Exposure**); chart colors moved to UI layer
- Documented `dashboard/` vs `website/`, privacy/hosting rules (public deploy = sample only)
- `platforms/cursor/skills/engineer-brain/SKILL.md` and `core/COMMANDS.md` sync flow no longer rely on authored git commits alone
- Cursor platform README documents scanner config knobs and install vs live-copy drift

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
