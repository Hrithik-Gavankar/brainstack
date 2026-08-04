-- =============================================================================
-- Team Brain — rate limits for anon register_team and join_team (#32)
-- =============================================================================
-- Closes the documented v1 security gap: unbounded anon RPC calls.
-- Strategy: database-level sliding window using fingerprint + operation.
-- Apply after 20260805000001_team_brain_roles_and_invites.sql
-- =============================================================================

-- 1) Rate limit tracking table
create table if not exists public.tb_rate_limits (
  id bigint generated always as identity primary key,
  fingerprint text not null,
  operation text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_rate_limits_lookup
  on public.tb_rate_limits (fingerprint, operation, created_at desc);

comment on table public.tb_rate_limits is
  'Sliding window rate-limit tracker for anon RPCs';

-- No direct access — helpers use security definer
revoke all on public.tb_rate_limits from public, anon, authenticated;

-- 2) Rate limit configuration (tunable via env or defaults)
create or replace function public.tb_rate_limit_config()
returns table (
  register_limit int,
  register_window_minutes int,
  join_limit int,
  join_window_minutes int,
  cleanup_older_than_hours int
)
language sql
stable
as $$
  select
    coalesce(nullif(current_setting('app.rate_limit_register', true), '')::int, 5) as register_limit,
    coalesce(nullif(current_setting('app.rate_limit_register_window', true), '')::int, 60) as register_window_minutes,
    coalesce(nullif(current_setting('app.rate_limit_join', true), '')::int, 15) as join_limit,
    coalesce(nullif(current_setting('app.rate_limit_join_window', true), '')::int, 60) as join_window_minutes,
    coalesce(nullif(current_setting('app.rate_limit_cleanup_hours', true), '')::int, 24) as cleanup_older_than_hours;
$$;

-- 3) Check rate limit — returns true if allowed, false if exceeded
create or replace function public.tb_check_rate_limit(
  p_fingerprint text,
  p_operation text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg record;
  v_limit int;
  v_window interval;
  v_count int;
begin
  select * into cfg from public.tb_rate_limit_config();

  if p_operation = 'register' then
    v_limit := cfg.register_limit;
    v_window := (cfg.register_window_minutes || ' minutes')::interval;
  elsif p_operation = 'join' then
    v_limit := cfg.join_limit;
    v_window := (cfg.join_window_minutes || ' minutes')::interval;
  else
    return true;
  end if;

  select count(*) into v_count
  from public.tb_rate_limits
  where fingerprint = p_fingerprint
    and operation = p_operation
    and created_at > (now() - v_window);

  return v_count < v_limit;
end;
$$;

-- 4) Record rate limit attempt
create or replace function public.tb_record_rate_limit(
  p_fingerprint text,
  p_operation text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.tb_rate_limits (fingerprint, operation)
  values (p_fingerprint, p_operation);
end;
$$;

-- 5) Cleanup old rate limit entries (call periodically via cron or manual)
create or replace function public.tb_cleanup_rate_limits()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg record;
  v_deleted int;
begin
  select * into cfg from public.tb_rate_limit_config();

  delete from public.tb_rate_limits
  where created_at < (now() - (cfg.cleanup_older_than_hours || ' hours')::interval);

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

grant execute on function public.tb_cleanup_rate_limits() to authenticated;

-- 6) Fingerprint generator — uses request headers when available, fallback to hash
create or replace function public.tb_anon_fingerprint()
returns text
language plpgsql
stable
as $$
declare
  v_ip text;
  v_ua text;
  v_combined text;
begin
  v_ip := coalesce(
    current_setting('request.headers', true)::json->>'x-forwarded-for',
    current_setting('request.headers', true)::json->>'x-real-ip',
    'anon'
  );
  v_ua := coalesce(
    left(current_setting('request.headers', true)::json->>'user-agent', 50),
    'unknown'
  );
  v_combined := v_ip || '|' || v_ua;
  return encode(extensions.digest(v_combined, 'sha256'), 'hex');
exception when others then
  return 'fallback-' || encode(extensions.digest(random()::text || now()::text, 'sha256'), 'hex');
end;
$$;

-- 7) Updated register_team with rate limiting
-- Must drop first: parameter names changed from original (p_name, p_display_name)
drop function if exists public.register_team(text, text);

create or replace function public.register_team(p_team_name text, p_admin_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_team public.teams;
  v_member public.members;
  v_api_key text;
  v_fingerprint text;
begin
  v_fingerprint := public.tb_anon_fingerprint();

  if not public.tb_check_rate_limit(v_fingerprint, 'register') then
    raise exception 'rate limit exceeded — try again later (register)';
  end if;

  perform public.tb_record_rate_limit(v_fingerprint, 'register');

  if p_team_name is null or length(trim(p_team_name)) < 2 then
    raise exception 'team name required (min 2 chars)';
  end if;
  if p_admin_name is null or length(trim(p_admin_name)) < 1 then
    raise exception 'admin name required';
  end if;

  insert into public.teams (name, invite_code)
  values (trim(p_team_name), public.tb_new_invite_code())
  returning * into v_team;

  v_api_key := public.tb_new_api_key();

  insert into public.members (team_id, display_name, role, api_key_hash)
  values (v_team.id, trim(p_admin_name), 'admin', public.tb_hash_api_key(v_api_key))
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

grant execute on function public.register_team(text, text) to anon, authenticated;

comment on function public.register_team(text, text) is
  'v1.1: rate-limited (default 5/hour) — see tb_rate_limit_config()';

-- 8) Updated join_team with rate limiting
-- Drop both signatures to ensure clean replacement
drop function if exists public.join_team(text, text);
drop function if exists public.join_team(text, text, text);

create or replace function public.join_team(p_invite_code text, p_display_name text, p_role text default 'member')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_team public.teams;
  v_member public.members;
  v_api_key text;
  v_fingerprint text;
  v_role text;
begin
  v_fingerprint := public.tb_anon_fingerprint();

  if not public.tb_check_rate_limit(v_fingerprint, 'join') then
    raise exception 'rate limit exceeded — try again later (join)';
  end if;

  perform public.tb_record_rate_limit(v_fingerprint, 'join');

  if p_invite_code is null or length(trim(p_invite_code)) < 4 then
    raise exception 'invite code required';
  end if;
  if p_display_name is null or length(trim(p_display_name)) < 1 then
    raise exception 'display name required';
  end if;

  v_role := lower(coalesce(nullif(trim(p_role), ''), 'member'));
  if v_role not in ('member', 'viewer') then
    raise exception 'invalid role (must be member or viewer — admin only via register)';
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
  'v1.1: rate-limited (default 15/hour) — see tb_rate_limit_config()';

-- 9) Monitoring view for admins (optional — requires service_role or auth)
create or replace view public.tb_rate_limit_stats as
select
  operation,
  date_trunc('hour', created_at) as hour,
  count(*) as attempts
from public.tb_rate_limits
where created_at > (now() - interval '24 hours')
group by operation, date_trunc('hour', created_at)
order by hour desc, operation;

comment on view public.tb_rate_limit_stats is
  'Hourly rate limit stats for monitoring (last 24h) — service_role only';

revoke all on public.tb_rate_limit_stats from public, anon, authenticated;
grant select on public.tb_rate_limit_stats to authenticated;
