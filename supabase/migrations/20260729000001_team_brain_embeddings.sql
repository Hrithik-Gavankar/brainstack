-- =============================================================================
-- Team Brain — P2 semantic recall (pgvector)
-- =============================================================================
-- - extensions.vector + embedding column (768-d, OpenAI/Ollama compatible)
-- - remember accepts optional p_embedding
-- - search_memories: cosine when embedding provided; else FTS
-- - set_memory_embedding for backfill
-- Client embeds via TEAM_BRAIN_EMBED_PROVIDER (see docs/team-brain-memory.md)
-- =============================================================================

create schema if not exists extensions;
create extension if not exists vector with schema extensions;

-- 768 dims: OpenAI text-embedding-3-small with dimensions=768, or nomic-embed-text
alter table public.captures
  add column if not exists embedding extensions.vector(768);

-- HNSW cosine index (requires rows later; empty table is fine)
create index if not exists captures_embedding_hnsw_idx
  on public.captures
  using hnsw (embedding vector_cosine_ops)
  where embedding is not null;

-- ---------------------------------------------------------------------------
-- remember — optional embedding on write
-- ---------------------------------------------------------------------------

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

  if v_ref is not null then
    select * into existing
    from public.captures
    where initiative_id = init.id and source_ref = v_ref
    limit 1;
    if found then
      -- Backfill embedding on deduped row if missing
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
        'deduped', true
      );
    end if;
  end if;

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
      'deduped', true
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
    'deduped', false
  );
end;
$$;

-- Keep add_capture wrapper (no embedding)
create or replace function public.add_capture(
  p_api_key text,
  p_jira_key text,
  p_kind text,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return public.remember(p_api_key, p_jira_key, p_kind, p_body, null, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- set_memory_embedding — backfill / late embed
-- ---------------------------------------------------------------------------

create or replace function public.set_memory_embedding(
  p_api_key text,
  p_memory_id uuid,
  p_embedding float[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  m public.members;
  c public.captures;
  init public.initiatives;
begin
  m := public.tb_resolve_member(p_api_key);
  if p_embedding is null or array_length(p_embedding, 1) is distinct from 768 then
    raise exception 'embedding must be 768 dimensions';
  end if;

  select c.* into c
  from public.captures c
  join public.initiatives i on i.id = c.initiative_id
  where c.id = p_memory_id and i.team_id = m.team_id
  limit 1;
  if not found then
    raise exception 'memory not found';
  end if;

  update public.captures
  set embedding = p_embedding::extensions.vector(768)
  where id = c.id
  returning * into c;

  select * into init from public.initiatives where id = c.initiative_id;

  return jsonb_build_object(
    'id', c.id,
    'jira_key', init.jira_key,
    'has_embedding', true
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- search_memories — vector when p_embedding set; else FTS
-- ---------------------------------------------------------------------------

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
      where c.initiative_id = init.id and c.embedding is not null
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

grant execute on function public.remember(text, text, text, text, text, float[]) to anon, authenticated;
grant execute on function public.search_memories(text, text, text, int, float[]) to anon, authenticated;
grant execute on function public.set_memory_embedding(text, uuid, float[]) to anon, authenticated;
grant execute on function public.add_capture(text, text, text, text) to anon, authenticated;

-- Drop old 5-arg remember / 4-arg search if they linger (PostgREST overload ambiguity)
drop function if exists public.remember(text, text, text, text, text);
drop function if exists public.search_memories(text, text, text, int);
