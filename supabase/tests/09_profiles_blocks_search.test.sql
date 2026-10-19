-- Pace: Profilbild, Auffindbarkeit, Rate Limits für Benutzernamen, Präfixsuche, öffentliches Profil, Blockieren.
begin;
select plan(69);

-- =============================================================================================================
-- Struktur
-- =============================================================================================================

select is(
  (select array_agg(c.column_name || ':' || c.data_type || ':' || coalesce(c.column_default, '-') order by c.column_name)
     from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'profiles' and c.column_name in ('avatar_path', 'is_discoverable')),
  array['avatar_path:text:-', 'is_discoverable:boolean:true'],
  'profiles: avatar_path (optional) und is_discoverable (Standard an)'
);
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'avatar_path', 'update')
  and has_column_privilege('authenticated', 'public.profiles', 'is_discoverable', 'update')
  and not has_column_privilege('authenticated', 'public.profiles', 'avatar_path', 'insert'),
  'authenticated darf avatar_path und is_discoverable ändern (nicht beim Anlegen setzen)'
);
select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'profiles_username_prefix_idx'
            and indexdef like '%text_pattern_ops%'),
  'Index für die Präfixsuche (text_pattern_ops)'
);
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.user_blocks'::regclass), 'user_blocks: RLS aktiv');
select is((select count(*)::int from pg_policy p where p.polrelid = 'public.user_blocks'::regclass), 0, 'user_blocks: keine Policies');
select is(
  (select array_agg(pr.privilege order by 1) from unnest(array['anon', 'authenticated']) as r(role_name)
    cross join unnest(array['select', 'insert', 'update', 'delete']) as pr(privilege)
    where has_table_privilege(r.role_name, 'public.user_blocks', pr.privilege)
       or has_table_privilege(r.role_name, 'private.auth_rate_limit_events', pr.privilege)),
  null, 'keine Clientrechte auf user_blocks und auth_rate_limit_events'
);

-- =============================================================================================================
-- Testdaten
-- =============================================================================================================

-- 1 alex, 2 alexa, 3 alexander, 4 dana (nicht auffindbar), 5 emil, 6 ohne Profil, 7 finn, 8 gina, 9 hanna,
-- 101–125 Statisten mit gleichem Präfix „statist_“.
insert into auth.users (id, aud, role, is_anonymous)
select ('a9000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from (select generate_series(1, 9) union all select generate_series(101, 125)) as s(n);

insert into public.profiles (id, public_id, username, display_name)
select ('a9000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('b9000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'alex', 'Alex'), (2, 'alexa', 'Alexa'), (3, 'alexander', 'Alexander'), (4, 'dana', 'Dana'),
               (5, 'emil', 'Emil'), (7, 'finn', 'Finn'), (8, 'gina', 'Gina'), (9, 'hanna', 'Hanna')) as v(n, username, display_name)
