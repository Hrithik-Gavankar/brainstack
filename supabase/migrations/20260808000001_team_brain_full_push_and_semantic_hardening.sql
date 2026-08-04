-- =============================================================================
-- Team Brain — full-content encrypted realtime push + hardening (#31, #4)
-- =============================================================================
-- Closes two documented v1 gaps (docs/team-brain-post-launch-issues.md):
--
--   #2  Realtime push was signal-only (metadata; body fetched via authenticated
--       pull after the signal). This migration adds a *full-content* push path
--       without widening anon SELECT and without migrating auth to Supabase Auth
--       JWTs (Team Brain uses custom api_key RPCs — see #31 design note in
--       20260804000001_team_brain_realtime_broadcast.sql for why postgres_changes
--       CDC and JWT-scoped private channels were rejected).
--
--       Design: application-layer encryption, not a Supabase Realtime Authorization
--       change. Each team gets a random 256-bit `broadcast_key` (server-generated,
--       never anon-readable). The CLIENT encrypts the memory body with that key
--       (AES-256-CBC + HMAC-SHA256, encrypt-then-MAC, subkeys derived via
--       SHA-256(key || "enc" | "mac")) *before* calling `remember`, and the
--       ciphertext travels on the same public Broadcast topic used for #31's
--       signal. Only members who called `memory_broadcast_topic` with a valid
--       api_key ever receive the key — the DB never decrypts anything, so this
--       migration adds no new plaintext exposure surface. Peers with the key
--       decrypt inline and update their local cache with zero extra RPC
--       round-trip; peers without a decryptable payload (older client, missing
--       Python `cryptography` dependency, or key rotation in flight) transparently
--       fall back to the existing authenticated `_pull_signal` pull — unchanged,
--       zero regression.
--
--   #4  Semantic recall required reading the embeddings migration to discover
--       `TEAM_BRAIN_EMBED_PROVIDER`. This migration doesn't change the pgvector
--       plumbing (already shipped in 20260729000001) — the crew-facing "one
--       command to opt in" and mode-reporting docs land in the CLI
--       (`enable-semantic` command) and docs/team-brain-memory.md in this same
--       PR. Included here only for the body-size guard shared with hardening.
--
-- Hardening (infra maturity — bundled with #4/#31 closeout, no dedicated issue):
--   - `remember` now rejects bodies over 20,000 chars (previously unbounded).
--     Matches the "body size cap" posture of comparable hardened APIs.
--   - `restore_memory` clears any stale `body_ct` on rollback so a peer never
--     decrypts an out-of-date ciphertext — it falls back to authenticated pull,
--     which always returns the correct restored body.
--
-- Apply after 20260807000001_team_brain_aggregate_metrics.sql
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Per-team broadcast key (256-bit random; server-generated; never anon SELECT)
-- ---------------------------------------------------------------------------

alter table public.teams
  add column if not exists broadcast_key bytea;

comment on column public.teams.broadcast_key is
  'Random 256-bit key for app-layer AES-256-CBC+HMAC encryption of Broadcast push '
  'payloads (#31 full push). Only ever returned to a resolved member via '
  'memory_broadcast_topic(); the DB never encrypts/decrypts with it.';

-- Backfill existing teams created before this migration
update public.teams
set broadcast_key = extensions.gen_random_bytes(32)
where broadcast_key is null;

alter table public.captures
  add column if not exists body_ct text;

comment on column public.captures.body_ct is
  'Client-computed ciphertext of body for full realtime push: '
  '"<iv_hex>:<ciphertext_base64>:<hmac_sha256_hex>" using the team broadcast_key. '
  'Null means the writer could not encrypt (no openssl, key not cached yet) — '
  'peers fall back to authenticated pull. Never decrypted server-side.';

-- ---------------------------------------------------------------------------
-- 2) register_team — generate broadcast_key at team creation
--    (matches the rate-limited signature from 20260806000001: p_team_name, p_admin_name)
-- ---------------------------------------------------------------------------

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

  insert into public.teams (name, invite_code, broadcast_key)
  values (trim(p_team_name), public.tb_new_invite_code(), extensions.gen_random_bytes(32))
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
  'v1.2: rate-limited + generates per-team broadcast_key for full realtime push (#31).';

-- ---------------------------------------------------------------------------
-- 3) memory_broadcast_topic — also return broadcast_key (member-gated, same as topic)
-- ---------------------------------------------------------------------------

