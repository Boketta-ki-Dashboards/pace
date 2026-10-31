-- Pace: Spitznamen für Freunde – Rechte, Validierung, Ausgabe an allen Stellen, Privatsphäre, Aufräumen.
begin;
select plan(64);

-- =============================================================================================================
-- Struktur
-- =============================================================================================================

select ok(
  (select c.relrowsecurity from pg_class c where c.oid = 'public.friend_nicknames'::regclass),
  'RLS auf friend_nicknames'
);
select is(
  (select count(*)::int from pg_policy p where p.polrelid = 'public.friend_nicknames'::regclass),
  0, 'keine Policies: Zugriff nur über RPCs'
);
select is(
  (select array_agg(format('%s %s', r.role_name, pr.privilege) order by 1)
     from unnest(array['anon', 'authenticated']) as r(role_name)
    cross join unnest(array['select', 'insert', 'update', 'delete']) as pr(privilege)
    where has_table_privilege(r.role_name, 'public.friend_nicknames', pr.privilege)),
  null, 'anon/authenticated ohne Rechte auf friend_nicknames'
);
select ok(
  not has_function_privilege('anon', 'public.social_set_friend_nickname(uuid, text)', 'execute')
  and not has_function_privilege('public', 'public.social_set_friend_nickname(uuid, text)', 'execute')
  and has_function_privilege('authenticated', 'public.social_set_friend_nickname(uuid, text)', 'execute'),
  'social_set_friend_nickname: nur authenticated'
);
select ok(
  (select p.prosecdef and p.proconfig = array['search_path=""'] and obj_description(p.oid, 'pg_proc') is not null
     from pg_proc p where p.oid = 'public.social_set_friend_nickname(uuid, text)'::regprocedure),
  'social_set_friend_nickname: security definer, leerer search_path, Kommentar'
);
select ok(
  not has_function_privilege('authenticated', 'private.friend_nickname(uuid, uuid)', 'execute'),
  'private.friend_nickname für Clients nicht ausführbar'
);

-- =============================================================================================================
-- Testdaten
-- =============================================================================================================

-- 1 lena, 2 max, 3 nora, 4 otto (Fremder, aber in der Gruppe), 5 pia, 6 rosa.
-- Freunde: lena–max, lena–nora, lena–pia, max–nora, lena–rosa.
insert into auth.users (id, aud, role, is_anonymous)
select ('ae000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 6) n;
insert into public.profiles (id, public_id, username, display_name)
select ('ae000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('be000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'lena', 'Lena'), (2, 'max_m', 'Max'), (3, 'nora', 'Nora'), (4, 'otto', 'Otto'), (5, 'pia', 'Pia'),
               (6, 'rosa', 'Rosa')) as v(n, username, display_name);

