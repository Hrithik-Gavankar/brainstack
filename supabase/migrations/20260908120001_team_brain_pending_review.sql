-- =============================================================================
-- Team Brain — redundant-memory guard + admin approval queue (#67)
-- =============================================================================
-- Feedback engine: remember() blocks near-duplicates / cross-author overrides;
-- members queue with p_queue_for_review; admins approve/reject via RPC.
-- Apply after 20260908000001_team_brain_delete_permissions.sql
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Pending submissions (admin review queue)
-- ---------------------------------------------------------------------------

create table if not exists public.memory_pending_submissions (
  id uuid primary key default extensions.gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  initiative_id uuid not null references public.initiatives (id) on delete cascade,
  author_member_id uuid not null references public.members (id) on delete cascade,
  kind text not null,
  body text not null,
  source_ref text,
  content_hash text not null,
  target_capture_id uuid references public.captures (id) on delete set null,
  conflict_reason text not null check (conflict_reason in (
    'semantic_duplicate', 'source_ref_override'
  )),
  match_metadata jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by_member_id uuid references public.members (id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists memory_pending_team_status_idx
  on public.memory_pending_submissions (team_id, status, created_at desc);

create index if not exists memory_pending_initiative_status_idx
  on public.memory_pending_submissions (initiative_id, status, created_at desc);

alter table public.memory_pending_submissions enable row level security;
revoke all on public.memory_pending_submissions from anon, authenticated;

comment on table public.memory_pending_submissions is
  'Admin review queue for redundant/conflicting memory writes (#67). RPC access only.';

-- ---------------------------------------------------------------------------
-- 2) Similar-memory detector (FTS + optional vector)
-- ---------------------------------------------------------------------------

create or replace function public.tb_find_similar_memories(
  p_initiative_id uuid,
  p_body text,
  p_embedding extensions.vector(768) default null,
  p_exclude_source_ref text default null,
  p_limit int default 5
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_lim int;
  v_matches jsonb := '[]'::jsonb;
  v_vector jsonb;
  v_fts jsonb;
  v_query text;
begin
  v_lim := greatest(1, least(coalesce(p_limit, 5), 10));

  if p_embedding is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.distance asc), '[]'::jsonb)
    into v_vector
    from (
      select
        c.id as capture_id,
        c.source_ref,
        c.kind,
        left(c.body, 240) as body_preview,
        c.author_member_id,
        mem.display_name as author_name,
        (c.embedding <=> p_embedding) as distance,
        null::float as rank,
        'vector'::text as match_type,
        greatest(0, least(1, 1 - (c.embedding <=> p_embedding))) as similarity
      from public.captures c
      join public.members mem on mem.id = c.author_member_id
      where c.initiative_id = p_initiative_id
        and c.deleted_at is null
        and c.embedding is not null
        and (p_exclude_source_ref is null or c.source_ref is distinct from p_exclude_source_ref)
        and (c.embedding <=> p_embedding) <= 0.12
      order by c.embedding <=> p_embedding
      limit v_lim
    ) x;
    v_matches := v_vector;
  end if;

  v_query := left(regexp_replace(trim(coalesce(p_body, '')), '\s+', ' ', 'g'), 400);
  if length(v_query) >= 8 then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.rank desc), '[]'::jsonb)
    into v_fts
    from (
      select
        c.id as capture_id,
        c.source_ref,
        c.kind,
        left(c.body, 240) as body_preview,
        c.author_member_id,
        mem.display_name as author_name,
        null::float as distance,
        ts_rank(c.search_tsv, plainto_tsquery('english', v_query)) as rank,
        'fts'::text as match_type,
        ts_rank(c.search_tsv, plainto_tsquery('english', v_query)) as similarity
      from public.captures c
      join public.members mem on mem.id = c.author_member_id
      where c.initiative_id = p_initiative_id
        and c.deleted_at is null
        and c.search_tsv @@ plainto_tsquery('english', v_query)
        and (p_exclude_source_ref is null or c.source_ref is distinct from p_exclude_source_ref)
        and ts_rank(c.search_tsv, plainto_tsquery('english', v_query)) >= 0.05
      order by rank desc
      limit v_lim
    ) x;

    if v_matches = '[]'::jsonb or v_matches is null then
      v_matches := coalesce(v_fts, '[]'::jsonb);
    end if;
  end if;

  return coalesce(v_matches, '[]'::jsonb);
end;
$$;

