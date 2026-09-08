-- =============================================================================
-- Team Brain — explicit delete permission + tombstone (#2 workshop governance)
-- =============================================================================
-- Permission tiers (crew-wide):
--   viewer  — read-only (recall, list, breakdown, history, metrics)
--   member  — read + write + delete (remember, correct, restore, delete_memory)
--   admin   — member + rotate_invite / set_member_role / list_members
--
-- Tombstone: captures.deleted_at (hidden from read RPCs; audit in capture_revisions
-- + memory_deletions). remember() at same source_ref undeletes (clears tombstone).
-- Apply after 20260809000001_fix_tb_anon_fingerprint_digest.sql
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Tombstone columns on captures
-- ---------------------------------------------------------------------------

alter table public.captures
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by_member_id uuid references public.members (id) on delete set null;

create index if not exists captures_active_initiative_idx
  on public.captures (initiative_id, coalesce(updated_at, created_at) desc)
  where deleted_at is null;

comment on column public.captures.deleted_at is
  'Tombstone timestamp — non-null rows hidden from recall/list/search; audit preserved.';
comment on column public.captures.deleted_by_member_id is
  'Member who tombstoned this memory (member or admin role).';

-- ---------------------------------------------------------------------------
-- 2) Delete audit table (append-only; no anon SELECT)
-- ---------------------------------------------------------------------------

create table if not exists public.memory_deletions (
  id uuid primary key default extensions.gen_random_uuid(),
  capture_id uuid not null references public.captures (id) on delete cascade,
  initiative_id uuid not null references public.initiatives (id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  source_ref text,
  kind text not null,
  body text not null,
  content_hash text,
  deleted_by_member_id uuid references public.members (id) on delete set null,
  deleted_at timestamptz not null default now()
);

create index if not exists memory_deletions_team_id_idx
  on public.memory_deletions (team_id, deleted_at desc);

alter table public.memory_deletions enable row level security;
revoke all on public.memory_deletions from anon, authenticated;

comment on table public.memory_deletions is
  'Append-only audit of tombstoned memories. Access only via security definer RPCs.';

-- ---------------------------------------------------------------------------
-- 3) Role helpers + comment refresh
-- ---------------------------------------------------------------------------

comment on column public.members.role is
  'admin = full + invite rotate; member = read/write/delete; viewer = read-only';

create or replace function public.tb_require_delete(p_member public.members)
returns void
language plpgsql
stable
as $$
begin
  if p_member.role = 'viewer' then
    raise exception 'forbidden: delete requires member role (viewer is read-only)';
  end if;
end;
$$;

revoke all on function public.tb_require_delete(public.members) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) delete_memory — tombstone + audit (member/admin only)
-- ---------------------------------------------------------------------------

create or replace function public.delete_memory(
  p_api_key text,
  p_jira_key text,
  p_source_ref text
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
  v_ref text;
  v_archived_rev int;
begin
  m := public.tb_resolve_member(p_api_key);
  perform public.tb_require_delete(m);
  v_ref := nullif(trim(coalesce(p_source_ref, '')), '');
  if v_ref is null then
    raise exception 'source_ref required';
  end if;

  select * into init
  from public.initiatives
  where team_id = m.team_id and jira_key = upper(trim(p_jira_key))
  limit 1;
  if not found then
    raise exception 'initiative not found — attach first';
  end if;

  select * into c
  from public.captures
  where initiative_id = init.id and source_ref = v_ref
  limit 1
  for update;
  if not found then
    raise exception 'memory not found for source_ref';
  end if;

  if c.deleted_at is not null then
    return jsonb_build_object(
      'ok', true,
      'deleted', false,
      'deduped', true,
      'jira_key', init.jira_key,
      'source_ref', v_ref,
      'capture_id', c.id,
      'deleted_at', c.deleted_at
    );
  end if;

  v_archived_rev := public.tb_snapshot_capture(c, m.team_id);

  insert into public.memory_deletions (
    capture_id, initiative_id, team_id, source_ref, kind, body, content_hash, deleted_by_member_id
  ) values (
    c.id, init.id, m.team_id, c.source_ref, c.kind, c.body, c.content_hash, m.id
  );

  update public.captures
  set
    deleted_at = now(),
    deleted_by_member_id = m.id,
    body_ct = null,
    updated_at = now()
  where id = c.id
  returning * into c;

  return jsonb_build_object(
    'ok', true,
    'deleted', true,
    'deduped', false,
    'jira_key', init.jira_key,
    'source_ref', v_ref,
    'capture_id', c.id,
    'archived_revision', v_archived_rev,
    'deleted_at', c.deleted_at,
    'deleted_by', m.display_name
  );
end;
$$;

grant execute on function public.delete_memory(text, text, text) to anon, authenticated;

comment on function public.delete_memory(text, text, text) is
  'Tombstone memory at source_ref (member/admin only; viewers forbidden). Audit in capture_revisions + memory_deletions.';

-- ---------------------------------------------------------------------------
-- 5) list_members — admin audit (display_name + role only)
-- ---------------------------------------------------------------------------

