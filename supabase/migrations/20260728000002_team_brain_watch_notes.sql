-- =============================================================================
-- Team Brain — P1 watch notes (no destructive changes)
-- =============================================================================
-- Near-realtime sync is implemented in the CLI via authenticated polling:
--   bash team-brain-api.sh watch <JIRA-KEY> [interval-seconds]
-- using list_recent(p_since=…) with the member api_key.
--
-- Why not postgres_changes Realtime here?
--   Tables revoke SELECT from anon/authenticated; auth is custom p_api_key on
--   security-definer RPCs. Realtime CDC applies RLS with the JWT role (anon),
--   which cannot see captures — and opening SELECT to anon would leak all
--   team memories. Polling with api_key preserves the security model.
--
-- Future (optional): private Broadcast channels or Supabase Auth–linked members.
-- See docs/team-brain-memory.md
-- =============================================================================

-- Ensure list_recent exists (no-op marker for migration history when applied
-- after 20260728000001_team_brain_memory.sql).
do $$
begin
  if to_regprocedure('public.list_recent(text, text, timestamptz, int)') is null then
    raise exception 'Apply 20260728000001_team_brain_memory.sql before this migration';
  end if;
end $$;
