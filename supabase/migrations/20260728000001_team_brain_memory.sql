-- =============================================================================
-- Team Brain — collaborative memory (P0)
-- =============================================================================
-- Additive on top of 20260727000001_team_brain.sql
-- - source_ref / content_hash for dedup
-- - FTS for recall
-- - remember / search_memories / list_recent RPCs
-- See docs/team-brain-memory.md
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Columns + indexes
-- ---------------------------------------------------------------------------

alter table public.captures
  add column if not exists source_ref text,
  add column if not exists content_hash text;

-- Generated FTS vector (body + kind)
alter table public.captures
  add column if not exists search_tsv tsvector
  generated always as (
    setweight(to_tsvector('english', coalesce(kind, '')), 'B')
    || setweight(to_tsvector('english', coalesce(body, '')), 'A')
  ) stored;

create unique index if not exists captures_initiative_source_ref_uidx
  on public.captures (initiative_id, source_ref)
  where source_ref is not null and length(trim(source_ref)) > 0;

create index if not exists captures_content_hash_idx
  on public.captures (initiative_id, content_hash)
  where content_hash is not null;

create index if not exists captures_search_tsv_idx
  on public.captures using gin (search_tsv);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.tb_content_hash(p_body text)
returns text
language sql
immutable
as $$
  select encode(extensions.digest(trim(coalesce(p_body, '')), 'sha256'), 'hex');
$$;

-- ---------------------------------------------------------------------------
-- remember — write memory with optional source_ref dedup
-- ---------------------------------------------------------------------------