create or replace function public.list_members(p_api_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.members;
  result jsonb;
begin
  m := public.tb_resolve_member(p_api_key);
  perform public.tb_require_admin(m);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'display_name', mem.display_name,
      'role', mem.role,
      'member_id', mem.id,
      'created_at', mem.created_at
    ) order by mem.created_at
  ), '[]'::jsonb)
  into result
  from public.members mem
  where mem.team_id = m.team_id;

  return jsonb_build_object(
    'team_id', m.team_id,
    'members', result
  );
end;
$$;

grant execute on function public.list_members(text) to anon, authenticated;

comment on function public.list_members(text) is
  'Admin-only: list crew members (display_name + role). Never returns api_key.';

-- ---------------------------------------------------------------------------
-- 6) Read RPCs — exclude tombstoned captures
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

  select coalesce(jsonb_agg(to_jsonb(x) order by coalesce(x.updated_at, x.created_at) desc), '[]'::jsonb)
  into result
  from (
    select
      c.id,
      c.kind,
      c.body,
      c.source_ref,
      c.content_hash,
      c.created_at,
      c.updated_at,
      c.author_member_id,
      mem.display_name as author_name
    from public.captures c
    join public.members mem on mem.id = c.author_member_id
    where c.initiative_id = init.id
      and c.deleted_at is null
      and (
        p_since is null
        or c.created_at > p_since
        or coalesce(c.updated_at, c.created_at) > p_since
      )
    order by coalesce(c.updated_at, c.created_at) desc
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
    'captures', result
  );
end;
$$;

