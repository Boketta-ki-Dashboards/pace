-- Pace: Gruppenkalender – Rechte, Zeitraumgrenzen, historische Mitglieder und Ziele, ⌈n/3⌉, Gleichstände, leere
-- Tage, Spitznamen, Blockierte und Übereinstimmung mit social_group_days (gleiche Berechnung wie die Streak).
begin;
select plan(40);

-- =============================================================================================================
-- Struktur
-- =============================================================================================================

select ok(
  not has_function_privilege('anon', 'public.social_group_calendar(uuid, date, date)', 'execute')
  and not has_function_privilege('public', 'public.social_group_calendar(uuid, date, date)', 'execute')
  and has_function_privilege('authenticated', 'public.social_group_calendar(uuid, date, date)', 'execute'),
  'social_group_calendar: nur authenticated'
);
select ok(
  (select p.prosecdef and p.proconfig = array['search_path=""'] and obj_description(p.oid, 'pg_proc') is not null
     from pg_proc p where p.oid = 'public.social_group_calendar(uuid, date, date)'::regprocedure),
  'social_group_calendar: security definer, leerer search_path, Kommentar'
);

-- =============================================================================================================
-- Testdaten
-- =============================================================================================================

-- 1 olaf (Owner), 2 paul (ausgetreten an t-5), 3 quirin (beigetreten an t-2), 4 rita (blockiert von quirin),
-- 5 sina (Fremde). Gruppe in Berlin, gegründet an t-10 um 08:00; Ziel 5000, ab t-3 8000.
insert into auth.users (id, aud, role, is_anonymous)
select ('a5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 5) n;
insert into public.profiles (id, public_id, username, display_name)
select ('a5000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('b5000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'olaf_k', 'Olaf'), (2, 'paul_k', 'Paul'), (3, 'quirin_k', 'Quirin'), (4, 'rita_k', 'Rita'),
               (5, 'sina_k', 'Sina')) as v(n, username, display_name);

create function pg_temp.uid(n int) returns uuid language sql immutable as $$
  select ('a5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;
create function pg_temp.pid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;
create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claims',
                    format('{"sub":"a5000000-0000-4000-8000-%s","role":"authenticated"}', lpad(n::text, 12, '0')), true);
$$;
create temporary table t_dates on commit drop as select (now() at time zone 'Europe/Berlin')::date as t;
grant select on t_dates to authenticated;
create function pg_temp.t() returns date language sql stable as $$ select t from t_dates $$;
create function pg_temp.at(p_day date, p_time time) returns timestamptz language sql immutable as $$
  select (p_day + p_time) at time zone 'Europe/Berlin';
$$;
create function pg_temp.g() returns uuid language sql immutable as $$ select 'c5000000-0000-4000-8000-000000000001'::uuid $$;

insert into public.groups (id, name, kind, time_zone, invite_code, created_by, created_at)
values (pg_temp.g(), 'Kalendergruppe', 'friends', 'Europe/Berlin', 'KALNDRXY', pg_temp.uid(1), pg_temp.at(pg_temp.t() - 10, '08:00'));
insert into public.group_goal_history (group_id, effective_from, daily_goal)
values (pg_temp.g(), pg_temp.t() - 10, 5000), (pg_temp.g(), pg_temp.t() - 3, 8000);
insert into public.group_members (group_id, user_id, role, joined_at)
values (pg_temp.g(), pg_temp.uid(1), 'owner', pg_temp.at(pg_temp.t() - 10, '08:00')),
       (pg_temp.g(), pg_temp.uid(4), 'member', pg_temp.at(pg_temp.t() - 10, '09:00')),
       (pg_temp.g(), pg_temp.uid(3), 'member', pg_temp.at(pg_temp.t() - 2, '12:00'));
-- paul war von der Gründung bis t-5 (12:00) Mitglied.
insert into public.group_membership_periods (group_id, user_id, joined_at, left_at)
values (pg_temp.g(), pg_temp.uid(2), pg_temp.at(pg_temp.t() - 10, '09:30'), pg_temp.at(pg_temp.t() - 5, '12:00'));

