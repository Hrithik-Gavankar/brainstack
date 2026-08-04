# Team Brain (Supabase)

Collaborative **AI memory** for a crew on the same Jira initiative:

| Layer | Role |
|-------|------|
| **Jira** | Initiative identity (`AAP-81423`, …) |
| **Supabase** | Membership + shared memories (SoT) |
| **Local cache** | `.team-brain/cache/<KEY>.json` for agents |
| **Markdown** | Optional export under `initiatives/<KEY>.md` |

[`project.public.env`](project.public.env) ships **placeholders only**. Each crew uses **their own** Supabase project — never commit a live URL or anon JWT to a public repo.

| Role | Needs Supabase account? | Needs |
|------|-------------------------|--------|
| **Crew admin** (once) | **Yes** — create one project for the crew | URL + anon in local `project.public.env` / `team.yaml` / env |
| **Joiner** | No | Crew’s URL + anon (from admin) + invite code + Jira key |

Each engineer gets a personal `credentials.json` after register/join — **never commit** that file.

**Junior onboarding (step-by-step):** [docs/team-brain-onboarding.md](../docs/team-brain-onboarding.md)  
Full plan: [docs/team-brain-memory.md](../docs/team-brain-memory.md) · MCP: [mcp/team-brain/](../mcp/team-brain/)

---

## Start a team (admin — do this first)

