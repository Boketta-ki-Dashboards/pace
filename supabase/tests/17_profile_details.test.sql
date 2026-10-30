-- Pace: Social-Profil 2.0 – Bio, Interessen, Banner, freiwillige Auszeichnungen (Migration 20261030100000).
begin;
select plan(32);

-- =============================================================================================================
-- Struktur
-- =============================================================================================================

select is(
  (select array_agg(c.column_name || ':' || c.data_type order by c.column_name)
     from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'profiles'
      and c.column_name in ('bio', 'interests', 'banner_path', 'shows_achievements', 'achievements')),
  array['achievements:ARRAY', 'banner_path:text', 'bio:text', 'interests:ARRAY', 'shows_achievements:boolean'],
  'profiles: neue optionale Spalten'
);
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'bio', 'update')
  and has_column_privilege('authenticated', 'public.profiles', 'interests', 'update')
  and has_column_privilege('authenticated', 'public.profiles', 'banner_path', 'update')
  and has_column_privilege('authenticated', 'public.profiles', 'shows_achievements', 'update')
  and has_column_privilege('authenticated', 'public.profiles', 'achievements', 'update')
  and not has_column_privilege('authenticated', 'public.profiles', 'bio', 'insert')
  and not has_column_privilege('authenticated', 'public.profiles', 'banner_path', 'insert'),
  'authenticated darf die neuen Felder ändern (nicht beim Anlegen setzen)'
);
select ok(
  not has_function_privilege('anon', 'public.social_profile_details(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.social_profile_details(uuid)', 'execute'),
  'social_profile_details: nur für Angemeldete'
);

-- =============================================================================================================
-- Testdaten: 1 lena, 2 marco, 3 nora (nicht auffindbar), 4 otto (hat lena blockiert)
-- =============================================================================================================

insert into auth.users (id, aud, role, is_anonymous)
select ('a1700000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 4) as n;

insert into public.profiles (id, public_id, username, display_name)
select ('a1700000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('b1700000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'lena', 'Lena'), (2, 'marco', 'Marco'), (3, 'nora', 'Nora'), (4, 'otto', 'Otto')) as v(n, username, display_name);

update public.profiles set is_discoverable = false where username = 'nora';
insert into public.user_blocks (blocker_id, blocked_id)
values ('a1700000-0000-4000-8000-000000000004', 'a1700000-0000-4000-8000-000000000001');

-- Hochgeladenes Banner von lena und eine Datei von marco (wie nach einem Upload über die Storage-API).
insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('avatars', 'b1700000-0000-4000-8000-000000000001/banner.jpg', 'a1700000-0000-4000-8000-000000000001', '{"mimetype":"image/jpeg"}'),
       ('avatars', 'b1700000-0000-4000-8000-000000000002/fremd.jpg', 'a1700000-0000-4000-8000-000000000002', '{"mimetype":"image/jpeg"}');