-- Tageswerte: (Person, Tag relativ zu t, Schritte, Änderungszeit)
insert into public.daily_activity (user_id, activity_date, competition_steps)
select pg_temp.uid(v.n), pg_temp.t() + v.d, v.steps
  from (values (1, -7, 6000), (2, -7, 6000), (4, -7, 0),     -- Gleichstand olaf/paul; paul hatte den Wert früher
               (1, -4, 4000), (4, -4, 7000),                 -- paul ist ausgetreten, sein Wert zählt nicht mehr
               (2, -4, 9000),
               (1, -3, 7000),                                -- neues Ziel 8000: niemand erreicht es
               (1, -1, 8000), (4, -1, 8000),                 -- Gleichstand mit gleicher Änderungszeit → public_id
               (3, 0, 9000)) as v(n, d, steps);
alter table public.daily_activity disable trigger daily_activity_maintain_timestamps;
update public.daily_activity a set steps_changed_at = pg_temp.at(a.activity_date, '20:00')
 where a.user_id in (pg_temp.uid(1), pg_temp.uid(2), pg_temp.uid(3), pg_temp.uid(4));
update public.daily_activity a set steps_changed_at = pg_temp.at(a.activity_date, '18:00')
 where a.user_id = pg_temp.uid(2) and a.activity_date = pg_temp.t() - 7;
alter table public.daily_activity enable trigger daily_activity_maintain_timestamps;

-- olaf und rita sind befreundet (Spitzname), quirin hat rita blockiert.
insert into public.friendships (user_a, user_b) values (pg_temp.uid(1), pg_temp.uid(4));
insert into public.user_blocks (blocker_id, blocked_id) values (pg_temp.uid(3), pg_temp.uid(4));

create temporary table t_cal (name text primary key, result jsonb) on commit drop;
grant select, insert on t_cal to authenticated;
create function pg_temp.cal(p_name text) returns jsonb language sql stable as $$
  select c.result from t_cal c where c.name = p_name;
$$;
create function pg_temp.day(p_name text, p_offset int) returns jsonb language sql stable as $$
  select e from jsonb_array_elements(pg_temp.cal(p_name)->'days') e where (e->>'day')::date = pg_temp.t() + p_offset;
$$;
create function pg_temp.order_of(p_day jsonb) returns text[] language sql immutable as $$
  select array_agg(e->>'username' || ':' || (e->>'rank') || ':' || (e->>'competition_steps') || ':' || (e->>'reached') order by (e->>'rank')::int)
    from jsonb_array_elements(p_day->'ranking') e;
$$;

set local role authenticated;

-- =============================================================================================================
-- Abruf als Owner (olaf)
-- =============================================================================================================

select pg_temp.as_user(1);
select lives_ok(
  $$select public.social_set_friend_nickname(pg_temp.pid(4), 'Rita Rakete')$$, 'olaf vergibt einen Spitznamen für rita'
);
insert into t_cal select 'olaf', public.social_group_calendar(pg_temp.g(), pg_temp.t() - 13, pg_temp.t() + 5);

select is(
  pg_temp.cal('olaf') - 'days',
  jsonb_build_object('group_id', pg_temp.g(), 'time_zone', 'Europe/Berlin', 'group_today', pg_temp.t(),
                     'first_group_day', pg_temp.t() - 10),
  'Kopf: Gruppe, Zeitzone, heute, Gründungstag'
);
select is(
  (select array_agg((e->>'day')::date order by ord) from jsonb_array_elements(pg_temp.cal('olaf')->'days') with ordinality x(e, ord)),
  (select array_agg(d::date order by d) from generate_series(pg_temp.t() - 10, pg_temp.t(), interval '1 day') d),
  'Zeitraum begrenzt auf Gründung … heute, aufsteigend'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(pg_temp.day('olaf', -7)) k),
  array['daily_goal', 'day', 'has_data', 'is_today', 'member_count', 'ranking', 'reached_count', 'required_count', 'secured'],
  'Tag: Felder'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(pg_temp.day('olaf', -7)->'ranking'->0) k),
  array['avatar_path', 'competition_steps', 'display_name', 'is_current_user', 'nickname', 'public_id', 'rank', 'reached',
        'username'],
  'Ranglistenzeile: Felder'
);

