# Team Brain — Collaborative AI Memory (plan)

Status: **active build**  
Related: [#2](https://github.com/Hrithik-Gavankar/engineer-brain/issues/2), [team-brain.md](team-brain.md), [scopes.md](scopes.md)

This document captures the original Team Brain intent, what we shipped for the demo, and the Supabase-only path to **collaborative AI memory** (realtime + semantic recall) — without depending on external memory products.

---

## 1. Original plan (issue #2)

When engineer-brain was personal-only, Team Brain meant:

| Intent | Detail |
|--------|--------|
| **Problem** | 2–3 engineers on the same spike each cold-start AI → duplicate research and token burn |
| **Product** | Initiative-scoped shared context (research, decisions, open questions) |
| **Privacy** | Personal `BRAIN.md` stays private; team layer is opt-in |
| **Commands** | `init` / `attach` / `sync` / `breakdown` (+ team config) |
| **Portability** | Same cross-platform story as personal brain |
| **Success** | Less duplicate research, lower tokens before first PR, faster 2nd/3rd engineer onboard, better epic breakdown |

Markdown was always a **portable surface**. The outcome was **agents reusing team memory** — not a shared wiki.

### Demo slice we already shipped

- Invite / register / join on Supabase
- Jira key as initiative identity
- `capture` + pull `sync` → rewrite `## Capture log` in `initiatives/<KEY>.md`

That is a thin storage + human-readable log. It is **not** yet automatic collaborative memory.

---

## 2. Target product

**Not a notebook. Collaborative AI memory between engineers on a Jira key, backed only by Supabase.**

```text
Engineer A agent                    Supabase                         Engineer B agent
     |                                 |                                    |
     |-- remember(jira, kind, body) -->| INSERT memory (+ embed async)      |
     |                                 |-- Realtime INSERT event ---------->|
     |                                 |                                    |-- inject into context
     |-- recall(jira, "auth flow") --->| vector / FTS search                |
     |<-- top-k memories --------------|                                    |
```

| Layer | Role |
|-------|------|
| **Jira** | Initiative spine (`AAP-81423`) |
| **Supabase** | Source of truth for memories + membership + realtime |
| **Local cache** | `.team-brain/cache/<KEY>.json` for agents (fast read) |
| **Markdown export** | Optional human/git mirror — **not** the sync bus |

### When sync happens

| Mode | Trigger |
|------|---------|
| **Realtime (preferred)** | Subscribe to inserts for attached initiatives |
| **Periodic / session** | On `attach`, skill start, before `breakdown`, or every N minutes |
| **Write** | `remember` when a finding is durable (agent or human) |

Re-running sync must **not** duplicate rows. Local cache/log is rebuilt or merged from server identity (`id` / `source_ref`).

---

## 3. HiveShare-level bar (Supabase-only)

Reach parity on the **core memory loop** with these five:

1. **Write once, reuse by others** — `remember` (today: `add_capture`)
2. **Retrieve by meaning** — `recall` / `search_memories` (FTS → pgvector)
3. **Live awareness** — Supabase Realtime on `captures` (or `memories`)
4. **Agent-native surface** — MCP / skill tools: `remember`, `recall`, `list_recent`
5. **Dedup / source identity** — `source_ref` (+ content hash) unique per initiative

**Beat** on product fit (not by cloning their server):

- Jira-native attach (no separate space UUID ritual)
- Zero self-host (invite + committed anon project)
- Brain umbrella (same install as engineer-brain; clear personal vs team privacy)
- Skill defaults: auto-`recall` on attach, auto-`remember` after research
- `breakdown` consumes `recall` — workflow differentiator

Later polish (not the win condition): version/rollback, snapshots, rich metrics.

---

## 4. Phased build

### P0 — Stop being a notebook *(in progress)*

- [x] Plan doc (this file)
- [x] Schema: `source_ref`, `content_hash`, FTS column; soft dedup on remember  
  (`supabase/migrations/20260728000001_team_brain_memory.sql` — **apply on live project**)
- [x] RPCs: `remember`, `search_memories`, `list_recent` (+ `add_capture` wrapper)
- [x] CLI: `remember` / `recall`; attach pulls recent → `cache/<KEY>.json`
- [x] Skill + docs: memories are SoT; md is optional export
- [x] Keep existing `capture` / `sync` as compatibility aliases

### P1 — Near-realtime watch *(in progress)*

**Decision:** use authenticated **polling** (`list_recent` + `p_since`), not `postgres_changes`.

Reason: captures revoke SELECT from anon; auth is custom `p_api_key` on RPCs. Realtime CDC uses the JWT role and cannot see rows without opening SELECT to everyone (leak). Polling keeps member-key security.

- [x] `team-brain-api.sh watch <JIRA-KEY> [secs]` — poll, print deltas, refresh cache/md
- [x] Doc note migration `20260728000002_team_brain_watch_notes.sql`
- [ ] Skill: during long sessions, suggest `watch` in background or periodic `recall`
- [ ] Later optional: private Broadcast / Supabase Auth–linked members for push CDC

### P2 — Semantic recall

- [x] `embedding vector(768)` + `pgvector` (`20260729000001_team_brain_embeddings.sql`)
- [x] Embed-on-write in CLI when `TEAM_BRAIN_EMBED_PROVIDER` is set (OpenAI or Ollama)
- [x] `search_memories` cosine when query embedding provided; else FTS
- [x] `reembed <KEY>` backfill via `set_memory_embedding`
- [x] Provider docs below

#### Embedding providers (OSS)

| Provider | Env | Notes |
|----------|-----|--------|
| none (default) | unset | FTS-only recall; no API key needed |
| `openai` | `TEAM_BRAIN_EMBED_PROVIDER=openai` + `TEAM_BRAIN_EMBED_API_KEY` or `OPENAI_API_KEY` | Model default `text-embedding-3-small` with `dimensions=768` |
| `ollama` | `TEAM_BRAIN_EMBED_PROVIDER=ollama` | Default model `nomic-embed-text` (768-d); `TEAM_BRAIN_EMBED_BASE_URL` optional |

```bash
export TEAM_BRAIN_EMBED_PROVIDER=openai
export TEAM_BRAIN_EMBED_API_KEY=sk-...
bash core/scripts/team-brain-api.sh remember AAP-81423 research "EE schema path lives in …"
bash core/scripts/team-brain-api.sh recall AAP-81423 "where is decision_environment scaffolded"
# response includes "mode": "vector" when embeddings exist
```

### P3 — Agent parity

- [x] MCP tools: `remember`, `recall`, `list_recent`, `attach`, `whoami`, … (`mcp/team-brain/`)
- [x] `source_ref` / content-hash dedup (P0 RPCs; documented on MCP `remember`)
- [x] **Mandatory agent loop** — recall *before* research; remember *immediately after* findings  
      (`platforms/cursor/rules/team-brain.mdc` + skill + MCP instructions)
- [ ] Optional long-lived push into the other agent session (HiveShare-style SSE) — still open

### Agent loop (what makes it a shared brain)

```text
Engineer A laptop                         Supabase                         Engineer B laptop
     |                                       |                                    |
     |-- recall(KEY) ----------------------->|                                    |
     |<-- crew memories ---------------------|                                    |
     |-- (research) --- remember(KEY, ref) ->|                                    |
     |                                       |<-- recall(KEY) --------------------|
     |                                       |--- memories (incl. A's) ---------->|
     |                                       |                                    |-- (reuse, then research)
```

Humans can still run CLI manually; **agents must not skip the loop**.

### P4 — Beat on workflow

- [x] `breakdown` consumes recall → `initiatives/<KEY>-breakdown.md` (CLI + MCP)
- [x] Simple reuse metrics → `.team-brain/metrics.json` + `metrics` command
- [ ] Optional Slack/digest via Edge Function (deferred)
- [ ] Team aggregation metrics from roadmap (coverage, collab) — separate track

```bash
bash core/scripts/team-brain-api.sh breakdown AAP-81423
bash core/scripts/team-brain-api.sh metrics AAP-81423
# → initiatives/AAP-81423-breakdown.md + metrics.json (gitignored)
```

---

## 5. Working TODO checklist

Use this as the build board (check off in PRs):

| ID | Phase | Task | Owner notes |
|----|-------|------|-------------|
| M1 | P0 | Migration `…_team_brain_memory.sql` | **Apply after v1** (SQL Editor) |
| M2 | P0 | `remember` RPC (+ dedup) | ✅ in migration |
| M3 | P0 | `search_memories` + `list_recent` | ✅ FTS |
| M4 | P0 | CLI `remember` / `recall` + cache write | ✅ |
| M5 | P0 | Skill/docs language shift | ✅ |
| M6 | P1 | `watch` (authenticated poll) | ✅ |
| M7 | P2 | pgvector + embed path | ✅ — apply `…embeddings.sql` |
| M8 | P3 | MCP server tools | ✅ `mcp/team-brain/` |
| M9 | P4 | breakdown ← recall + metrics | ✅ |

---

## 6. Privacy & security

- Never upload personal `BRAIN.md`
- Never commit `credentials.json` or `service_role`
- Memories are team-visible by design — keep professional
- RPCs stay security-definer; no direct anon table reads
- Unique `(team_id, display_name)`; invite codes 16 hex chars
- **Known v1 gap:** anon `register_team` / `join_team` have no app-level rate limit — document mitigations in [supabase/README.md](../supabase/README.md); prefer Edge Function / Auth for register later
- Near-realtime uses authenticated poll (`watch`), not open postgres_changes

---

## 7. Success metrics (from #2, updated)

- Reduced duplicate research sessions on the same Jira key
- Lower tokens before first meaningful PR on shared work
- Faster onboard of 2nd/3rd engineer (`onboard` + auto-`recall`)
- Epic breakdown quality when prior memories exist
- **New:** recall hit rate / memories reused per initiative week

---

## 8. Still missing vs HiveShare (honest gap list)

| Capability | Team Brain now | HiveShare-class |
|------------|----------------|-----------------|
| Recall before research | ✅ Enforced in rule/skill/MCP instructions | ✅ MCP habit |
| Remember after findings | ✅ Enforced (direct save) | ✅ MCP habit |
| Dedup (`source_ref`) | ✅ | ✅ |
| Semantic search | Optional (embeddings); FTS default | ✅ Core |
| Live push into other agent’s context | ❌ Poll `watch` / next `recall` only | ✅ SSE stream |
| Guaranteed model compliance | Soft (rules/skills — model can still skip) | Soft too, but product is MCP-first |
| Version/history/snapshots | ❌ | ✅ |
| Metrics dashboard | Local `metrics.json` only | Richer reuse metrics |

**Closing the remaining gap:** keep the agent loop mandatory; add optional background cache refresh; turn on embeddings for semantic “did someone already crunch this?”; later private Realtime/Broadcast if we link auth.

## 9. Out of scope (for now)

- Integrating or depending on third-party collaborative memory servers
- Replacing personal engineer-brain commands
- Full org-wide brain (v2 roadmap)

---

## References

- Issue: feat Team Brain — [#2](https://github.com/Hrithik-Gavankar/engineer-brain/issues/2)
- Hybrid sync (current): [team-brain.md](team-brain.md)
- Schema: [../supabase/migrations/](../supabase/migrations/)
- Client: [../core/scripts/team-brain-api.sh](../core/scripts/team-brain-api.sh)
