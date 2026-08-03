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

Fill local `supabase/project.public.env` with **your** project URL + anon (placeholders only in git). Joiners do not need their own Supabase account — only the crew’s URL/anon + invite.

### Correction / learning example

When research was wrong, update the **same** `source_ref` (do not fork a second topic):

```bash
# Bad research landed earlier:
bash core/scripts/team-brain-api.sh remember DEMO-EE-1 research \
  --source-ref "DEMO-EE-1#ee-schema" \
  "Schema lives under tox-ansible (WRONG — for demo)."

# Human corrects → merge update + learning row
bash core/scripts/team-brain-api.sh correct DEMO-EE-1 \
  --source-ref "DEMO-EE-1#ee-schema" \
  --was "Schema lives under tox-ansible" \
  --learning "Was wrong: schema under tox-ansible. Prefer: packages/ansible-language-server." \
  "Prefer packages/ansible-language-server for EE schema paths; avoid assuming tox-ansible owns it."
```

Expect `corrected.updated: true` and a `learning` memory at `DEMO-EE-1#ee-schema/learning`.  
Bodies use prefer/avoid prose — not TODO/NO-TODO dumps.

Personal standups: `/engineer-brain sync` only (same absorb-and-learn correction pattern in the engineer-brain skill).
