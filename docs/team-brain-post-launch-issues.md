# Team Brain — post-launch GitHub issues

Ready-to-file issues after [#29](https://github.com/Hrithik-Gavankar/engineer-brain/pull/29) merges.

**How to use:** for each block below, create a GitHub issue with the **Title** as the issue title and the **Body** as the issue body (copy from the fenced section). Suggested labels: `enhancement`, `team-brain`.

**Parent context:** [#2](https://github.com/Hrithik-Gavankar/engineer-brain/issues/2), [team-brain-memory.md](team-brain-memory.md), [roadmap.md](roadmap.md).

---

## 1. Sync correction / learning loop

### Title

```
feat(team-brain): sync correction and learning loop for bad research
```

### Body

```markdown
## Summary

When a human corrects bad research or a wrong sync summary, Team Brain (and personal engineer-brain sync) should absorb the correction as ground truth instead of leaving stale or contradictory memory in place.

## Problem

Agents and sync summaries can be wrong. Today there is no first-class path to:

1. Correct the matching memory in place
2. Capture what was learned from the mistake
3. Prefer durable guidance over noisy TODO / NO-TODO lists in memory bodies

## Goals

- On human correction, **update** the matching memory via stable `source_ref` (merge — do not fork a second row for the same topic)
- Record a short **learning**: what was wrong → what is true
- Prefer natural language guidance (“avoid doing X” / “prefer Y”) — **not** explicit `TODO` / `NO-TODO` lists in memory bodies
- Apply the same correction pattern to personal `engineer-brain sync` → update `BRAIN.md` and close scanner/signal gaps when systemic

## Acceptance criteria

- [x] Documented correction flow in team-brain skill + onboarding (human pastes correction → agent updates memory)
- [x] CLI/MCP path: correct or re-`remember` with same `source_ref` → `updated`, not duplicate
- [x] Optional `learning` (or equivalent) kind / convention for “what we got wrong”
- [x] Skill guidance: no TODO/NO-TODO dump style in remembered bodies
- [x] Personal sync correction path mirrors existing standup correction feedback in engineer-brain skill
- [x] Example in docs or `examples/team-spike-crew`

> Implemented in branch `feat/team-brain-correction-learning-loop` (issue #30).

## References

- PR #29 (Team Brain collaborative memory + sync mode)
- Issue #2 (Team Brain)
- `docs/team-brain-memory.md` — agent loop + `source_ref` merge rules
```

---

## 2. Realtime push into peer agent context

### Title

```
feat(team-brain): realtime push of new memories into peer agent context
```

### Body

```markdown
## Summary

Close the HiveShare-class gap: when Engineer A `remember`s, Engineer B’s active session should learn about it without waiting on the next `recall` or `watch` poll.

## Problem

v1 uses authenticated polling (`watch` / sync-mode background pull). That is secure with custom `p_api_key` RPCs, but peer agents do not get true live push into an open chat/session.

## Goals

- Private Broadcast or Auth-linked Realtime CDC that does **not** open anon `SELECT` on memories
- Peer cache refresh and optional agent-visible notification when new rows land for an attached Jira key
- Preserve merge-safe `source_ref` / content-hash dedup

## Acceptance criteria

- [ ] Design note: why poll was chosen (security) and how push stays member-scoped
- [ ] Prototype push path (Supabase Auth-linked members **or** private Broadcast channel)
- [ ] Document fallback: poll/`watch` still works if push unavailable
- [ ] No widening of anon table reads

## References

- `docs/team-brain-memory.md` — P1 watch decision + “Future hardening”
- `docs/roadmap.md` — Team Brain Realtime push
```

---

## 3. Anon register/join rate limits

### Title

```
security(team-brain): rate-limit anon register_team and join_team
```

### Body

```markdown
## Summary

Close the documented v1 security gap: anon `register_team` / `join_team` RPCs have no app-level rate limiting.

## Problem

Invite entropy and unique display names help, but unbounded anon RPC calls remain open to abuse (spam teams / join attempts).

## Goals

- Rate limit or gate `register_team` / `join_team` via Edge Function and/or Supabase Auth
- Keep zero-friction onboard for invite holders as much as possible
- Document the chosen control in `supabase/README.md`

## Acceptance criteria

- [ ] Rate limit or Auth gate on register/join paths
- [ ] Legitimate `onboard INVITE_CODE "Name" JIRA-KEY` still works for invitees
- [ ] Docs updated (known gap removed or marked resolved)
- [ ] Notes on monitoring / abuse response

## References

- `supabase/README.md` — known v1 gap
- Migration `20260729000002_team_brain_security.sql`
- PR #29 review feedback (@tejas161)
```

---

## 4. Semantic recall opt-in for crews

### Title

```
feat(team-brain): one-command semantic recall opt-in for crews
```

### Body

```markdown
## Summary

Embeddings exist (optional OpenAI/Ollama path) but FTS is the default. Make semantic recall an easy, documented crew opt-in so “did someone already crunch this?” works by meaning.

## Problem

HiveShare-class products treat semantic search as core. Team Brain has the plumbing; crews need a clear enable path without reading the full embeddings migration notes.

## Goals

- One-command or short checklist to enable embeddings for a crew
- Clear guidance: when FTS is enough vs when to turn vectors on
- `recall` reports mode (`fts` vs `vector`) consistently in CLI/MCP docs

## Acceptance criteria

- [ ] Crew-facing enable docs (env + `reembed` backfill)
- [ ] Optional helper command or install flag documented
- [ ] Example recall showing `"mode": "vector"` after enable
- [ ] Cost/privacy notes for OpenAI vs Ollama

## References

- Migration `20260729000001_team_brain_embeddings.sql`
- `docs/team-brain-memory.md` — P2 Semantic recall
```

---

## 5. Memory version / history / soft rollback

### Title

```
feat(team-brain): memory version history and soft rollback on source_ref updates
```

### Body

```markdown
## Summary

When a `source_ref` is corrected (especially via the sync correction / learning loop), keep an audit trail and allow soft rollback to a prior body.

## Problem

Merge-safe updates overwrite the current body. Without history, crews cannot see what changed after a bad research correction, or restore a previous finding.

## Goals

- Version or history rows (or append-only revisions) keyed by memory id / `source_ref`
- Soft rollback to a previous revision without losing the audit trail
- Fits the correction/learning loop (issue: sync correction)

## Acceptance criteria

- [x] Schema + RPC design for revisions (or equivalent)
- [x] Update-via-`source_ref` records prior body
- [x] CLI/MCP: list history + restore (or documented SQL/admin path for v1)
- [x] Privacy: history stays team-scoped like memories

> Implemented in branch `feat/team-brain-memory-version-history` (issue #34).

## References

- `docs/team-brain-memory.md` — Future hardening: version/history/snapshots
- Depends on / pairs with: sync correction and learning loop
```

---

## 6. Team aggregation metrics

### Title

```
feat(team-brain): team aggregation metrics (coverage, collab, reuse)
```

### Body

```markdown
## Summary

Ship the second half of Team Brain from issue #2: team-level aggregation beyond per-initiative `metrics.json`.

## Problem

Initiative memory + local reuse metrics exist. Tech leads still lack skill coverage, collaboration patterns, and initiative reuse hit-rate across the crew.

## Goals

- Skill coverage matrix (who is deep where — from opt-in signals, not stalking personal BRAIN.md)
- Collaboration graph (reviews / cross-repo patterns where data is available)
- Reuse hit-rate / memories reused per initiative week
- Privacy-first: opt-in scopes; no upload of personal `BRAIN.md`

## Acceptance criteria

- [ ] Spec which signals are in-scope for v1 of aggregation
- [ ] CLI and/or dashboard surface for at least one aggregation view
- [ ] Document privacy boundaries
- [ ] Link from `docs/roadmap.md` / issue #2

## References

- Issue #2 — Team aggregation section
- `docs/roadmap.md` — Team aggregation metrics
- Existing `metrics` command + `.team-brain/metrics.json`
```

---

## 7. Stronger MCP-first compliance

### Title

```
feat(team-brain): stronger MCP-first recall/remember compliance
```

### Body

```markdown
## Summary

Reduce soft failure where the model skips `recall` before research or `remember` after findings, even when rules/skills say it must.

## Problem

v1 enforcement is soft (Cursor rule + skill + MCP instructions). Models can still skip the loop. HiveShare-class products are MCP-habit-first; we should tighten defaults without blocking legitimate offline CLI use.

## Goals

- Stronger MCP-first defaults for Cursor (and document patterns for other platforms)
- Clear agent-visible failures or prompts when sync is active and recall was skipped
- Keep CLI manual path for humans

## Acceptance criteria

- [ ] Proposal: hard gate vs stronger prompts (pick one for v1 follow-up)
- [ ] Implementation for at least Cursor + team-brain MCP
- [ ] Docs updated in skill + `mcp/team-brain/README.md`
- [ ] No requirement to upload personal BRAIN.md

## References

- `platforms/cursor/rules/team-brain.mdc`
- `platforms/cursor/skills/team-brain/SKILL.md`
- `docs/team-brain-memory.md` — Model compliance row
```

---

## 8. Long-session watch hint

### Title

```
feat(team-brain): skill hint for watch / periodic recall during long sessions
```

### Body

```markdown
## Summary

During long spikes, the team-brain skill should nudge periodic cache refresh via `watch` or `recall` so peer findings land without waiting for idle sleep / next `start`.

## Problem

Sync mode background pull helps, but long sessions can still go stale relative to teammates. The memory plan already calls out: suggest `watch` in background or periodic `recall`.

## Goals

- Skill guidance: every N turns or after long research blocks, refresh
- Optional CLI one-liner in onboarding for background `watch`
- Do not spam the user every turn

## Acceptance criteria

- [ ] Skill/rule text for long-session refresh nudge
- [ ] Onboarding blurb for optional background `watch`
- [ ] Consistent with sync-mode sleep/wake (no conflicting advice)

## References

- `docs/team-brain-memory.md` — P1 open checkbox
- Sync mode: `start` / `touch` / `wake`
```

---

## 9. Launch polish (demo GIF + Office Hours one-pager)

### Title

```
docs(team-brain): launch polish — demo GIF and Office Hours one-pager
```

### Body

```markdown
## Summary

Finish v1.0 launch polish for Team Brain: a short visual demo and a one-pager for Office Hours / social.

## Problem

Collaborative memory + sync mode are demo-ready in code/docs, but README/social still need a GIF/screenshot path (roadmap v1.0 leftover).

## Goals

- Short GIF or screenshot sequence: `start` → summarize crew memory → `remember` → peer `recall`
- One-pager (markdown or slide outline) for AT-AT / Office Hours
- Link from README and website docs

## Acceptance criteria

- [ ] Demo asset in repo or docs site
- [ ] README / website link
- [ ] Office Hours one-pager checked in under `docs/` (or website)

## References

- `docs/roadmap.md` — Now (v1.0): GIF/screenshot demos
- `docs/team-brain-onboarding.md`
```

---

## Filing checklist

After creating issues on GitHub:

- [ ] Link each issue back to #2 and/or PR #29
- [ ] Update `docs/roadmap.md` checkboxes / links if desired
- [ ] Optionally close or comment on #2 with “collaborative memory shipped; remaining work tracked in …”
```