create or replace function public.search_memories(
  p_api_key text,
  p_jira_key text,
  p_query text,
  p_limit int default 10,
  p_embedding float[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  m public.members;
  init public.initiatives;
  result jsonb;
  lim int;
  use_vector boolean;
  v_emb extensions.vector(768);
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

  use_vector := false;
  if p_embedding is not null then
    if array_length(p_embedding, 1) is distinct from 768 then
      raise exception 'embedding must be 768 dimensions';
    end if;
    v_emb := p_embedding::extensions.vector(768);
    select exists (
      select 1 from public.captures c
      where c.initiative_id = init.id
        and c.embedding is not null
        and c.deleted_at is null
    ) into use_vector;
  end if;

  if use_vector then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.distance asc, x.created_at desc), '[]'::jsonb)
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
        (c.embedding <=> v_emb) as distance,
        null::float as rank,
        'vector'::text as match
      from public.captures c
      join public.members mem on mem.id = c.author_member_id
      where c.initiative_id = init.id
        and c.embedding is not null
        and c.deleted_at is null
      order by c.embedding <=> v_emb, c.created_at desc
      limit lim
    ) x;
  else
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
        null::float as distance,
        ts_rank(c.search_tsv, plainto_tsquery('english', trim(p_query))) as rank,
        'fts'::text as match
      from public.captures c
      join public.members mem on mem.id = c.author_member_id
      where c.initiative_id = init.id
        and c.deleted_at is null
        and c.search_tsv @@ plainto_tsquery('english', trim(p_query))
      order by rank desc, c.created_at desc
      limit lim
    ) x;
  end if;

  return jsonb_build_object(
    'initiative', jsonb_build_object(
      'id', init.id,
      'jira_key', init.jira_key,
      'title', init.title,
      'status', init.status
    ),
    'query', trim(p_query),
    'mode', case when use_vector then 'vector' else 'fts' end,
    'memories', coalesce(result, '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7) remember — undelete tombstoned source_ref on write; skip tombstones in dedup
-- ---------------------------------------------------------------------------

create or replace function public.remember(
  p_api_key text,
  p_jira_key text,
  p_kind text,
  p_body text,
  p_source_ref text default null,
  p_embedding float[] default null,
  p_broadcast_ct text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  m public.members;
  init public.initiatives;
  c public.captures;
  v_kind text;
  v_hash text;
  v_ref text;
  v_emb extensions.vector(768);
  v_ct text;
  author_name text;
  existing public.captures;
  v_archived_rev int;
  v_undeleted boolean := false;
begin
  m := public.tb_resolve_member(p_api_key);
  perform public.tb_require_write(m);
  author_name := m.display_name;
  v_kind := lower(coalesce(nullif(trim(p_kind), ''), 'note'));
  if v_kind not in ('research', 'decision', 'note', 'learning') then
    raise exception 'kind must be research, decision, note, or learning';
  end if;
  if p_body is null or length(trim(p_body)) < 1 then
    raise exception 'body required';
  end if;
  if length(p_body) > 20000 then
    raise exception 'body too long (% chars, max 20000) — split into multiple memories', length(p_body);
  end if;

  if p_embedding is not null then
    if array_length(p_embedding, 1) is distinct from 768 then
      raise exception 'embedding must be 768 dimensions (got %)', coalesce(array_length(p_embedding, 1), 0);
    end if;
    v_emb := p_embedding::extensions.vector(768);
  end if;

  v_ct := nullif(trim(coalesce(p_broadcast_ct, '')), '');
  if v_ct is not null and array_length(regexp_split_to_array(v_ct, ':'), 1) is distinct from 3 then
    v_ct := null;
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
  v_archived_rev := null;

  if v_ref is not null then
    select * into existing
    from public.captures
    where initiative_id = init.id and source_ref = v_ref
    limit 1
    for update;
    if found then
      if existing.deleted_at is not null then
        v_undeleted := true;
      end if;

      if existing.deleted_at is null
         and existing.content_hash is not distinct from v_hash
         and existing.kind is not distinct from v_kind then
        if v_emb is not null and existing.embedding is null then
          update public.captures set embedding = v_emb where id = existing.id
          returning * into existing;
        end if;
        return jsonb_build_object(
          'id', existing.id,
          'initiative_id', existing.initiative_id,
          'jira_key', init.jira_key,
          'kind', existing.kind,
          'body', existing.body,
          'source_ref', existing.source_ref,
          'content_hash', existing.content_hash,
          'has_embedding', existing.embedding is not null,
          'author_member_id', existing.author_member_id,
          'author_name', author_name,
          'created_at', existing.created_at,
          'updated_at', existing.updated_at,
          'deduped', true,
          'updated', false,
          'undeleted', false,
          'archived_revision', null
        );
      end if;

      if existing.deleted_at is null then
        v_archived_rev := public.tb_snapshot_capture(existing, m.team_id);
      end if;

      update public.captures
      set
        kind = v_kind,
        body = trim(p_body),
        content_hash = v_hash,
        embedding = coalesce(v_emb, case when existing.content_hash is distinct from v_hash then null else existing.embedding end),
        body_ct = v_ct,
        deleted_at = null,
        deleted_by_member_id = null,
        updated_at = now()
      where id = existing.id
      returning * into c;

      return jsonb_build_object(
        'id', c.id,
        'initiative_id', c.initiative_id,
        'jira_key', init.jira_key,
        'kind', c.kind,
        'body', c.body,
        'source_ref', c.source_ref,
        'content_hash', c.content_hash,
        'has_embedding', c.embedding is not null,
        'author_member_id', c.author_member_id,
        'author_name', author_name,
        'created_at', c.created_at,
        'updated_at', c.updated_at,
        'deduped', false,
        'updated', true,
        'undeleted', v_undeleted,
        'archived_revision', v_archived_rev
      );
    end if;
  end if;

  select * into existing
  from public.captures
  where initiative_id = init.id
    and content_hash = v_hash
    and deleted_at is null
  order by created_at desc
  limit 1;
  if found then
    if v_emb is not null and existing.embedding is null then
      update public.captures set embedding = v_emb where id = existing.id
      returning * into existing;
    end if;
    return jsonb_build_object(
      'id', existing.id,
      'initiative_id', existing.initiative_id,
      'jira_key', init.jira_key,
      'kind', existing.kind,
      'body', existing.body,
      'source_ref', existing.source_ref,
      'content_hash', existing.content_hash,
      'has_embedding', existing.embedding is not null,
      'author_member_id', existing.author_member_id,
      'author_name', author_name,
      'created_at', existing.created_at,
      'updated_at', existing.updated_at,
      'deduped', true,
      'updated', false,
      'undeleted', false,
      'archived_revision', null
    );
  end if;

  insert into public.captures (initiative_id, author_member_id, kind, body, source_ref, content_hash, embedding, body_ct)
  values (init.id, m.id, v_kind, trim(p_body), v_ref, v_hash, v_emb, v_ct)
  returning * into c;

  return jsonb_build_object(
    'id', c.id,
    'initiative_id', c.initiative_id,
    'jira_key', init.jira_key,
    'kind', c.kind,
    'body', c.body,
    'source_ref', c.source_ref,
    'content_hash', c.content_hash,
    'has_embedding', c.embedding is not null,
    'author_member_id', c.author_member_id,
    'author_name', author_name,
    'created_at', c.created_at,
    'updated_at', c.updated_at,
    'deduped', false,
    'updated', false,
    'undeleted', false,
    'archived_revision', null
  );
end;
$$;

comment on function public.remember(text, text, text, text, text, float[], text) is
  'Write memory (member/admin). Tombstoned source_ref is undeleted on write. Viewers forbidden.';

-- ---------------------------------------------------------------------------
-- 8) restore_memory — clear tombstone on rollback
-- ---------------------------------------------------------------------------

create or replace function public.restore_memory(
  p_api_key text,
  p_jira_key text,
  p_source_ref text,
  p_revision int
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  m public.members;
  init public.initiatives;
  c public.captures;
  r public.capture_revisions;
  v_ref text;
  v_archived_rev int;
  author_name text;
begin
  m := public.tb_resolve_member(p_api_key);
  perform public.tb_require_write(m);
  author_name := m.display_name;
  v_ref := nullif(trim(coalesce(p_source_ref, '')), '');
  if v_ref is null then
    raise exception 'source_ref required';
  end if;
  if p_revision is null or p_revision < 1 then
    raise exception 'revision must be >= 1';
  end if;

  select * into init
  from public.initiatives
  where team_id = m.team_id and jira_key = upper(trim(p_jira_key))
  limit 1;
  if not found then
    raise exception 'initiative not found — attach first';
  end if;

  select * into c
  from public.captures
  where initiative_id = init.id and source_ref = v_ref
  limit 1
  for update;
  if not found then
    raise exception 'memory not found for source_ref';
  end if;

  select * into r
  from public.capture_revisions
  where capture_id = c.id
    and team_id = m.team_id
    and revision = p_revision
  limit 1;
  if not found then
    raise exception 'revision % not found for source_ref (use history; only archived revisions are restorable)', p_revision;
  end if;

  if c.deleted_at is null
     and c.content_hash is not distinct from r.content_hash
     and c.kind is not distinct from r.kind then
    return jsonb_build_object(
      'ok', true,
      'restored', false,
      'deduped', true,
      'jira_key', init.jira_key,
      'source_ref', v_ref,
      'restored_from_revision', p_revision,
      'archived_revision', null,
      'capture', jsonb_build_object(
        'id', c.id,
        'kind', c.kind,
        'body', c.body,
        'content_hash', c.content_hash,
        'source_ref', c.source_ref,
        'updated_at', c.updated_at,
        'author_name', author_name
      )
    );
  end if;

  if c.deleted_at is null then
    v_archived_rev := public.tb_snapshot_capture(c, m.team_id);
  end if;

  update public.captures
  set
    kind = r.kind,
    body = r.body,
    content_hash = r.content_hash,
    embedding = null,
    body_ct = null,
    deleted_at = null,
    deleted_by_member_id = null,
    updated_at = now()
  where id = c.id
  returning * into c;

  return jsonb_build_object(
    'ok', true,
    'restored', true,
    'deduped', false,
    'jira_key', init.jira_key,
    'source_ref', v_ref,
    'restored_from_revision', p_revision,
    'archived_revision', v_archived_rev,
    'capture', jsonb_build_object(
      'id', c.id,
      'kind', c.kind,
      'body', c.body,
      'content_hash', c.content_hash,
      'source_ref', c.source_ref,
      'updated_at', c.updated_at,
      'author_name', author_name
    )
  );
end;
$$;

comment on function public.restore_memory(text, text, text, int) is
  'Soft-rollback (member/admin). Clears tombstone + body_ct. Viewers forbidden.';

-- ---------------------------------------------------------------------------
-- 9) list_memory_history — include tombstone status on current row
-- ---------------------------------------------------------------------------

create or replace function public.list_memory_history(
  p_api_key text,
  p_jira_key text,
  p_source_ref text
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
  v_ref text;
  v_revs jsonb;
  v_max int;
begin
  m := public.tb_resolve_member(p_api_key);
  v_ref := nullif(trim(coalesce(p_source_ref, '')), '');
  if v_ref is null then
    raise exception 'source_ref required';
  end if;

  select * into init
  from public.initiatives
  where team_id = m.team_id and jira_key = upper(trim(p_jira_key))
  limit 1;
  if not found then
    raise exception 'initiative not found — attach first';
  end if;

  select * into c
  from public.captures
  where initiative_id = init.id and source_ref = v_ref
  limit 1;
  if not found then
    raise exception 'memory not found for source_ref';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'revision', r.revision,
      'kind', r.kind,
      'body', r.body,
      'content_hash', r.content_hash,
      'source_ref', r.source_ref,
      'author_member_id', r.author_member_id,
      'created_at', r.created_at,
      'is_current', false,
      'restorable', true
    ) order by r.revision
  ), '[]'::jsonb)
  into v_revs
  from public.capture_revisions r
  where r.capture_id = c.id
    and r.team_id = m.team_id;

  select coalesce(max(revision), 0) into v_max
  from public.capture_revisions
  where capture_id = c.id;

  return jsonb_build_object(
    'jira_key', init.jira_key,
    'source_ref', v_ref,
    'capture_id', c.id,
    'deleted', c.deleted_at is not null,
    'deleted_at', c.deleted_at,
    'revisions', v_revs,
    'current', case
      when c.deleted_at is not null then null
      else jsonb_build_object(
        'revision', null,
        'kind', c.kind,
        'body', c.body,
        'content_hash', c.content_hash,
        'source_ref', c.source_ref,
        'updated_at', c.updated_at,
        'is_current', true,
        'restorable', false
      )
    end,
    'max_archived_revision', v_max
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 10) team_aggregate_metrics — exclude tombstoned memories
-- ---------------------------------------------------------------------------