-- t-7: Mitglieder olaf, paul, rita (n = 3, benötigt 1); Gleichstand olaf/paul → wer den Wert zuerst hatte.
select is(
  pg_temp.day('olaf', -7) - 'ranking' - 'day',
  jsonb_build_object('daily_goal', 5000, 'member_count', 3, 'required_count', 1, 'reached_count', 2, 'secured', true,
                     'has_data', true, 'is_today', false),
  't-7: historische Mitglieder (inkl. später ausgetretener), Ziel 5000, gesichert'
);
select is(
  pg_temp.order_of(pg_temp.day('olaf', -7)),
  array['paul_k:1:6000:true', 'olaf_k:2:6000:true', 'rita_k:3:0:false'],
  't-7: Gleichstand wie in den übrigen Rankings (früherer Wert zuerst)'
);
-- t-4: paul ist seit t-5 ausgetreten (sein Wert zählt nicht), n = 2, benötigt 1.
select is(
  pg_temp.day('olaf', -4) - 'ranking' - 'day',
  jsonb_build_object('daily_goal', 5000, 'member_count', 2, 'required_count', 1, 'reached_count', 1, 'secured', true,
                     'has_data', true, 'is_today', false),
  't-4: Ausgetretene zählen nicht mehr'
);
select is(
  pg_temp.order_of(pg_temp.day('olaf', -4)),
  array['rita_k:1:7000:true', 'olaf_k:2:4000:false'],
  't-4: Rangliste ohne Ausgetretene'
);
select is(pg_temp.day('olaf', -4)->'ranking'->0->>'nickname', 'Rita Rakete', 'eigener Spitzname in der Rangliste');
select is(
  (select e->>'is_current_user' from jsonb_array_elements(pg_temp.day('olaf', -4)->'ranking') e where e->>'username' = 'olaf_k'),
  'true', 'eigene Zeile markiert'
);
-- t-3: neues Ziel 8000 gilt historisch ab diesem Tag.
select is(
  pg_temp.day('olaf', -3) - 'ranking' - 'day',
  jsonb_build_object('daily_goal', 8000, 'member_count', 2, 'required_count', 1, 'reached_count', 0, 'secured', false,
                     'has_data', true, 'is_today', false),
  't-3: Zieländerung, nicht gesichert'
);
select is(pg_temp.day('olaf', -4)->>'daily_goal', '5000', 'Tag vor der Zieländerung behält das alte Ziel');
-- t-2: quirin beigetreten (n = 3, benötigt 1), niemand hat Daten.
select is(
  pg_temp.day('olaf', -2) - 'ranking' - 'day',
  jsonb_build_object('daily_goal', 8000, 'member_count', 3, 'required_count', 1, 'reached_count', 0, 'secured', false,
                     'has_data', false, 'is_today', false),
  't-2: leerer Tag – has_data false, nicht gesichert'
);
select is(
  (select array_agg(e->>'username' order by (e->>'rank')::int) from jsonb_array_elements(pg_temp.day('olaf', -2)->'ranking') e),
  array['olaf_k', 'quirin_k', 'rita_k'],  -- public_id …01 < …03 < …04
  't-2: ohne Werte alle mit 0, Reihenfolge nach public_id'
);
-- t-1: Gleichstand mit gleicher Änderungszeit → public_id.
select is(
  pg_temp.order_of(pg_temp.day('olaf', -1)),
  array['olaf_k:1:8000:true', 'rita_k:2:8000:true', 'quirin_k:3:0:false'],
  't-1: gleicher Wert und Zeitpunkt → public_id'
);
select is(
  pg_temp.day('olaf', 0) - 'ranking' - 'day',
  jsonb_build_object('daily_goal', 8000, 'member_count', 3, 'required_count', 1, 'reached_count', 1, 'secured', true,
                     'has_data', true, 'is_today', true),
  'heute: laufender Tag gekennzeichnet'
);
select is(
  (select count(*)::int from jsonb_array_elements(pg_temp.cal('olaf')->'days') e where (e->>'is_today')::boolean),
  1, 'genau ein Tag ist heute'
);