create function pg_temp.pid(n int) returns uuid language sql immutable as $$
  select ('b1700000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;

select is(
  (select array[cardinality(p.interests)::text, p.shows_achievements::text, cardinality(p.achievements)::text, coalesce(p.bio, '-')]
     from public.profiles p where p.username = 'marco'),
  array['0', 'false', '0', '-'],
  'bestehende Profile: leere Standardwerte, Auszeichnungen nicht sichtbar'
);

-- =============================================================================================================
-- Eigene Angaben ändern (als lena)
-- =============================================================================================================

set local role authenticated;
set local request.jwt.claims = '{"sub":"a1700000-0000-4000-8000-000000000001","role":"authenticated"}';

select lives_ok(
  $$update public.profiles set bio = 'Jeden Tag ein bisschen aktiver. 🚶‍♀️' where id = auth.uid()$$,
  'Bio mit Emoji'
);
select lives_ok(
  $$update public.profiles set bio = E'Fitness\nFußball\nlange Spaziergänge\nund mehr' where id = auth.uid()$$,
  'Bio mit vier Zeilen'
);
select throws_ok(
  $$update public.profiles set bio = E'1\n2\n3\n4\n5' where id = auth.uid()$$, '23514', null, 'Bio: höchstens vier Zeilen'
);
select throws_ok(
  $$update public.profiles set bio = repeat('a', 161) where id = auth.uid()$$, '23514', null, 'Bio: höchstens 160 Zeichen'
);
select throws_ok(
  $$update public.profiles set bio = E'Hallo\u200B' where id = auth.uid()$$, '23514', null, 'Bio: kein unsichtbares Formatzeichen'
);
select throws_ok(
  $$update public.profiles set bio = E'Hallo\tWelt' where id = auth.uid()$$, '23514', null, 'Bio: keine Steuerzeichen'
);
select throws_ok(
  $$update public.profiles set bio = ' Hallo' where id = auth.uid()$$, '23514', null, 'Bio: ohne Leerzeichen am Rand'
);
select lives_ok($$update public.profiles set bio = null where id = auth.uid()$$, 'Bio entfernen');
select lives_ok($$update public.profiles set bio = 'Auf dem Weg zu 100 Tagen.' where id = auth.uid()$$, 'Bio erneut setzen');

select lives_ok(
  $$update public.profiles set interests = array['walking', 'running', 'hiking', 'fitness', 'cycling'] where id = auth.uid()$$,
  'fünf Interessen'
);
select throws_ok(
  $$update public.profiles set interests = array['walking', 'running', 'hiking', 'fitness', 'cycling', 'football'] where id = auth.uid()$$,
  '23514', null, 'höchstens fünf Interessen'
);
select throws_ok(
  $$update public.profiles set interests = array['basejumping'] where id = auth.uid()$$, '23514', null, 'nur Interessen aus dem Katalog'
);
select throws_ok(
  $$update public.profiles set interests = array['walking', 'walking'] where id = auth.uid()$$,
  '23514', 'invalid_interests', 'keine doppelten Interessen'
);

select throws_ok(
  $$update public.profiles set banner_path = 'b1700000-0000-4000-8000-000000000001/fehlt.jpg' where id = auth.uid()$$,
  '23514', 'invalid_banner_path', 'Banner: Datei muss hochgeladen sein'
);
select throws_ok(
  $$update public.profiles set banner_path = 'b1700000-0000-4000-8000-000000000002/fremd.jpg' where id = auth.uid()$$,
  '23514', 'invalid_banner_path', 'Banner: nur im eigenen Ordner'
);
select lives_ok(
  $$update public.profiles set banner_path = 'b1700000-0000-4000-8000-000000000001/banner.jpg' where id = auth.uid()$$,
  'Banner: eigene hochgeladene Datei'
);

select throws_ok(
  $$update public.profiles set achievements = array['marathon_king'] where id = auth.uid()$$, '23514', null,
  'nur Auszeichnungen aus dem Katalog'
);
select lives_ok(
  $$update public.profiles set achievements = array['streak_7', 'streak_30', 'best_day_10k'] where id = auth.uid()$$,
  'Auszeichnungen speichern (noch nicht sichtbar)'
);

select is(
  public.social_profile_details(pg_temp.pid(1)),
  jsonb_build_object(
    'bio', 'Auf dem Weg zu 100 Tagen.',
    'interests', jsonb_build_array('walking', 'running', 'hiking', 'fitness', 'cycling'),
    'banner_path', 'b1700000-0000-4000-8000-000000000001/banner.jpg',
    'shows_achievements', false,
    'achievements', jsonb_build_array('streak_7', 'streak_30', 'best_day_10k')
  ),
  'eigenes Profil: alle Angaben samt Einstellung'
);

-- =============================================================================================================
-- Fremde Profile
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a1700000-0000-4000-8000-000000000002","role":"authenticated"}';

select is(
  public.social_profile_details(pg_temp.pid(1))->'achievements', '[]'::jsonb,
  'Auszeichnungen ohne Freigabe nicht sichtbar'
);
select is(
  public.social_profile_details(pg_temp.pid(1))->>'bio', 'Auf dem Weg zu 100 Tagen.', 'Bio für andere sichtbar'
);
select ok(
  not (public.social_profile_details(pg_temp.pid(1)) ? 'shows_achievements'),
  'andere sehen die Einstellung selbst nicht'
);
select ok(
  pace_access.can_read_avatar('b1700000-0000-4000-8000-000000000001/banner.jpg'),
  'aktuelles Banner ist für Angemeldete lesbar'
);
select throws_ok(
  format('select public.social_profile_details(%L)', pg_temp.pid(3)),
  'P0001', 'not_found', 'nicht auffindbares Profil ohne Kontext: not_found'
);

set local request.jwt.claims = '{"sub":"a1700000-0000-4000-8000-000000000001","role":"authenticated"}';
select lives_ok($$update public.profiles set shows_achievements = true where id = auth.uid()$$, 'Auszeichnungen freigeben');

set local request.jwt.claims = '{"sub":"a1700000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  public.social_profile_details(pg_temp.pid(1))->'achievements', jsonb_build_array('streak_7', 'streak_30', 'best_day_10k'),
  'freigegebene Auszeichnungen sichtbar'
);

-- otto hat lena blockiert: lena sieht otto nicht, otto sieht von lena keine persönlichen Angaben und kein Banner.
set local request.jwt.claims = '{"sub":"a1700000-0000-4000-8000-000000000001","role":"authenticated"}';
select throws_ok(
  format('select public.social_profile_details(%L)', pg_temp.pid(4)),
  'P0001', 'not_found', 'wer mich blockiert hat: not_found'
);
set local request.jwt.claims = '{"sub":"a1700000-0000-4000-8000-000000000004","role":"authenticated"}';
select is(
  public.social_profile_details(pg_temp.pid(1)),
  jsonb_build_object('bio', null, 'interests', '[]'::jsonb, 'banner_path', null, 'achievements', '[]'::jsonb),
  'von mir blockierte Person: keine persönlichen Angaben'
);

select * from finish();
rollback;