create or replace function public.remember(
  p_api_key text,
  p_jira_key text,
  p_kind text,
  p_body text,
  p_source_ref text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.members;
  init public.initiatives;
  c public.captures;
  v_kind text;
  v_hash text;
  v_ref text;
  author_name text;
  existing public.captures;
begin
  m := public.tb_resolve_member(p_api_key);
  author_name := m.display_name;
  v_kind := lower(coalesce(nullif(trim(p_kind), ''), 'note'));
  if v_kind not in ('research', 'decision', 'note') then
    raise exception 'kind must be research, decision, or note';
  end if;
  if p_body is null or length(trim(p_body)) < 1 then
    raise exception 'body required';
  end if;

  select * into init
  from public.initiatives
  where team_id = m.team_id and jira_key = upper(trim(p_jira_key))
  limit 1;
  if not found then
    raise exception 'initiative not found — attach first';
  end if;

  v_hash := public.tb_content_hash(p_body);
  v_ref := nullif(trim(coalesce(p_source_ref, '')), '');

  -- Dedup by source_ref
  if v_ref is not null then
    select * into existing
    from public.captures
    where initiative_id = init.id and source_ref = v_ref
    limit 1;
    if found then
      return jsonb_build_object(
        'id', existing.id,
        'initiative_id', existing.initiative_id,
        'jira_key', init.jira_key,
        'kind', existing.kind,
        'body', existing.body,
        'source_ref', existing.source_ref,
        'content_hash', existing.content_hash,
        'author_member_id', existing.author_member_id,
        'author_name', author_name,
        'created_at', existing.created_at,
        'deduped', true
      );
    end if;
  end if;

  -- Soft dedup: identical body already stored for this initiative
  select * into existing
  from public.captures
  where initiative_id = init.id and content_hash = v_hash
  order by created_at desc
  limit 1;
  if found then
    return jsonb_build_object(
      'id', existing.id,
      'initiative_id', existing.initiative_id,
      'jira_key', init.jira_key,
      'kind', existing.kind,
      'body', existing.body,
      'source_ref', existing.source_ref,
      'content_hash', existing.content_hash,
      'author_member_id', existing.author_member_id,
      'author_name', author_name,
      'created_at', existing.created_at,
      'deduped', true
    );
  end if;

  insert into public.captures (initiative_id, author_member_id, kind, body, source_ref, content_hash)
  values (init.id, m.id, v_kind, trim(p_body), v_ref, v_hash)
  returning * into c;

  return jsonb_build_object(
    'id', c.id,
    'initiative_id', c.initiative_id,
    'jira_key', init.jira_key,
    'kind', c.kind,
    'body', c.body,
    'source_ref', c.source_ref,
    'content_hash', c.content_hash,
    'author_member_id', c.author_member_id,
    'author_name', author_name,
    'created_at', c.created_at,
    'deduped', false
  );
end;
$$;

-- Keep add_capture as thin wrapper (compat)
create or replace function public.add_capture(
  p_api_key text,
  p_jira_key text,
  p_kind text,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.remember(p_api_key, p_jira_key, p_kind, p_body, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- search_memories — FTS recall (P2 will add vector)
-- ---------------------------------------------------------------------------

create or replace function public.search_memories(
  p_api_key text,
  p_jira_key text,
  p_query text,
  p_limit int default 10
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.members;
  init public.initiatives;
  result jsonb;
  lim int;
begin
  m := public.tb_resolve_member(p_api_key);
  lim := greatest(1, least(coalesce(p_limit, 10), 50));

  select * into init
  from public.initiatives
  where team_id = m.team_id and jira_key = upper(trim(p_jira_key))
  limit 1;
  if not found then
    raise exception 'initiative not found — attach first';
  end if;

  if p_query is null or length(trim(p_query)) < 1 then
    raise exception 'query required';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.rank desc, x.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      c.id,
      c.kind,
      c.body,
      c.source_ref,
      c.content_hash,
      c.created_at,
      c.author_member_id,
      mem.display_name as author_name,
      ts_rank(c.search_tsv, plainto_tsquery('english', trim(p_query))) as rank
    from public.captures c
    join public.members mem on mem.id = c.author_member_id
    where c.initiative_id = init.id
      and c.search_tsv @@ plainto_tsquery('english', trim(p_query))
    order by rank desc, c.created_at desc
    limit lim
  ) x;

  return jsonb_build_object(
    'initiative', jsonb_build_object(
      'id', init.id,
      'jira_key', init.jira_key,
      'title', init.title,
      'status', init.status
    ),
    'query', trim(p_query),
    'memories', result
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- list_recent — periodic / session sync cursor
-- ---------------------------------------------------------------------------

create or replace function public.list_recent(
  p_api_key text,
  p_jira_key text,
  p_since timestamptz default null,
  p_limit int default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.members;
  init public.initiatives;
  result jsonb;
  lim int;
begin
  m := public.tb_resolve_member(p_api_key);
  lim := greatest(1, least(coalesce(p_limit, 50), 200));

  select * into init
  from public.initiatives
  where team_id = m.team_id and jira_key = upper(trim(p_jira_key))
  limit 1;
  if not found then
    raise exception 'initiative not found — attach first';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      c.id,
      c.kind,
      c.body,
      c.source_ref,
      c.content_hash,
      c.created_at,
      c.author_member_id,
      mem.display_name as author_name
    from public.captures c
    join public.members mem on mem.id = c.author_member_id
    where c.initiative_id = init.id
      and (p_since is null or c.created_at > p_since)
    order by c.created_at desc
    limit lim
  ) x;

  return jsonb_build_object(
    'initiative', jsonb_build_object(
      'id', init.id,
      'jira_key', init.jira_key,
      'title', init.title,
      'status', init.status,
      'jira_url', init.jira_url
    ),
    'since', p_since,
    'memories', result,
    -- compat alias for existing CLI mirror path
    'captures', result
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant execute on function public.remember(text, text, text, text, text) to anon, authenticated;
grant execute on function public.search_memories(text, text, text, int) to anon, authenticated;
grant execute on function public.list_recent(text, text, timestamptz, int) to anon, authenticated;
-- add_capture signature unchanged; re-grant
grant execute on function public.add_capture(text, text, text, text) to anon, authenticated;
