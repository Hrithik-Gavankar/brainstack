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

1. Create a project at [supabase.com](https://supabase.com) (free tier is fine).
2. Put **Project URL** + **anon** key into local [`project.public.env`](project.public.env) (replace the placeholders). Set `TEAM_BRAIN_JIRA_SITE` to your org.
3. Apply migrations in order (SQL Editor or `supabase db push`) — see [`migrations/README.md`](migrations/README.md).
4. Register and share the **invite code** (and privately share URL + anon with joiners):

```bash
cd engineer-brain
bash core/scripts/team-brain-api.sh register "Team Atlas" "Your Name"
```

| Share with the crew | Keep private |
|---------------------|--------------|
| Invite code + project URL + anon key | `credentials.json` / member `api_key` |
| Jira key | Supabase `service_role` key |

`register` prints the invite code once. `join` / `onboard` do **not** return it (members cannot re-share from credentials).

---

## Join a team

Ask your admin for: **invite code**, **Jira key**, and the crew’s **Supabase URL + anon key**. Put URL/anon in `project.public.env` (or `.team-brain/team.yaml` / env), then:

```bash
cd engineer-brain
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
| Anon `register_team` / `join_team` **rate limiting** | ⚠️ known gap — use Edge Function / plan limits / Auth for register in a follow-up |

Do not commit `service_role` keys or live anon keys to public repos. Rotate invite codes / anon keys if leaked.

**Existing projects:** apply any new migration files once (memory → embeddings → security → sync_mode → **invite_hygiene**).

**Sync mode:** `bash core/scripts/team-brain-api.sh start <JIRA-KEY>` — one entry, background pull, idle sleep. Requires `…_sync_mode.sql` for merge-on-`source_ref` updates.

**Semantic recall (optional):** `TEAM_BRAIN_EMBED_PROVIDER=openai|ollama` — otherwise `recall` uses FTS.