create or replace function public.team_aggregate_metrics(p_api_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.members;
  t public.teams;
  coverage_member_kind jsonb;
  coverage_member_initiative jsonb;
  coverage_matrix jsonb;
  reuse_per_initiative jsonb;
  reuse_weeks jsonb;
  member_count int;
  initiative_count int;
  memory_count int;
begin
  m := public.tb_resolve_member(p_api_key);

  select * into t from public.teams where id = m.team_id;

  select count(*)::int into member_count
  from public.members where team_id = m.team_id;

  select count(*)::int into initiative_count
  from public.initiatives where team_id = m.team_id;

  select count(*)::int into memory_count
  from public.captures c
  join public.initiatives i on i.id = c.initiative_id
  where i.team_id = m.team_id
    and c.deleted_at is null;

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.count desc, x.author_name, x.kind), '[]'::jsonb)
  into coverage_member_kind
  from (
    select
      mem.display_name as author_name,
      c.kind,
      count(*)::int as count
    from public.captures c
    join public.initiatives i on i.id = c.initiative_id
    join public.members mem on mem.id = c.author_member_id
    where i.team_id = m.team_id
      and c.deleted_at is null
    group by mem.display_name, c.kind
  ) x;

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.count desc, x.author_name, x.jira_key), '[]'::jsonb)
  into coverage_member_initiative
  from (
    select
      mem.display_name as author_name,
      i.jira_key,
      count(*)::int as count
    from public.captures c
    join public.initiatives i on i.id = c.initiative_id
    join public.members mem on mem.id = c.author_member_id
    where i.team_id = m.team_id
      and c.deleted_at is null
    group by mem.display_name, i.jira_key
  ) x;

  select coalesce(jsonb_object_agg(author_name, kinds), '{}'::jsonb)
  into coverage_matrix
  from (
    select
      mem.display_name as author_name,
      jsonb_object_agg(c.kind, cnt) as kinds
    from (
      select author_member_id, kind, count(*)::int as cnt
      from public.captures c
      join public.initiatives i on i.id = c.initiative_id
      where i.team_id = m.team_id
        and c.deleted_at is null
      group by author_member_id, kind
    ) per
    join public.members mem on mem.id = per.author_member_id
    group by mem.display_name
  ) y;

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.memory_count desc, x.jira_key), '[]'::jsonb)
  into reuse_per_initiative
  from (
    select
      i.jira_key,
      i.title,
      i.status,
      count(c.id) filter (where c.deleted_at is null)::int as memory_count,
      count(c.id) filter (
        where c.deleted_at is null
        and coalesce(c.updated_at, c.created_at) >= (now() - interval '7 days')
      )::int as memories_last_7d,
      count(c.id) filter (
        where c.deleted_at is null
        and coalesce(c.updated_at, c.created_at) >= (now() - interval '30 days')
      )::int as memories_last_30d,
      count(distinct c.author_member_id) filter (where c.deleted_at is null)::int as unique_authors
    from public.initiatives i
    left join public.captures c on c.initiative_id = i.id
    where i.team_id = m.team_id
    group by i.jira_key, i.title, i.status
  ) x;

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.week desc, x.jira_key), '[]'::jsonb)
  into reuse_weeks
  from (
    select
      to_char(date_trunc('week', coalesce(c.updated_at, c.created_at)), 'IYYY-"W"IW') as week,
      i.jira_key,
      count(*)::int as memories
    from public.captures c
    join public.initiatives i on i.id = c.initiative_id
    where i.team_id = m.team_id
      and c.deleted_at is null
      and coalesce(c.updated_at, c.created_at) >= (now() - interval '12 weeks')
    group by 1, i.jira_key
  ) x;

  return jsonb_build_object(
    'version', 1,
    'team_id', m.team_id,
    'team_name', t.name,
    'member_count', member_count,
    'initiative_count', initiative_count,
    'memory_count', memory_count,
    'coverage_member_kind', coverage_member_kind,
    'coverage_member_initiative', coverage_member_initiative,
    'coverage_matrix', coverage_matrix,
    'reuse_per_initiative', reuse_per_initiative,
    'reuse_weeks', reuse_weeks,
    'privacy', 'no bodies, no source_ref text, no BRAIN.md'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 11) Legacy list_captures — exclude tombstones (fetch_memories fallback path)