union all
select ('a9000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       ('b9000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'statist_' || n, 'Statist ' || n
  from generate_series(101, 125) n;

update public.profiles set is_discoverable = false where username = 'dana';

-- Freundschaften: alex–emil, alex–finn, alex–gina. Offene Anfrage hanna → alex.
insert into public.friendships (user_a, user_b)
select least(a, b), greatest(a, b)
  from (values (1, 5), (1, 7), (1, 8)) as v(x, y),
       lateral (select ('a9000000-0000-4000-8000-' || lpad(v.x::text, 12, '0'))::uuid as a,
                       ('a9000000-0000-4000-8000-' || lpad(v.y::text, 12, '0'))::uuid as b) ids;
insert into public.friend_requests (requester_id, addressee_id)
values ('a9000000-0000-4000-8000-000000000009', 'a9000000-0000-4000-8000-000000000001');

-- Gruppe von alex mit offener Einladung an finn (für die Wirkung einer Blockierung).
insert into public.groups (id, name, kind, invite_code, created_by)
values ('c9000000-0000-4000-8000-000000000001', 'Lauftreff', 'friends', 'ABCDEFGH', 'a9000000-0000-4000-8000-000000000001');
insert into public.group_goal_history (group_id, effective_from, daily_goal)
values ('c9000000-0000-4000-8000-000000000001', current_date - 30, 8000);
insert into public.group_members (group_id, user_id, role)
values ('c9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001', 'owner');
insert into public.group_invitations (group_id, inviter_id, invitee_id)
values ('c9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000007');

-- Schritte von emil für das öffentliche Profil.
insert into public.daily_activity (user_id, activity_date, competition_steps)
values ('a9000000-0000-4000-8000-000000000005', (now() at time zone 'utc')::date, 7000);

-- Hochgeladenes Profilbild von alex (wie nach einem Upload über die Storage-API).
insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('avatars', 'b9000000-0000-4000-8000-000000000001/neu.jpg', 'a9000000-0000-4000-8000-000000000001', '{"mimetype":"image/jpeg"}'),
       ('avatars', 'b9000000-0000-4000-8000-000000000002/fremd.jpg', 'a9000000-0000-4000-8000-000000000002', '{"mimetype":"image/jpeg"}');

create function pg_temp.pid(n int) returns uuid language sql immutable as $$
  select ('b9000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;
create function pg_temp.uid(n int) returns uuid language sql immutable as $$
  select ('a9000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;
create function pg_temp.names(p_result jsonb) returns text[] language sql immutable as $$
  select array_agg(e->>'username' order by ord) from jsonb_array_elements(p_result) with ordinality as x(e, ord);
$$;

-- =============================================================================================================
-- Profilbild und Auffindbarkeit (als alex über die eigene Zeile)
-- =============================================================================================================

set local role authenticated;
set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-000000000001","role":"authenticated"}';

select throws_ok(
  $$update public.profiles set avatar_path = 'b9000000-0000-4000-8000-000000000001/fehlt.jpg' where id = auth.uid()$$,
  '23514', 'invalid_avatar_path', 'Profilbild: Datei muss hochgeladen sein'
);
select throws_ok(
  $$update public.profiles set avatar_path = 'b9000000-0000-4000-8000-000000000002/fremd.jpg' where id = auth.uid()$$,
  '23514', 'invalid_avatar_path', 'Profilbild: nur im eigenen Ordner'
);
select throws_ok(
  $$update public.profiles set avatar_path = '../b9000000-0000-4000-8000-000000000001/neu.jpg' where id = auth.uid()$$,
  '23514', null, 'Profilbild: Pfadformat wird geprüft'
);
select lives_ok(
  $$update public.profiles set avatar_path = 'b9000000-0000-4000-8000-000000000001/neu.jpg' where id = auth.uid()$$,
  'Profilbild: eigene hochgeladene Datei'
);
select is(
  (select avatar_path from public.profiles where id = auth.uid()), 'b9000000-0000-4000-8000-000000000001/neu.jpg',
  'Profilbild gespeichert'
);
select lives_ok($$update public.profiles set avatar_path = null where id = auth.uid()$$, 'Profilbild entfernen');
select lives_ok(
  $$update public.profiles set avatar_path = 'b9000000-0000-4000-8000-000000000001/neu.jpg' where id = auth.uid()$$,
  'Profilbild erneut setzen'
);
select lives_ok($$update public.profiles set is_discoverable = false where id = auth.uid()$$, 'Auffindbarkeit ändern');
select lives_ok($$update public.profiles set is_discoverable = true where id = auth.uid()$$, 'Auffindbarkeit zurück');

-- Namen ändern: Constraints greifen, höchstens 5 Benutzernamen-Änderungen je 24 Stunden.
select throws_ok(
  $$update public.profiles set username = 'a b' where id = auth.uid()$$, '23514', null, 'Benutzername: Format geprüft'
);
select lives_ok(
  $$update public.profiles set display_name = 'Alex B.' where id = auth.uid()$$, 'Anzeigename ändern zählt nicht'
);
select lives_ok(
  $t$do $do$ begin
      update public.profiles set username = 'alex_1' where id = auth.uid();
      update public.profiles set username = 'alex_2' where id = auth.uid();
      update public.profiles set username = 'alex_3' where id = auth.uid();
      update public.profiles set username = 'alex_4' where id = auth.uid();
      update public.profiles set username = 'alex' where id = auth.uid();
    end $do$$t$,
  'fünf Änderungen des Benutzernamens'
);
select throws_ok(
  $$update public.profiles set username = 'alex_6' where id = auth.uid()$$, 'P0001', 'rate_limited',
  'sechste Änderung in 24 Stunden: rate_limited'
);

-- =============================================================================================================
-- is_username_available: Rate Limit auch ohne Profil
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-000000000006","role":"authenticated"}';
select is(public.is_username_available('ALEX'), false, 'ohne Profil: vergebener Name (Groß-/Kleinschreibung egal)');
select is(public.is_username_available('frei_name'), true, 'ohne Profil: freier Name');
select is(
  (select count(*)::int from generate_series(1, 58) s cross join lateral public.is_username_available('n' || s) a),
  58, '60 Prüfungen je 10 Minuten erlaubt'
);
select throws_ok($$select public.is_username_available('zuviel')$$, 'P0001', 'rate_limited', '61. Prüfung: rate_limited');
set local request.jwt.claims = '{"role":"authenticated"}';
select throws_ok($$select public.is_username_available('x')$$, '42501', 'not_authenticated', 'ohne Anmeldung: not_authenticated');

-- =============================================================================================================
-- Präfixsuche (als alex)
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-000000000001","role":"authenticated"}';

select is(public.social_search_profiles('al'), '[]'::jsonb, 'unter 3 Zeichen: keine Treffer');
select is(public.social_search_profiles('a%x'), '[]'::jsonb, 'LIKE-Platzhalter: keine Treffer');
select is(public.social_search_profiles('al_'), '[]'::jsonb, 'Unterstrich gilt wörtlich, nicht als Platzhalter');
select is(public.social_search_profiles(null), '[]'::jsonb, 'null: keine Treffer');
select is(pg_temp.names(public.social_search_profiles('ALE')), array['alexa', 'alexander'], 'Präfix ohne mich selbst, kürzere zuerst');
select is(pg_temp.names(public.social_search_profiles('@alexa')), array['alexa', 'alexander'], 'führendes @ wird ignoriert, exakter Treffer zuerst');
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_search_profiles('alexa')->0) k),
  array['avatar_path', 'display_name', 'public_id', 'relationship', 'request_id', 'username'],
  'Treffer: nur öffentliche Felder'
);
select ok(public.social_search_profiles('alexa')::text not like '%a9000000-%', 'keine Auth-IDs');
select is(public.social_search_profiles('dan'), '[]'::jsonb, 'nicht auffindbares Profil: kein Präfixtreffer');
select is(pg_temp.names(public.social_search_profiles('dana')), array['dana'], 'nicht auffindbares Profil: exakt auffindbar');
select is(public.social_search_profiles('hanna')->0->>'relationship', 'incoming_request', 'Beziehung incoming_request mit request_id');
select ok(public.social_search_profiles('hanna')->0->>'request_id' is not null, 'request_id bei offener Anfrage');
select is(jsonb_array_length(public.social_search_profiles('statist')), 20, 'höchstens 20 Treffer');