create function pg_temp.uid(n int) returns uuid language sql immutable as $$
  select ('ae000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;
create function pg_temp.pid(n int) returns uuid language sql immutable as $$
  select ('be000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;
create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claims',
                    format('{"sub":"ae000000-0000-4000-8000-%s","role":"authenticated"}', lpad(n::text, 12, '0')), true);
$$;
create function pg_temp.befriend(a int, b int) returns void language sql as $$
  insert into public.friendships (user_a, user_b)
  values (least(pg_temp.uid(a), pg_temp.uid(b)), greatest(pg_temp.uid(a), pg_temp.uid(b)));
$$;
-- Spitzname eines Profils in einer Liste (nach public_id bzw. public_user_id).
create function pg_temp.nick(p_list jsonb, n int) returns text language sql immutable as $$
  select e->>'nickname' from jsonb_array_elements(p_list) e
   where coalesce(e->>'public_id', e->>'public_user_id') = pg_temp.pid(n)::text;
$$;

select pg_temp.befriend(1, 2);
select pg_temp.befriend(1, 3);
select pg_temp.befriend(1, 5);
select pg_temp.befriend(2, 3);
select pg_temp.befriend(1, 6);

-- Gruppe von lena mit max, nora und otto; Tageswerte für die Rankings.
insert into public.groups (id, name, kind, invite_code, created_by)
values ('ce000000-0000-4000-8000-000000000001', 'Spitzgruppe', 'friends', 'NCKNAMES', pg_temp.uid(1));
insert into public.group_goal_history (group_id, effective_from, daily_goal)
values ('ce000000-0000-4000-8000-000000000001', current_date - 30, 5000);
insert into public.group_members (group_id, user_id, role)
values ('ce000000-0000-4000-8000-000000000001', pg_temp.uid(1), 'owner'),
       ('ce000000-0000-4000-8000-000000000001', pg_temp.uid(2), 'member'),
       ('ce000000-0000-4000-8000-000000000001', pg_temp.uid(3), 'member'),
       ('ce000000-0000-4000-8000-000000000001', pg_temp.uid(4), 'member');
insert into public.daily_activity (user_id, activity_date, competition_steps)
select pg_temp.uid(n), (now() at time zone 'utc')::date, 1000 * n from generate_series(1, 4) n;

-- Privatchat lena–max mit einer Nachricht von max, Gruppenchat mit einer Nachricht von max.
insert into public.conversations (id, kind, user_a, user_b)
values ('de000000-0000-4000-8000-000000000001', 'direct', pg_temp.uid(1), pg_temp.uid(2));
insert into public.chat_messages (conversation_id, sender_id, client_id, kind, body)
select 'de000000-0000-4000-8000-000000000001', pg_temp.uid(2), gen_random_uuid(), 'text', 'Hallo Lena';
insert into public.chat_messages (conversation_id, sender_id, client_id, kind, body)
select c.id, pg_temp.uid(2), gen_random_uuid(), 'text', 'Hallo Gruppe'
  from public.conversations c where c.group_id = 'ce000000-0000-4000-8000-000000000001';

-- Offene Einladung von max an rosa (Freundschaft max–rosa nötig).
select pg_temp.befriend(2, 6);
insert into public.group_invitations (group_id, inviter_id, invitee_id)
values ('ce000000-0000-4000-8000-000000000001', pg_temp.uid(2), pg_temp.uid(6));

create temporary table t_out (name text primary key, result jsonb) on commit drop;
grant select, insert, delete on t_out to authenticated;
insert into t_out select 'group_chat', to_jsonb(c.id) from public.conversations c where c.group_id = 'ce000000-0000-4000-8000-000000000001';
create function pg_temp.group_chat() returns uuid language sql stable as $$
  select (o.result #>> '{}')::uuid from t_out o where o.name = 'group_chat';
$$;

set local role authenticated;

-- =============================================================================================================
-- Setzen, Normalisieren, Validieren (als lena)
-- =============================================================================================================

select pg_temp.as_user(1);
select is(
  public.social_set_friend_nickname(pg_temp.pid(2), 'Maxi'),
  jsonb_build_object('public_id', pg_temp.pid(2), 'username', 'max_m', 'display_name', 'Max', 'avatar_path', null,
                     'nickname', 'Maxi'),
  'Spitzname setzen: Profil mit nickname'
);
select is(
  public.social_set_friend_nickname(pg_temp.pid(3), E'  Die \t  Nora  ')->>'nickname', 'Die Nora',
  'Leerraum wird zusammengefasst und am Rand entfernt'
);
select is(
  public.social_set_friend_nickname(pg_temp.pid(5), repeat('ä', 30))->>'nickname', repeat('ä', 30),
  '30 Zeichen erlaubt'
);
select throws_ok(
  format('select public.social_set_friend_nickname(%L, %L)', pg_temp.pid(5), repeat('x', 31)),
  'P0001', 'invalid_nickname', '31 Zeichen: invalid_nickname'
);
select throws_ok(
  format('select public.social_set_friend_nickname(%L, %L)', pg_temp.pid(5), E'Pi\u0007a'),
  'P0001', 'invalid_nickname', 'Steuerzeichen: invalid_nickname'
);
select throws_ok(
  format('select public.social_set_friend_nickname(%L, %L)', pg_temp.pid(5), E'Pi\u200Ba'),
  'P0001', 'invalid_nickname', 'unsichtbares Formatzeichen: invalid_nickname'
);
select is(
  public.social_set_friend_nickname(pg_temp.pid(5), 'Pia 🏃')->>'nickname', 'Pia 🏃', 'Emoji erlaubt'
);
select throws_ok(
  format('select public.social_set_friend_nickname(%L, %L)', pg_temp.pid(4), 'Otti'),
  'P0001', 'not_found', 'kein Freund: not_found'
);
select throws_ok(
  format('select public.social_set_friend_nickname(%L, %L)', pg_temp.pid(1), 'Ich'),
  'P0001', 'not_found', 'ich selbst: not_found'
);
select throws_ok(
  $$select public.social_set_friend_nickname('be000000-0000-4000-8000-00000000dead', 'X')$$,
  'P0001', 'not_found', 'unbekannt: not_found'
);
select is(public.social_set_friend_nickname(pg_temp.pid(6), 'Röschen')->>'nickname', 'Röschen', 'Spitzname für rosa');
select is(public.social_set_friend_nickname(pg_temp.pid(6), 'Rosi')->>'nickname', 'Rosi', 'Spitzname ändern');
select is(public.social_set_friend_nickname(pg_temp.pid(6), '   ')->'nickname', 'null'::jsonb, 'leer entfernt');
select is(public.social_set_friend_nickname(pg_temp.pid(6), null)->'nickname', 'null'::jsonb, 'null entfernt (idempotent)');
select is(public.social_set_friend_nickname(pg_temp.pid(6), 'Rosi')->>'nickname', 'Rosi', 'wieder gesetzt');

-- =============================================================================================================
-- Ausgabe an allen Stellen (als lena)
-- =============================================================================================================

select is(pg_temp.nick(public.social_friends(), 2), 'Maxi', 'Freundesliste: nickname');
select is(pg_temp.nick(public.social_friends(), 1), null, 'Freundesliste: ohne mich');
select is(
  pg_temp.nick(public.social_friend_ranking('daily', (now() at time zone 'utc')::date)->'entries', 2), 'Maxi',
  'Freundesranking: nickname'
);
select is(
  pg_temp.nick(public.social_friend_ranking('daily', (now() at time zone 'utc')::date)->'entries', 1), null,
  'Freundesranking: eigener Eintrag ohne nickname'
);
select is(
  pg_temp.nick(public.social_group_ranking('ce000000-0000-4000-8000-000000000001', 'daily')->'entries', 2), 'Maxi',
  'Gruppenranking: nickname'
);
select is(
  pg_temp.nick(public.social_group_ranking('ce000000-0000-4000-8000-000000000001', 'daily')->'entries', 4), null,
  'Gruppenranking: Fremder ohne nickname'
);
select is(
  public.social_public_profile(pg_temp.pid(2), (now() at time zone 'utc')::date)->>'nickname', 'Maxi',
  'Profilansicht: nickname'
);
select is(
  public.social_friend_profile(pg_temp.pid(2), (now() at time zone 'utc')::date)->>'nickname', 'Maxi',
  'Freundesprofil: nickname'
);
select is(public.social_find_profile('max_m')->>'nickname', 'Maxi', 'Suche (exakt): nickname');
select is(pg_temp.nick(public.social_search_profiles('max'), 2), 'Maxi', 'Präfixsuche: nickname');
select is(
  public.chat_messages('de000000-0000-4000-8000-000000000001')->0->'sender'->>'nickname', 'Maxi',
  'Privatchat: Absender mit nickname'
);
select is(
  (select e->'peer'->>'nickname' from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'direct'),
  'Maxi', 'Chatliste: Gegenüber mit nickname'
);
select is(
  (select e->'last_message'->>'sender_nickname' from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'group'),
  'Maxi', 'Chatliste: Absender der letzten Gruppennachricht mit nickname'
);
select is(
  (select e->'last_message'->>'sender_name' from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'group'),
  'Max', 'Chatliste: Anzeigename bleibt erhalten (ältere App-Versionen)'
);
insert into t_out select 'shared', public.chat_send('de000000-0000-4000-8000-000000000001', gen_random_uuid(), 'profile', p_shared_profile_id => pg_temp.pid(3));
select is((select result->'shared_profile'->>'nickname' from t_out where name = 'shared'), 'Die Nora', 'geteiltes Profil mit nickname');
insert into t_out select 'export', public.account_export();
select is(
  (select array_agg(e->>'nickname' order by e->>'nickname') from t_out, jsonb_array_elements(result->'friend_nicknames') e where name = 'export'),
  array['Die Nora', 'Maxi', 'Pia 🏃', 'Rosi'], 'Export: eigene Spitznamen'
);

-- Meldungen: Der Schnappschuss (nur für das Moderationsteam) enthält nicht den privaten Spitznamen der meldenden Person.
select lives_ok(format('select public.social_report(%L, %L, %L)', 'user', pg_temp.pid(2), 'spam'), 'lena meldet max');
select lives_ok(
  format('select public.social_report(%L, %L, %L)', 'message',
         (select e->>'id' from jsonb_array_elements(public.chat_messages('de000000-0000-4000-8000-000000000001')) e where e->>'body' = 'Hallo Lena'),
         'harassment'),
  'lena meldet eine Nachricht von max'
);
reset role;
-- Bio, Interessen und Banner (seit 20261030100000 im Schnappschuss) prüft 17_profile_details.
select is(
  (select r.target_snapshot - array['bio', 'interests', 'banner_path'] from public.reports r
    where r.reporter_id = pg_temp.uid(1) and r.target_type = 'user'),
  jsonb_build_object('public_id', pg_temp.pid(2), 'username', 'max_m', 'display_name', 'Max', 'avatar_path', null),
  'Meldung einer Person: Schnappschuss ohne nickname'
);
select is(
  (select r.target_snapshot->'sender' from public.reports r where r.reporter_id = pg_temp.uid(1) and r.target_type = 'message'),
  jsonb_build_object('public_id', pg_temp.pid(2), 'username', 'max_m', 'display_name', 'Max', 'avatar_path', null),
  'Meldung einer Nachricht: Absender ohne nickname'
);
select ok(
  not exists (select 1 from public.reports r where r.reporter_id = pg_temp.uid(1) and r.target_snapshot::text like '%Maxi%'),
  'kein Spitzname in Meldungen'
);
set local role authenticated;
select pg_temp.as_user(1);

-- Einladung von max an rosa: rosa sieht ihren eigenen Spitznamen für max.
select pg_temp.as_user(6);
select is(public.social_set_friend_nickname(pg_temp.pid(2), 'Maximilian')->>'nickname', 'Maximilian', 'rosa vergibt eigenen Spitznamen');
select is(public.social_group_invitations()->0->>'inviter_nickname', 'Maximilian', 'Einladung: inviter_nickname (eigener)');
select is(public.social_group_invitations()->0->>'inviter_display_name', 'Max', 'Einladung: Anzeigename bleibt');

-- =============================================================================================================
-- Privatsphäre: fremde Spitznamen sind nie sichtbar
-- =============================================================================================================

select pg_temp.as_user(2);
select is(public.social_set_friend_nickname(pg_temp.pid(1), 'Lenchen')->>'nickname', 'Lenchen', 'max vergibt eigenen Spitznamen');
select is(pg_temp.nick(public.social_friends(), 3), null, 'max sieht lenas Spitznamen für nora nicht');
select ok(
  public.social_friends()::text not like '%Maxi%' and public.social_friends()::text not like '%Die Nora%',
  'max: keine fremden Spitznamen in der Freundesliste'
);
select ok(
  public.social_group_ranking('ce000000-0000-4000-8000-000000000001', 'daily')::text not like '%Maxi%'
  and public.social_group_ranking('ce000000-0000-4000-8000-000000000001', 'daily')::text not like '%Die Nora%',
  'max: keine fremden Spitznamen im Gruppenranking'
);
select ok(public.chat_conversations()::text not like '%Maximilian%', 'max: rosas Spitzname für ihn erscheint nicht');

select pg_temp.as_user(3);
select is(
  pg_temp.nick(public.social_group_ranking('ce000000-0000-4000-8000-000000000001', 'daily')->'entries', 2), null,
  'nora sieht lenas Spitznamen für max nicht'
);
select ok(
  public.chat_messages(pg_temp.group_chat())::text not like '%Maxi%',
  'nora: Gruppenchat ohne fremde Spitznamen'
);

select pg_temp.as_user(1);
select ok(
  public.social_friends()::text not like '%Lenchen%'
  and public.chat_conversations()::text not like '%Lenchen%'
  and public.chat_messages('de000000-0000-4000-8000-000000000001')::text not like '%Lenchen%',
  'lena sieht max’ Spitznamen für sie nirgends'
);

-- =============================================================================================================
-- Rate Limit
-- =============================================================================================================

reset role;
delete from private.rate_limit_events e where e.user_id = pg_temp.uid(1) and e.action = 'friend_nickname';
set local role authenticated;
select pg_temp.as_user(1);
select is(
  (select count(*)::int from generate_series(1, 30) s
    cross join lateral public.social_set_friend_nickname(pg_temp.pid(2), 'Maxi ' || s) r),
  30, '30 Änderungen je 10 Minuten erlaubt'
);
select throws_ok(
  format('select public.social_set_friend_nickname(%L, %L)', pg_temp.pid(2), 'Maxi'),
  'P0001', 'rate_limited', '31. Änderung: rate_limited'
);

-- =============================================================================================================
-- Aufräumen: Freundschaft endet, Blockieren, Konto löschen
-- =============================================================================================================

select lives_ok(format('select public.social_remove_friend(%L)', pg_temp.pid(3)), 'lena beendet die Freundschaft mit nora');
reset role;
select is(
  (select count(*)::int from public.friend_nicknames n where n.owner_id = pg_temp.uid(1) and n.target_id = pg_temp.uid(3)),
  0, 'Ende der Freundschaft löscht den Spitznamen'
);
select pg_temp.befriend(1, 3);
set local role authenticated;
select pg_temp.as_user(1);
select is(pg_temp.nick(public.social_friends(), 3), null, 'erneute Freundschaft: kein alter Spitzname');

select pg_temp.as_user(5);
select is(public.social_set_friend_nickname(pg_temp.pid(1), 'Leni')->>'nickname', 'Leni', 'pia vergibt Spitznamen für lena');
select pg_temp.as_user(1);
select lives_ok(format('select public.social_block_user(%L)', pg_temp.pid(5)), 'lena blockiert pia');
reset role;
select is(
  (select count(*)::int from public.friend_nicknames n
    where (n.owner_id, n.target_id) in ((pg_temp.uid(1), pg_temp.uid(5)), (pg_temp.uid(5), pg_temp.uid(1)))),
  0, 'Blockieren löscht die Spitznamen beider Seiten'
);
-- Auch ohne Freundschaft bleibt zwischen Blockierten nichts übrig (Trigger auf user_blocks).
insert into public.friend_nicknames (owner_id, target_id, nickname) values (pg_temp.uid(4), pg_temp.uid(3), 'Nono');
insert into public.user_blocks (blocker_id, blocked_id) values (pg_temp.uid(3), pg_temp.uid(4));
select is(
  (select count(*)::int from public.friend_nicknames n where n.owner_id = pg_temp.uid(4)), 0,
  'Blockierung entfernt auch Spitznamen ohne Freundschaft'
);
select throws_ok(
  format('insert into public.friend_nicknames (owner_id, target_id, nickname) values (%L, %L, %L)', pg_temp.uid(2), pg_temp.uid(2), 'Ich'),
  '23514', null, 'kein Spitzname für sich selbst'
);
delete from auth.users u where u.id = pg_temp.uid(2);
select is(
  (select count(*)::int from public.friend_nicknames n where pg_temp.uid(2) in (n.owner_id, n.target_id)), 0,
  'Konto löschen entfernt eigene und auf das Konto bezogene Spitznamen'
);

select * from finish();
rollback;
