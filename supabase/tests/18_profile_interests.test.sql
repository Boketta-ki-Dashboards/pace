-- Pace: Interessen 2.0 – Katalog in Kategorien, eigene Interessen, gesprochene Sprachen, Land (Migration 20261102100000).
begin;
select plan(41);

-- =============================================================================================================
-- Struktur
-- =============================================================================================================

select is(
  (select array_agg(c.column_name || ':' || c.data_type || ':' || c.is_nullable order by c.column_name)
     from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'profiles'
      and c.column_name in ('custom_interests', 'spoken_languages', 'country_code')),
  array['country_code:text:YES', 'custom_interests:ARRAY:NO', 'spoken_languages:ARRAY:NO'],
  'profiles: neue optionale Spalten'
);
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'custom_interests', 'update')
  and has_column_privilege('authenticated', 'public.profiles', 'spoken_languages', 'update')
  and has_column_privilege('authenticated', 'public.profiles', 'country_code', 'update')
  and not has_column_privilege('authenticated', 'public.profiles', 'custom_interests', 'insert')
  and not has_column_privilege('authenticated', 'public.profiles', 'country_code', 'insert'),
  'authenticated darf die neuen Felder ändern (nicht beim Anlegen setzen)'
);
select ok(
  not has_table_privilege('authenticated', 'private.profile_interest_catalog', 'select')
  and not has_table_privilege('anon', 'private.profile_interest_catalog', 'select')
  and not has_table_privilege('authenticated', 'private.profile_interest_catalog', 'insert'),
  'Katalog: nicht über die API les- oder änderbar'
);
select is(
  (select count(*)::int from private.profile_interest_catalog
    where id in ('walking', 'running', 'hiking', 'fitness', 'cycling', 'football', 'outdoor', 'everyday_movement',
                 'challenges', 'wellbeing')),
  10,
  'Katalog: alle zehn bisherigen IDs bleiben gültig'
);
select is(
  (select array_agg(c.category || ':' || c.n order by c.category)
     from (select category, count(*) as n from private.profile_interest_catalog group by category) c),
  array['creative:10', 'culture:5', 'leisure:9', 'sport:18', 'tech:8'],
  'Katalog: 50 Interessen in fünf Kategorien'
);
select ok(
  not exists (select 1 from pg_constraint where conname = 'profiles_interests_valid')
  and exists (select 1 from pg_constraint where conname = 'profiles_interests_total')
  and exists (select 1 from pg_constraint where conname = 'profiles_spoken_languages_valid')
  and exists (select 1 from pg_constraint where conname = 'profiles_country_code_valid'),
  'Constraints: feste Fünferliste ersetzt durch Gesamtgrenze, Sprachen und Land geprüft'
);

-- =============================================================================================================
-- Testdaten: 1 lena, 2 marco, 3 otto (hat lena blockiert), 4 ida (altes Profil mit drei Interessen),
-- 5 paul (altes Profil mit fünf Interessen)
-- =============================================================================================================

insert into auth.users (id, aud, role, is_anonymous)
select ('a1800000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 5) as n;

insert into public.profiles (id, public_id, username, display_name)
select ('a1800000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('b1800000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'lena18', 'Lena'), (2, 'marco18', 'Marco'), (3, 'otto18', 'Otto'), (4, 'ida18', 'Ida'),
               (5, 'paul18', 'Paul')) as v(n, username, display_name);

-- Bestandsdaten wie vor der Migration (nur Katalog-IDs aus 20261030100000).
update public.profiles set interests = array['walking', 'hiking', 'fitness'] where username = 'ida18';
update public.profiles set interests = array['walking', 'running', 'hiking', 'fitness', 'cycling'] where username = 'paul18';
insert into public.user_blocks (blocker_id, blocked_id)
values ('a1800000-0000-4000-8000-000000000003', 'a1800000-0000-4000-8000-000000000001');