-- Übereinstimmung mit social_group_days (gleiche Berechnung wie Streak und Gruppenansicht).
select is(
  (select array_agg(jsonb_build_object('day', e->'day', 'member_count', e->'member_count', 'required_count', e->'required_count',
                                       'reached_count', e->'reached_count', 'daily_goal', e->'daily_goal',
                                       'reached', e->'secured', 'is_today', e->'is_today') order by e->>'day')
     from jsonb_array_elements(pg_temp.cal('olaf')->'days') e),
  (select array_agg(e order by e->>'day') from jsonb_array_elements(public.social_group_days(pg_temp.g(), 60)) e),
  'alle Tage stimmen mit social_group_days überein'
);
select ok(
  (select bool_and((e->>'reached_count')::int = (select count(*) from jsonb_array_elements(e->'ranking') r where (r->>'reached')::boolean)
                   and (e->>'member_count')::int = jsonb_array_length(e->'ranking')
                   and (e->>'required_count')::int = ((e->>'member_count')::int + 2) / 3)
     from jsonb_array_elements(pg_temp.cal('olaf')->'days') e),
  'je Tag: Rangliste = Mitglieder, reached = erreicht, benötigt = ⌈n/3⌉'
);

-- =============================================================================================================
-- Zeitraumgrenzen
-- =============================================================================================================

select is(
  jsonb_array_length(public.social_group_calendar(pg_temp.g(), pg_temp.t() - 41, pg_temp.t())->'days'), 11,
  '42 Tage erlaubt (begrenzt auf Gründung … heute)'
);
select throws_ok(
  $$select public.social_group_calendar(pg_temp.g(), pg_temp.t() - 42, pg_temp.t())$$,
  'P0001', 'invalid_date', '43 Tage: invalid_date'
);
select throws_ok(
  $$select public.social_group_calendar(pg_temp.g(), pg_temp.t(), pg_temp.t() - 1)$$,
  'P0001', 'invalid_date', 'Ende vor Anfang: invalid_date'
);
select throws_ok(
  $$select public.social_group_calendar(pg_temp.g(), null, pg_temp.t())$$,
  'P0001', 'invalid_date', 'ohne Anfang: invalid_date'
);
select is(
  public.social_group_calendar(pg_temp.g(), pg_temp.t() + 1, pg_temp.t() + 30)->'days', '[]'::jsonb,
  'nur zukünftige Tage: keine Einträge'
);
select is(
  public.social_group_calendar(pg_temp.g(), pg_temp.t() - 40, pg_temp.t() - 11)->'days', '[]'::jsonb,
  'nur Tage vor der Gründung: keine Einträge'
);

-- =============================================================================================================
-- Rechte, Spitznamen anderer, Blockierte
-- =============================================================================================================

select pg_temp.as_user(3);
insert into t_cal select 'quirin', public.social_group_calendar(pg_temp.g(), pg_temp.t() - 5, pg_temp.t());
select is(
  (select array_agg(e->>'username' order by e->>'username') from jsonb_array_elements(pg_temp.day('quirin', -1)->'ranking') e),
  array['olaf_k', 'quirin_k', 'rita_k'],
  'Blockierte bleiben wie im Gruppenranking in der Rangliste'
);
select ok(pg_temp.cal('quirin')::text not like '%Rita Rakete%', 'fremde Spitznamen erscheinen nie');

