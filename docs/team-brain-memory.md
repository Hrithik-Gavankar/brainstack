# Team Brain — Collaborative AI Memory (plan)

Status: **P0–P4 + sync mode + Realtime full push (#31) + semantic recall opt-in (#4) shipped** (anon rate limits closed — see [#32](https://github.com/Hrithik-Gavankar/brainstack/issues/32))  
Related: [#2](https://github.com/Hrithik-Gavankar/brainstack/issues/2), [team-brain.md](team-brain.md), [team-brain-onboarding.md](team-brain-onboarding.md), [scopes.md](scopes.md)

This document captures the original Team Brain intent, what shipped for collaborative AI memory (FTS + optional semantic recall + agent loop), and remaining gaps — without depending on external memory products.

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

### Early demo slice (superseded)

- Invite / register / join on Supabase
- Jira key as initiative identity
- `capture` + pull `sync` → rewrite `## Capture log` in `initiatives/<KEY>.md`

That thin log is kept as **compat aliases**. Current product: `remember` / `recall` → Supabase SoT + `cache/<KEY>.json`, MCP, Cursor agent loop, `breakdown` / `metrics`.

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

## 3. Core memory bar (Supabase-only)

The product must deliver this **core memory loop**:

1. **Write once, reuse by others** — `remember`
2. **Retrieve by meaning** — `recall` / `search_memories` (FTS → optional pgvector)
3. **Live awareness** — near-realtime updates for attached initiatives (`watch` today; push later)
4. **Agent-native surface** — MCP / skill tools: `remember`, `recall`, `list_recent`
5. **Dedup / source identity** — `source_ref` (+ content hash) unique per initiative

**Product fit (Brain umbrella):**

- Jira-native attach
- Zero Supabase account for joiners (admin hosts one project; share invite + URL/anon out of band — repo ships placeholders only)
- Admin **bootstrap** one-shot (`team-brain-bootstrap.sh` / `bootstrap`) for migrate + register + share bundle (#41)
- Clear personal vs team privacy
- Agent loop: `recall` before research, `remember` after findings
- Correction loop: human paste → `correct` / same `source_ref` update + optional `learning`
- `breakdown` consumes `recall`

Later polish: version/rollback, snapshots, richer metrics.

---

## 4. Phased build

### P0 — Stop being a notebook *(done)*

- [x] Plan doc (this file)
- [x] Schema: `source_ref`, `content_hash`, FTS column; soft dedup on remember  
  (`supabase/migrations/20260728000001_team_brain_memory.sql` — **apply on live project**)
- [x] RPCs: `remember`, `search_memories`, `list_recent` (+ `add_capture` wrapper)
- [x] CLI: `remember` / `recall`; attach pulls recent → `cache/<KEY>.json`
- [x] Skill + docs: memories are SoT; md is optional export
- [x] Keep existing `capture` / `sync` as compatibility aliases

### P1 — Near-realtime watch *(done — poll + full-content Broadcast push)*

**Decision (poll):** use authenticated **polling** (`list_recent` + `p_since`), not `postgres_changes`.

Reason: captures revoke SELECT from anon; auth is custom `p_api_key` on RPCs. Realtime CDC uses the JWT role and cannot see rows without opening SELECT to everyone (leak). Polling keeps member-key security for **content**.

**Decision (push, #31 — full content):** rather than migrating membership to Supabase Auth JWTs to unlock private Realtime Authorization, Team Brain closes the same gap with **application-layer encryption**. Each team gets a random 256-bit `broadcast_key` (server-generated; returned only to a resolved member via `memory_broadcast_topic`). The CLI encrypts the body (AES-256-CBC + HMAC-SHA256, encrypt-then-MAC) *before* `remember`, and the DB trigger forwards that opaque `body_ct` — still on the same **public** topic `team-brain:{team_id}:{JIRA_KEY}` — never decrypting it. A peer holding the key decrypts inline in `team-brain-realtime.py` and writes straight into `.team-brain/cache/<KEY>.json`: **zero extra RPC round-trip**. Anyone without the key (or without the optional `cryptography` dependency) only ever sees ciphertext, and transparently falls back to the original signal + authenticated `_pull_signal` pull — the same safety net #31 shipped with initially.

- [x] `team-brain-api.sh watch <JIRA-KEY> [secs]` — poll, print deltas, refresh cache/md
- [x] Doc note migration `20260728000002_team_brain_watch_notes.sql`
- [x] Push transport: migration `20260804000001_team_brain_realtime_broadcast.sql` + `team-brain-realtime.py`
- [x] **Full content push:** migration `20260808000001_team_brain_full_push_and_semantic_hardening.sql` — encrypted `body_ct`, per-team `broadcast_key`, inline decrypt-and-cache in the listener
- [x] Fallback: poll / `watch` / sync-mode loop if Realtime, `websockets`, or `cryptography` unavailable (`TEAM_BRAIN_REALTIME=off`); also falls back on HMAC mismatch, decrypt failure, or a `restore`d row (ciphertext cleared server-side to force a correct re-pull)
- [x] Skill: during long sessions, suggest `watch` in background or periodic `recall` (#37)
- [x] No widening of anon `SELECT` — the DB never decrypts `body_ct`; it is opaque end-to-end except to members who resolved the key with a valid `api_key`

### P2 — Semantic recall *(done — one-command crew opt-in, #4)*

- [x] `embedding vector(768)` + `pgvector` (`20260729000001_team_brain_embeddings.sql`)
- [x] Embed-on-write in CLI when `TEAM_BRAIN_EMBED_PROVIDER` is set (OpenAI or Ollama)
- [x] `search_memories` cosine when query embedding provided; else FTS
- [x] `reembed <KEY>` backfill via `set_memory_embedding`
- [x] **One-command crew opt-in (#4):** `enable-semantic <openai|ollama>` persists `provider`/`model` to `team.yaml` (non-secret, shareable — every teammate who pulls the repo/config inherits it) and tests one live embed call
- [x] Provider docs below

#### Embedding providers (OSS)

| Provider | Env | Notes |
|----------|-----|--------|
| none (default) | unset | FTS-only recall; no API key needed |
| `openai` | `TEAM_BRAIN_EMBED_PROVIDER=openai` + `TEAM_BRAIN_EMBED_API_KEY` or `OPENAI_API_KEY` | Model default `text-embedding-3-small` with `dimensions=768`. Cost: ~$0.02 per 1M input tokens (Aug 2026 pricing) — a crew writing a few hundred memories/month costs cents. Body leaves your machine → OpenAI. |
| `ollama` | `TEAM_BRAIN_EMBED_PROVIDER=ollama` | Default model `nomic-embed-text` (768-d); `TEAM_BRAIN_EMBED_BASE_URL` optional. Cost: $0 (local inference). Body never leaves your machine — best choice for sensitive/regulated content. |

**One-command opt-in (recommended path):**

```bash
bash core/scripts/team-brain-api.sh enable-semantic openai   # or: enable-semantic ollama
export TEAM_BRAIN_EMBED_API_KEY=sk-...                        # openai only — never persisted to team.yaml
bash core/scripts/team-brain-api.sh enable-semantic openai   # re-run to verify: prints vector dims on success

bash core/scripts/team-brain-api.sh remember AAP-81423 research "EE schema path lives in …"
bash core/scripts/team-brain-api.sh recall AAP-81423 "where is decision_environment scaffolded"
# → stderr: "recall mode: vector (openai)"; response body: "mode": "vector"
bash core/scripts/team-brain-api.sh reembed AAP-81423        # backfill memories written before opt-in
```

Manual/legacy path (still works, e.g. for one-off scripting): export `TEAM_BRAIN_EMBED_PROVIDER` / `_MODEL` / `_BASE_URL` directly — `enable-semantic` is just a documented, persisted shortcut for the same env vars.

**When FTS is enough vs when to turn on vectors:** FTS (default, zero setup) is fine for exact/near-exact keyword recall — "find the memory where we discussed X". Turn on vectors once a crew is asking conceptual questions ("did anyone already figure out auth for this service?") where the right memory doesn't share vocabulary with the query.

### P3 — Agent parity

- [x] MCP tools: `remember`, `recall`, `list_recent`, `attach`, `whoami`, … (`mcp/team-brain/`)
- [x] `source_ref` / content-hash dedup (P0 RPCs; documented on MCP `remember`)
- [x] **Mandatory agent loop** — recall *before* research; remember *immediately after* findings  
      (`platforms/cursor/rules/team-brain.mdc` + skill + MCP instructions)
- [x] **Correction / learning loop** — `correct` CLI/MCP; `learning` kind; skill + onboarding  
      (`20260802000001_team_brain_learning_kind.sql`, issue [#30](https://github.com/Hrithik-Gavankar/brainstack/issues/30))
- [x] **Memory version history / soft rollback** — `capture_revisions`; archive on `source_ref` update;  
      `history` / `restore` CLI+MCP (`20260803000001_team_brain_memory_history.sql`, issue [#34](https://github.com/Hrithik-Gavankar/brainstack/issues/34))
- [x] Optional long-lived push into the other agent session — encrypted full-content Broadcast + `notify/<KEY>.json` (#31); poll remains fallback

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
- [x] Team aggregation metrics (#35) — coverage + reuse via `metrics --team` / `aggregate` (collab graph deferred)

```bash
bash core/scripts/team-brain-api.sh breakdown AAP-81423
bash core/scripts/team-brain-api.sh metrics AAP-81423
# → initiatives/AAP-81423-breakdown.md + metrics.json (gitignored)
bash core/scripts/team-brain-api.sh metrics --team   # crew coverage + reuse (#35)
```

### Team aggregation v1 signals (#35)

| In scope (opt-in Team Brain activity) | Out of scope for v1 |
|---------------------------------------|---------------------|
| Member `display_name` × memory `kind` counts | Personal `BRAIN.md` / career skills |
| Member × initiative (`jira_key`) memory counts | Memory bodies / `source_ref` text in aggregate payload |
| Memories per initiative + ISO-week activity | GitHub/GitLab review collaboration graph |
| Local `metrics.json` recall overlay (this machine only) | Uploading local metrics to the server |
| Crew members with a valid team `api_key` | Org-wide dashboards beyond the crew |

**CLI:** `metrics --team` or `aggregate` → prefers RPC `team_aggregate_metrics` (migration `20260807000001_…`); falls back to `list_recent` with bodies stripped.  
**Privacy:** same boundary as `list_initiatives` — never uploads personal `BRAIN.md`; aggregate response has no bodies.  
**Parent:** [#2](https://github.com/Hrithik-Gavankar/brainstack/issues/2) · issue [#35](https://github.com/Hrithik-Gavankar/brainstack/issues/35) · roadmap: [roadmap.md](roadmap.md)

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
- **Aggregation (#35):** `team_aggregate_metrics` returns counts + `display_name` only — never memory bodies, never personal `BRAIN.md`, never local `metrics.json` upload
- **Closed (#32):** anon `register_team` / `join_team` are DB-level rate limited (sliding window; default 5 register/h, 15 join/h) — see [supabase/README.md](../supabase/README.md)
- Near-realtime: authenticated poll (`watch`) + full-content Broadcast — body travels **app-layer encrypted** (`body_ct`), never plaintext, never via a widened anon `SELECT`; the DB stores/forwards ciphertext but never decrypts it
- `remember` rejects bodies over 20,000 characters (hardening — see migration `20260808000001_…`)
- `doctor` gives a client-side readiness preflight (deps, config, migrations, push/embedding mode) — run it before reporting "Team Brain is broken"

---

## 7. Success metrics (from #2, updated)

- Reduced duplicate research sessions on the same Jira key
- Lower tokens before first meaningful PR on shared work
- Faster onboard of 2nd/3rd engineer (`onboard` + auto-`recall`)
- Epic breakdown quality when prior memories exist
- **New:** recall hit rate / memories reused per initiative week

---

## 8. Future hardening (roadmap)

| Capability | Today | Next |
|------------|-------|------|
| Recall before research | ✅ Rule/skill/MCP | Keep mandatory |
| Remember after findings | ✅ Direct save | Keep mandatory |
| Dedup (`source_ref`) | ✅ | — |
| Correction / learning | ✅ `correct` + `learning` kind | — |
| Version/history/soft rollback | ✅ `history` / `restore` + `capture_revisions` | Optional snapshots / UI |
| Semantic search | ✅ One-command opt-in (`enable-semantic`); FTS default (#4) | — |
| Live push into other agent context | ✅ Full-content encrypted Broadcast + poll fallback (#31) | Optional key rotation command if a member is offboarded |
| Model compliance | ✅ Stronger prompts + soft session gate (`compliance` / `prepare_research`; CLI not hard-blocked) | Optional hard gate / metrics later |
| Metrics | Local `metrics.json` + crew `metrics --team` (#35) | Optional team dashboard UI |
| Request/body hardening | ✅ `remember` 20000-char body cap; `curl --max-time` on all RPCs; `doctor` readiness preflight | — |

## 9. Out of scope (for now)

- Replacing personal engineer-brain commands
- Full org-wide brain (v2 roadmap)

---

## References

- Issue: feat Team Brain — [#2](https://github.com/Hrithik-Gavankar/brainstack/issues/2)
- Overview: [team-brain.md](team-brain.md)
- Beginner onboarding: [team-brain-onboarding.md](team-brain-onboarding.md)
- Architecture: [architecture.md](architecture.md)
- Schema: [../supabase/migrations/](../supabase/migrations/)
- Client: [../core/scripts/team-brain-api.sh](../core/scripts/team-brain-api.sh)
- MCP: [../mcp/team-brain/README.md](../mcp/team-brain/README.md)
