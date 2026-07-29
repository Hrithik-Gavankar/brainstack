-- =============================================================================
-- Team Brain — invite hygiene (PR #29 review round 2)
-- =============================================================================
-- 1) join_team must NOT return invite_code (members must not rediscover/share it)
-- 2) tb_whoami returns invite_code only for role = admin
-- Apply after sync_mode migration.
-- =============================================================================

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

  if exists (
    select 1 from public.members
    where team_id = v_team.id and display_name = trim(p_display_name)
  ) then
    raise exception 'member already exists — use a different display name';
  end if;

  v_api_key := public.tb_new_api_key();

  insert into public.members (team_id, display_name, role, api_key_hash)
  values (v_team.id, trim(p_display_name), 'member', public.tb_hash_api_key(v_api_key))
  returning * into v_member;

  -- Intentionally omit invite_code — only register_team (admin) returns it.
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

grant execute on function public.join_team(text, text) to anon, authenticated;

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
  result jsonb;
begin
  m := public.tb_resolve_member(p_api_key);
  select * into t from public.teams where id = m.team_id;
  result := jsonb_build_object(
    'member_id', m.id,
    'display_name', m.display_name,
    'role', m.role,
    'team_id', t.id,
    'team_name', t.name
  );
  -- Invite code only for admins (register role)
  if m.role = 'admin' then
    result := result || jsonb_build_object('invite_code', t.invite_code);
  end if;
  return result;
end;
$$;

grant execute on function public.tb_whoami(text) to anon, authenticated;

comment on function public.join_team(text, text) is
  'v1: anon-callable; no invite_code in response — ask admin for invites';
comment on function public.tb_whoami(text) is
  'Returns member/team; invite_code only when role=admin';
