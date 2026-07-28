# Team Brain sync

Team Brain keeps initiative context shared across a crew:

- **Jira** identifies the work (`AAP-81423`, …)
- **Supabase** syncs membership and captures
- **Local markdown** mirrors each initiative under `.team-brain/initiatives/<KEY>.md`

Project connection details ship in the repo ([`project.public.env`](project.public.env)).  
Each engineer gets a personal `credentials.json` after they join — never commit that file.

---

## Join a team

Ask a teammate for an **invite code** (and the Jira key you are working on).

```bash
cd engineer-brain
bash core/scripts/team-brain-api.sh onboard <INVITE> "Your Name" AAP-81423
```

You are ready when that command finishes — no dashboard, no API keys to copy.

**Day to day**

```bash
bash core/scripts/team-brain-api.sh capture AAP-81423 research "What I learned…"
bash core/scripts/team-brain-api.sh sync AAP-81423
```

---

## Start a team

Run once as the person creating the crew, then share the printed **invite code** (not your personal API key):

```bash
bash core/scripts/team-brain-api.sh register "Team Atlas" "Your Name"
```

| Share with the crew | Keep private |
|---------------------|--------------|
| Invite code | Your `credentials.json` / `api_key` |
| Jira key for the initiative | Supabase `service_role` key |

---

## Useful commands

```bash
bash core/scripts/team-brain-api.sh whoami
bash core/scripts/team-brain-api.sh sync AAP-81423
bash core/scripts/team-brain-api.sh list
bash core/scripts/team-brain-api.sh status
```

---

## Appendix — provision a new Supabase project

Only when standing up sync on a **new** project (not required to join an existing team).

1. Create a project at [supabase.com](https://supabase.com).
2. Put the Project URL and **anon** key in [`project.public.env`](project.public.env).
3. Apply [`migrations/20260727000001_team_brain.sql`](migrations/20260727000001_team_brain.sql) (SQL Editor or `supabase db push`).
4. `register` a team and share invite codes with the crew.