revoke all on function public.tb_find_similar_memories(uuid, text, extensions.vector(768), text, int) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Queue helper
-- ---------------------------------------------------------------------------

create or replace function public.tb_insert_pending_submission(
  p_team_id uuid,
  p_initiative_id uuid,
  p_author_member_id uuid,
  p_kind text,
  p_body text,
  p_source_ref text,
  p_content_hash text,
  p_target_capture_id uuid,
  p_conflict_reason text,
  p_match_metadata jsonb
)
returns public.memory_pending_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  row public.memory_pending_submissions;
begin
  insert into public.memory_pending_submissions (
    team_id, initiative_id, author_member_id, kind, body, source_ref, content_hash,
    target_capture_id, conflict_reason, match_metadata, status
  ) values (
    p_team_id, p_initiative_id, p_author_member_id, p_kind, trim(p_body), p_source_ref,
    p_content_hash, p_target_capture_id, p_conflict_reason, coalesce(p_match_metadata, '{}'::jsonb),
    'pending'
  )
  returning * into row;
  return row;
end;
$$;

revoke all on function public.tb_insert_pending_submission(uuid, uuid, uuid, text, text, text, text, uuid, text, jsonb)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) remember — redundant guard + optional queue (#67)
-- ---------------------------------------------------------------------------

-- Standard capture payload (preserves pre-#67 remember response fields on success paths)
create or replace function public.tb_remember_capture_json(
  p_result text,
  p_capture public.captures,
  p_jira_key text,
  p_author_name text,
  p_deduped boolean,
  p_updated boolean,
  p_undeleted boolean,
  p_archived_revision int
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'result', p_result,
    'id', p_capture.id,
    'initiative_id', p_capture.initiative_id,
    'jira_key', p_jira_key,
    'kind', p_capture.kind,
    'body', p_capture.body,
    'source_ref', p_capture.source_ref,
    'content_hash', p_capture.content_hash,
    'has_embedding', p_capture.embedding is not null,
    'author_member_id', p_capture.author_member_id,
    'author_name', p_author_name,
    'created_at', p_capture.created_at,
    'updated_at', p_capture.updated_at,
    'deduped', p_deduped,
    'updated', p_updated,
    'undeleted', p_undeleted,
    'archived_revision', p_archived_revision,
    'redundant_candidate', false,
    'pending_submitted', false
  );
$$;

revoke all on function public.tb_remember_capture_json(text, public.captures, text, text, boolean, boolean, boolean, int)
  from public, anon, authenticated;

drop function if exists public.remember(text, text, text, text, text, float[], text);

create or replace function public.remember(
  p_api_key text,
  p_jira_key text,
  p_kind text,
  p_body text,
  p_source_ref text default null,
  p_embedding float[] default null,
  p_broadcast_ct text default null,
  p_force_apply boolean default false,
  p_queue_for_review boolean default false
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
  v_matches jsonb;
  v_pending public.memory_pending_submissions;
  v_top_capture_id uuid;
  v_is_admin boolean;
begin
  m := public.tb_resolve_member(p_api_key);
  perform public.tb_require_write(m);
  v_is_admin := m.role = 'admin';
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
  if coalesce(p_force_apply, false) and not v_is_admin then
    raise exception 'forbidden: force_apply requires admin role';
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
        return public.tb_remember_capture_json(
          'deduped', existing, init.jira_key, author_name, true, false, false, null
        );
      end if;

      -- Cross-author override on research/decision → queue or block (#67)
      if existing.deleted_at is null
         and existing.author_member_id is distinct from m.id
         and v_kind in ('research', 'decision')
         and not coalesce(p_force_apply, false) then
        v_matches := jsonb_build_array(jsonb_build_object(
          'capture_id', existing.id,
          'source_ref', existing.source_ref,
          'kind', existing.kind,
          'body_preview', left(existing.body, 240),
          'author_member_id', existing.author_member_id,
          'match_type', 'source_ref_override',
          'conflict', 'different_author'
        ));
        if coalesce(p_queue_for_review, false) then
          v_pending := public.tb_insert_pending_submission(
            m.team_id, init.id, m.id, v_kind, trim(p_body), v_ref, v_hash,
            existing.id, 'source_ref_override', v_matches
          );
          return jsonb_build_object(
            'result', 'pending_submitted',
            'pending_id', v_pending.id,
            'jira_key', init.jira_key,
            'source_ref', v_ref,
            'conflict_reason', 'source_ref_override',
            'pending_submitted', true,
            'redundant_candidate', false,
            'suggested_action', 'await_admin_approval'
          );
        end if;
        return jsonb_build_object(
          'result', 'redundant_candidate',
          'redundant_candidate', true,
          'pending_submitted', false,
          'jira_key', init.jira_key,
          'source_ref', v_ref,
          'conflict_reason', 'source_ref_override',
          'suggested_action', 'use_same_source_ref_after_recall_or_queue_with_p_queue_for_review',
          'matches', v_matches
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

      return public.tb_remember_capture_json(
        'updated', c, init.jira_key, author_name, false, true, v_undeleted, v_archived_rev
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
    return public.tb_remember_capture_json(
      'deduped', existing, init.jira_key, author_name, true, false, false, null
    );
  end if;

  -- Semantic / FTS near-duplicate guard before insert
  v_matches := public.tb_find_similar_memories(init.id, trim(p_body), v_emb, v_ref, 5);
  if jsonb_array_length(v_matches) > 0 and not coalesce(p_force_apply, false) then
    v_top_capture_id := (v_matches->0->>'capture_id')::uuid;
    if coalesce(p_queue_for_review, false) then
      v_pending := public.tb_insert_pending_submission(
        m.team_id, init.id, m.id, v_kind, trim(p_body), v_ref, v_hash,
        v_top_capture_id, 'semantic_duplicate', jsonb_build_object('matches', v_matches)
      );
      return jsonb_build_object(
        'result', 'pending_submitted',
        'pending_id', v_pending.id,
        'jira_key', init.jira_key,
        'source_ref', v_ref,
        'conflict_reason', 'semantic_duplicate',
        'pending_submitted', true,
        'redundant_candidate', false,
        'matches', v_matches,
        'suggested_action', 'await_admin_approval'
      );
    end if;
    return jsonb_build_object(
      'result', 'redundant_candidate',
      'redundant_candidate', true,
      'pending_submitted', false,
      'jira_key', init.jira_key,
      'source_ref', v_ref,
      'conflict_reason', 'semantic_duplicate',
      'suggested_action', 'recall_and_merge_same_source_ref_or_queue_for_review',
      'matches', v_matches
    );
  end if;

  insert into public.captures (initiative_id, author_member_id, kind, body, source_ref, content_hash, embedding, body_ct)
  values (init.id, m.id, v_kind, trim(p_body), v_ref, v_hash, v_emb, v_ct)
  returning * into c;

  return public.tb_remember_capture_json(
    'inserted', c, init.jira_key, author_name, false, false, false, null
  );
end;
$$;

grant execute on function public.remember(text, text, text, text, text, float[], text, boolean, boolean)
  to anon, authenticated;

comment on function public.remember(text, text, text, text, text, float[], text, boolean, boolean) is
  'Write memory (#67): blocks semantic duplicates; cross-author source_ref overrides queue or return redundant_candidate.';

-- ---------------------------------------------------------------------------
-- 5) list_pending_memories
-- ---------------------------------------------------------------------------

create or replace function public.list_pending_memories(
  p_api_key text,
  p_jira_key text default null,
  p_status text default 'pending'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.members;
  v_status text;
  result jsonb;
begin
  m := public.tb_resolve_member(p_api_key);
  v_status := lower(coalesce(nullif(trim(p_status), ''), 'pending'));
  if v_status not in ('pending', 'approved', 'rejected', 'all') then
    raise exception 'status must be pending, approved, rejected, or all';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      p.id,
      p.status,
      p.conflict_reason,
      p.kind,
      left(p.body, 500) as body_preview,
      p.source_ref,
      p.target_capture_id,
      p.match_metadata,
      p.review_note,
      p.created_at,
      p.reviewed_at,
      i.jira_key,
      mem.display_name as author_name,
      rev.display_name as reviewed_by
    from public.memory_pending_submissions p
    join public.initiatives i on i.id = p.initiative_id
    join public.members mem on mem.id = p.author_member_id
    left join public.members rev on rev.id = p.reviewed_by_member_id
    where p.team_id = m.team_id
      and (p_jira_key is null or i.jira_key = upper(trim(p_jira_key)))
      and (v_status = 'all' or p.status = v_status)
      and (m.role = 'admin' or p.author_member_id = m.id)
    order by p.created_at desc
    limit 100
  ) x;

  return jsonb_build_object(
    'team_id', m.team_id,
    'viewer_role', m.role,
    'status_filter', v_status,
    'pending', result
  );
end;
$$;

grant execute on function public.list_pending_memories(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6) approve_pending_memory (admin only)
-- ---------------------------------------------------------------------------

create or replace function public.approve_pending_memory(
  p_api_key text,
  p_pending_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  m public.members;
  p public.memory_pending_submissions;
  init public.initiatives;
  c public.captures;
  v_archived_rev int;
begin
  m := public.tb_resolve_member(p_api_key);
  perform public.tb_require_admin(m);

  select * into p
  from public.memory_pending_submissions
  where id = p_pending_id and team_id = m.team_id
  limit 1
  for update;
  if not found then
    raise exception 'pending submission not found';
  end if;
  if p.status is distinct from 'pending' then
    raise exception 'pending submission is not pending (status=%)', p.status;
  end if;

  select * into init from public.initiatives where id = p.initiative_id;

  if p.target_capture_id is not null then
    select * into c
    from public.captures
    where id = p.target_capture_id and initiative_id = p.initiative_id
    limit 1
    for update;
    if not found then
      raise exception 'target capture missing — may have been deleted';
    end if;
    if c.deleted_at is null then
      v_archived_rev := public.tb_snapshot_capture(c, m.team_id);
    end if;
    update public.captures
    set
      kind = p.kind,
      body = p.body,
      content_hash = p.content_hash,
      source_ref = coalesce(p.source_ref, c.source_ref),
      author_member_id = p.author_member_id,
      deleted_at = null,
      deleted_by_member_id = null,
      updated_at = now()
    where id = c.id
    returning * into c;
  elsif p.source_ref is not null then
    select * into c
    from public.captures
    where initiative_id = p.initiative_id and source_ref = p.source_ref
    limit 1
    for update;
    if found then
      if c.deleted_at is null then
        v_archived_rev := public.tb_snapshot_capture(c, m.team_id);
      end if;
      update public.captures
      set kind = p.kind, body = p.body, content_hash = p.content_hash,
          author_member_id = p.author_member_id, deleted_at = null, updated_at = now()
      where id = c.id returning * into c;
    else
      insert into public.captures (initiative_id, author_member_id, kind, body, source_ref, content_hash)
      values (p.initiative_id, p.author_member_id, p.kind, p.body, p.source_ref, p.content_hash)
      returning * into c;
    end if;
  else
    insert into public.captures (initiative_id, author_member_id, kind, body, source_ref, content_hash)
    values (p.initiative_id, p.author_member_id, p.kind, p.body, p.source_ref, p.content_hash)
    returning * into c;
  end if;

  update public.memory_pending_submissions
  set status = 'approved',
      reviewed_by_member_id = m.id,
      reviewed_at = now(),
      review_note = nullif(trim(coalesce(p_note, '')), ''),
      updated_at = now()
  where id = p.id;

  return jsonb_build_object(
    'ok', true,
    'approved', true,
    'pending_id', p.id,
    'jira_key', init.jira_key,
    'capture_id', c.id,
    'source_ref', c.source_ref,
    'archived_revision', v_archived_rev,
    'reviewed_by', m.display_name
  );
end;
$$;

grant execute on function public.approve_pending_memory(text, uuid, text) to anon, authenticated;

comment on function public.approve_pending_memory(text, uuid, text) is
  'Admin promotes pending submission to live memory; attributes author_member_id to submitter (#67).';

-- ---------------------------------------------------------------------------
-- 7) reject_pending_memory (admin only)
-- ---------------------------------------------------------------------------

create or replace function public.reject_pending_memory(
  p_api_key text,
  p_pending_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.members;
  p public.memory_pending_submissions;
begin
  m := public.tb_resolve_member(p_api_key);
  perform public.tb_require_admin(m);

  update public.memory_pending_submissions
  set status = 'rejected',
      reviewed_by_member_id = m.id,
      reviewed_at = now(),
      review_note = nullif(trim(coalesce(p_note, '')), ''),
      updated_at = now()
  where id = p_pending_id
    and team_id = m.team_id
    and status = 'pending'
  returning * into p;

  if not found then
    raise exception 'pending submission not found or not pending';
  end if;

  return jsonb_build_object(
    'ok', true,
    'rejected', true,
    'pending_id', p.id,
    'reviewed_by', m.display_name,
    'review_note', p.review_note
  );
end;
$$;

grant execute on function public.reject_pending_memory(text, uuid, text) to anon, authenticated;
