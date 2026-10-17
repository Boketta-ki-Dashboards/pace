-- Pace: tägliche Wettbewerbsschritte – Upsert, Fenster, Grenzen, Sichtbarkeit.
begin;
select plan(16);

insert into auth.users (id, aud, role, is_anonymous) values
  ('11111111-1111-4111-8111-111111111111', 'authenticated', 'authenticated', true),
  ('22222222-2222-4222-8222-222222222222', 'authenticated', 'authenticated', true);
insert into public.profiles (id, username, display_name) values
  ('11111111-1111-4111-8111-111111111111', 'erster', 'Erster'),
  ('22222222-2222-4222-8222-222222222222', 'zweiter', 'Zweiter');

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":true}';

select lives_ok(
  $$insert into public.daily_activity (user_id, activity_date, competition_steps)
    values ('11111111-1111-4111-8111-111111111111', (now() at time zone 'utc')::date, 5000)$$,
  'eigenen Tageswert schreiben'
);
select lives_ok(
  $$insert into public.daily_activity (user_id, activity_date, competition_steps)
    values ('11111111-1111-4111-8111-111111111111', (now() at time zone 'utc')::date, 7500)
    on conflict (user_id, activity_date) do update
      set user_id = excluded.user_id, activity_date = excluded.activity_date, competition_steps = excluded.competition_steps$$,
  'Upsert wie PostgREST'
);
select is((select count(*)::int from public.daily_activity), 1, 'kein doppelter Tagesdatensatz');
select is((select competition_steps from public.daily_activity), 7500, 'Upsert aktualisiert den Wert');
select throws_ok(
  $$insert into public.daily_activity (user_id, activity_date, competition_steps)
    values ('22222222-2222-4222-8222-222222222222', (now() at time zone 'utc')::date, 100)$$,
  '42501', null, 'kein Schreiben für fremde Nutzer'
);
select throws_ok(
  $$insert into public.daily_activity (user_id, activity_date, competition_steps)
    values ('11111111-1111-4111-8111-111111111111', (now() at time zone 'utc')::date - 30, 100)$$,
  '42501', null, 'Tage außerhalb des Sync-Fensters abgelehnt'
);
select throws_ok(
  $$insert into public.daily_activity (user_id, activity_date, competition_steps)
    values ('11111111-1111-4111-8111-111111111111', (now() at time zone 'utc')::date + 5, 100)$$,
  '42501', null, 'Tage in der Zukunft abgelehnt'
);
select throws_ok(
  $$insert into public.daily_activity (user_id, activity_date, competition_steps)
    values ('11111111-1111-4111-8111-111111111111', (now() at time zone 'utc')::date - 1, 250000)$$,
  '23514', null, 'unplausible Schrittzahl abgelehnt'
);
select throws_ok(
  $$insert into public.daily_activity (user_id, activity_date, competition_steps, synced_at)
    values ('11111111-1111-4111-8111-111111111111', (now() at time zone 'utc')::date - 2, 100, '2000-01-01')$$,
  '42501', null, 'synced_at kann der Client nicht setzen'
);

-- Nutzer und Tag sind unveränderlich: alte Tage lassen sich nicht ins Fenster verschieben.
select throws_ok(
  $$update public.daily_activity set activity_date = (now() at time zone 'utc')::date - 1
     where user_id = '11111111-1111-4111-8111-111111111111'$$,
  '42501', 'immutable_key', 'Tag einer Zeile nicht änderbar'
);
reset role;
insert into public.daily_activity (user_id, activity_date, competition_steps)
values ('11111111-1111-4111-8111-111111111111', (now() at time zone 'utc')::date - 30, 4000);
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":true}';
select is_empty(
  $$update public.daily_activity set competition_steps = 1
     where activity_date = (now() at time zone 'utc')::date - 30 returning user_id$$,
  'Tage außerhalb des Fensters nicht mehr änderbar'
);

-- Zeitstempel kommen vom Server: synced_at bei jedem Schreiben, steps_changed_at (Tiebreaker im Ranking) nur bei
-- einem neuen Wert. Dafür zuerst alte Zeitstempel setzen.
reset role;
alter table public.daily_activity disable trigger daily_activity_maintain_timestamps;
update public.daily_activity set synced_at = '2000-01-01 00:00+00', steps_changed_at = '2000-01-01 00:00+00'
 where user_id = '11111111-1111-4111-8111-111111111111' and activity_date = (now() at time zone 'utc')::date;
alter table public.daily_activity enable trigger daily_activity_maintain_timestamps;

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":true}';
insert into public.daily_activity (user_id, activity_date, competition_steps)
values ('11111111-1111-4111-8111-111111111111', (now() at time zone 'utc')::date, 7500)
on conflict (user_id, activity_date) do update
  set user_id = excluded.user_id, activity_date = excluded.activity_date, competition_steps = excluded.competition_steps;
reset role;
select is(
  (select steps_changed_at from public.daily_activity
    where user_id = '11111111-1111-4111-8111-111111111111' and activity_date = (now() at time zone 'utc')::date),
  '2000-01-01 00:00+00'::timestamptz, 'gleicher Wert: steps_changed_at bleibt'
);
select is(
  (select synced_at from public.daily_activity
    where user_id = '11111111-1111-4111-8111-111111111111' and activity_date = (now() at time zone 'utc')::date),
  now(), 'synced_at bei jedem Sync vom Server gesetzt'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":true}';
insert into public.daily_activity (user_id, activity_date, competition_steps)
values ('11111111-1111-4111-8111-111111111111', (now() at time zone 'utc')::date, 8000)
on conflict (user_id, activity_date) do update
  set user_id = excluded.user_id, activity_date = excluded.activity_date, competition_steps = excluded.competition_steps;
reset role;
select is(
  (select steps_changed_at from public.daily_activity
    where user_id = '11111111-1111-4111-8111-111111111111' and activity_date = (now() at time zone 'utc')::date),
  now(), 'neuer Wert: steps_changed_at vom Server gesetzt'
);

-- Nutzer 2 sieht und ändert keine fremden Werte.
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated","is_anonymous":true}';
select is((select count(*)::int from public.daily_activity), 0, 'fremde Tageswerte nicht lesbar');
select is_empty(
  $$update public.daily_activity set competition_steps = 1 where user_id = '11111111-1111-4111-8111-111111111111' returning user_id$$,
  'fremde Tageswerte nicht änderbar'
);

reset role;
select * from finish();
rollback;
