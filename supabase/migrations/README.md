# Migrations

| File | Description |
|------|-------------|
| [`20260727000001_team_brain.sql`](20260727000001_team_brain.sql) | Team Brain v1 — tables, RLS, RPCs |
| [`20260728000001_team_brain_memory.sql`](20260728000001_team_brain_memory.sql) | **P0 — apply next** — `remember` / FTS / `list_recent` |
| [`20260728000002_team_brain_watch_notes.sql`](20260728000002_team_brain_watch_notes.sql) | P1 — asserts memory RPCs exist (watch is CLI poll) |
| [`20260729000001_team_brain_embeddings.sql`](20260729000001_team_brain_embeddings.sql) | P2 — pgvector(768), vector search, `set_memory_embedding` |
| [`20260729000002_team_brain_security.sql`](20260729000002_team_brain_security.sql) | **PR review** — unique members, stronger invites, `updated_at` trigger |

Apply in timestamp order (`supabase db push` or SQL Editor).  
Joiners do **not** run migrations. Existing projects: apply any new files once.

| Doc | Link |
|-----|------|
| Setup + security | [../README.md](../README.md) |
| Beginner onboard | [../../docs/team-brain-onboarding.md](../../docs/team-brain-onboarding.md) |
| Memory plan | [../../docs/team-brain-memory.md](../../docs/team-brain-memory.md) |
