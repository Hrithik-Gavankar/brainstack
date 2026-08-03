-- =============================================================================
-- Team Brain — team aggregation metrics (#35 / parent #2)
-- =============================================================================
-- Privacy-first crew aggregates for tech leads:
--   • coverage: who remembers which kinds / initiatives (display_name only)
--   • reuse: memory activity per initiative + ISO-week buckets
-- Never returns memory bodies, source_ref text, or personal BRAIN.md.
-- Opt-in: any authenticated team member with a valid api_key can call
-- (same visibility as list_initiatives / list_recent — crew-scoped only).
-- =============================================================================

create or replace function public.team_aggregate_metrics(p_api_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.members;
  t public.teams;
  coverage_member_kind jsonb;
  coverage_member_initiative jsonb;
  coverage_matrix jsonb;
  reuse_per_initiative jsonb;
  reuse_weeks jsonb;
  member_count int;
  initiative_count int;
  memory_count int;
begin
  m := public.tb_resolve_member(p_api_key);

  select * into t from public.teams where id = m.team_id;

  select count(*)::int into member_count
  from public.members where team_id = m.team_id;

  select count(*)::int into initiative_count
  from public.initiatives where team_id = m.team_id;

  select count(*)::int into memory_count
  from public.captures c
  join public.initiatives i on i.id = c.initiative_id
  where i.team_id = m.team_id;

  -- Who is deep where: member × memory kind (opt-in Team Brain activity only)
  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.count desc, x.author_name, x.kind), '[]'::jsonb)
  into coverage_member_kind
  from (
    select
      mem.display_name as author_name,
      c.kind,
      count(*)::int as count
    from public.captures c
    join public.initiatives i on i.id = c.initiative_id
    join public.members mem on mem.id = c.author_member_id
    where i.team_id = m.team_id
    group by mem.display_name, c.kind
  ) x;

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.count desc, x.author_name, x.jira_key), '[]'::jsonb)
  into coverage_member_initiative
  from (
    select
      mem.display_name as author_name,
      i.jira_key,
      count(*)::int as count
    from public.captures c
    join public.initiatives i on i.id = c.initiative_id
    join public.members mem on mem.id = c.author_member_id
    where i.team_id = m.team_id
    group by mem.display_name, i.jira_key
  ) x;

  -- Compact matrix: author → { kind: count, … }
  select coalesce(jsonb_object_agg(author_name, kinds), '{}'::jsonb)
  into coverage_matrix
  from (
    select
      mem.display_name as author_name,
      jsonb_object_agg(c.kind, cnt) as kinds
    from (
      select author_member_id, kind, count(*)::int as cnt
      from public.captures c
      join public.initiatives i on i.id = c.initiative_id
      where i.team_id = m.team_id
      group by author_member_id, kind
    ) per
    join public.members mem on mem.id = per.author_member_id
    group by mem.display_name
  ) y;

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.memory_count desc, x.jira_key), '[]'::jsonb)
  into reuse_per_initiative
  from (
    select
      i.jira_key,
      i.title,
      i.status,
      count(c.id)::int as memory_count,
      count(c.id) filter (
        where coalesce(c.updated_at, c.created_at) >= (now() - interval '7 days')
      )::int as memories_last_7d,
      count(c.id) filter (
        where coalesce(c.updated_at, c.created_at) >= (now() - interval '30 days')
      )::int as memories_last_30d,
      count(distinct c.author_member_id)::int as unique_authors
    from public.initiatives i
    left join public.captures c on c.initiative_id = i.id
    where i.team_id = m.team_id
    group by i.jira_key, i.title, i.status
  ) x;

  -- Memories created/updated per ISO week × initiative (reuse / activity rate)
  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.week desc, x.jira_key), '[]'::jsonb)
  into reuse_weeks
  from (
    select
      to_char(date_trunc('week', coalesce(c.updated_at, c.created_at)), 'IYYY-"W"IW') as week,
      i.jira_key,
      count(*)::int as memories
    from public.captures c
    join public.initiatives i on i.id = c.initiative_id
    where i.team_id = m.team_id
      and coalesce(c.updated_at, c.created_at) >= (now() - interval '12 weeks')
    group by 1, i.jira_key
  ) x;

  return jsonb_build_object(
    'version', 1,
    'team', jsonb_build_object(
      'id', t.id,
      'name', t.name
    ),
    'totals', jsonb_build_object(
      'members', member_count,
      'initiatives', initiative_count,
      'memories', memory_count
    ),
    'coverage', jsonb_build_object(
      'by_member_kind', coverage_member_kind,
      'by_member_initiative', coverage_member_initiative,
      'matrix', coverage_matrix,
      'note', 'Derived from Team Brain remember activity (display_name + kind/initiative). Not personal BRAIN.md.'
    ),
    'reuse', jsonb_build_object(
      'per_initiative', reuse_per_initiative,
      'per_week', reuse_weeks,
      'note', 'Server activity = memories written/updated. Local recall hit-rate overlays via CLI metrics --team when metrics.json exists.'
    ),
    'privacy', jsonb_build_object(
      'includes', jsonb_build_array(
        'member display_name',
        'memory kind counts',
        'initiative keys',
        'memory timestamps (aggregated)'
      ),
      'excludes', jsonb_build_array(
        'memory bodies',
        'source_ref text',
        'personal BRAIN.md',
        'api keys / credentials',
        'GitHub review graph (deferred)'
      ),
      'scope', 'crew members with a valid team api_key — same boundary as list_initiatives'
    ),
    'out_of_scope_v1', jsonb_build_array(
      'collaboration_graph_from_github',
      'workload_heatmap_from_calendar',
      'personal_BRAIN_md_skills'
    )
  );
end;
$$;

revoke all on function public.team_aggregate_metrics(text) from public;
grant execute on function public.team_aggregate_metrics(text) to anon, authenticated;

comment on function public.team_aggregate_metrics(text) is
  'Team Brain #35 — privacy-first crew aggregation (coverage + reuse). No memory bodies / no BRAIN.md.';
