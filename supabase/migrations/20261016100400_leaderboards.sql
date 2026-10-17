-- =============================================================================================================
-- Pace – regionale Rankings (serverseitig).
--
-- * Teilnehmer: Profile mit ausdrücklicher Zustimmung (regional_leaderboard_enabled), aktiver Gemeinde im Scope
--   und mindestens einem Tageswert im Zeitraum.
-- * Scope: Region beliebiger Ebene; Zugehörigkeit über die Hierarchie der Gemeinde.
-- * Zeitraum: 'daily' (ein Tag) oder 'weekly' (ISO-Woche Montag–Sonntag, Summe).
-- * Reihenfolge: Schritte absteigend, bei Gleichstand wer den Wert zuerst erreicht hat, dann public_id.
-- * Ausgabe: nur öffentliche Felder. Nie Auth-IDs, E-Mail, Provider, Gesundheitsdetails oder Gemeinden anderer.
-- * Nie wird das gesamte Ranking an den Client geliefert: nur Seiten (limit/offset) oder die eigene Umgebung.
-- =============================================================================================================

-- Vollständiges Ranking eines Scopes. Intern; nur über die security-definer-Funktionen unten erreichbar.
create function private.leaderboard_ranking(p_region_id text, p_period text, p_date date)
returns table (
  rank bigint,
  user_id uuid,
  public_user_id uuid,
  username text,
  display_name text,
  competition_steps bigint,
  total_participants bigint
)
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_level public.region_level;
  v_start date;
  v_end date;
begin
  select r.level into v_level from public.regions r where r.id = p_region_id;
  if v_level is null then
    raise exception 'unknown_region' using errcode = '22023';
  end if;
  if p_date is null then
    raise exception 'invalid_date' using errcode = '22023';
  end if;

  case p_period
    when 'daily' then
      v_start := p_date;
      v_end := p_date;
    when 'weekly' then
      v_start := date_trunc('week', p_date::timestamp)::date;
      v_end := v_start + 6;
    else
      raise exception 'invalid_period' using errcode = '22023';
  end case;

  return query
  with participants as (
    select p.id as participant_id,
           p.public_id as participant_public_id,
           p.username as participant_username,
           p.display_name as participant_display_name,
           sum(a.competition_steps)::bigint as steps,
           max(a.steps_changed_at) as changed_at
      from public.profiles p
      join public.regions m
        on m.id = p.municipality_id
       and m.is_active
      join public.daily_activity a
        on a.user_id = p.id
       and a.activity_date between v_start and v_end
     where p.regional_leaderboard_enabled
       and case v_level
             when 'municipality' then m.id = p_region_id
             when 'district' then m.district_id = p_region_id
             when 'state' then m.state_id = p_region_id
             else m.country_id = p_region_id
           end
     group by p.id, p.public_id, p.username, p.display_name
  )
  select row_number() over (order by pa.steps desc, pa.changed_at asc, pa.participant_public_id asc),
         pa.participant_id,
         pa.participant_public_id,
         pa.participant_username,
         pa.participant_display_name,
         pa.steps,
         count(*) over ()
    from participants pa;
end;
$$;
revoke all on function private.leaderboard_ranking(text, text, date) from public, anon, authenticated;

-- Wandelt Ranking-Zeilen in die öffentliche JSON-Form.
create function private.leaderboard_entry_json(
  p_rank bigint,
  p_public_user_id uuid,
  p_username text,
  p_display_name text,
  p_competition_steps bigint,
  p_is_current_user boolean
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'rank', p_rank,
    'public_user_id', p_public_user_id,
    'username', p_username,
    'display_name', p_display_name,
    'competition_steps', p_competition_steps,
    'is_current_user', p_is_current_user
  );
$$;
revoke all on function private.leaderboard_entry_json(bigint, uuid, text, text, bigint, boolean)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- RPC: eine Seite des Rankings (Plätze offset+1 bis offset+limit).
-- ---------------------------------------------------------------------------------------------------------------
create function public.leaderboard_page(
  p_region_id text,
  p_period text,
  p_date date,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total bigint;
  v_entries jsonb;
begin
  if v_user_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  with ranking as (
    select * from private.leaderboard_ranking(p_region_id, p_period, p_date)
  )
  select coalesce(max(r.total_participants), 0),
         coalesce(
           jsonb_agg(
             private.leaderboard_entry_json(
               r.rank, r.public_user_id, r.username, r.display_name, r.competition_steps, r.user_id = v_user_id
             ) order by r.rank
           ) filter (where r.rank > v_offset and r.rank <= v_offset + v_limit),
           '[]'::jsonb
         )
    into v_total, v_entries
    from ranking r;

  return jsonb_build_object('total_participants', v_total, 'entries', v_entries);
end;
$$;

revoke all on function public.leaderboard_page(text, text, date, integer, integer) from public, anon;
grant execute on function public.leaderboard_page(text, text, date, integer, integer) to authenticated;
comment on function public.leaderboard_page(text, text, date, integer, integer) is
  'Pace: Seite eines regionalen Rankings ({total_participants, entries}). Nur öffentliche Felder.';

-- ---------------------------------------------------------------------------------------------------------------
-- RPC: der eigene Platz mit bis zu p_radius Plätzen darüber und darunter. Leer, wenn man nicht im Ranking ist.
-- ---------------------------------------------------------------------------------------------------------------
create function public.leaderboard_neighborhood(
  p_region_id text,
  p_period text,
  p_date date,
  p_radius integer default 1
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_radius integer := least(greatest(coalesce(p_radius, 1), 0), 10);
  v_total bigint;
  v_my_rank bigint;
  v_entries jsonb;
begin
  if v_user_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  with ranking as (
    select * from private.leaderboard_ranking(p_region_id, p_period, p_date)
  )
  select coalesce(max(r.total_participants), 0),
         max(r.rank) filter (where r.user_id = v_user_id)
    into v_total, v_my_rank
    from ranking r;

  if v_my_rank is null then
    return jsonb_build_object('total_participants', v_total, 'entries', '[]'::jsonb);
  end if;

  select coalesce(
           jsonb_agg(
             private.leaderboard_entry_json(
               r.rank, r.public_user_id, r.username, r.display_name, r.competition_steps, r.user_id = v_user_id
             ) order by r.rank
           ),
           '[]'::jsonb
         )
    into v_entries
    from private.leaderboard_ranking(p_region_id, p_period, p_date) r
   where r.rank between v_my_rank - v_radius and v_my_rank + v_radius;

  return jsonb_build_object('total_participants', v_total, 'entries', v_entries);
end;
$$;

revoke all on function public.leaderboard_neighborhood(text, text, date, integer) from public, anon;
grant execute on function public.leaderboard_neighborhood(text, text, date, integer) to authenticated;
comment on function public.leaderboard_neighborhood(text, text, date, integer) is
  'Pace: eigener Platz ± Radius im regionalen Ranking ({total_participants, entries}). Nur öffentliche Felder.';
