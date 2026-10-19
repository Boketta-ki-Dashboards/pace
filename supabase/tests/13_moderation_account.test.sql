-- Pace: Meldungen, Rückmeldungen, Datenexport, eigene Dateien und Konto löschen.
begin;
select plan(50);

-- =============================================================================================================
-- Struktur
-- =============================================================================================================

select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
    where c.oid in ('public.reports'::regclass, 'public.feedback'::regclass) and c.relrowsecurity),
  array['feedback', 'reports'], 'RLS auf reports und feedback'
);
select is(
  (select array_agg(format('%s %s %s', r.role_name, t.table_name, pr.privilege) order by 1)
     from unnest(array['anon', 'authenticated']) as r(role_name)
    cross join unnest(array['public.reports', 'public.feedback']) as t(table_name)
    cross join unnest(array['select', 'insert', 'update', 'delete']) as pr(privilege)
    where has_table_privilege(r.role_name, t.table_name, pr.privilege)),
  null, 'kein Clientzugriff auf Meldungen und Rückmeldungen'
);
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('social_report', 'submit_feedback', 'account_export', 'account_own_media', 'account_delete')
      and not has_function_privilege('anon', p.oid, 'execute')
      and has_function_privilege('authenticated', p.oid, 'execute')
      and p.prosecdef and p.proconfig = array['search_path=""']),
  array['account_delete', 'account_export', 'account_own_media', 'social_report', 'submit_feedback'],
  'RPCs: nur authenticated, security definer, leerer search_path'
);

-- =============================================================================================================
-- Testdaten
-- =============================================================================================================

-- 1 ina, 2 jan, 3 kim (Fremde), 4 lou; 5 ohne Profil.
insert into auth.users (id, aud, role, is_anonymous)
select ('ad000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 5) n;
insert into public.profiles (id, public_id, username, display_name)
select ('ad000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('bd000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'ina', 'Ina'), (2, 'jan', 'Jan'), (3, 'kim', 'Kim'), (4, 'lou', 'Lou')) as v(n, username, display_name);
insert into public.friendships (user_a, user_b)
values ('ad000000-0000-4000-8000-000000000001', 'ad000000-0000-4000-8000-000000000002');

-- Gruppe von ina mit jan und lou (lou ist am längsten nach ina dabei).
insert into public.groups (id, name, kind, invite_code, created_by)
values ('cd000000-0000-4000-8000-000000000001', 'Meldegruppe', 'friends', 'MELDEXYZ', 'ad000000-0000-4000-8000-000000000001'),
       ('cd000000-0000-4000-8000-000000000002', 'Fremdgruppe', 'friends', 'FREMDXYZ', 'ad000000-0000-4000-8000-000000000003');
insert into public.group_goal_history (group_id, effective_from, daily_goal)
values ('cd000000-0000-4000-8000-000000000001', current_date - 5, 8000),
       ('cd000000-0000-4000-8000-000000000002', current_date - 5, 8000);
insert into public.group_members (group_id, user_id, role, joined_at)
values ('cd000000-0000-4000-8000-000000000001', 'ad000000-0000-4000-8000-000000000001', 'owner', now() - interval '3 days'),
       ('cd000000-0000-4000-8000-000000000001', 'ad000000-0000-4000-8000-000000000004', 'member', now() - interval '2 days'),
       ('cd000000-0000-4000-8000-000000000001', 'ad000000-0000-4000-8000-000000000002', 'member', now() - interval '1 day'),
       ('cd000000-0000-4000-8000-000000000002', 'ad000000-0000-4000-8000-000000000003', 'owner', now());