-- Ehemalige Mitglieder, die mich blockiert haben, und Gruppenhistorie: paul (ausgetreten an t-5) blockiert quirin
-- (beigetreten an t-2).
reset role;
insert into public.user_blocks (blocker_id, blocked_id) values (pg_temp.uid(2), pg_temp.uid(3));
set local role authenticated;
select pg_temp.as_user(3);
insert into t_cal select 'quirin_hist', public.social_group_calendar(pg_temp.g(), pg_temp.t() - 13, pg_temp.t());
select is(
  (select array_agg((e->>'day')::date order by e->>'day') from jsonb_array_elements(pg_temp.cal('quirin_hist')->'days') e),
  (select array_agg(d::date order by d) from generate_series(pg_temp.t() - 10, pg_temp.t(), interval '1 day') d),
  'Gruppenhistorie: Mitglied sieht auch Tage vor dem eigenen Beitritt (ab Gründung)'
);
select is(
  pg_temp.day('quirin_hist', -7)->'ranking'->0,
  jsonb_build_object('public_id', null, 'username', null, 'display_name', null, 'avatar_path', null, 'nickname', null,
                     'rank', 1, 'competition_steps', 6000, 'reached', true, 'is_current_user', false),
  'ehemaliges Mitglied, das mich blockiert hat: anonymisiert, Platz und Schritte bleiben'
);
select ok(
  pg_temp.cal('quirin_hist')::text not like '%paul_k%' and pg_temp.cal('quirin_hist')::text not like '%Paul%'
  and pg_temp.cal('quirin_hist')::text not like '%' || pg_temp.pid(2)::text || '%',
  'weder Name noch Benutzername noch public_id des blockierenden Ex-Mitglieds'
);
select ok(
  (select bool_and((e->>'member_count')::int = jsonb_array_length(e->'ranking')
                   and (e->>'reached_count')::int = (select count(*) from jsonb_array_elements(e->'ranking') r where (r->>'reached')::boolean))
     from jsonb_array_elements(pg_temp.cal('quirin_hist')->'days') e),
  'anonymisiert: member_count = Zeilen, reached_count = Zeilen mit reached'
);
select is(
  (select array_agg(e - 'ranking' order by e->>'day') from jsonb_array_elements(pg_temp.cal('quirin_hist')->'days') e),
  (select array_agg(e - 'ranking' order by e->>'day') from jsonb_array_elements(pg_temp.cal('olaf')->'days') e),
  'Kennzahlen für alle Mitglieder gleich (Blockierung ändert keine Zählwerte)'
);
select pg_temp.as_user(1);
select is(
  public.social_group_calendar(pg_temp.g(), pg_temp.t() - 7, pg_temp.t() - 7)->'days'->0->'ranking'->0->>'username',
  'paul_k', 'andere Mitglieder sehen das ehemalige Mitglied weiter'
);
-- quirin hat rita blockiert: rita sieht das aktuelle Mitglied quirin trotzdem – wie im Gruppenranking.
select pg_temp.as_user(4);
select ok(
  exists (select 1 from jsonb_array_elements(public.social_group_calendar(pg_temp.g(), pg_temp.t() - 1, pg_temp.t() - 1)->'days'->0->'ranking') e
           where e->>'username' = 'quirin_k'),
  'aktuelles Mitglied, das mich blockiert hat, bleibt sichtbar (wie im Gruppenranking)'
);
select pg_temp.as_user(2);
select throws_ok(
  $$select public.social_group_calendar(pg_temp.g(), pg_temp.t() - 7, pg_temp.t())$$,
  'P0001', 'not_found', 'ehemaliges Mitglied: not_found'
);
select pg_temp.as_user(5);
select throws_ok(
  $$select public.social_group_calendar(pg_temp.g(), pg_temp.t() - 7, pg_temp.t())$$,
  'P0001', 'not_found', 'Fremde: not_found'
);
set local request.jwt.claims = '{"role":"authenticated"}';
select throws_ok(
  $$select public.social_group_calendar(pg_temp.g(), pg_temp.t() - 7, pg_temp.t())$$,
  '42501', 'not_authenticated', 'ohne Anmeldung: not_authenticated'
);

select * from finish();
rollback;
