-- Team Brain — sync mode merge semantics
-- When source_ref matches but body changed → UPDATE (not silent ignore).
-- Identical body → deduped no-op. Never blind-overwrite unrelated rows.
-- Adds captures.updated_at for merge / cache freshness.
--
-- Requires pgvector (same as P2 embeddings). Safe if embeddings migration
-- already ran — create extension / column are IF NOT EXISTS.

create schema if not exists extensions;
create extension if not exists vector with schema extensions;

-- Ensure embedding column exists even if P2 was skipped
alter table public.captures
  add column if not exists embedding extensions.vector(768);

alter table public.captures
  add column if not exists updated_at timestamptz not null default now();

drop trigger if exists captures_updated_at on public.captures;
create trigger captures_updated_at
  before update on public.captures
  for each row execute function public.tb_set_updated_at();

-- remember with merge-on-source_ref (keeps optional p_embedding from P2)
-- Signature matches embeddings migration: float[] (not float8[])
create or replace function public.remember(
  p_api_key text,
  p_jira_key text,
  p_kind text,
  p_body text,
  p_source_ref text default null,
  p_embedding float[] default null
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

  if p_embedding is not null then
    if array_length(p_embedding, 1) is distinct from 768 then
      raise exception 'embedding must be 768 dimensions (got %)', coalesce(array_length(p_embedding, 1), 0);
    end if;
    v_emb := p_embedding::extensions.vector(768);
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

  -- Same source_ref: no-op if identical; UPDATE if body/kind changed (merge, not clobber-other-refs)
  if v_ref is not null then
    select * into existing
    from public.captures
    where initiative_id = init.id and source_ref = v_ref
    limit 1;
    if found then
      if existing.content_hash is not distinct from v_hash
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
          'updated', false
        );
      end if;

      update public.captures
      set
        kind = v_kind,
        body = trim(p_body),
        content_hash = v_hash,
        embedding = coalesce(v_emb, case when existing.content_hash is distinct from v_hash then null else existing.embedding end),
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
        'updated', true
      );
    end if;
  end if;

  -- Soft dedup: identical body already stored (no source_ref or new ref)
  select * into existing
  from public.captures
  where initiative_id = init.id and content_hash = v_hash
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
      'updated', false
    );
  end if;

  insert into public.captures (initiative_id, author_member_id, kind, body, source_ref, content_hash, embedding)
  values (init.id, m.id, v_kind, trim(p_body), v_ref, v_hash, v_emb)
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
    'updated', false
  );
end;
$$;

grant execute on function public.remember(text, text, text, text, text, float[]) to anon, authenticated;

comment on function public.remember(text, text, text, text, text, float[]) is
  'Write memory: insert new; identical body/hash → deduped; same source_ref + new body → update (merge).';

-- list_recent: include UPDATED rows (merge sync), not only new inserts
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

grant execute on function public.list_recent(text, text, timestamptz, int) to anon, authenticated;
