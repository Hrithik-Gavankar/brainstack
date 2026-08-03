-- =============================================================================
-- Team Brain — access roles + admin invite rotate (#40)
-- =============================================================================
-- Roles: admin | member (write) | viewer (read-only)
-- Write RPCs reject viewers. Invite rotate + role assignment are admin-only.
-- Join accepts optional p_role = member|viewer (not admin).
-- Does NOT widen anon SELECT on captures.
-- Apply after 20260804000001_team_brain_realtime_broadcast.sql
-- =============================================================================

-- 1) Widen role check
alter table public.members drop constraint if exists members_role_check;
alter table public.members
  add constraint members_role_check
  check (role in ('admin', 'member', 'viewer'));

comment on column public.members.role is
  'admin = full + invite rotate; member = read/write; viewer = read-only';

-- 2) Helpers
create or replace function public.tb_require_write(p_member public.members)
returns void
language plpgsql
stable
as $$
begin
  if p_member.role = 'viewer' then
    raise exception 'forbidden: viewer role is read-only (cannot write memories)';
  end if;
end;
$$;

create or replace function public.tb_require_admin(p_member public.members)
returns void
language plpgsql
stable
as $$
begin
  if p_member.role is distinct from 'admin' then
    raise exception 'forbidden: admin only';
  end if;
end;
$$;

revoke all on function public.tb_require_write(public.members) from public, anon, authenticated;
revoke all on function public.tb_require_admin(public.members) from public, anon, authenticated;

-- 3) upsert_initiative — writers only (viewers may recall attached keys, not create)
create or replace function public.upsert_initiative(
  p_api_key text,
  p_jira_key text,
  p_title text default '',
  p_status text default 'active',
  p_jira_url text default null,
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.members;
  init public.initiatives;
  v_key text;
begin
  m := public.tb_resolve_member(p_api_key);
  perform public.tb_require_write(m);
  v_key := upper(trim(p_jira_key));
  if v_key is null or length(v_key) < 2 then
    raise exception 'jira_key required';
  end if;

  insert into public.initiatives (team_id, jira_key, title, status, jira_url, meta)
  values (
    m.team_id,
    v_key,
    coalesce(nullif(trim(p_title), ''), v_key),
    coalesce(nullif(trim(p_status), ''), 'active'),
    p_jira_url,
    coalesce(p_meta, '{}'::jsonb)
  )
  on conflict (team_id, jira_key) do update
    set title = excluded.title,
        status = excluded.status,
        jira_url = coalesce(excluded.jira_url, public.initiatives.jira_url),
        meta = public.initiatives.meta || excluded.meta,
        updated_at = now()
  returning * into init;

  return jsonb_build_object(
    'id', init.id,
    'team_id', init.team_id,
    'jira_key', init.jira_key,
    'title', init.title,
    'status', init.status,
    'jira_url', init.jira_url,
    'meta', init.meta,
    'updated_at', init.updated_at
  );
end;
$$;

grant execute on function public.upsert_initiative(text, text, text, text, text, jsonb) to anon, authenticated;

-- 4) set_memory_embedding — writers only
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
  perform public.tb_require_write(m);
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

grant execute on function public.set_memory_embedding(text, uuid, float[]) to anon, authenticated;

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
  perform public.tb_require_write(m);
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


grant execute on function public.remember(text, text, text, text, text, float[]) to anon, authenticated;
grant execute on function public.restore_memory(text, text, text, int) to anon, authenticated;

comment on function public.remember(text, text, text, text, text, float[]) is
  'Write memory (admin/member only; viewers forbidden).';
comment on function public.restore_memory(text, text, text, int) is
  'Soft-rollback (admin/member only; viewers forbidden).';

-- 5) join_team — optional role member|viewer
drop function if exists public.join_team(text, text);

