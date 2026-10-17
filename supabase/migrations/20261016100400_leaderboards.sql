-- =============================================================================================================
-- Pace – regionale Rankings (serverseitig).
--
-- * Teilnehmer: Profile mit ausdrücklicher Zustimmung (regional_leaderboard_enabled), aktiver Gemeinde im Scope
--   und mindestens einem Tageswert im Zeitraum.
-- * Scope: Region beliebiger Ebene; Zugehörigkeit über die Hierarchie der Gemeinde. Abrufen darf man nur Rankings
--   der eigenen Regionen (Gemeinde, Kreis, Bundesland, Land der eigenen Gemeinde) – sonst ließe sich durch Abfragen
--   aller Gemeinden ermitteln, wo andere wohnen.
-- * Stichtag: nur die letzten 14 Tage bis morgen (UTC). Ältere Tageswerte anderer sind nicht abrufbar.
-- * Zeitraum: 'daily' (ein Tag) oder 'weekly' (ISO-Woche Montag–Sonntag, Summe).
-- * Reihenfolge: Schritte absteigend, bei Gleichstand wer den Wert zuerst erreicht hat, dann public_id.
-- * Ausgabe: nur öffentliche Felder. Nie Auth-IDs, E-Mail, Provider, Gesundheitsdetails oder Gemeinden anderer.
-- * Nie wird das gesamte Ranking an den Client geliefert: nur Seiten (limit/offset) oder die eigene Umgebung.
-- =============================================================================================================

-- Vollständiges Ranking eines Scopes. Intern; nur über die security-definer-Funktionen unten erreichbar.
-- Aktive Gemeinden eines Scopes. Eine Abfrage je Ebene, damit jeweils der passende Index genutzt wird.
create function private.scope_municipalities(p_level public.region_level, p_region_id text)
returns table (municipality_id text)
language plpgsql
stable
set search_path = ''
as $$
begin
  case p_level
    when 'municipality' then
      return query select m.id from public.regions m
        where m.level = 'municipality' and m.is_active and m.id = p_region_id;
    when 'district' then
      return query select m.id from public.regions m
        where m.level = 'municipality' and m.is_active and m.district_id = p_region_id;
    when 'state' then
      return query select m.id from public.regions m
        where m.level = 'municipality' and m.is_active and m.state_id = p_region_id;
    else
      return query select m.id from public.regions m
        where m.level = 'municipality' and m.is_active and m.country_id = p_region_id;
  end case;
end;
$$;
revoke all on function private.scope_municipalities(public.region_level, text) from public, anon, authenticated;

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
      from private.scope_municipalities(v_level, p_region_id) sm
      join public.profiles p
        on p.municipality_id = sm.municipality_id
       and p.regional_leaderboard_enabled
      join public.daily_activity a
        on a.user_id = p.id
       and a.activity_date between v_start and v_end
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

-- Prüft, ob der angemeldete Nutzer dieses Ranking abrufen darf: Region existiert, gehört zur Hierarchie seiner
-- eigenen Gemeinde, Stichtag liegt im erlaubten Fenster. Wer keine Gemeinde gewählt hat, sieht keine Rankings.
create function private.assert_leaderboard_access(p_user_id uuid, p_region_id text, p_date date)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
begin
  if p_user_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not exists (select 1 from public.regions r where r.id = p_region_id) then
    raise exception 'unknown_region' using errcode = '22023';
  end if;
  if not exists (
    select 1
      from public.profiles p
      join public.regions m on m.id = p.municipality_id
     where p.id = p_user_id
       and p_region_id in (m.id, m.district_id, m.state_id, m.country_id)
  ) then
    raise exception 'region_not_allowed' using errcode = '22023';
  end if;
  if p_date is null or p_date not between v_today - 14 and v_today + 1 then
    raise exception 'invalid_date' using errcode = '22023';
  end if;
end;
$$;
revoke all on function private.assert_leaderboard_access(uuid, text, date) from public, anon, authenticated;

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
  perform private.assert_leaderboard_access(v_user_id, p_region_id, p_date);

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
  v_entries jsonb;
begin
  perform private.assert_leaderboard_access(v_user_id, p_region_id, p_date);

  -- Das Ranking wird einmal berechnet (CTE mit mehreren Verweisen wird materialisiert).
  with ranking as materialized (
    select * from private.leaderboard_ranking(p_region_id, p_period, p_date)
  ),
  me as (
    select r.rank from ranking r where r.user_id = v_user_id
  )
  select coalesce((select max(r.total_participants) from ranking r), 0),
         coalesce(
           (select jsonb_agg(
                     private.leaderboard_entry_json(
                       r.rank, r.public_user_id, r.username, r.display_name, r.competition_steps, r.user_id = v_user_id
                     ) order by r.rank
                   )
              from ranking r
              join me on r.rank between me.rank - v_radius and me.rank + v_radius),
           '[]'::jsonb
         )
    into v_total, v_entries;

  return jsonb_build_object('total_participants', v_total, 'entries', v_entries);
end;
$$;

revoke all on function public.leaderboard_neighborhood(text, text, date, integer) from public, anon;
grant execute on function public.leaderboard_neighborhood(text, text, date, integer) to authenticated;
comment on function public.leaderboard_neighborhood(text, text, date, integer) is
  'Pace: eigener Platz ± Radius im regionalen Ranking ({total_participants, entries}). Nur öffentliche Felder.';
