# Example: Team spike crew

Demo fixture for **Team Brain** layout (one markdown file per initiative).

For **live multi-engineer sync**, use Supabase (`supabase/README.md`) + `team-brain-api.sh` — this folder is the local shape only.

## Layout

```
TEAM.md
team.yaml
initiatives/DEMO-EE-1.md    ← one file per initiative
```

## Walkthrough (local files)

```bash
cp -r examples/team-spike-crew /path/to/workspace/.team-brain
```

```
/team-brain attach DEMO-EE-1
/team-brain breakdown DEMO-EE-1
```

## Walkthrough (Supabase hybrid)

1. Apply migrations from `supabase/`
2. Put `supabase_url` + `supabase_anon_key` in `.team-brain/team.yaml`
3. `/team-brain register "Spike Crew"`
4. `/team-brain attach AAP-81423` (real Jira key)
5. Capture → teammate sync

Personal standups: `/engineer-brain sync` only.
