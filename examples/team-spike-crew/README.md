# Example: Team spike crew

Demo fixture for **Team Brain** local shape (norms + one markdown file per initiative).

For **live multi-engineer memory**, use Supabase + `team-brain-api.sh` (or MCP) — see [team-brain-onboarding.md](../../docs/team-brain-onboarding.md). This folder is the local layout only.

## Layout

```
TEAM.md
team.yaml
initiatives/DEMO-EE-1.md    ← optional export per initiative
```

Live crews also get (gitignored / generated):

```
credentials.json
cache/<JIRA-KEY>.json
metrics.json
```

## Walkthrough (local files)

```bash
cp -r examples/team-spike-crew /path/to/workspace/.team-brain
```

```
/team-brain attach DEMO-EE-1
/team-brain breakdown DEMO-EE-1
```

## Walkthrough (Supabase collaborative memory)

1. Apply migrations from `supabase/` ([migrations/README.md](../../supabase/migrations/README.md))
2. Admin once: `bash core/scripts/team-brain-api.sh register "Spike Crew" "Alice"`
3. Teammate: `bash core/scripts/team-brain-api.sh onboard <INVITE> "Bob" AAP-81423`
4. `remember` → teammate `recall` / agent loop / MCP
5. Optional: `breakdown` / `watch` / `metrics`

URL + anon key ship in `supabase/project.public.env` — joiners do not need a dashboard.

Personal standups: `/engineer-brain sync` only.
