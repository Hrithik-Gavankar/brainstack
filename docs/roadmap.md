# Roadmap

Engineer Brain's development is organized into three horizons.

---

## Now (v1.0 — Launch)

The foundation: a working system with multi-platform support.

- [x] Core engine: BRAIN.md template + COMMANDS.md + scanner
- [x] Platform adapters: Cursor, Claude Code, Copilot, Windsurf, Aider, Continue.dev
- [x] Universal installer (`install.sh`)
- [x] Commands: sync, update, quarterly, reflect, scan
- [x] Pattern detection: fix-heavy mode, cooling repos, velocity tracking
- [x] Auto-expertise classification (Strong / Growing / Exposure)
- [x] Monday-aware standups with blocker detection
- [x] Documentation: architecture, BRAIN.md spec, vision, FAQ
- [x] Examples for multiple engineering profiles
- [x] `engineer-brain doctor` — brain health check and completeness score
- [ ] GIF/screenshot demos for README and social media

---

## Next (v1.x — Ecosystem)

Growing beyond individual use into a richer tool.

- [ ] **Zed editor support** — platform adapter for Zed's AI features
- [ ] **JetBrains AI Assistant support** — platform adapter for IntelliJ/WebStorm/PyCharm
- [ ] **Neovim + AI plugin support** — adapter for Neovim-based AI workflows
- [x] **Web dashboard (MVP)** — Vite/React UI with sample data + data-port seam (`dashboard/`); local `BRAIN.md` parser still open
- [x] **Team Brain (scopes)** — `team-brain` skill + cache / optional md; see [scopes.md](scopes.md)
- [x] **Team Brain collaborative memory (P0–P4)** — `remember` / `recall`, cache, `watch` poll, optional pgvector, MCP, breakdown + metrics; see [team-brain-memory.md](team-brain-memory.md)
- [x] **Team Brain agent loop** — Cursor always-on `team-brain.mdc` + skill: recall before research, remember after findings
- [x] **Team Brain onboarding** — invite + Jira key via `onboard`; beginner guide [team-brain-onboarding.md](team-brain-onboarding.md)
- [x] **Team Brain sync mode** — `start` / `stop` / `wake` / idle sleep; merge-safe `source_ref` updates
- [ ] **Team Brain Realtime push** — private broadcast into other agents (v1 uses sync-mode poll)
- [ ] **Anon register/join rate limits** — Edge Function / Auth hardening (documented gap)
- [ ] **Team aggregation metrics** — skill coverage matrix, workload heatmap, collaboration graph
- [ ] **GitLab/Bitbucket support** — scanner support beyond GitHub
- [ ] **Engineer-brain MCP** — personal BRAIN.md / sync as MCP resources (team-brain MCP ships first)
- [ ] **Weekly email digest** — scheduled summary of patterns and recommendations
- [ ] **BRAIN.md validator** — CLI tool to check completeness and freshness
- [ ] **Import from LinkedIn/GitHub** — bootstrap BRAIN.md from existing profiles
- [ ] **Jira/Linear deep integration** — pull sprint data, issue assignments, cycle velocity

---

## Later (v2.0 — Standard)

BRAIN.md as an open standard adopted by the ecosystem.

- [ ] **BRAIN.md RFC process** — formalize the spec with community input
- [ ] **Native tool integration** — AI assistants natively recognize and consume BRAIN.md
- [ ] **Organization-level intelligence** — aggregated engineering patterns for teams
- [ ] **Growth analytics** — longitudinal tracking of expertise development
- [ ] **Mentorship matching** — connect engineers with complementary skills
- [ ] **CI/CD integration** — auto-update BRAIN.md on PR merge events
- [ ] **VS Code extension** — dedicated extension for brain management
- [ ] **Docusaurus docs site** — full documentation website

---

## How to Influence the Roadmap

1. **Open an issue** — describe what you'd like to see and why
2. **Vote on existing issues** — thumbs-up issues you care about
3. **Submit a PR** — implement a roadmap item and reference it in your PR description
4. **Start a discussion** — use GitHub Discussions for open-ended ideas

We prioritize based on community signal and alignment with the [vision](vision.md).
