-- Team Brain — memory version history + soft rollback (#34)
-- Append-only capture_revisions; remember() snapshots prior body on source_ref UPDATE.
-- RPCs: list_memory_history, restore_memory (team-scoped via p_api_key).
--
-- Apply after …_learning_kind.sql (timestamp order).
-- Privacy: table has RLS + revoke SELECT; access only via security definer RPCs.

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

create table if not exists public.capture_revisions (
  id uuid primary key default extensions.gen_random_uuid(),
  capture_id uuid not null references public.captures (id) on delete cascade,
  initiative_id uuid not null references public.initiatives (id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  source_ref text,
  revision int not null check (revision >= 1),
  kind text not null,
  body text not null,
  content_hash text,
  author_member_id uuid references public.members (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (capture_id, revision)
);

create index if not exists capture_revisions_capture_id_idx
  on public.capture_revisions (capture_id, revision desc);
create index if not exists capture_revisions_initiative_ref_idx
  on public.capture_revisions (initiative_id, source_ref);

alter table public.capture_revisions enable row level security;
revoke all on public.capture_revisions from anon, authenticated;

comment on table public.capture_revisions is
  'Append-only prior bodies for captures (source_ref merge / correct / restore). Team-scoped via RPCs.';

-- Snapshot current capture row as next revision number (before overwrite).
create or replace function public.tb_snapshot_capture(
  p_capture public.captures,
  p_team_id uuid
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rev int;
begin
  select coalesce(max(revision), 0) + 1 into v_rev
  from public.capture_revisions
  where capture_id = p_capture.id;

  insert into public.capture_revisions (
    capture_id, initiative_id, team_id, source_ref, revision,
    kind, body, content_hash, author_member_id
  ) values (
    p_capture.id,
    p_capture.initiative_id,
    p_team_id,
    p_capture.source_ref,
    v_rev,
    p_capture.kind,
    p_capture.body,
    p_capture.content_hash,
    p_capture.author_member_id
  );

  return v_rev;
end;
$$;

revoke all on function public.tb_snapshot_capture(public.captures, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- remember — snapshot prior body before source_ref UPDATE
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
  v_archived_rev int;
begin
  m := public.tb_resolve_member(p_api_key);
  author_name := m.display_name;
  v_kind := lower(coalesce(nullif(trim(p_kind), ''), 'note'));
  if v_kind not in ('research', 'decision', 'note', 'learning') then
    raise exception 'kind must be research, decision, note, or learning';
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
  v_archived_rev := null;

  -- Same source_ref: no-op if identical; UPDATE if body/kind changed (merge)
  if v_ref is not null then
    -- Lock row so concurrent merges archive the true prior body (no lost intermediate)
    select * into existing
    from public.captures
    where initiative_id = init.id and source_ref = v_ref
    limit 1
    for update;
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
          'updated', false,
          'archived_revision', null
        );
      end if;

      -- Archive prior body before overwrite (audit trail for correct / restore)
      v_archived_rev := public.tb_snapshot_capture(existing, m.team_id);

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
        'updated', true,
        'archived_revision', v_archived_rev
      );
    end if;
  end if;

  -- Soft dedup: identical body already stored
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
      'updated', false,
      'archived_revision', null
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
    'updated', false,
    'archived_revision', null
  );
end;
$$;

grant execute on function public.remember(text, text, text, text, text, float[]) to anon, authenticated;

comment on function public.remember(text, text, text, text, text, float[]) is
  'Write memory: insert; identical → deduped; same source_ref + new body → archive prior revision then update.';

-- ---------------------------------------------------------------------------
-- list_memory_history — prior revisions + current body (team-scoped)
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

  -- current.revision is null — only archived revisions[] are valid restore targets
  return jsonb_build_object(
    'jira_key', init.jira_key,
    'source_ref', v_ref,
    'capture_id', c.id,
    'revisions', v_revs,
    'current', jsonb_build_object(
      'revision', null,
      'label', 'current',
      'kind', c.kind,
      'body', c.body,
      'content_hash', c.content_hash,
      'source_ref', c.source_ref,
      'author_member_id', c.author_member_id,
      'created_at', c.created_at,
      'updated_at', c.updated_at,
      'is_current', true,
      'restorable', false
    ),
    'revision_count', v_max,
    'note', 'Pass an archived revisions[].revision to restore (current is not a restore target).'
  );
end;
$$;

grant execute on function public.list_memory_history(text, text, text) to anon, authenticated;

comment on function public.list_memory_history(text, text, text) is
  'List archived revisions + current body for a source_ref (member team only).';

-- ---------------------------------------------------------------------------
-- restore_memory — soft rollback; archives current before restore
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

  -- Soft rollback: keep audit trail by archiving current before overwrite
  if c.content_hash is not distinct from r.content_hash
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

  v_archived_rev := public.tb_snapshot_capture(c, m.team_id);

  update public.captures
  set
    kind = r.kind,
    body = r.body,
    content_hash = r.content_hash,
    embedding = null,
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

grant execute on function public.restore_memory(text, text, text, int) to anon, authenticated;

comment on function public.restore_memory(text, text, text, int) is
  'Soft-rollback capture to an archived revision; archives current body first (audit preserved).';
