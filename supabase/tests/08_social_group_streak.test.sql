-- Pace: Social – Gruppentag und Gruppen-Streak: Rundung, Tageswechsel, Lücken, Zieländerung, Beitritt/Austritt,
-- verspätete Synchronisation, leere Tage, Zeitzonen und Sommer-/Winterzeit.
-- Vergangene Tage entstehen durch gezielt zurückdatierte Gruppen, Mitgliedschaften und Tageswerte relativ zu „heute“
-- in der Gruppenzeitzone.
begin;
select plan(33);

-- 1 alex, 2 bea, 3 cem, 4 dina, 5 eli, 6 finn, 7 gabi, 8 hana, 9 ivan, 10 jana, 11–16 Sommerzeit-Test,
-- 101–120 Rundungstest.
insert into auth.users (id, aud, role, is_anonymous)
select ('a8000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 120) n;
insert into public.profiles (id, public_id, username, display_name)
select ('a8000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       ('b8000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'streak_' || n, 'Streak ' || n
  from generate_series(1, 120) n;

create function pg_temp.uid(n integer) returns uuid language sql immutable as $$
  select ('a8000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;
-- Zeitpunkt zu einer lokalen Uhrzeit an einem Tag in einer Zeitzone.
create function pg_temp.local_ts(p_day date, p_time time, p_time_zone text) returns timestamptz language sql immutable as $$
  select (p_day + p_time) at time zone p_time_zone;
$$;

-- Gruppen direkt anlegen (zurückdatierbar); das Ziel gilt ab dem Erstellungstag.
create temporary table t_groups (name text primary key, id uuid not null) on commit drop;
grant select on t_groups to authenticated;
create function pg_temp.gid(p_name text) returns uuid language sql stable as $$
  select g.id from t_groups g where g.name = p_name;
$$;
create function pg_temp.make_group(p_name text, p_time_zone text, p_created_at timestamptz, p_daily_goal integer)
returns void language sql as $$
  with g as (
    insert into public.groups (name, kind, time_zone, invite_code, created_at)
    values (p_name, 'friends', p_time_zone, private.generate_invite_code(), p_created_at)
    returning id, time_zone, created_at
  ),
  goal as (
    insert into public.group_goal_history (group_id, effective_from, daily_goal)
    select g.id, (g.created_at at time zone g.time_zone)::date, p_daily_goal from g
  )
  insert into t_groups (name, id) select p_name, g.id from g;
$$;

-- Heute in Berlin.
create temporary table t_dates on commit drop as select (now() at time zone 'Europe/Berlin')::date as t;
grant select on t_dates to authenticated;
create function pg_temp.t() returns date language sql stable as $$ select t from t_dates $$;

-- =============================================================================================================
-- Rundung: required = ceil(n / 3)
-- =============================================================================================================

select pg_temp.make_group('rundung', 'Europe/Berlin', now(), 5000);
insert into public.group_members (group_id, user_id, role) values (pg_temp.gid('rundung'), pg_temp.uid(101), 'owner');

create temporary table t_required (member_count integer, required_count integer) on commit drop;
do $$
declare
  v_size integer;
  v_next integer := 102;
begin
  foreach v_size in array array[1, 2, 3, 4, 6, 10, 12, 20] loop
    while (select count(*) from public.group_members m where m.group_id = pg_temp.gid('rundung')) < v_size loop
      insert into public.group_members (group_id, user_id) values (pg_temp.gid('rundung'), pg_temp.uid(v_next));
      v_next := v_next + 1;
    end loop;
    insert into t_required
    select s.member_count, s.required_count from private.group_day_stats(pg_temp.gid('rundung'), pg_temp.t(), pg_temp.t()) s;
  end loop;
end
$$;
select is(
  (select array_agg(r.member_count || '→' || r.required_count order by r.member_count) from t_required r),
  array['1→1', '2→1', '3→1', '4→2', '6→2', '10→4', '12→4', '20→7'],
  'benötigte Mitglieder: 1→1, 2→1, 3→1, 4→2, 6→2, 10→4, 12→4, 20→7'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-000000000101","role":"authenticated"}';
select is(
  (select r->>'member_count' || ':' || (r->>'today_required_count') from (select public.social_group(pg_temp.gid('rundung')) as r) x),
  '20:7', 'summary: 20 Mitglieder → 7 benötigt'
);
reset role;

-- =============================================================================================================
-- Streak: Gruppe „streak“ seit T−20, alex (owner), bea, cem → 1 von 3 muss das Ziel erreichen.
-- Ziel 10000 ab T−20, 11000 ab T−10.
-- Erreicht: T−16 … T−9 (8 Tage; T−12 nur durch bea mit genau dem Ziel), nicht erreicht: T−8 … T−6,
-- erreicht: T−5 … T−1 (5 Tage), heute noch offen.
-- =============================================================================================================

select pg_temp.make_group('streak', 'Europe/Berlin', pg_temp.local_ts(pg_temp.t() - 20, '08:00', 'Europe/Berlin'), 10000);
insert into public.group_goal_history (group_id, effective_from, daily_goal) values (pg_temp.gid('streak'), pg_temp.t() - 10, 11000);
insert into public.group_members (group_id, user_id, role, joined_at)
select pg_temp.gid('streak'), pg_temp.uid(n), case when n = 1 then 'owner' else 'member' end,
       pg_temp.local_ts(pg_temp.t() - 20, '08:00', 'Europe/Berlin')
  from generate_series(1, 3) n;

insert into public.daily_activity (user_id, activity_date, competition_steps)
select pg_temp.uid(1), pg_temp.t() - d, 12000 from generate_series(9, 16) d where d <> 12
union all select pg_temp.uid(2), pg_temp.t() - 12, 10000
union all select pg_temp.uid(1), pg_temp.t() - d, 5000 from generate_series(6, 8) d
union all select pg_temp.uid(2), pg_temp.t() - d, 9999 from generate_series(6, 8) d
union all select pg_temp.uid(1), pg_temp.t() - d, 12000 from generate_series(1, 5) d;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-000000000001","role":"authenticated"}';

select is(
  public.social_group(pg_temp.gid('streak'))
    - 'group_id' - 'name' - 'description' - 'kind' - 'role' - 'time_zone' - 'invite_code' - 'created_at' - 'group_today',
  '{"member_count": 3, "daily_goal": 11000, "next_daily_goal": null, "current_streak": 5, "best_streak": 8,
    "today_reached_count": 0, "today_required_count": 1, "today_complete": false}'::jsonb,
  'laufender Tag ohne Erfolg bricht die Streak nicht; best_streak über Lücke hinweg'
);
select is(
  (select array_agg(case when (e->>'reached')::boolean then 'x' else '-' end order by e->>'day') from jsonb_array_elements(public.social_group_days(pg_temp.gid('streak'))) e),
  array['x', 'x', 'x', 'x', 'x', '-', '-', '-', 'x', 'x', 'x', 'x', 'x', '-'],
  'Gruppentage T−13 … T: erreicht/nicht erreicht'
);
select is(
  (select e->>'day' || ':' || (e->>'is_today') from jsonb_array_elements(public.social_group_days(pg_temp.gid('streak'))) with ordinality as x(e, ord) where ord = 1),
  pg_temp.t()::text || ':true', 'Gruppentage: neueste zuerst, heute markiert'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_group_days(pg_temp.gid('streak'))->0) k),
  array['daily_goal', 'day', 'is_today', 'member_count', 'reached', 'reached_count', 'required_count'],
  'Gruppentage: Felder'
);
select is(
  (select array_agg((e->>'daily_goal') || '/' || (e->>'reached_count') || '/' || (e->>'required_count') || '/' || (e->>'member_count') order by e->>'day')
     from jsonb_array_elements(public.social_group_days(pg_temp.gid('streak'), 4)) e),
  array['11000/1/1/3', '11000/1/1/3', '11000/1/1/3', '11000/0/1/3'],
  'Gruppentage: p_days begrenzt, Kennzahlen je Tag'
);
select is(
  (select array_agg(e->>'daily_goal' order by e->>'day') from jsonb_array_elements(public.social_group_days(pg_temp.gid('streak'))) e
    where (e->>'day')::date in (pg_temp.t() - 12, pg_temp.t() - 11, pg_temp.t() - 10)),
  array['10000', '10000', '11000'], 'Ziel des Tages aus der Zielhistorie'
);
select is(jsonb_array_length(public.social_group_days(pg_temp.gid('streak'), 100)), 21, 'höchstens 60 Tage, nie vor dem Erstellungstag');
select is(jsonb_array_length(public.social_group_days(pg_temp.gid('streak'), 0)), 1, 'mindestens 1 Tag');

-- Heute erreicht → zählt sofort.
reset role;
insert into public.daily_activity (user_id, activity_date, competition_steps) values (pg_temp.uid(1), pg_temp.t(), 12000);
set local role authenticated;
select is(
  (select r->>'current_streak' || ':' || (r->>'best_streak') || ':' || (r->>'today_complete') || ':' || (r->>'today_reached_count')
     from (select public.social_group(pg_temp.gid('streak')) as r) x),
  '6:8:true:1', 'erreichter laufender Tag zählt zur Streak'
);

-- Lücke (T−3 fehlt) beendet die Streak.
reset role;
delete from public.daily_activity where user_id = pg_temp.uid(1) and activity_date = pg_temp.t() - 3;
set local role authenticated;
select is((public.social_group(pg_temp.gid('streak'))->>'current_streak')::int, 3, 'Lücke beendet die Streak');

-- Verspätete Synchronisation: nachträglich eingefügter Wert für T−3 verlängert die Streak beim nächsten Lesen.
reset role;
insert into public.daily_activity (user_id, activity_date, competition_steps) values (pg_temp.uid(1), pg_temp.t() - 3, 11000);
set local role authenticated;
select is((public.social_group(pg_temp.gid('streak'))->>'current_streak')::int, 6, 'verspäteter Wert schließt die Lücke');

-- Zieländerung gilt erst ab morgen.
select is(
  (select r->>'daily_goal' || ':' || (r->>'next_daily_goal') || ':' || (r->>'current_streak') || ':' || (r->>'today_complete')
     from (select public.social_set_group_goal(pg_temp.gid('streak'), 20000) as r) x),
  '11000:20000:6:true', 'Zieländerung: heute unverändert, ab morgen 20000'
);
select is(
  (select e->>'daily_goal' from jsonb_array_elements(public.social_group_days(pg_temp.gid('streak'))) e where (e->>'is_today')::boolean),
  '11000', 'Gruppentage: heutiges Ziel unverändert'
);
reset role;
select is(
  (select daily_goal from public.group_goal_history where group_id = pg_temp.gid('streak') and effective_from = pg_temp.t() + 1),
  20000, 'Zielhistorie: neues Ziel ab morgen'
);

-- Verspätete Werte für T−8 … T−6 verbinden beide Folgen: best_streak schließt heute ein.
update public.daily_activity set competition_steps = 12000
 where user_id = pg_temp.uid(1) and activity_date between pg_temp.t() - 8 and pg_temp.t() - 6;
set local role authenticated;
select is(
  (select r->>'current_streak' || ':' || (r->>'best_streak') from (select public.social_group(pg_temp.gid('streak')) as r) x),
  '17:17', 'aktualisierte Werte: durchgehende Streak inkl. heute'
);

-- Nur Mitglieder sehen Streak und Gruppentage.
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-000000000004","role":"authenticated"}';
select throws_ok(format('select public.social_group_days(%L)', pg_temp.gid('streak')), 'P0001', 'not_found', 'Gruppentage nur für Mitglieder');
reset role;

-- =============================================================================================================
-- Beitritt und Austritt an einem Tag: gezählt wird, wer am Tagesende Mitglied ist (Gruppe „wechsel“ seit T−5).
--   dina (owner) seit Beginn; eli: T−2 10:00–18:00; finn: seit T−2 20:00; gabi: T−3 09:00 bis T−2 08:00;
--   hana: T−4 10:00 bis genau zum Ende von T−3; finn zusätzlich mit überlappender Periode über das Ende von T−1.
-- =============================================================================================================

select pg_temp.make_group('wechsel', 'Europe/Berlin', pg_temp.local_ts(pg_temp.t() - 5, '08:00', 'Europe/Berlin'), 5000);
insert into public.group_members (group_id, user_id, role, joined_at) values
  (pg_temp.gid('wechsel'), pg_temp.uid(4), 'owner', pg_temp.local_ts(pg_temp.t() - 5, '08:00', 'Europe/Berlin')),
  (pg_temp.gid('wechsel'), pg_temp.uid(6), 'member', pg_temp.local_ts(pg_temp.t() - 2, '20:00', 'Europe/Berlin'));
insert into public.group_membership_periods (group_id, user_id, joined_at, left_at) values
  (pg_temp.gid('wechsel'), pg_temp.uid(5), pg_temp.local_ts(pg_temp.t() - 2, '10:00', 'Europe/Berlin'), pg_temp.local_ts(pg_temp.t() - 2, '18:00', 'Europe/Berlin')),
  (pg_temp.gid('wechsel'), pg_temp.uid(7), pg_temp.local_ts(pg_temp.t() - 3, '09:00', 'Europe/Berlin'), pg_temp.local_ts(pg_temp.t() - 2, '08:00', 'Europe/Berlin')),
  (pg_temp.gid('wechsel'), pg_temp.uid(8), pg_temp.local_ts(pg_temp.t() - 4, '10:00', 'Europe/Berlin'), pg_temp.local_ts(pg_temp.t() - 2, '00:00', 'Europe/Berlin')),
  (pg_temp.gid('wechsel'), pg_temp.uid(6), pg_temp.local_ts(pg_temp.t() - 1, '07:00', 'Europe/Berlin'), pg_temp.local_ts(pg_temp.t(), '06:00', 'Europe/Berlin'));
insert into public.daily_activity (user_id, activity_date, competition_steps) values
  (pg_temp.uid(5), pg_temp.t() - 2, 9000),   -- eli war am Tagesende nicht mehr Mitglied
  (pg_temp.uid(6), pg_temp.t() - 1, 6000);   -- finn

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-000000000004","role":"authenticated"}';
select is(
  (select array_agg((e->>'member_count')::int order by e->>'day') from jsonb_array_elements(public.social_group_days(pg_temp.gid('wechsel'))) e),
  array[1, 2, 3, 2, 2, 2], 'Mitglieder je Tag (T−5 … T) zum Tagesende'
);
select is(
  (select (e->>'reached_count') || ':' || (e->>'reached') from jsonb_array_elements(public.social_group_days(pg_temp.gid('wechsel'))) e
    where (e->>'day')::date = pg_temp.t() - 2),
  '0:false', 'Austritt am selben Tag: Schritte zählen nicht'
);
select is(
  (select (e->>'member_count') || ':' || (e->>'reached_count') || ':' || (e->>'reached') from jsonb_array_elements(public.social_group_days(pg_temp.gid('wechsel'))) e
    where (e->>'day')::date = pg_temp.t() - 1),
  '2:1:true', 'Mitglied zählt pro Tag einmal, auch bei überlappenden Perioden'
);
select is(
  (select r->>'member_count' || ':' || (r->>'today_required_count') from (select public.social_group(pg_temp.gid('wechsel')) as r) x),
  '2:1', 'laufender Tag: aktuelle Mitglieder'
);
reset role;

-- Austritt über die RPC schließt die Periode: Für heute zählt finn nicht mehr, gestern schon.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-000000000006","role":"authenticated"}';
select lives_ok(format('select public.social_leave_group(%L)', pg_temp.gid('wechsel')), 'finn verlässt die Gruppe');
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-000000000004","role":"authenticated"}';
select is(
  (select array_agg((e->>'member_count')::int order by e->>'day') from jsonb_array_elements(public.social_group_days(pg_temp.gid('wechsel'), 2)) e),
  array[2, 1], 'Austritt heute: gestern unverändert, heute nicht mehr gezählt'
);
reset role;
select is(
  (select count(*)::int from public.group_membership_periods
    where group_id = pg_temp.gid('wechsel') and user_id = pg_temp.uid(6) and left_at is null),
  0, 'Austritt schließt die offene Periode'
);

-- =============================================================================================================
-- Tage ohne Mitglieder: keine Streak, auch wenn spätere Mitglieder an diesen Tagen Schritte hatten (Gruppe „leer“).
-- =============================================================================================================

select pg_temp.make_group('leer', 'Europe/Berlin', pg_temp.local_ts(pg_temp.t() - 3, '08:00', 'Europe/Berlin'), 5000);
insert into public.group_members (group_id, user_id, role) values (pg_temp.gid('leer'), pg_temp.uid(9), 'owner');
insert into public.daily_activity (user_id, activity_date, competition_steps)
select pg_temp.uid(9), pg_temp.t() - d, 8000 from generate_series(1, 3) d;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-000000000009","role":"authenticated"}';
select is(
  (select array_agg((e->>'member_count') || '/' || (e->>'required_count') || '/' || (e->>'reached') order by e->>'day')
     from jsonb_array_elements(public.social_group_days(pg_temp.gid('leer'))) e),
  array['0/0/false', '0/0/false', '0/0/false', '1/1/false'], 'Tage ohne Mitglieder sind nie erreicht'
);
select is(
  (select r->>'current_streak' || ':' || (r->>'best_streak') from (select public.social_group(pg_temp.gid('leer')) as r) x),
  '0:0', 'leere Gruppe: keine Streak'
);
reset role;
insert into public.daily_activity (user_id, activity_date, competition_steps) values (pg_temp.uid(9), pg_temp.t(), 8000);
set local role authenticated;
select is(
  (select r->>'current_streak' || ':' || (r->>'best_streak') from (select public.social_group(pg_temp.gid('leer')) as r) x),
  '1:1', 'erst ab dem Beitritt zählt die Streak'
);
reset role;

-- =============================================================================================================
-- Zeitzonen: Gruppentag = Kalendertag in der Gruppenzeitzone (Kiritimati UTC+14, Pago Pago UTC−11).
-- =============================================================================================================

select pg_temp.make_group('kiritimati', 'Pacific/Kiritimati', now() - interval '3 days', 5000);
select pg_temp.make_group('pagopago', 'Pacific/Pago_Pago', now() - interval '3 days', 5000);
insert into public.group_members (group_id, user_id, role) values
  (pg_temp.gid('kiritimati'), pg_temp.uid(10), 'owner'),
  (pg_temp.gid('pagopago'), pg_temp.uid(10), 'owner');
insert into public.daily_activity (user_id, activity_date, competition_steps) values
  (pg_temp.uid(10), (now() at time zone 'Pacific/Kiritimati')::date, 7000),
  (pg_temp.uid(10), (now() at time zone 'Pacific/Pago_Pago')::date, 3000);

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-000000000010","role":"authenticated"}';
select is(
  (select r->>'group_today' || ':' || (r->>'today_complete') from (select public.social_group(pg_temp.gid('kiritimati')) as r) x),
  (now() at time zone 'Pacific/Kiritimati')::date::text || ':true', 'Kiritimati: eigener Gruppentag, Ziel erreicht'
);
select is(
  (select r->>'group_today' || ':' || (r->>'today_complete') from (select public.social_group(pg_temp.gid('pagopago')) as r) x),
  (now() at time zone 'Pacific/Pago_Pago')::date::text || ':false', 'Pago Pago: eigener Gruppentag, Ziel offen'
);
select is(
  (public.social_group_ranking(pg_temp.gid('pagopago'), 'daily')->'entries'->0->>'competition_steps')::int, 3000,
  'Gruppenranking nutzt den Gruppentag'
);
reset role;

-- =============================================================================================================
-- Sommer-/Winterzeit: Tagesende = Mitternacht in der Gruppenzeitzone (Europe/Berlin).
--   29.03.2026: Umstellung auf Sommerzeit, Tagesende = 30.03. 00:00 MESZ = 22:00 UTC.
--   26.10.2025: Umstellung auf Winterzeit (25 Stunden), Tagesende = 23:00 UTC.
-- =============================================================================================================

select pg_temp.make_group('sommerzeit', 'Europe/Berlin', '2025-01-01 12:00+00', 5000);
insert into public.group_membership_periods (group_id, user_id, joined_at, left_at) values
  (pg_temp.gid('sommerzeit'), pg_temp.uid(11), '2025-01-01 12:00+00', null),
  (pg_temp.gid('sommerzeit'), pg_temp.uid(12), '2026-03-29 22:30+00', null),                  -- 30.03. 00:30 MESZ
  (pg_temp.gid('sommerzeit'), pg_temp.uid(13), '2026-03-29 21:30+00', null),                  -- 29.03. 23:30 MESZ
  (pg_temp.gid('sommerzeit'), pg_temp.uid(14), '2026-03-01 12:00+00', '2026-03-29 21:59:59+00'), -- bis 23:59:59 MESZ
  (pg_temp.gid('sommerzeit'), pg_temp.uid(15), '2025-10-26 22:30+00', null),                  -- 26.10. 23:30 MEZ
  (pg_temp.gid('sommerzeit'), pg_temp.uid(16), '2025-10-26 23:00+00', null);                  -- 27.10. 00:00 MEZ

select is(
  (select array_agg(s.member_count order by s.day) from private.group_day_stats(pg_temp.gid('sommerzeit'), '2026-03-28', '2026-03-30') s),
  array[4, 4, 5], 'Sommerzeitbeginn: Tagesende in Ortszeit'
);
select is(
  (select array_agg(s.member_count order by s.day) from private.group_day_stats(pg_temp.gid('sommerzeit'), '2025-10-25', '2025-10-27') s),
  array[1, 2, 3], 'Sommerzeitende (25-Stunden-Tag): Tagesende in Ortszeit'
);

select * from finish();
rollback;
