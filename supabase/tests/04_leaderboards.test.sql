-- Pace: regionale Rankings – Teilnehmer, Ebenen, Reihenfolge, eigene Position, Datenschutz.
-- Verwendet ein synthetisches Land „XT“, damit Dev-Seed und echte Daten keinen Einfluss haben.
begin;
select plan(35);

-- Stichtag relativ zu heute (UTC), damit der Test an jedem Tag gilt: Freitag der Vorwoche (3–10 Tage zurück,
-- innerhalb des erlaubten Fensters von 14 Tagen).
create temporary table t_dates on commit drop as
select monday, monday + 4 as stichtag, monday - 1 as previous_sunday, utc_today
  from (select date_trunc('week', ((now() at time zone 'utc')::date - 7)::timestamp)::date as monday,
               (now() at time zone 'utc')::date as utc_today) d;
grant select on t_dates to authenticated, anon;

-- XT (Land) → XT:01 (Bundesland) → XT:01001 (Kreis mit 2 Gemeinden), XT:01002 (kreisfreie Stadt)
insert into public.regions (id, level, code, name, official_name, kind, parent_id, district_id, state_id, country_id, municipality_count, source) values
  ('XT', 'country', 'XT', 'Testland', 'Testland', 'country', null, null, null, 'XT', 3, 'test'),
  ('XT:01', 'state', '01', 'Testbundesland', 'Testbundesland', 'state', 'XT', null, null, 'XT', 3, 'test'),
  ('XT:01001', 'district', '01001', 'Testkreis', 'Testkreis', 'landkreis', 'XT:01', null, 'XT:01', 'XT', 2, 'test'),
  ('XT:01002', 'district', '01002', 'Teststadt', 'Teststadt, Stadt', 'kreisfreie_stadt', 'XT:01', null, 'XT:01', 'XT', 1, 'test'),
  ('XT:01001001', 'municipality', '01001001', 'Adorf', 'Adorf', 'gemeinde', 'XT:01001', 'XT:01001', 'XT:01', 'XT', 1, 'test'),
  ('XT:01001002', 'municipality', '01001002', 'Bedorf', 'Bedorf', 'gemeinde', 'XT:01001', 'XT:01001', 'XT:01', 'XT', 1, 'test'),
  ('XT:01002000', 'municipality', '01002000', 'Teststadt', 'Teststadt, Stadt', 'kreisfreie_stadt', 'XT:01002', 'XT:01002', 'XT:01', 'XT', 1, 'test');

insert into auth.users (id, aud, role, is_anonymous)
select ('aaaaaaaa-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 7) n;

-- 1–2 Adorf, 3 Bedorf, 4 Teststadt, 5 Adorf ohne Zustimmung, 6 Adorf ohne Tageswert, 7 ohne Gemeinde
insert into public.profiles (id, public_id, username, display_name, municipality_id, regional_leaderboard_enabled) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000001', 'eins', 'Eins', 'XT:01001001', true),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000002', 'zwei', 'Zwei', 'XT:01001001', true),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'bbbbbbbb-0000-4000-8000-000000000003', 'drei', 'Drei', 'XT:01001002', true),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'bbbbbbbb-0000-4000-8000-000000000004', 'vier', 'Vier', 'XT:01002000', true),
  ('aaaaaaaa-0000-4000-8000-000000000005', 'bbbbbbbb-0000-4000-8000-000000000005', 'fuenf', 'Fünf', 'XT:01001001', false),
  ('aaaaaaaa-0000-4000-8000-000000000006', 'bbbbbbbb-0000-4000-8000-000000000006', 'sechs', 'Sechs', 'XT:01001001', true),
  ('aaaaaaaa-0000-4000-8000-000000000007', 'bbbbbbbb-0000-4000-8000-000000000007', 'sieben', 'Sieben', null, false);

-- Woche Montag bis Sonntag der Vorwoche; Stichtag ist deren Freitag.
insert into public.daily_activity (user_id, activity_date, competition_steps)
select v.user_id::uuid, d.monday + v.day_offset, v.steps
  from t_dates d,
       (values
         ('aaaaaaaa-0000-4000-8000-000000000001', 4, 9000),
         ('aaaaaaaa-0000-4000-8000-000000000002', 4, 12000),
         ('aaaaaaaa-0000-4000-8000-000000000003', 4, 9000),
         ('aaaaaaaa-0000-4000-8000-000000000004', 4, 3000),
         ('aaaaaaaa-0000-4000-8000-000000000005', 4, 50000),
         ('aaaaaaaa-0000-4000-8000-000000000001', 0, 10000),
         ('aaaaaaaa-0000-4000-8000-000000000004', -1, 99999) -- Sonntag der Woche davor
       ) as v(user_id, day_offset, steps);

