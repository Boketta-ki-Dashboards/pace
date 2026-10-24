-- =============================================================================================================
-- Pace – Gruppenkalender: Tagesergebnisse und Tagesranglisten einer Gruppe (höchstens 42 Tage je Abruf).
--
-- Nur additiv: eine neue RPC, keine Änderung an Tabellen oder bestehenden Funktionen.
--
-- * Nur aktuelle Mitglieder (sonst not_found, Existenz bleibt verborgen).
-- * Zeitraum p_first_day … p_last_day (höchstens 42 Tage, sonst invalid_date) wird auf Gründungstag … heute
--   begrenzt – jeweils Gruppentage in der Zeitzone der Gruppe. Tage davor bzw. danach fehlen in days; die App zeigt
--   sie ehrlich als „vor der Gruppe“ bzw. „noch nicht erreicht“ (first_group_day und group_today stehen in der
--   Antwort).
-- * Kennzahlen je Tag kommen unverändert aus private.group_day_stats – dieselbe Berechnung wie Streak,
--   social_group und social_group_days: Mitglieder des Tages laut Mitgliedschaftsperioden (zum Tagesende),
--   historisches Tagesziel (Zielhistorie), required = ⌈n/3⌉, reached = Mitglieder mit Wettbewerbsschritten ≥ Ziel,
--   secured = Flamme gesichert.
-- * ranking: alle Mitglieder des Tages (auch später ausgetretene) mit ihren Wettbewerbsschritten dieses Tages,
--   Reihenfolge wie in allen Social-Rankings (private.social_step_ranking: Schritte absteigend, wer den Wert zuerst
--   hatte, public_id – Plätze sind eindeutig), reached und nickname (eigener Spitzname). Eine Zeile je Mitglied des
--   Tages, damit member_count = Zeilenzahl und reached_count = Zeilen mit reached bleiben.
-- * Blockierungen: Aktuelle Mitglieder erscheinen wie im Gruppenranking immer (auch bei einer Blockierung in einer
--   der beiden Richtungen). Ehemalige Mitglieder, die den Aufrufer blockiert haben, erscheinen anonymisiert: Zeile
--   mit Platz, Schritten und reached, aber public_id, username, display_name, avatar_path und nickname null (wie
--   private.can_view_profile, das solche Profile für den Aufrufer verbirgt).
-- * Gruppenhistorie: Mitglieder sehen alle Tage ab der Gründung, auch vor ihrem eigenen Beitritt (wie die Streak
--   und social_group_days) – ehemalige Mitglieder gehören zur Geschichte der Gruppe (can_view_profile erlaubt
--   ihre Profile allen aktuellen Mitgliedern, außer bei einer Blockierung, siehe oben).
-- * has_data: Mindestens ein Mitglied des Tages hat für diesen Tag Schritte synchronisiert.
-- =============================================================================================================

create function public.social_group_calendar(p_group_id uuid, p_first_day date, p_last_day date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_group public.groups%rowtype;
  v_today date;
  v_first_group_day date;
  v_from date;
  v_to date;
  v_days jsonb;
begin
  perform private.require_group_member(p_group_id, v_me);
  if p_first_day is null or p_last_day is null or p_last_day < p_first_day or p_last_day - p_first_day > 41 then
    raise exception 'invalid_date';
  end if;

  select * into v_group from public.groups g where g.id = p_group_id;
  v_today := private.local_today(v_group.time_zone);
  v_first_group_day := (v_group.created_at at time zone v_group.time_zone)::date;
  v_from := greatest(p_first_day, v_first_group_day);
  v_to := least(p_last_day, v_today);

  if v_from <= v_to then
    with stats as materialized (
      select s.day, s.member_count, s.required_count, s.reached_count, s.daily_goal, s.reached
        from private.group_day_stats(p_group_id, v_from, v_to) s
    ),
    -- Mitglieder je Tag wie in group_day_stats: Perioden, die das Tagesende abdecken.
    days as (
      select st.*,
             array(
               select distinct mp.user_id
                 from public.group_membership_periods mp
                where mp.group_id = p_group_id
                  and mp.joined_at < ((st.day + 1)::timestamp at time zone v_group.time_zone)
                  and (mp.left_at is null or mp.left_at >= ((st.day + 1)::timestamp at time zone v_group.time_zone))
             ) as member_ids
        from stats st
    )
    select jsonb_agg(
             jsonb_build_object(
               'day', d.day,
               'daily_goal', d.daily_goal,
               'member_count', d.member_count,
               'required_count', d.required_count,
               'reached_count', d.reached_count,
               'secured', d.reached,
               'has_data', exists (
                 select 1 from public.daily_activity a
                  where a.user_id = any (d.member_ids) and a.activity_date = d.day
               ),
               'is_today', d.day = v_today,
               'ranking', (
                 select coalesce(
                          jsonb_agg(
                            case
                              when gm.user_id is null and private.has_blocked(r.user_id, v_me) then
                                -- Ehemaliges Mitglied, das mich blockiert hat: anonymisiert (Zählwerte bleiben).
                                jsonb_build_object('public_id', null, 'username', null, 'display_name', null,
                                                   'avatar_path', null, 'nickname', null)
                              else private.profile_json(p)
                            end || jsonb_build_object(
                              'rank', r.rank,
                              'competition_steps', r.competition_steps,
                              'reached', coalesce(r.competition_steps >= d.daily_goal, false),
                              'is_current_user', r.user_id = v_me
                            ) order by r.rank
                          ),
                          '[]'::jsonb
                        )
                   from private.social_step_ranking(d.member_ids, d.day, d.day) r
                   join public.profiles p on p.id = r.user_id
                   left join public.group_members gm on gm.group_id = p_group_id and gm.user_id = r.user_id
               )
             ) order by d.day
           )
      into v_days
      from days d;
  end if;

  return jsonb_build_object(
    'group_id', p_group_id,
    'time_zone', v_group.time_zone,
    'group_today', v_today,
    'first_group_day', v_first_group_day,
    'days', coalesce(v_days, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.social_group_calendar(uuid, date, date) from public, anon;
grant execute on function public.social_group_calendar(uuid, date, date) to authenticated;
comment on function public.social_group_calendar(uuid, date, date) is
  'Pace: Gruppenkalender für Mitglieder – je Gruppentag (höchstens 42, begrenzt auf Gründung … heute) Ziel, Mitglieder, benötigt (⌈n/3⌉), erreicht, gesichert, has_data, is_today und Tagesrangliste (wie social_group_days/Streak). Ehemalige Mitglieder, die den Aufrufer blockiert haben, ohne Profilfelder (null).';
