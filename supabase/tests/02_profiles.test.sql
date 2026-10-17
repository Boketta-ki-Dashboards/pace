-- Pace: Profile – eigene Zeile, Benutzernamen, Anzeigenamen, Gemeinde.
begin;
select plan(21);

insert into auth.users (id, aud, role, is_anonymous) values
  ('11111111-1111-4111-8111-111111111111', 'authenticated', 'authenticated', true),
  ('22222222-2222-4222-8222-222222222222', 'authenticated', 'authenticated', true);

-- Nutzer 1
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":true}';

select lives_ok(
  $$insert into public.profiles (id, username, display_name) values ('11111111-1111-4111-8111-111111111111', 'Niklas_76', 'Niklas')$$,
  'eigenes Profil anlegen'
);
select throws_ok(
  $$insert into public.profiles (id, username, display_name) values ('22222222-2222-4222-8222-222222222222', 'fremd', 'Fremd')$$,
  '42501', null, 'kein Profil für fremde ID'
);
select is((select count(*)::int from public.profiles), 1, 'nur das eigene Profil sichtbar');
select is((select username from public.profiles), 'Niklas_76', 'Groß-/Kleinschreibung bleibt erhalten');
select ok(not public.is_username_available('niklas_76'), 'Name belegt (ohne Groß-/Kleinschreibung)');
select ok(public.is_username_available('noch_frei'), 'freier Name');

select throws_ok(
  $$update public.profiles set public_id = gen_random_uuid() where id = '11111111-1111-4111-8111-111111111111'$$,
  '42501', null, 'public_id nicht änderbar'
);
select throws_ok(
  $$update public.profiles set municipality_id = 'DE:06432' where id = '11111111-1111-4111-8111-111111111111'$$,
  '23514', null, 'Kreis statt Gemeinde abgelehnt'
);
select throws_ok(
  $$update public.profiles set municipality_id = 'DE:99999999' where id = '11111111-1111-4111-8111-111111111111'$$,
  '23514', null, 'unbekannte Gemeinde abgelehnt'
);
select lives_ok(
  $$update public.profiles set municipality_id = 'DE:06432018', regional_leaderboard_enabled = true where id = '11111111-1111-4111-8111-111111111111'$$,
  'Gemeinde setzen'
);
select is((select municipality_id from public.profiles), 'DE:06432018', 'Gemeinde gespeichert');

-- Nutzer 2
set local request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated","is_anonymous":true}';

select throws_ok(
  $$insert into public.profiles (id, username, display_name) values ('22222222-2222-4222-8222-222222222222', 'NIKLAS_76', 'Kopie')$$,
  '23505', null, 'Benutzername ohne Groß-/Kleinschreibung eindeutig'
);
select throws_ok(
  $$insert into public.profiles (id, username, display_name) values ('22222222-2222-4222-8222-222222222222', 'ab', 'Kurz')$$,
  '23514', null, 'zu kurzer Benutzername'
);
select throws_ok(
  $$insert into public.profiles (id, username, display_name) values ('22222222-2222-4222-8222-222222222222', 'mit leer', 'Leer')$$,
  '23514', null, 'Leerzeichen im Benutzernamen'
);
select throws_ok(
  $$insert into public.profiles (id, username, display_name) values ('22222222-2222-4222-8222-222222222222', 'ADMIN', 'Admin')$$,
  '23514', null, 'reservierter Benutzername'
);
select throws_ok(
  $$insert into public.profiles (id, username, display_name) values ('22222222-2222-4222-8222-222222222222', 'jürgen', 'Jürgen')$$,
  '23514', null, 'Umlaut im Benutzernamen'
);
select throws_ok(
  $$insert into public.profiles (id, username, display_name) values ('22222222-2222-4222-8222-222222222222', 'zweiter', ' Leerzeichen ')$$,
  '23514', null, 'Anzeigename mit Leerzeichen am Rand'
);
select throws_ok(
  $$insert into public.profiles (id, username, display_name) values ('22222222-2222-4222-8222-222222222222', 'zweiter', E'Nik\u200Blas')$$,
  '23514', null, 'Anzeigename mit unsichtbarem Formatzeichen'
);
select lives_ok(
  $$insert into public.profiles (id, username, display_name) values ('22222222-2222-4222-8222-222222222222', 'zweiter', 'Jürgen 🏃')$$,
  'Anzeigename mit Umlaut und Emoji'
);
select is((select count(*)::int from public.profiles), 1, 'Nutzer 2 sieht nur sein Profil');
select is_empty(
  $$update public.profiles set display_name = 'Gekapert' where id = '11111111-1111-4111-8111-111111111111' returning id$$,
  'fremdes Profil nicht änderbar'
);

reset role;
select * from finish();
rollback;
