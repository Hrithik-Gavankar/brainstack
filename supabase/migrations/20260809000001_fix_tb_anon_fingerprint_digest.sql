-- Fix tb_anon_fingerprint: pgcrypto lives in extensions schema on Supabase
-- (bare digest() fails when search_path is public only — register_team/join_team 42883)

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