create or replace function public.join_team(
  p_invite_code text,
  p_display_name text,
  p_role text default 'member'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_team public.teams;
  v_member public.members;
  v_api_key text;
  v_role text;
begin
  if p_invite_code is null or length(trim(p_invite_code)) < 4 then
    raise exception 'invite code required';
  end if;
  if p_display_name is null or length(trim(p_display_name)) < 1 then
    raise exception 'display name required';
  end if;

  v_role := lower(coalesce(nullif(trim(p_role), ''), 'member'));
  if v_role not in ('member', 'viewer') then
    raise exception 'join role must be member or viewer (admin is register-only)';
  end if;

  select * into v_team
  from public.teams
  where invite_code = upper(trim(p_invite_code))
  limit 1;
  if not found then
    raise exception 'invalid invite code';
  end if;

  if exists (
    select 1 from public.members
    where team_id = v_team.id and display_name = trim(p_display_name)
  ) then
    raise exception 'member already exists — use a different display name';
  end if;

  v_api_key := public.tb_new_api_key();

  insert into public.members (team_id, display_name, role, api_key_hash)
  values (v_team.id, trim(p_display_name), v_role, public.tb_hash_api_key(v_api_key))
  returning * into v_member;

  return jsonb_build_object(
    'team_id', v_team.id,
    'team_name', v_team.name,
    'member_id', v_member.id,
    'display_name', v_member.display_name,
    'role', v_member.role,
    'api_key', v_api_key
  );
end;
$$;

grant execute on function public.join_team(text, text, text) to anon, authenticated;

comment on function public.join_team(text, text, text) is
  'Join with role member (default) or viewer. Invite omitted from response; ask admin for invites.';

-- 6) Admin: rotate invite code
create or replace function public.rotate_invite(p_api_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.members;
  t public.teams;
  v_code text;
begin
  m := public.tb_resolve_member(p_api_key);
  perform public.tb_require_admin(m);
  v_code := public.tb_new_invite_code();
  update public.teams
  set invite_code = v_code
  where id = m.team_id
  returning * into t;
  return jsonb_build_object(
    'team_id', t.id,
    'team_name', t.name,
    'invite_code', t.invite_code,
    'rotated', true,
    'note', 'Share the new invite privately. Old invite codes stop working immediately.'
  );
end;
$$;

grant execute on function public.rotate_invite(text) to anon, authenticated;

comment on function public.rotate_invite(text) is
  'Admin-only: rotate team invite_code. Members/viewers cannot invite.';

-- 7) Admin: set member role (member|viewer|admin)
create or replace function public.set_member_role(
  p_api_key text,
  p_display_name text,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  admin public.members;
  target public.members;
  v_role text;
  admin_count int;
begin
  admin := public.tb_resolve_member(p_api_key);
  perform public.tb_require_admin(admin);
  if p_display_name is null or length(trim(p_display_name)) < 1 then
    raise exception 'display name required';
  end if;
  v_role := lower(trim(p_role));
  if v_role not in ('admin', 'member', 'viewer') then
    raise exception 'role must be admin, member, or viewer';
  end if;

  select * into target
  from public.members
  where team_id = admin.team_id and display_name = trim(p_display_name)
  limit 1;
  if not found then
    raise exception 'member not found';
  end if;

  if target.role = 'admin' and v_role is distinct from 'admin' then
    select count(*) into admin_count
    from public.members
    where team_id = admin.team_id and role = 'admin';
    if admin_count <= 1 then
      raise exception 'cannot demote the last admin';
    end if;
  end if;

  update public.members
  set role = v_role
  where id = target.id
  returning * into target;

  return jsonb_build_object(
    'member_id', target.id,
    'display_name', target.display_name,
    'role', target.role,
    'team_id', target.team_id,
    'updated', true
  );
end;
$$;

grant execute on function public.set_member_role(text, text, text) to anon, authenticated;

comment on function public.set_member_role(text, text, text) is
  'Admin-only: set a teammate role to admin|member|viewer.';