-- Gleichstand 1 und 3: Nutzer 3 hatte den Wert zuerst.
alter table public.daily_activity disable trigger daily_activity_maintain_timestamps;
update public.daily_activity set steps_changed_at = (select stichtag from t_dates) + time '08:00'
 where user_id = 'aaaaaaaa-0000-4000-8000-000000000003' and activity_date = (select stichtag from t_dates);
update public.daily_activity set steps_changed_at = (select stichtag from t_dates) + time '09:00'
 where user_id = 'aaaaaaaa-0000-4000-8000-000000000001' and activity_date = (select stichtag from t_dates);
alter table public.daily_activity enable trigger daily_activity_maintain_timestamps;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}';

-- Gemeinde: nur Adorf mit Zustimmung und Tageswert (1, 2).
select is((public.leaderboard_page('XT:01001001', 'daily', (select stichtag from t_dates))->>'total_participants')::int, 2, 'Gemeinde: 2 Teilnehmer');
select is(
  (select array_agg(e->>'username' order by (e->>'rank')::int)
     from jsonb_array_elements(public.leaderboard_page('XT:01001001', 'daily', (select stichtag from t_dates))->'entries') e),
  array['zwei', 'eins'], 'Gemeinde: absteigend nach Schritten'
);
select is(
  (select (e->>'is_current_user')::boolean from jsonb_array_elements(public.leaderboard_page('XT:01001001', 'daily', (select stichtag from t_dates))->'entries') e
    where e->>'username' = 'eins'),
  true, 'eigener Eintrag markiert'
);
select is(
  (select count(*)::int from jsonb_array_elements(public.leaderboard_page('XT:01001001', 'daily', (select stichtag from t_dates))->'entries') e
    where (e->>'is_current_user')::boolean),
  1, 'genau ein eigener Eintrag'
);

-- Kreis: Adorf + Bedorf (1, 2, 3); Gleichstand 1/3 → 3 zuerst.
select is(
  (select array_agg(e->>'username' order by (e->>'rank')::int)
     from jsonb_array_elements(public.leaderboard_page('XT:01001', 'daily', (select stichtag from t_dates))->'entries') e),
  array['zwei', 'drei', 'eins'], 'Kreis: Gleichstand – wer den Wert zuerst hatte'
);
-- Bundesland und Land: alle mit Zustimmung (1–4).
select is((public.leaderboard_page('XT:01', 'daily', (select stichtag from t_dates))->>'total_participants')::int, 4, 'Bundesland: 4 Teilnehmer');
select is((public.leaderboard_page('XT', 'daily', (select stichtag from t_dates))->>'total_participants')::int, 4, 'Land: 4 Teilnehmer');

-- Nur Rankings der eigenen Regionen.
select throws_ok($$select public.leaderboard_page('XT:01002000', 'daily', (select stichtag from t_dates))$$, '22023', 'region_not_allowed', 'fremde Gemeinde abgelehnt');
select throws_ok($$select public.leaderboard_page('XT:01002', 'daily', (select stichtag from t_dates))$$, '22023', 'region_not_allowed', 'fremder Kreis abgelehnt');
select throws_ok($$select public.leaderboard_neighborhood('XT:01002', 'daily', (select stichtag from t_dates), 1)$$, '22023', 'region_not_allowed', 'Nachbarschaft: fremder Kreis abgelehnt');

-- Nur Stichtage der letzten 14 Tage bis morgen.
select throws_ok($$select public.leaderboard_page('XT', 'daily', (select utc_today - 15 from t_dates))$$, '22023', 'invalid_date', 'älter als 14 Tage abgelehnt');
select throws_ok($$select public.leaderboard_page('XT', 'daily', (select utc_today + 2 from t_dates))$$, '22023', 'invalid_date', 'übermorgen abgelehnt');
select lives_ok($$select public.leaderboard_page('XT', 'daily', (select utc_today from t_dates))$$, 'heute erlaubt');

set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';
select is((public.leaderboard_page('XT:01002000', 'daily', (select stichtag from t_dates))->>'total_participants')::int, 1, 'kreisfreie Stadt als Gemeinde');
select is((public.leaderboard_page('XT:01002', 'daily', (select stichtag from t_dates))->>'total_participants')::int, 1, 'kreisfreie Stadt als Kreis');
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}';