-- Privatchat ina–jan mit Nachrichten beider.
insert into public.conversations (id, kind, user_a, user_b)
values ('dd000000-0000-4000-8000-000000000001', 'direct', 'ad000000-0000-4000-8000-000000000001', 'ad000000-0000-4000-8000-000000000002');
insert into public.chat_messages (id, conversation_id, sender_id, client_id, kind, body)
values ('ed000000-0000-4000-8000-000000000001', 'dd000000-0000-4000-8000-000000000001', 'ad000000-0000-4000-8000-000000000002', gen_random_uuid(), 'text', 'Spam von Jan'),
       ('ed000000-0000-4000-8000-000000000002', 'dd000000-0000-4000-8000-000000000001', 'ad000000-0000-4000-8000-000000000001', gen_random_uuid(), 'text', 'Antwort von Ina');

insert into public.daily_activity (user_id, activity_date, competition_steps)
values ('ad000000-0000-4000-8000-000000000001', (now() at time zone 'utc')::date, 5000);

insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('avatars', 'bd000000-0000-4000-8000-000000000001/ina.jpg', 'ad000000-0000-4000-8000-000000000001', '{"mimetype":"image/jpeg"}'),
       ('chat-media', 'dd000000-0000-4000-8000-000000000001/bild.jpg', 'ad000000-0000-4000-8000-000000000001', '{"mimetype":"image/jpeg"}'),
       ('group-images', 'cd000000-0000-4000-8000-000000000001/von-lou.jpg', 'ad000000-0000-4000-8000-000000000004', '{"mimetype":"image/jpeg"}'),
       ('avatars', 'bd000000-0000-4000-8000-000000000002/jan.jpg', 'ad000000-0000-4000-8000-000000000002', '{"mimetype":"image/jpeg"}');

create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claims',
                    format('{"sub":"ad000000-0000-4000-8000-%s","role":"authenticated"}', lpad(n::text, 12, '0')), true);
$$;

set local role authenticated;
select pg_temp.as_user(1);

-- =============================================================================================================
-- Meldungen (ina)
-- =============================================================================================================

select throws_ok($$select public.social_report('user', 'bd000000-0000-4000-8000-000000000001', 'spam')$$, 'P0001', 'not_found', 'sich selbst melden: not_found');
select throws_ok($$select public.social_report('user', 'bd000000-0000-4000-8000-00000000dead', 'spam')$$, 'P0001', 'not_found', 'unbekannte Person');
select throws_ok($$select public.social_report('user', 'bd000000-0000-4000-8000-000000000003', 'langweilig')$$, 'P0001', 'invalid_input', 'unbekannter Grund');
select throws_ok($$select public.social_report('user', 'bd000000-0000-4000-8000-000000000003', 'spam', repeat('x', 1001))$$, 'P0001', 'invalid_input', 'Details über 1000 Zeichen');
select throws_ok($$select public.social_report('comment', 'bd000000-0000-4000-8000-000000000003', 'spam')$$, 'P0001', 'invalid_input', 'unbekannte Zielart');
select lives_ok($$select public.social_report('user', 'bd000000-0000-4000-8000-000000000003', 'impersonation', '  gibt sich als Kim aus  ')$$, 'Person melden');
select lives_ok($$select public.social_report('user', 'bd000000-0000-4000-8000-000000000003', 'spam')$$, 'erneut melden ist unschädlich');
select throws_ok($$select public.social_report('message', 'ed000000-0000-4000-8000-000000000002', 'spam')$$, 'P0001', 'not_found', 'eigene Nachricht melden: not_found');
select lives_ok($$select public.social_report('message', 'ed000000-0000-4000-8000-000000000001', 'spam')$$, 'Nachricht melden');
select lives_ok($$select public.social_report('group', 'cd000000-0000-4000-8000-000000000001', 'inappropriate', 'Name')$$, 'eigene Gruppe melden');
select throws_ok($$select public.social_report('group', 'cd000000-0000-4000-8000-000000000002', 'spam')$$, 'P0001', 'not_found', 'fremde Gruppe: not_found');

select pg_temp.as_user(3);
select throws_ok($$select public.social_report('message', 'ed000000-0000-4000-8000-000000000001', 'spam')$$, 'P0001', 'not_found', 'Nachricht aus fremder Unterhaltung: not_found');

