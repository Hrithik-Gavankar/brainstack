-- =============================================================================
-- Team Brain — security & hygiene follow-ups (PR #29 review)
-- =============================================================================
-- Apply after embeddings (or after memory if embeddings skipped).
-- Safe on existing Team Atlas data (unique names already distinct).
-- =============================================================================

-- 1) Prevent duplicate display names per team (unlimited join spam)
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'members_team_display_unique'
  ) then
    alter table public.members
      add constraint members_team_display_unique unique (team_id, display_name);
  end if;
end $$;

-- 2) Stronger invite codes for NEW teams (16 hex chars)
create or replace function public.tb_new_invite_code()
returns text
language sql
volatile
as $$
  select upper(substr(encode(extensions.gen_random_bytes(12), 'hex'), 1, 16));
$$;

-- 3) join_team: reject duplicate display_name before insert
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

grant execute on function public.join_team(text, text) to anon, authenticated;

-- 4) Keep initiatives.updated_at fresh on any UPDATE
create or replace function public.tb_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists initiatives_updated_at on public.initiatives;
create trigger initiatives_updated_at
  before update on public.initiatives
  for each row execute function public.tb_set_updated_at();

-- 5) Known v1 limitation (documented): register_team / join_team are anon-callable
--    with no application-level rate limit. Mitigations for a later release:
--    Edge Function wrapper, Supabase plan rate limits, or require Supabase Auth
--    for register_team. Tracked in docs/team-brain-memory.md and supabase/README.md.
comment on function public.register_team(text, text) is
  'v1: anon-callable; no app rate limit — see supabase/README.md Security';
comment on function public.join_team(text, text) is
  'v1: anon-callable; no app rate limit — duplicate display_name rejected';