-- Freunde finden sich immer, auch wenn sie nicht auffindbar sind.
reset role;
update public.profiles set is_discoverable = false where username = 'emil';
set local role authenticated;
select is(public.social_search_profiles('emi')->0->>'relationship', 'friend', 'nicht auffindbarer Freund: per Präfix sichtbar');

-- Rate Limit: 120 Anfragen je 10 Minuten (bisher 14 gezählt).
select is(
  (select count(*)::int from generate_series(1, 106) s cross join lateral public.social_search_profiles('zz' || s) r),
  106, 'bis 120 Anfragen erlaubt'
);
select throws_ok($$select public.social_search_profiles('ale')$$, 'P0001', 'rate_limited', '121. Anfrage: rate_limited');

-- =============================================================================================================
-- Blockieren (alex blockiert finn; gina blockiert alex)
-- =============================================================================================================

select throws_ok(format('select public.social_block_user(%L)', pg_temp.pid(1)), 'P0001', 'self_request', 'sich selbst blockieren');
select throws_ok(
  $$select public.social_block_user('b9000000-0000-4000-8000-00000000dead')$$, 'P0001', 'not_found', 'unbekannte Person'
);
select lives_ok(format('select public.social_block_user(%L)', pg_temp.pid(7)), 'finn blockieren');
select lives_ok(format('select public.social_block_user(%L)', pg_temp.pid(7)), 'erneut blockieren ist unschädlich');

reset role;
select ok(not private.are_friends(pg_temp.uid(1), pg_temp.uid(7)), 'Blockieren beendet die Freundschaft');
select is(
  (select status from public.group_invitations where invitee_id = pg_temp.uid(7)), 'cancelled',
  'Blockieren zieht offene Gruppeneinladungen zurück'
);
-- hanna (offene Anfrage an alex) wird von alex blockiert: Anfrage gilt als abgelehnt.
set local role authenticated;
select lives_ok(format('select public.social_block_user(%L)', pg_temp.pid(9)), 'hanna blockieren');
reset role;
select is(
  (select status from public.friend_requests where requester_id = pg_temp.uid(9)), 'declined',
  'eingehende Anfrage einer blockierten Person gilt als abgelehnt'
);
set local role authenticated;