**Preferred (one command, ~10 minutes):** [crew bootstrap](#crew-bootstrap-admin-under--10-minutes) — configure → migrate → register → print share bundle.

### Manual path (equivalent steps)

1. Create a project at [supabase.com](https://supabase.com) (free tier is fine).
2. Put **Project URL** + **anon** key into local [`project.public.env`](project.public.env) (replace the placeholders). Set `TEAM_BRAIN_JIRA_SITE` to your org.
3. Apply migrations in order (SQL Editor or `supabase db push`) — see [`migrations/README.md`](migrations/README.md).
4. Register and share the **invite code** (and privately share URL + anon with joiners):

```bash
cd brainstack
bash core/scripts/team-brain-api.sh register "Team Atlas" "Your Name"
```

| Share with the crew | Keep private |
|---------------------|--------------|
| Invite code + project URL + anon key | `credentials.json` / member `api_key` |
| Jira key | Supabase `service_role` key |

`register` prints the invite code once. `join` / `onboard` do **not** return it (members cannot re-share from credentials).

---

## Crew bootstrap (admin under ~10 minutes)

Collapses owner setup into one script ([`core/scripts/team-brain-bootstrap.sh`](../core/scripts/team-brain-bootstrap.sh)):

```bash
cd brainstack

# Hosted project (URL + anon + DB password URI for migrations):
bash core/scripts/team-brain-api.sh bootstrap \
  --team "Spike Crew" --admin "Alice" \
  --url "https://YOUR_REF.supabase.co" \
  --anon "eyJ..." \
  --db-url "postgresql://postgres:YOUR_DB_PASSWORD@db.YOUR_REF.supabase.co:5432/postgres" \
  --jira AAP-81423 \
  --write-env

# Or: fill project.public.env first, link CLI (`supabase link`), then:
bash core/scripts/team-brain-api.sh bootstrap --team "Spike Crew" --admin "Alice" --jira AAP-81423

# Local Docker demo:
bash core/scripts/team-brain-api.sh bootstrap --team "Local Crew" --admin "Alice" --local --jira DEMO-1
```

| Migration path | When |
|----------------|------|
| `--local` | Docker `supabase start` (CLI applies `migrations/`) |
| Linked CLI | `supabase db push` |
| `--db-url` | `psql` applies each migration in timestamp order |
| Neither | Writes `supabase/.bootstrap-migrations.combined.sql` + SQL Editor steps; re-run with `--skip-migrations` |

Bootstrap prints a **share bundle** (invite + URL + anon + joiner checklist).  
**Never commit** live URL/anon/DB password. `--db-url` is never written to `project.public.env`.

Dry-run (no mutations): add `--dry-run`.

---

## Join a team

Ask your admin for: **invite code**, **Jira key**, and the crew’s **Supabase URL + anon key**. Put URL/anon in `project.public.env` (or `.team-brain/team.yaml` / env), then:

```bash
cd brainstack
bash core/scripts/team-brain-api.sh onboard <INVITE> "Your Name" AAP-81423
```

**Day to day**

```bash
bash core/scripts/team-brain-api.sh remember AAP-81423 research "What I learned…"
bash core/scripts/team-brain-api.sh recall AAP-81423
bash core/scripts/team-brain-api.sh breakdown AAP-81423
```

---

## Security (v1)

| Control | Status |
|---------|--------|
| API keys hashed (SHA-256); never stored plaintext | ✅ |
| Direct table access revoked; RPCs security-definer | ✅ |
| Unique `(team_id, display_name)` — no unlimited join spam | ✅ |
| Invite codes 16 hex chars | ✅ |
| Live project URL/anon **not** committed to OSS | ✅ placeholders only |
| `join_team` omits `invite_code`; `whoami` returns it only for admin | ✅ |
| Anon `register_team` / `join_team` **rate limiting** | ✅ DB-level sliding window (default 5 register/h, 15 join/h) |
| pgcrypto calls schema-qualified (`extensions.digest`) | ✅ Required on Supabase (`search_path = public`); see migration `60809` |
| Realtime push body **encrypted app-layer**, not plaintext on the wire | ✅ AES-256-CBC + HMAC-SHA256, per-team key, DB never decrypts |
| `remember` body-size cap | ✅ 20,000 chars |
| RPC request timeouts (client) | ✅ `curl --max-time` (default 20s, `TEAM_BRAIN_HTTP_TIMEOUT`) |
| Client-side readiness preflight | ✅ `team-brain-api.sh doctor` |

Do not commit `service_role` keys or live anon keys to public repos. Rotate invite codes / anon keys if leaked.

**Rate limiting (#32):** `register_team` and `join_team` are rate-limited via a DB-level sliding window (`…_rate_limits.sql`). Defaults: 5 registers/hour, 15 joins/hour per fingerprint. Tunable via Postgres settings (`app.rate_limit_register`, `app.rate_limit_join`). Run `select tb_cleanup_rate_limits()` periodically (or via `pg_cron`) to purge old entries. Monitor: `select * from tb_rate_limit_stats` (authenticated/service_role only).

**Existing projects:** apply any new migration files once (… → **realtime_broadcast** → **roles_and_invites** → **rate_limits** → **aggregate_metrics** → **full_push_and_semantic_hardening**).

**Sync mode:** `bash core/scripts/team-brain-api.sh start <JIRA-KEY>` — one entry, background pull, idle sleep. Requires `…_sync_mode.sql` for merge-on-`source_ref` updates.

**Correction / history:** `correct` + `learning` kind (`…_learning_kind.sql`); `history` / `restore` soft rollback (`…_memory_history.sql` — revisions team-scoped via RPCs, no anon table SELECT).

**Realtime push (#31, full content):** Broadcast on remember (`…_realtime_broadcast.sql` + `…_full_push_and_semantic_hardening.sql`) — no anon SELECT on captures, and the body itself travels **app-layer encrypted** (`body_ct`: AES-256-CBC + HMAC-SHA256, per-team `broadcast_key`), never plaintext, never decrypted by the DB. A resolved member (valid `api_key`) fetches the key once via `memory_broadcast_topic` and decrypts locally with zero extra round-trip. Peers without the key/`cryptography`, or a row just `restore`d (ciphertext cleared to force a correct re-pull), fall back to the original signal + authenticated `list_recent` pull. Peers: `start` / `watch --push` + `pip install websockets cryptography` (`cryptography` optional — omit it and you still get signal + pull). Fallback: poll/`watch` always work (`TEAM_BRAIN_REALTIME=off` to disable push).

**Roles / invites (#40):** `admin` \| `member` (write) \| `viewer` (read-only). Apply `…_roles_and_invites.sql`. Joiners: `onboard … --role viewer`. Admins: `rotate-invite`, `set-role "Name" --role member`.

**Repo pin (#39):** commit `.team-brain/project.json` (Jira key + team name only — never anon/api_key/invite). `start` / `attach` use the pin when the key is omitted.

**Team aggregation (#35):** `team_aggregate_metrics` RPC + `metrics --team` / `aggregate`. Returns counts + `display_name` only — never memory bodies, never personal `BRAIN.md`, never uploads local `metrics.json`. Apply `…_aggregate_metrics.sql`.

**Semantic recall (optional, one-command opt-in — #4):** `bash core/scripts/team-brain-api.sh enable-semantic openai|ollama` persists the provider/model to `team.yaml` (non-secret, shareable with the crew) and tests one embed call; otherwise `recall` uses FTS. The embed API key (`TEAM_BRAIN_EMBED_API_KEY` / `OPENAI_API_KEY`) is always env-only, never written to disk.
