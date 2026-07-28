# Team Brain (Supabase)

Collaborative **AI memory** for a crew on the same Jira initiative:

| Layer | Role |
|-------|------|
| **Jira** | Initiative identity (`AAP-81423`, …) |
| **Supabase** | Membership + shared memories (SoT) |
| **Local cache** | `.team-brain/cache/<KEY>.json` for agents |
| **Markdown** | Optional export under `initiatives/<KEY>.md` |

Project connection details ship in [`project.public.env`](project.public.env) (URL + **anon** key only).  
Each engineer gets a personal `credentials.json` after join — **never commit** that file.

**Junior onboarding (step-by-step):** [docs/team-brain-onboarding.md](../docs/team-brain-onboarding.md)  
Full plan: [docs/team-brain-memory.md](../docs/team-brain-memory.md) · MCP: [mcp/team-brain/](../mcp/team-brain/)

---

## Join a team

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

## Start a team

```bash
bash core/scripts/team-brain-api.sh register "Team Atlas" "Your Name"
```

| Share with the crew | Keep private |
|---------------------|--------------|
| Invite code | `credentials.json` / `api_key` |
| Jira key | Supabase `service_role` key |

---

## Security (v1)

| Control | Status |
|---------|--------|
| API keys hashed (SHA-256); never stored plaintext | ✅ |
| Direct table access revoked; RPCs security-definer | ✅ |
| Unique `(team_id, display_name)` — no unlimited join spam | ✅ |
| Invite codes 16 hex chars | ✅ |
| Anon `register_team` / `join_team` **rate limiting** | ⚠️ known gap — use Edge Function / plan limits / Auth for register in a follow-up |

Do not commit `service_role` keys. Rotate invite codes if leaked.

---

## Appendix — provision a new Supabase project

1. Create a project at [supabase.com](https://supabase.com).
2. Put Project URL + **anon** key in [`project.public.env`](project.public.env). Set `TEAM_BRAIN_JIRA_SITE` to your org (placeholder: `https://your-org.atlassian.net`).
3. Apply migrations in order (SQL Editor or `supabase db push`) — see [`migrations/README.md`](migrations/README.md).
4. `register` a team and share invite codes.

**Existing demo projects:** apply any new migration files once (memory → embeddings → security).

**Semantic recall (optional):** `TEAM_BRAIN_EMBED_PROVIDER=openai|ollama` — otherwise `recall` uses FTS.
