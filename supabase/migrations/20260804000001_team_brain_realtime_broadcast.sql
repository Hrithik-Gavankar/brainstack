-- =============================================================================
-- Team Brain — Realtime push prototype (#31)
-- =============================================================================
-- Design (why poll stayed default; how push stays member-scoped for content):
--
--   v1 used authenticated polling (list_recent + p_api_key) because postgres_changes
--   Realtime evaluates the JWT role (anon). Captures revoke SELECT from anon; opening
--   SELECT would leak all team memories. That security choice remains correct.
--
--   This migration adds a *signal-only* Broadcast from the database:
--     • Payload: team_id, jira_key, capture_id, source_ref, kind, updated_at, op
--     • Never includes memory body
--     • Topic: team-brain:{team_id}:{JIRA_KEY}
--     • Public Broadcast flag (false = public topic) — Team Brain auth is custom
--       api_key RPCs, not Supabase Auth JWTs, so private Realtime Authorization
--       RLS is not available without migrating membership to Auth.
--     • Knowing the topic requires team_id (already in member credentials.json).
--     • Peers still load content only via member-scoped list_recent / recall RPCs
--       (merge-safe source_ref / content-hash unchanged).
--
-- Fallback: CLI watch / sync-mode poll keeps working if realtime.send is missing,
-- websockets unavailable, or TEAM_BRAIN_REALTIME=off.
--
-- Apply after 20260803000001_team_brain_memory_history.sql (captures.source_ref /
-- updated_at already present from earlier memory migrations).
-- =============================================================================

-- Topic helper for clients (member-scoped; returns empty topic if unauthorized)
create or replace function public.memory_broadcast_topic(
  p_api_key text,
  p_jira_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.members;
  init public.initiatives;
  topic text;
begin
  m := public.tb_resolve_member(p_api_key);
  if p_jira_key is null or length(trim(p_jira_key)) < 2 then
    raise exception 'jira_key required';
  end if;
  select * into init
  from public.initiatives
  where team_id = m.team_id and upper(jira_key) = upper(trim(p_jira_key))
  limit 1;
  if not found then
    raise exception 'initiative not found — attach first';
  end if;
  topic := 'team-brain:' || m.team_id::text || ':' || upper(init.jira_key);
  return jsonb_build_object(
    'topic', topic,
    'event', 'memory_changed',
    'private', false,
    'team_id', m.team_id,
    'jira_key', upper(init.jira_key),
    'policy', 'signal_broadcast_public_topic',
    'note', 'Signal only — subscribe with anon key + topic; fetch bodies via list_recent with api_key. No anon SELECT on captures.'
  );
end;
$$;

comment on function public.memory_broadcast_topic(text, text) is
  'Return Realtime Broadcast topic for an attached initiative (member api_key). Signal channel; content still RPC-gated.';

grant execute on function public.memory_broadcast_topic(text, text) to anon, authenticated;

-- Trigger: broadcast metadata after capture insert/update (never fail the write)
create or replace function public.tb_notify_memory_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  init public.initiatives;
  topic text;
  payload jsonb;
begin
  select * into init from public.initiatives where id = NEW.initiative_id;
  if not found then
    return NEW;
  end if;

  topic := 'team-brain:' || init.team_id::text || ':' || upper(init.jira_key);
  payload := jsonb_build_object(
    'team_id', init.team_id,
    'jira_key', upper(init.jira_key),
    'capture_id', NEW.id,
    'source_ref', NEW.source_ref,
    'kind', NEW.kind,
    'updated_at', coalesce(NEW.updated_at, NEW.created_at),
    'op', TG_OP
  );

  begin
    -- Public topic (4th arg false): matches custom api_key auth model (no Auth JWT).
    perform realtime.send(payload, 'memory_changed', topic, false);
  exception
    when undefined_function then
      raise warning 'team-brain: realtime.send unavailable — apply on hosted Supabase or keep poll/watch';
    when undefined_table then
      raise warning 'team-brain: realtime schema unavailable — keep poll/watch';
    when others then
      raise warning 'team-brain broadcast skipped: %', SQLERRM;
  end;

  return NEW;
end;
$$;

comment on function public.tb_notify_memory_changed() is
  'Signal-only Realtime Broadcast on capture write; never includes body; never blocks remember.';

drop trigger if exists captures_notify_memory_changed on public.captures;
create trigger captures_notify_memory_changed
  after insert or update on public.captures
  for each row
  execute function public.tb_notify_memory_changed();