-- Datenschutz und Teilnahme.
select ok(
  not exists (select 1 from jsonb_array_elements(public.leaderboard_page('XT', 'daily', (select stichtag from t_dates))->'entries') e
               where e->>'username' in ('fuenf', 'sechs')),
  'ohne Zustimmung bzw. ohne Tageswert nicht im Ranking'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.leaderboard_page('XT', 'daily', (select stichtag from t_dates))) k),
  array['entries', 'total_participants'], 'Antwort enthält nur total_participants und entries'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.leaderboard_page('XT', 'daily', (select stichtag from t_dates))->'entries'->0) k),
  array['competition_steps', 'display_name', 'is_current_user', 'public_user_id', 'rank', 'username'],
  'Einträge enthalten nur öffentliche Felder'
);
select ok(
  public.leaderboard_page('XT', 'daily', (select stichtag from t_dates))::text not like '%aaaaaaaa-%',
  'keine Auth-IDs in der Antwort'
);

-- Seiten.
select is(jsonb_array_length(public.leaderboard_page('XT', 'daily', (select stichtag from t_dates), 2, 0)->'entries'), 2, 'limit');
select is(
  (public.leaderboard_page('XT', 'daily', (select stichtag from t_dates), 2, 2)->'entries'->0->>'rank')::int, 3, 'offset'
);
select is(jsonb_array_length(public.leaderboard_page('XT', 'daily', (select stichtag from t_dates), 0, 0)->'entries'), 1, 'limit mindestens 1');
select is(jsonb_array_length(public.leaderboard_page('XT', 'daily', (select stichtag from t_dates), 1000, -5)->'entries'), 4, 'limit/offset begrenzt');

-- Eigene Umgebung.
select is(
  (select array_agg((e->>'rank')::int order by (e->>'rank')::int)
     from jsonb_array_elements(public.leaderboard_neighborhood('XT', 'daily', (select stichtag from t_dates), 1)->'entries') e),
  array[2, 3, 4], 'Nachbarschaft: eigener Platz ± 1'
);
select is(
  jsonb_array_length(public.leaderboard_neighborhood('XT', 'daily', (select stichtag from t_dates), 50)->'entries'), 4,
  'Radius begrenzt, nie mehr als vorhanden'
);

-- Woche: Summe Montag–Sonntag (Nutzer 1: 9000 + 10000; Vorwoche von Nutzer 4 zählt nicht).
select is(
  (select (e->>'competition_steps')::int from jsonb_array_elements(public.leaderboard_page('XT', 'weekly', (select stichtag from t_dates))->'entries') e
    where e->>'username' = 'eins'),
  19000, 'Woche: Summe der ISO-Woche'
);
select is(
  (select (e->>'competition_steps')::int from jsonb_array_elements(public.leaderboard_page('XT', 'weekly', (select stichtag from t_dates))->'entries') e
    where e->>'username' = 'vier'),
  3000, 'Woche: Vorwoche zählt nicht'
);

-- Fehler.
select throws_ok($$select public.leaderboard_page('XT:404', 'daily', (select stichtag from t_dates))$$, '22023', null, 'unbekannte Region');
select throws_ok($$select public.leaderboard_page('XT', 'monthly', (select stichtag from t_dates))$$, '22023', null, 'unbekannter Zeitraum');

-- Nutzer ohne Teilnahme: Nachbarschaft leer.
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":true}';
select is(
  jsonb_array_length(public.leaderboard_neighborhood('XT', 'daily', (select stichtag from t_dates), 1)->'entries'), 0,
  'ohne Zustimmung keine eigene Position'
);
select is(
  (public.leaderboard_neighborhood('XT', 'daily', (select stichtag from t_dates), 1)->>'total_participants')::int, 4,
  'Teilnehmerzahl trotzdem sichtbar'
);

-- Ohne Gemeinde keine Rankings.
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000007","role":"authenticated","is_anonymous":true}';
select throws_ok($$select public.leaderboard_page('XT', 'daily', (select stichtag from t_dates))$$, '22023', 'region_not_allowed', 'ohne Gemeinde abgelehnt');

-- Ohne Anmeldung.
set local request.jwt.claims = '{"role":"authenticated"}';
select throws_ok($$select public.leaderboard_page('XT', 'daily', (select stichtag from t_dates))$$, '42501', null, 'ohne Nutzer-ID abgelehnt');

reset role;
set local role anon;
select throws_ok($$select public.leaderboard_page('XT', 'daily', (select stichtag from t_dates))$$, '42501', null, 'anon darf nicht ausführen');
select throws_ok($$select public.search_municipalities('Adorf', 5)$$, '42501', null, 'anon: keine Suche');

reset role;
select * from finish();
rollback;