create function pg_temp.pid(n int) returns uuid language sql immutable as $$
  select ('b1800000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;

select is(
  (select array[array_to_string(p.interests, ','), cardinality(p.custom_interests)::text,
                cardinality(p.spoken_languages)::text, coalesce(p.country_code, '-')]
     from public.profiles p where p.username = 'ida18'),
  array['walking,hiking,fitness', '0', '0', '-'],
  'altes Profil mit drei Interessen: unverändert, neue Felder leer'
);

-- =============================================================================================================
-- Eigenes Profil ändern (lena)
-- =============================================================================================================

set local role authenticated;
set local request.jwt.claims = '{"sub":"a1800000-0000-4000-8000-000000000004","role":"authenticated"}';
select is(
  public.social_profile_details(pg_temp.pid(4)) - array['bio', 'banner_path', 'shows_achievements', 'achievements'],
  jsonb_build_object('interests', jsonb_build_array('walking', 'hiking', 'fitness'), 'custom_interests', '[]'::jsonb,
                     'spoken_languages', '[]'::jsonb, 'country_code', null),
  'altes Profil (drei Interessen) liest sich unverändert'
);
set local request.jwt.claims = '{"sub":"a1800000-0000-4000-8000-000000000005","role":"authenticated"}';
select lives_ok(
  $$update public.profiles set bio = 'Neu', interests = interests || array['rap'] where id = auth.uid()$$,
  'altes Profil mit fünf Interessen: Bio ändern und ein neues Katalog-Interesse ergänzen'
);

set local request.jwt.claims = '{"sub":"a1800000-0000-4000-8000-000000000001","role":"authenticated"}';

select lives_ok(
  $$update public.profiles set interests = array['rap', 'basketball', 'programming', 'travel', 'international_friendships'] where id = auth.uid()$$,
  'neue Katalog-Interessen'
);
select throws_ok(
  $$update public.profiles set interests = array['basejumping'] where id = auth.uid()$$,
  '23514', 'invalid_interests', 'nur Interessen aus dem Katalog'
);
select throws_ok(
  $$update public.profiles set interests = array['rap', 'rap'] where id = auth.uid()$$,
  '23514', 'invalid_interests', 'keine doppelten Katalog-Interessen'
);
select throws_ok(
  $$update public.profiles set interests = array['rap', null] where id = auth.uid()$$,
  '23514', null, 'keine leeren Einträge'
);

-- Eigene Interessen
select lives_ok(
  $$update public.profiles set custom_interests = array['Musik produzieren', 'Рэп-баттлы', 'Kaffee ☕', 'Webcoding mit Swift'] where id = auth.uid()$$,
  'eigene Interessen: Deutsch, Russisch, Emoji'
);
select throws_ok(
  $$update public.profiles set custom_interests = array['Rap battles', 'RAP BATTLES'] where id = auth.uid()$$,
  '23514', 'invalid_custom_interests', 'keine Doppelten ohne Rücksicht auf Groß-/Kleinschreibung'
);
select throws_ok(
  $$update public.profiles set custom_interests = array['Музыка', 'МУЗЫКА'] where id = auth.uid()$$,
  '23514', 'invalid_custom_interests', 'auch kyrillisch keine Doppelten in anderer Schreibweise'
);
select throws_ok(
  $$update public.profiles set custom_interests = array['x'] where id = auth.uid()$$,
  '23514', 'invalid_custom_interests', 'mindestens zwei Zeichen'
);
select throws_ok(
  $$update public.profiles set custom_interests = array[repeat('a', 31)] where id = auth.uid()$$,
  '23514', 'invalid_custom_interests', 'höchstens 30 Zeichen'
);
select lives_ok(
  $$update public.profiles set custom_interests = array[repeat('я', 30)] where id = auth.uid()$$,
  '30 kyrillische Zeichen sind erlaubt (Zeichen, nicht Bytes)'
);
select throws_ok(
  $$update public.profiles set custom_interests = array[' Rap'] where id = auth.uid()$$,
  '23514', 'invalid_custom_interests', 'ohne Leerzeichen am Rand'
);
select throws_ok(
  $$update public.profiles set custom_interests = array['Rap  Battles'] where id = auth.uid()$$,
  '23514', 'invalid_custom_interests', 'ohne doppelte Leerzeichen'
);
select throws_ok(
  format('update public.profiles set custom_interests = array[%L] where id = auth.uid()', 'Zeile' || chr(10) || 'Zwei'),
  '23514', 'invalid_custom_interests', 'ohne Zeilenumbruch'
);
select throws_ok(
  format('update public.profiles set custom_interests = array[%L] where id = auth.uid()', 'Rap' || chr(8203) || 'Battle'),
  '23514', 'invalid_custom_interests', 'ohne unsichtbare Zeichen'
);
select throws_ok(
  $$update public.profiles set custom_interests = array['www.spam.example'] where id = auth.uid()$$,
  '23514', 'invalid_custom_interests', 'ohne Links'
);
select throws_ok(
  $$update public.profiles set custom_interests = array['@lena18'] where id = auth.uid()$$,
  '23514', 'invalid_custom_interests', 'ohne @-Erwähnungen'
);
select throws_ok(
  format('update public.profiles set custom_interests = array[%L] where id = auth.uid()', 'Cafe' || chr(769)),
  '23514', 'invalid_custom_interests', 'nur Unicode-NFC (sonst Doppelte in anderer Schreibweise möglich)'
);

-- Gesamtgrenze: Katalog und eigene zusammen höchstens 20.
select lives_ok(
  $$update public.profiles
       set interests = array['rap', 'basketball', 'programming', 'travel', 'international_friendships', 'football',
                             'volleyball', 'fitness', 'running', 'hiking', 'cycling', 'swimming', 'dancing', 'gaming', 'books'],
           custom_interests = array['Musik produzieren', 'Рэп-баттлы', 'Kaffee ☕', 'Webcoding mit Swift', 'Freestyle Rap']
     where id = auth.uid()$$,
  'zwanzig Interessen (15 aus dem Katalog, 5 eigene)'
);
select throws_ok(
  $$update public.profiles set custom_interests = custom_interests || array['Breakdance'] where id = auth.uid()$$,
  '23514', null, 'einundzwanzig Interessen: abgelehnt'
);

-- Sprachen und Land
select lives_ok(
  $$update public.profiles set spoken_languages = array['de', 'ru', 'sr', 'sq', 'ka', 'gsw'], country_code = 'IT' where id = auth.uid()$$,
  'gesprochene Sprachen und Land'
);
select throws_ok(
  $$update public.profiles set spoken_languages = array['de', 'de'] where id = auth.uid()$$,
  '23514', 'invalid_spoken_languages', 'keine doppelten Sprachen'
);
select throws_ok(
  $$update public.profiles set spoken_languages = array['Deutsch'] where id = auth.uid()$$,
  '23514', null, 'Sprachen nur als ISO-Code'
);
select throws_ok(
  $$update public.profiles set spoken_languages = array['de','en','ru','it','sr','sq','ka','fr','es','pt','nl'] where id = auth.uid()$$,
  '23514', null, 'höchstens zehn Sprachen'
);
select throws_ok(
  $$update public.profiles set country_code = 'Italien' where id = auth.uid()$$,
  '23514', null, 'Land nur als ISO-Code'
);

select is(
  public.social_profile_details(pg_temp.pid(1)) - array['bio', 'banner_path', 'shows_achievements', 'achievements', 'interests'],
  jsonb_build_object(
    'custom_interests', jsonb_build_array('Musik produzieren', 'Рэп-баттлы', 'Kaffee ☕', 'Webcoding mit Swift', 'Freestyle Rap'),
    'spoken_languages', jsonb_build_array('de', 'ru', 'sr', 'sq', 'ka', 'gsw'),
    'country_code', 'IT'
  ),
  'eigenes Profil: eigene Interessen wie eingegeben, Sprachen, Land'
);

-- =============================================================================================================
-- Fremde Profile, Blockierung
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a1800000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  public.social_profile_details(pg_temp.pid(1))->'custom_interests',
  jsonb_build_array('Musik produzieren', 'Рэп-баттлы', 'Kaffee ☕', 'Webcoding mit Swift', 'Freestyle Rap'),
  'andere sehen eigene Interessen'
);
select is(
  (select array[public.social_profile_details(pg_temp.pid(1))->>'country_code',
                jsonb_array_length(public.social_profile_details(pg_temp.pid(1))->'spoken_languages')::text]),
  array['IT', '6'],
  'andere sehen Sprachen und Land'
);
-- RLS: Die Änderung trifft keine fremde Zeile (der Datenexport unten zeigt lenas Angaben unverändert).
select lives_ok(
  $$update public.profiles set custom_interests = array['Fremd'] where username = 'lena18'$$,
  'fremde Profile: Änderung trifft keine Zeile (RLS)'
);

