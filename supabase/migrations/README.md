# Migrations

| File | Description |
|------|-------------|
| [`20260727000001_team_brain.sql`](20260727000001_team_brain.sql) | Team Brain v1 — tables, RLS, RPCs |
| [`20260728000001_team_brain_memory.sql`](20260728000001_team_brain_memory.sql) | **P0 — apply next** — `remember` / FTS / `list_recent` |
| [`20260728000002_team_brain_watch_notes.sql`](20260728000002_team_brain_watch_notes.sql) | P1 — asserts memory RPCs exist (watch is CLI poll) |
| [`20260729000001_team_brain_embeddings.sql`](20260729000001_team_brain_embeddings.sql) | P2 — pgvector(768), vector search, `set_memory_embedding` |
| [`20260729000002_team_brain_security.sql`](20260729000002_team_brain_security.sql) | **PR review** — unique members, stronger invites, `updated_at` trigger |
| [`20260729000003_team_brain_sync_mode.sql`](20260729000003_team_brain_sync_mode.sql) | **Sync mode** — `remember` merge-on-`source_ref`; `list_recent` includes updates; enables `vector` if missing |
| [`20260729000004_team_brain_invite_hygiene.sql`](20260729000004_team_brain_invite_hygiene.sql) | **PR review** — `join_team` omits invite; `whoami` invite only for admin |
| [`20260802000001_team_brain_learning_kind.sql`](20260802000001_team_brain_learning_kind.sql) | **#30** — `learning` kind; `remember` accepts correction-loop learnings |
| [`20260803000001_team_brain_memory_history.sql`](20260803000001_team_brain_memory_history.sql) | **#34** — `capture_revisions`; archive on `source_ref` update; `list_memory_history` / `restore_memory` |
| [`20260804000001_team_brain_realtime_broadcast.sql`](20260804000001_team_brain_realtime_broadcast.sql) | **#31** — signal-only Realtime Broadcast on capture write; `memory_broadcast_topic` |

Apply in timestamp order (`supabase db push`, `psql` via bootstrap `--db-url`, or SQL Editor).  
**Admin shortcut:** `bash core/scripts/team-brain-api.sh bootstrap …` ([supabase/README.md](../README.md)).  
Joiners do **not** run migrations. Existing projects: apply any new files once.

| Doc | Link |
|-----|------|
| Setup + security | [../README.md](../README.md) |
| Beginner onboard | [../../docs/team-brain-onboarding.md](../../docs/team-brain-onboarding.md) |
| Memory plan | [../../docs/team-brain-memory.md](../../docs/team-brain-memory.md) |