select is(pg_temp.names(public.social_blocked_users()), array['finn', 'hanna'], 'Liste der Blockierten, nach Name');
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_blocked_users()->0) k),
  array['avatar_path', 'blocked_at', 'display_name', 'public_id', 'username'], 'Blockierte: nur öffentliche Felder'
);
select is(public.social_find_profile('finn'), null, 'exakte Suche findet Blockierte nicht');
select throws_ok(
  format('select public.social_send_friend_request(%L)', pg_temp.pid(7)), 'P0001', 'blocked',
  'Anfrage an eine von mir blockierte Person: blocked'
);

-- finn sieht alex nicht mehr und kann keine Anfrage senden.
set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-000000000007","role":"authenticated"}';
select is(public.social_find_profile('alex'), null, 'Blockierte Person findet mich nicht (exakt)');
select is(pg_temp.names(public.social_search_profiles('alex')), array['alexa', 'alexander'], 'Blockierte Person findet mich nicht (Präfix)');
select throws_ok(
  format('select public.social_send_friend_request(%L)', pg_temp.pid(1)), 'P0001', 'not_found',
  'Anfrage einer blockierten Person: wie nicht vorhanden'
);
select throws_ok(
  format('select public.social_public_profile(%L, %L)', pg_temp.pid(1), (now() at time zone 'utc')::date),
  'P0001', 'not_found', 'öffentliches Profil: für Blockierte nicht sichtbar'
);
select is(public.social_blocked_users(), '[]'::jsonb, 'Blockierte Person sieht keine eigene Blockierung');

-- gina blockiert alex.
set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-000000000008","role":"authenticated"}';
select lives_ok(format('select public.social_block_user(%L)', pg_temp.pid(1)), 'gina blockiert alex');

-- =============================================================================================================
-- Öffentliches Profil (als alex)
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-000000000001","role":"authenticated"}';

select is(
  public.social_public_profile(pg_temp.pid(5), (now() at time zone 'utc')::date)
    - 'friends_since' - 'request_id',
  jsonb_build_object(
    'public_id', pg_temp.pid(5), 'username', 'emil', 'display_name', 'Emil', 'avatar_path', null,
    'relationship', 'friend', 'steps_today', 7000, 'steps_week', 7000, 'is_blocked_by_me', false
  ),
  'Freund: Schritte heute und in der Woche'
);
select ok(
  public.social_public_profile(pg_temp.pid(5), (now() at time zone 'utc')::date)->>'friends_since' is not null,
  'Freund: friends_since'
);
select is(
  public.social_public_profile(pg_temp.pid(2), (now() at time zone 'utc')::date)
    - 'public_id' - 'username' - 'display_name' - 'avatar_path',
  '{"relationship": "none", "request_id": null, "friends_since": null, "steps_today": null, "steps_week": null, "is_blocked_by_me": false}'::jsonb,
  'Fremde Person: keine Schritte'
);
select is(
  public.social_public_profile(pg_temp.pid(7), (now() at time zone 'utc')::date)->>'is_blocked_by_me', 'true',
  'von mir blockierte Person: sichtbar mit is_blocked_by_me'
);
select throws_ok(
  format('select public.social_public_profile(%L, %L)', pg_temp.pid(8), (now() at time zone 'utc')::date),
  'P0001', 'not_found', 'Person, die mich blockiert hat: not_found'
);
select throws_ok(
  format('select public.social_public_profile(%L, %L)', pg_temp.pid(5), (now() at time zone 'utc')::date - 20),
  'P0001', 'invalid_date', 'Stichtag außerhalb des Fensters'
);
select ok(
  public.social_public_profile(pg_temp.pid(5), (now() at time zone 'utc')::date)::text not like '%a9000000-%',
  'öffentliches Profil: keine Auth-IDs'
);

-- Aufheben: idempotent, Freundschaft wird nicht wiederhergestellt.
select lives_ok(format('select public.social_unblock_user(%L)', pg_temp.pid(7)), 'Blockierung aufheben');
select lives_ok(format('select public.social_unblock_user(%L)', pg_temp.pid(7)), 'erneut aufheben ist unschädlich');
select is(pg_temp.names(public.social_blocked_users()), array['hanna'], 'finn nicht mehr blockiert');
select is(public.social_find_profile('finn')->>'relationship', 'none', 'nach dem Aufheben: auffindbar, nicht befreundet');

select * from finish();
rollback;