-- otto hat lena blockiert: otto sieht von lena nichts davon.
set local request.jwt.claims = '{"sub":"a1800000-0000-4000-8000-000000000003","role":"authenticated"}';
select is(
  public.social_profile_details(pg_temp.pid(1)) - array['bio', 'interests', 'banner_path', 'achievements'],
  jsonb_build_object('custom_interests', '[]'::jsonb, 'spoken_languages', '[]'::jsonb, 'country_code', null),
  'blockierte Person: keine eigenen Interessen, Sprachen oder Länder'
);

-- =============================================================================================================
-- Meldungen und Datenexport
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a1800000-0000-4000-8000-000000000002","role":"authenticated"}';
select lives_ok(
  format('select public.social_report(%L, %L, %L)', 'user', pg_temp.pid(1), 'inappropriate'), 'marco meldet lena'
);

set local request.jwt.claims = '{"sub":"a1800000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(
  (select array[jsonb_array_length(e->'profile'->'custom_interests')::text, e->'profile'->>'country_code']
     from (select public.account_export() as e) x),
  array['5', 'IT'],
  'Datenexport enthält die neuen Angaben'
);

reset role;
select is(
  (select jsonb_build_object('custom_interests', r.target_snapshot -> 'custom_interests',
                             'spoken_languages', r.target_snapshot -> 'spoken_languages',
                             'country_code', r.target_snapshot -> 'country_code')
     from public.reports r where r.target_type = 'user' and r.target_id = pg_temp.pid(1)),
  jsonb_build_object(
    'custom_interests', jsonb_build_array('Musik produzieren', 'Рэп-баттлы', 'Kaffee ☕', 'Webcoding mit Swift', 'Freestyle Rap'),
    'spoken_languages', jsonb_build_array('de', 'ru', 'sr', 'sq', 'ka', 'gsw'),
    'country_code', 'IT'
  ),
  'Meldung: Schnappschuss mit eigenen Interessen, Sprachen und Land'
);

select * from finish();
rollback;
