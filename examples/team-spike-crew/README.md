# Example: Team spike crew

Demo fixture for **Team Brain** local shape (norms + optional markdown export + **commit-safe pin**).

For **live multi-engineer memory**, use Supabase + `team-brain-api.sh` (or MCP) — see [team-brain-onboarding.md](../../docs/team-brain-onboarding.md).

## Layout

```
TEAM.md
team.yaml                 ← local fixture (do not put live anon here in a real crew repo)
project.json              ← commit-safe pin (#39): default Jira key + team name (NO secrets)
initiatives/DEMO-EE-1.md  ← optional export per initiative
```

Live crews also get (gitignored / generated):

```
credentials.json          ← NEVER commit
cache/<JIRA-KEY>.json
metrics.json
sync/
notify/
```

## Path A — pull pin, then onboard with secrets

1. Copy the pin into your workspace (or commit `project.json` under `.team-brain/` in the product repo):

```bash
mkdir -p /path/to/workspace/.team-brain
cp examples/team-spike-crew/project.json /path/to/workspace/.team-brain/project.json
```

2. Admin shares **invite + URL + anon** out of band (not in git).

3. Joiner:

```bash
export TEAM_BRAIN_SUPABASE_URL=https://….supabase.co
export TEAM_BRAIN_SUPABASE_ANON_KEY=eyJ…
# optional viewer:
bash core/scripts/team-brain-api.sh onboard <INVITE> "Bob" --role member
# Jira key comes from project.json pin when omitted
bash core/scripts/team-brain-api.sh start
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

**Admin (preferred):**

```bash
bash core/scripts/team-brain-api.sh bootstrap \
  --team "Spike Crew" --admin "Alice" \
  --url "https://….supabase.co" --anon "eyJ…" \
  --db-url "postgresql://postgres:…@db….supabase.co:5432/postgres" \
  --jira DEMO-EE-1 --write-env

# Commit-safe pin for the product repo:
bash core/scripts/team-brain-api.sh pin set --jira DEMO-EE-1 --team-name "Spike Crew"
# Commit .team-brain/project.json — never credentials.json
```

Or manual: apply migrations → `register "Spike Crew" "Alice"` ([migrations/README.md](../../supabase/migrations/README.md)).

Then:

1. Teammate (write): `onboard <INVITE> "Bob"` (uses pin for Jira when present)
2. Teammate (read-only): `onboard <INVITE> "Carol" --role viewer`
3. Admin: `rotate-invite` · `set-role "Carol" --role member`
4. `remember` → teammate `recall` / agent loop / MCP

### Roles (#40)

| Role | recall / list / breakdown | remember / correct / attach | rotate invite |
|------|---------------------------|-----------------------------|---------------|
| `admin` | ✅ | ✅ | ✅ |
| `member` | ✅ | ✅ | ❌ |
| `viewer` | ✅ | ❌ | ❌ |

### Correction / learning example

When research was wrong, update the **same** `source_ref` (do not fork a second topic):

```bash
bash core/scripts/team-brain-api.sh correct DEMO-EE-1 \
  --source-ref "DEMO-EE-1#ee-schema" \
  --was "Schema lives under tox-ansible" \
  --learning "Was wrong: schema under tox-ansible. Prefer: packages/ansible-language-server." \
  "Prefer packages/ansible-language-server for EE schema paths; avoid assuming tox-ansible owns it."
```

Expect `corrected.updated: true` and a `learning` memory at `DEMO-EE-1#ee-schema/learning`.  
Bodies use prefer/avoid prose — not TODO/NO-TODO dumps.

### History / soft rollback example

After a correction, the prior body is archived (apply `…_memory_history.sql`):

```bash
bash core/scripts/team-brain-api.sh history DEMO-EE-1 --source-ref "DEMO-EE-1#ee-schema"
bash core/scripts/team-brain-api.sh restore DEMO-EE-1 --source-ref "DEMO-EE-1#ee-schema" --revision 1
```
