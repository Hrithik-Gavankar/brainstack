# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