-- ---------------------------------------------------------------------------

create or replace function public.list_captures(
  p_api_key text,
  p_jira_key text,
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
begin
  m := public.tb_resolve_member(p_api_key);

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
      c.created_at,
      c.author_member_id,
      mem.display_name as author_name
    from public.captures c
    join public.members mem on mem.id = c.author_member_id
    where c.initiative_id = init.id
      and c.deleted_at is null
    order by c.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) x;

  return jsonb_build_object(
    'initiative', jsonb_build_object(
      'id', init.id,
      'jira_key', init.jira_key,
      'title', init.title,
      'status', init.status,
      'jira_url', init.jira_url
    ),
    'captures', result
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 12) Realtime broadcast — tombstone signal so peers purge local cache (#66)
-- ---------------------------------------------------------------------------

create or replace function public.tb_notify_memory_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  init public.initiatives;
  author_name text;
  topic text;
  payload jsonb;
  is_tombstone boolean;
begin
  select * into init from public.initiatives where id = NEW.initiative_id;
  if not found then
    return NEW;
  end if;

  select display_name into author_name from public.members where id = NEW.author_member_id;

  is_tombstone := NEW.deleted_at is not null;

  topic := 'team-brain:' || init.team_id::text || ':' || upper(init.jira_key);
  payload := jsonb_build_object(
    'team_id', init.team_id,
    'jira_key', upper(init.jira_key),
    'capture_id', NEW.id,
    'source_ref', NEW.source_ref,
    'kind', NEW.kind,
    'content_hash', NEW.content_hash,
    'author_name', author_name,
    'created_at', NEW.created_at,
    'updated_at', coalesce(NEW.updated_at, NEW.created_at),
    'op', TG_OP,
    'deleted', is_tombstone,
    'deleted_at', NEW.deleted_at,
    'body_ct', case when is_tombstone then null else NEW.body_ct end
  );

  begin
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
  'Realtime Broadcast on capture write/tombstone (#31 + #66): deleted=true signals peers to purge cache.';