reset role;
select is(
  (select array_agg(r.target_type || ':' || r.reason || ':' || coalesce(r.details, '-') order by r.target_type) from public.reports r),
  array['group:inappropriate:Name', 'message:spam:-', 'user:impersonation:gibt sich als Kim aus'],
  'Meldungen gespeichert (eine offene je Ziel, Details getrimmt)'
);
select is(
  (select r.target_snapshot->>'body' from public.reports r where r.target_type = 'message'),
  'Spam von Jan', 'Meldung hält den gemeldeten Inhalt fest'
);
select is((select count(*)::int from public.reports where status <> 'open'), 0, 'Status open');

-- Rate Limit: 10 je 24 h (ina hat 3).
insert into auth.users (id, aud, role, is_anonymous)
select ('ad000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(101, 108) n;
insert into public.profiles (id, public_id, username, display_name)
select ('ad000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, ('bd000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'statist_' || n, 'Statist ' || n
  from generate_series(101, 108) n;
set local role authenticated;
select pg_temp.as_user(1);
select is(
  (select count(*)::int from generate_series(101, 107) n
     cross join lateral public.social_report('user', ('bd000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'spam') r),
  7, 'bis zu 10 Meldungen je 24 h'
);
select throws_ok($$select public.social_report('user', 'bd000000-0000-4000-8000-000000000108', 'spam')$$, 'P0001', 'rate_limited', '11. Meldung: rate_limited');

-- =============================================================================================================
-- Rückmeldungen
-- =============================================================================================================

select throws_ok($$select public.submit_feedback('bug', 'Text', '1.0')$$, 'P0001', 'invalid_input', 'unbekannte Art');
select throws_ok($$select public.submit_feedback('problem', '   ', '1.0')$$, 'P0001', 'invalid_input', 'leere Nachricht');
select throws_ok($$select public.submit_feedback('problem', repeat('x', 2001), '1.0')$$, 'P0001', 'invalid_input', 'Nachricht zu lang');
select throws_ok($$select public.submit_feedback('problem', 'Text', repeat('9', 41))$$, 'P0001', 'invalid_input', 'App-Version zu lang');
select lives_ok($$select public.submit_feedback('idea', '  Mehr Widgets bitte  ', '1.4 (12)')$$, 'Rückmeldung gespeichert');
reset role;
select is((select message from public.feedback), 'Mehr Widgets bitte', 'Rückmeldung getrimmt');
set local role authenticated;
select is(
  (select count(*)::int from generate_series(1, 9) n cross join lateral public.submit_feedback('problem', 'Fehler ' || n, '1.4') f),
  9, 'bis zu 10 Rückmeldungen je 24 h'
);
select throws_ok($$select public.submit_feedback('problem', 'noch einer', '1.4')$$, 'P0001', 'rate_limited', '11. Rückmeldung: rate_limited');

-- =============================================================================================================
-- Datenexport und eigene Dateien
-- =============================================================================================================

create temporary table t_export (data jsonb) on commit drop;
grant select, insert on t_export to authenticated;
insert into t_export select public.account_export();
select is(
  (select array_agg(k order by k) from t_export, jsonb_object_keys(data) k),
  array['blocked_users', 'chat_messages', 'conversation_reads', 'daily_activity', 'exported_at', 'feedback', 'friend_requests',
        'friends', 'group_invitations', 'group_membership_periods', 'groups', 'media', 'profile', 'reports'],
  'Export: alle Bereiche'
);
select is((select data->'profile'->>'username' from t_export), 'ina', 'Export: Profil');
select is((select data->'profile'->>'auth_user_id' from t_export), 'ad000000-0000-4000-8000-000000000001', 'Export: eigene Auth-ID');
select is((select (data->'daily_activity'->0->>'competition_steps')::int from t_export), 5000, 'Export: Tageswerte');
select is((select data->'friends'->0->>'username' from t_export), 'jan', 'Export: Freunde');
select is(
  (select array_agg(e->>'body') from t_export, jsonb_array_elements(data->'chat_messages') e),
  array['Antwort von Ina'], 'Export: nur eigene Nachrichten'
);
select is((select jsonb_array_length(data->'reports') from t_export), 10, 'Export: eigene Meldungen');
select is((select jsonb_array_length(data->'feedback') from t_export), 10, 'Export: eigene Rückmeldungen');
select is((select data->'groups'->0->>'role' from t_export), 'owner', 'Export: Gruppen mit Rolle');
select ok((select data::text not like '%jan.jpg%' from t_export), 'Export: keine Dateien anderer');

select is(
  (select array_agg(e->>'bucket' || ':' || (e->>'path') order by e->>'bucket', e->>'path') from jsonb_array_elements(public.account_own_media()) e),
  array['avatars:bd000000-0000-4000-8000-000000000001/ina.jpg', 'chat-media:dd000000-0000-4000-8000-000000000001/bild.jpg',
        'group-images:cd000000-0000-4000-8000-000000000001/von-lou.jpg'],
  'eigene Dateien inkl. Bilder eigener Gruppen'
);
select is(
  (select count(*)::int from generate_series(1, 4) n cross join lateral (select public.account_export() where n > 0) e), 4,
  'bis zu 5 Exporte je Stunde'
);
select throws_ok($$select public.account_export()$$, 'P0001', 'rate_limited', '6. Export: rate_limited');

-- =============================================================================================================
-- Konto löschen (ina)
-- =============================================================================================================

select lives_ok($$select public.account_delete()$$, 'Konto löschen');
reset role;
select ok(not exists (select 1 from auth.users where id = 'ad000000-0000-4000-8000-000000000001'), 'Auth-Nutzer gelöscht');
select ok(not exists (select 1 from public.profiles where id = 'ad000000-0000-4000-8000-000000000001'), 'Profil gelöscht');
select is(
  (select array_agg(body) from public.chat_messages where conversation_id = 'dd000000-0000-4000-8000-000000000001'),
  array['Spam von Jan'], 'eigene Nachrichten gelöscht, die des Gegenübers bleiben'
);
select is(
  (select row(user_a is null, user_b)::text from public.conversations where id = 'dd000000-0000-4000-8000-000000000001'),
  '(t,ad000000-0000-4000-8000-000000000002)', 'Privatchat bleibt für das Gegenüber erhalten'
);
select is(
  (select p.username from public.group_members m join public.profiles p on p.id = m.user_id
    where m.group_id = 'cd000000-0000-4000-8000-000000000001' and m.role = 'owner'),
  'lou', 'Gruppe: dienstältestes Mitglied wird owner'
);
select ok(
  not exists (select 1 from public.reports where reporter_id = 'ad000000-0000-4000-8000-000000000001')
  and not exists (select 1 from public.feedback where user_id = 'ad000000-0000-4000-8000-000000000001')
  and not exists (select 1 from public.daily_activity where user_id = 'ad000000-0000-4000-8000-000000000001')
  and not exists (select 1 from public.friendships where user_a = 'ad000000-0000-4000-8000-000000000001' or user_b = 'ad000000-0000-4000-8000-000000000001'),
  'Meldungen, Rückmeldungen, Tageswerte und Freundschaften gelöscht'
);

-- Ohne Profil (abgebrochenes Onboarding) und ohne Anmeldung.
set local role authenticated;
select pg_temp.as_user(5);
select lives_ok($$select public.account_delete()$$, 'Konto ohne Profil löschen');
set local request.jwt.claims = '{"role":"authenticated"}';
select throws_ok($$select public.account_delete()$$, '42501', 'not_authenticated', 'ohne Anmeldung: not_authenticated');

select * from finish();
rollback;
