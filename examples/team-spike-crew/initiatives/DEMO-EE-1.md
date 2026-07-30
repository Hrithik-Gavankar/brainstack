# DEMO-EE-1: EE decision_environment scaffolding spike

**Tracker:** `DEMO-EE-1` (demo placeholder — replace with your Jira browse URL)  
**Status:** active  
**Owners:** Alex, Blair  
**Attached:** Alex, Blair

---

## Goal

Prove a reliable path to scaffold `decision_environment` for Execution Environments, document the real code paths, and leave enough context for epic breakdown without a second research pass.

---

## Decisions

| Date | Decision | Why | Decided by |
|------|----------|-----|------------|
| 2026-07-26 | Use CLI schema path in `example-cli/pkg/scaffold` as source of truth | Avoids duplicating YAML parsers in the extension | Casey |
| 2026-07-26 | Spike stays read-only on schemas until story 2 | Limits blast radius while mapping | Alex |

---

## Research & findings

### 2026-07-26 — Alex

- Entry point: `example-cli/cmd/scaffold.go` → `pkg/scaffold/ee.go`
- Schema samples under `example-schemas/ee/decision_environment/`
- Open: whether Cursor task provider should shell out to CLI or call a shared library

### 2026-07-26 — Blair

- Integration test harness expects env var `EE_SCHEMA_ROOT`
- Duplicate discovery risk if both INI and pyproject paths are parsed — prefer CLI `--list-json` later

---

## Open questions

- [ ] Library vs CLI for the VS Code integration?
- [ ] Do we need MCP tools in the spike or only in the implementation epic?

---

## Links

- PRs: (none yet)
- Docs / ADRs: (pending)
- Related initiatives: (none)

---

## Capture log

- `2026-07-26` [@Alex] Mapped CLI scaffold entrypoints
- `2026-07-26` [@Blair] Noted test harness env + duplicate discovery risk