create or replace function public.memory_broadcast_topic(
  p_api_key text,
  p_jira_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.members;
  t public.teams;
  init public.initiatives;
  topic text;
begin
  m := public.tb_resolve_member(p_api_key);
  if p_jira_key is null or length(trim(p_jira_key)) < 2 then
    raise exception 'jira_key required';
  end if;
  select * into init
  from public.initiatives
  where team_id = m.team_id and upper(jira_key) = upper(trim(p_jira_key))
  limit 1;
  if not found then
    raise exception 'initiative not found — attach first';
  end if;
  select * into t from public.teams where id = m.team_id;
  if t.broadcast_key is null then
    update public.teams set broadcast_key = extensions.gen_random_bytes(32)
    where id = t.id
    returning * into t;
  end if;
  topic := 'team-brain:' || m.team_id::text || ':' || upper(init.jira_key);
  return jsonb_build_object(
    'topic', topic,
    'event', 'memory_changed',
    'private', false,
    'team_id', m.team_id,
    'jira_key', upper(init.jira_key),
    'policy', 'encrypted_full_push_with_signal_fallback',
    'broadcast_key_b64', encode(t.broadcast_key, 'base64'),
    'note', 'Full push: body_ct travels encrypted on the public topic (app-layer AES-256-CBC+HMAC, key returned only to resolved members). Peers without the key/library fall back to authenticated pull via list_recent. No anon SELECT on captures.'
  );
end;
$$;

comment on function public.memory_broadcast_topic(text, text) is
  'Return Realtime Broadcast topic + team broadcast_key for an attached initiative (member api_key only). Full push (#31): body_ct is app-layer encrypted, never plaintext on the wire to non-members.';

grant execute on function public.memory_broadcast_topic(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) remember — add optional p_broadcast_ct (client-computed ciphertext) + body cap
--    Drop the 6-arg overload first (new signature adds a 7th param).
-- ---------------------------------------------------------------------------

drop function if exists public.remember(text, text, text, text, text, float[]);

create or replace function public.remember(
  p_api_key text,
  p_jira_key text,
  p_kind text,
  p_body text,
  p_source_ref text default null,
  p_embedding float[] default null,
  p_broadcast_ct text default null
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
  if length(p_body) > 20000 then
    raise exception 'body too long (% chars, max 20000) — split into multiple memories', length(p_body);
  end if;

  if p_embedding is not null then
    if array_length(p_embedding, 1) is distinct from 768 then
      raise exception 'embedding must be 768 dimensions (got %)', coalesce(array_length(p_embedding, 1), 0);
    end if;
    v_emb := p_embedding::extensions.vector(768);
  end if;

  -- Ciphertext is opaque to the DB — only format-checked (iv:ct:hmac), never decrypted.
  v_ct := nullif(trim(coalesce(p_broadcast_ct, '')), '');
  if v_ct is not null and array_length(regexp_split_to_array(v_ct, ':'), 1) is distinct from 3 then
    v_ct := null; -- malformed ciphertext never blocks the write; just skip full push for this row
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
        body_ct = v_ct,
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

  insert into public.captures (initiative_id, author_member_id, kind, body, source_ref, content_hash, embedding, body_ct)
  values (init.id, m.id, v_kind, trim(p_body), v_ref, v_hash, v_emb, v_ct)
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

grant execute on function public.remember(text, text, text, text, text, float[], text) to anon, authenticated;

comment on function public.remember(text, text, text, text, text, float[], text) is
  'v1.3: adds optional p_broadcast_ct (client-encrypted, opaque) for full realtime push (#31); 20000-char body cap.';

-- ---------------------------------------------------------------------------
-- 5) restore_memory — clear stale body_ct on rollback (avoid decrypting old content)
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

  -- body_ct cleared: it encrypted the PRE-restore body. A stale ciphertext would
  -- let a full-push peer decrypt the wrong content; clearing forces the safe
  -- fallback (authenticated _pull_signal, which always reads the true row).
  update public.captures
  set
    kind = r.kind,
    body = r.body,
    content_hash = r.content_hash,
    embedding = null,
    body_ct = null,
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
  'Soft-rollback (admin/member only; viewers forbidden). Clears body_ct so full-push peers fall back to authenticated pull for the restored body.';

-- ---------------------------------------------------------------------------
-- 6) tb_notify_memory_changed — carry full content (encrypted) + enough metadata
--    for peers to upsert their cache with zero extra round trip.
-- ---------------------------------------------------------------------------

create or replace function public.tb_notify_memory_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  init public.initiatives;
  author_name text;
  topic text;
  payload jsonb;
begin
  select * into init from public.initiatives where id = NEW.initiative_id;
  if not found then
    return NEW;
  end if;

  select display_name into author_name from public.members where id = NEW.author_member_id;

  topic := 'team-brain:' || init.team_id::text || ':' || upper(init.jira_key);
  payload := jsonb_build_object(
    'team_id', init.team_id,
    'jira_key', upper(init.jira_key),
    'capture_id', NEW.id,
    'source_ref', NEW.source_ref,
    'kind', NEW.kind,
    'content_hash', NEW.content_hash,
    'author_name', author_name,
    'created_at', NEW.created_at,
    'updated_at', coalesce(NEW.updated_at, NEW.created_at),
    'op', TG_OP,
    -- Full push (#31): opaque "<iv_hex>:<ct_b64>:<hmac_hex>", app-layer encrypted.
    -- Null when the writer couldn't encrypt — peers fall back to _pull_signal.
    'body_ct', NEW.body_ct
  );

  begin
    perform realtime.send(payload, 'memory_changed', topic, false);
  exception
    when undefined_function then
      raise warning 'team-brain: realtime.send unavailable — apply on hosted Supabase or keep poll/watch';
    when undefined_table then
      raise warning 'team-brain: realtime schema unavailable — keep poll/watch';
    when others then
      raise warning 'team-brain broadcast skipped: %', SQLERRM;
  end;

  return NEW;
end;
$$;

comment on function public.tb_notify_memory_changed() is
  'Full-content Realtime Broadcast on capture write (#31): body_ct is app-layer '
  'encrypted (never plaintext), never blocks remember. Signal-only when body_ct is null.';

drop trigger if exists captures_notify_memory_changed on public.captures;
create trigger captures_notify_memory_changed
  after insert or update on public.captures
  for each row
  execute function public.tb_notify_memory_changed();
