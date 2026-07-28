-- =============================================================================
-- Team Brain schema (v1) — single ship migration
-- =============================================================================
-- Tables : teams, members, initiatives, captures
-- Identity: Jira key on initiatives; captures sync via Supabase
-- Apply   : supabase db push  |  SQL Editor → Run this file once
-- RPCs    : register_team, join_team, tb_whoami, upsert_initiative,
--           add_capture, list_captures, list_initiatives
-- Auth    : p_api_key on RPCs; SHA-256 hash stored (never plaintext)
-- =============================================================================

-- Extensions (Supabase hosts pgcrypto under `extensions`, not `public`)
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.teams (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null,
  invite_code text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default extensions.gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  display_name text not null,
  role text not null default 'member' check (role in ('admin', 'member')),
  api_key_hash text not null,
  created_at timestamptz not null default now()
);

create index if not exists members_team_id_idx on public.members (team_id);
create index if not exists members_api_key_hash_idx on public.members (api_key_hash);

create table if not exists public.initiatives (
  id uuid primary key default extensions.gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  jira_key text not null,
  title text not null default '',
  status text not null default 'active',
  jira_url text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (team_id, jira_key)
);

create index if not exists initiatives_team_id_idx on public.initiatives (team_id);
create index if not exists initiatives_jira_key_idx on public.initiatives (jira_key);

create table if not exists public.captures (
  id uuid primary key default extensions.gen_random_uuid(),
  initiative_id uuid not null references public.initiatives (id) on delete cascade,
  author_member_id uuid not null references public.members (id) on delete cascade,
  kind text not null default 'note' check (kind in ('research', 'decision', 'note')),
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists captures_initiative_id_idx on public.captures (initiative_id);
create index if not exists captures_created_at_idx on public.captures (created_at desc);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.tb_hash_api_key(p_api_key text)
returns text
language sql
immutable
as $$
  select encode(extensions.digest(p_api_key, 'sha256'), 'hex');
$$;

create or replace function public.tb_new_api_key()
returns text
language sql
volatile
as $$
  select 'tb_' || encode(extensions.gen_random_bytes(24), 'hex');
$$;

create or replace function public.tb_new_invite_code()
returns text
language sql
volatile
as $$
  select upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 8));
$$;

create or replace function public.tb_resolve_member(p_api_key text)
returns public.members
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.members;
begin
  if p_api_key is null or length(p_api_key) < 10 then
    raise exception 'invalid api key';
  end if;
  select * into m
  from public.members
  where api_key_hash = public.tb_hash_api_key(p_api_key)
  limit 1;
  if not found then
    raise exception 'unauthorized';
  end if;
  return m;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPCs (anon-callable; auth via p_api_key where needed)
-- ---------------------------------------------------------------------------

create or replace function public.register_team(p_name text, p_display_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_team public.teams;
  v_member public.members;
  v_api_key text;
  v_invite text;
begin
  if p_name is null or length(trim(p_name)) < 2 then
    raise exception 'team name required';
  end if;
  if p_display_name is null or length(trim(p_display_name)) < 1 then
    raise exception 'display name required';
  end if;

  v_api_key := public.tb_new_api_key();
  v_invite := public.tb_new_invite_code();

  insert into public.teams (name, invite_code)
  values (trim(p_name), v_invite)
  returning * into v_team;

  insert into public.members (team_id, display_name, role, api_key_hash)
  values (v_team.id, trim(p_display_name), 'admin', public.tb_hash_api_key(v_api_key))
  returning * into v_member;

  return jsonb_build_object(
    'team_id', v_team.id,
    'team_name', v_team.name,
    'invite_code', v_team.invite_code,
    'member_id', v_member.id,
    'display_name', v_member.display_name,
    'role', v_member.role,
    'api_key', v_api_key
  );
end;
$$;

create or replace function public.join_team(p_invite_code text, p_display_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_team public.teams;
  v_member public.members;
  v_api_key text;
begin
  if p_invite_code is null or length(trim(p_invite_code)) < 4 then
    raise exception 'invite code required';
  end if;
  if p_display_name is null or length(trim(p_display_name)) < 1 then
    raise exception 'display name required';
  end if;

  select * into v_team
  from public.teams
  where invite_code = upper(trim(p_invite_code))
  limit 1;
  if not found then
    raise exception 'invalid invite code';
  end if;

  v_api_key := public.tb_new_api_key();

  insert into public.members (team_id, display_name, role, api_key_hash)
  values (v_team.id, trim(p_display_name), 'member', public.tb_hash_api_key(v_api_key))
  returning * into v_member;

  return jsonb_build_object(
    'team_id', v_team.id,
    'team_name', v_team.name,
    'invite_code', v_team.invite_code,
    'member_id', v_member.id,
    'display_name', v_member.display_name,
    'role', v_member.role,
    'api_key', v_api_key
  );
end;
$$;

create or replace function public.tb_whoami(p_api_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.members;
  t public.teams;
begin
  m := public.tb_resolve_member(p_api_key);
  select * into t from public.teams where id = m.team_id;
  return jsonb_build_object(
    'member_id', m.id,
    'display_name', m.display_name,
    'role', m.role,
    'team_id', t.id,
    'team_name', t.name,
    'invite_code', t.invite_code
  );
end;
$$;

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
declare
  m public.members;
  init public.initiatives;
  c public.captures;
  v_kind text;
  author_name text;
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

  insert into public.captures (initiative_id, author_member_id, kind, body)
  values (init.id, m.id, v_kind, trim(p_body))
  returning * into c;

  return jsonb_build_object(
    'id', c.id,
    'initiative_id', c.initiative_id,
    'jira_key', init.jira_key,
    'kind', c.kind,
    'body', c.body,
    'author_member_id', c.author_member_id,
    'author_name', author_name,
    'created_at', c.created_at
  );
end;
$$;

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

create or replace function public.list_initiatives(p_api_key text)
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

  select coalesce(jsonb_agg(to_jsonb(i) order by i.updated_at desc), '[]'::jsonb)
  into result
  from public.initiatives i
  where i.team_id = m.team_id;

  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants: anon + authenticated can call RPCs; no direct table access
-- ---------------------------------------------------------------------------

alter table public.teams enable row level security;
alter table public.members enable row level security;
alter table public.initiatives enable row level security;
alter table public.captures enable row level security;

-- Deny direct table access from anon/authenticated (RPCs are security definer)
revoke all on public.teams from anon, authenticated;
revoke all on public.members from anon, authenticated;
revoke all on public.initiatives from anon, authenticated;
revoke all on public.captures from anon, authenticated;

grant usage on schema public to anon, authenticated;

grant execute on function public.register_team(text, text) to anon, authenticated;
grant execute on function public.join_team(text, text) to anon, authenticated;
grant execute on function public.tb_whoami(text) to anon, authenticated;
grant execute on function public.upsert_initiative(text, text, text, text, text, jsonb) to anon, authenticated;
grant execute on function public.add_capture(text, text, text, text) to anon, authenticated;
grant execute on function public.list_captures(text, text, int) to anon, authenticated;
grant execute on function public.list_initiatives(text) to anon, authenticated;
