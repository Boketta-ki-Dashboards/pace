-- Pace: Social – Struktur (RLS, Rechte, RPC-Konventionen) und Freundschaften.
begin;
select plan(90);

-- =============================================================================================================
-- Struktur
-- =============================================================================================================

select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relrowsecurity
      and c.relname in ('friend_requests', 'friendships', 'groups', 'group_members', 'group_membership_periods',
                        'group_goal_history', 'group_invitations')),
  array['friend_requests', 'friendships', 'group_goal_history', 'group_invitations', 'group_members',
        'group_membership_periods', 'groups'],
  'RLS auf allen Social-Tabellen aktiv'
);
select is(
  (select count(*)::int from pg_policy p
    where p.polrelid in ('public.friend_requests'::regclass, 'public.friendships'::regclass, 'public.groups'::regclass,
                         'public.group_members'::regclass, 'public.group_membership_periods'::regclass,
                         'public.group_goal_history'::regclass, 'public.group_invitations'::regclass)),
  0, 'keine Policies: Zugriff nur über RPCs'
);
select is(
  (select array_agg(format('%s %s %s', r.role_name, t.table_name, pr.privilege) order by 1)
     from unnest(array['anon', 'authenticated']) as r(role_name)
    cross join unnest(array['public.friend_requests', 'public.friendships', 'public.groups', 'public.group_members',
                            'public.group_membership_periods', 'public.group_goal_history',
                            'public.group_invitations', 'private.rate_limit_events']) as t(table_name)
    cross join unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'])
               as pr(privilege)
    where has_table_privilege(r.role_name, t.table_name, pr.privilege)),
  null, 'anon/authenticated ohne Rechte auf Social-Tabellen'
);

select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname like 'social\_%'),
  array['social_cancel_friend_request', 'social_cancel_group_invitation', 'social_create_group',
        'social_delete_group', 'social_find_profile', 'social_friend_profile', 'social_friend_ranking',
        'social_friend_requests', 'social_friends', 'social_group', 'social_group_days', 'social_group_invitations',
        'social_group_outgoing_invitations', 'social_group_ranking', 'social_invite_to_group', 'social_join_group',
        'social_leave_group', 'social_my_groups', 'social_regenerate_invite_code', 'social_remove_friend',
        'social_remove_group_member', 'social_respond_friend_request', 'social_respond_group_invitation',
        'social_send_friend_request', 'social_set_group_goal', 'social_update_group'],
  'alle 26 Social-RPCs vorhanden'
);
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname like 'social\_%'
      and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'))),
  null, 'anon/public dürfen keine Social-RPC ausführen'
);
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname like 'social\_%'
      and not has_function_privilege('authenticated', p.oid, 'execute')),
  null, 'authenticated darf alle Social-RPCs ausführen'
);
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname like 'social\_%'
      and (not p.prosecdef or p.proconfig is distinct from array['search_path=""']
           or obj_description(p.oid, 'pg_proc') is null)),
  null, 'Social-RPCs: security definer, leerer search_path, Kommentar'
);
select is(
  (select array_agg(p.oid::regprocedure::text order by 1) from pg_proc p
    where p.pronamespace = 'private'::regnamespace
      and (has_function_privilege('anon', p.oid, 'execute')
           or has_function_privilege('authenticated', p.oid, 'execute'))),
  null, 'private-Helfer für Clients nicht ausführbar'
);
select is(
  (select array_agg(p.oid::regprocedure::text order by 1) from pg_proc p
    where p.pronamespace = 'private'::regnamespace and p.proconfig is distinct from array['search_path=""']),
  null, 'private-Helfer mit leerem search_path'
);

-- =============================================================================================================
-- Testdaten
-- =============================================================================================================

-- 1 anna, 2 benjamin, 3 carla, 4 dora, 5 ohne Profil, 6 fred, 7 greta (Fremde), 8 hugo, 9 ida, 10 jonas, 11 karl,
-- 12 lena, 13 mia; 101–400 Statisten für die Limits.
insert into auth.users (id, aud, role, is_anonymous)
select ('a6000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 400) n;

insert into public.profiles (id, public_id, username, display_name)
select ('a6000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('b6000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'anna', 'Anna'), (2, 'benjamin', 'Benjamin'), (3, 'carla', 'Carla'), (4, 'dora', 'Dora'),
               (6, 'fred', 'Fred'), (7, 'greta', 'Greta'), (8, 'hugo', 'Hugo'), (9, 'ida', 'Ida'),
               (10, 'jonas', 'Jonas'), (11, 'karl', 'Karl'), (12, 'lena', 'Lena'), (13, 'mia', 'Mia')
       ) as v(n, username, display_name)
union all
select ('a6000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       ('b6000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'nutzer_' || n, 'Nutzer ' || n
  from generate_series(101, 400) n;

-- Ältere eingehende Anfrage fred → anna (für die Sortierung „neueste zuerst“).
insert into public.friend_requests (requester_id, addressee_id, created_at)
values ('a6000000-0000-4000-8000-000000000006', 'a6000000-0000-4000-8000-000000000001', now() - interval '1 hour');

-- Ergebnisse von RPCs, auf die spätere Tests zugreifen.
create temporary table t_results (name text primary key, result jsonb) on commit drop;
grant select, insert on t_results to authenticated;

-- =============================================================================================================
-- Anmeldung und Profil
-- =============================================================================================================

set local role anon;
select throws_ok($$select public.social_friends()$$, '42501', null, 'anon darf nicht ausführen');

set local role authenticated;
set local request.jwt.claims = '{"role":"authenticated"}';
select throws_ok($$select public.social_friends()$$, '42501', 'not_authenticated', 'ohne Nutzer-ID: not_authenticated');

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000005","role":"authenticated"}';
select throws_ok($$select public.social_find_profile('anna')$$, 'P0001', 'profile_required', 'ohne Profil: profile_required');

-- =============================================================================================================
-- Profilsuche (als anna)
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';

select is(public.social_find_profile('BENJAMIN')->>'username', 'benjamin', 'Suche: exakt ohne Groß-/Kleinschreibung');
select is(
  public.social_find_profile('  benjamin ')->>'public_id', 'b6000000-0000-4000-8000-000000000002',
  'Suche: getrimmt, liefert public_id'
);
select is(public.social_find_profile('benja'), null, 'Suche: kein Präfix-Treffer');
select is(public.social_find_profile('niemand'), null, 'Suche: kein Treffer → null');
select is(public.social_find_profile('be'), null, 'Suche: ungültiges Format → null');
select is(public.social_find_profile('ben%'), null, 'Suche: Platzhalter sind ungültig → null');
select is(public.social_find_profile(null), null, 'Suche: null → null');
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_find_profile('benjamin')) k),
  array['display_name', 'public_id', 'relationship', 'request_id', 'username'], 'Suche: nur öffentliche Felder'
);
select is(public.social_find_profile('benjamin')->>'relationship', 'none', 'Beziehung: none');
select is(public.social_find_profile('benjamin')->'request_id', 'null'::jsonb, 'request_id null ohne offene Anfrage');
select is(public.social_find_profile('Anna')->>'relationship', 'self', 'Beziehung: self');
select is(public.social_find_profile('fred')->>'relationship', 'incoming_request', 'Beziehung: incoming_request');
select ok(public.social_find_profile('benjamin')::text not like '%a6000000-%', 'Suche: keine Auth-IDs');

-- =============================================================================================================
-- Anfrage senden, annehmen (idempotent), Sichtbarkeit
-- =============================================================================================================

insert into t_results select 'anna_benjamin', public.social_send_friend_request('b6000000-0000-4000-8000-000000000002');
select is((select result->>'status' from t_results where name = 'anna_benjamin'), 'requested', 'Anfrage: requested');
select is(
  public.social_send_friend_request('b6000000-0000-4000-8000-000000000002'),
  jsonb_build_object('status', 'already_requested', 'request_id', (select result->'request_id' from t_results where name = 'anna_benjamin')),
  'erneut senden: already_requested mit derselben ID'
);
select is(
  public.social_find_profile('benjamin') - 'public_id' - 'username' - 'display_name',
  jsonb_build_object('relationship', 'outgoing_request', 'request_id', (select result->'request_id' from t_results where name = 'anna_benjamin')),
  'Suche: outgoing_request mit request_id'
);
select is(
  (select array_agg(e->>'direction' || ':' || (e->>'username') order by ord)
     from jsonb_array_elements(public.social_friend_requests()) with ordinality as x(e, ord)),
  array['outgoing:benjamin', 'incoming:fred'], 'offene Anfragen: Richtung, neueste zuerst'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_friend_requests()->0) k),
  array['created_at', 'direction', 'display_name', 'public_id', 'request_id', 'username'],
  'offene Anfragen: nur öffentliche Felder'
);
select throws_ok(
  format('select public.social_respond_friend_request(%L, true)', (select result->>'request_id' from t_results where name = 'anna_benjamin')),
  'P0001', 'not_found', 'Absender kann die eigene Anfrage nicht annehmen'
);

-- Fremde (greta) sehen und beantworten fremde Anfragen nicht.
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000007","role":"authenticated"}';
select throws_ok(
  format('select public.social_respond_friend_request(%L, true)', (select result->>'request_id' from t_results where name = 'anna_benjamin')),
  'P0001', 'not_found', 'Fremde: annehmen → not_found'
);
select throws_ok(
  format('select public.social_cancel_friend_request(%L)', (select result->>'request_id' from t_results where name = 'anna_benjamin')),
  'P0001', 'not_found', 'Fremde: zurückziehen → not_found'
);
select is(public.social_friend_requests(), '[]'::jsonb, 'Fremde sehen keine fremden Anfragen');

-- benjamin nimmt an – zweimal.
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  public.social_find_profile('anna')->>'relationship', 'incoming_request', 'Empfänger: incoming_request'
);
select is(
  public.social_friend_requests()->0->>'direction', 'incoming', 'Empfänger sieht die Anfrage als eingehend'
);
select is(
  public.social_respond_friend_request((select (result->>'request_id')::uuid from t_results where name = 'anna_benjamin'), true),
  '{"status": "accepted"}'::jsonb, 'annehmen: accepted'
);
select is(
  public.social_respond_friend_request((select (result->>'request_id')::uuid from t_results where name = 'anna_benjamin'), true),
  '{"status": "accepted"}'::jsonb, 'doppeltes Annehmen ist idempotent'
);
select throws_ok(
  format('select public.social_respond_friend_request(%L, false)', (select result->>'request_id' from t_results where name = 'anna_benjamin')),
  'P0001', 'not_found', 'nach dem Annehmen nicht mehr ablehnbar'
);
select throws_ok(
  format('select public.social_respond_friend_request(%L, null)', (select result->>'request_id' from t_results where name = 'anna_benjamin')),
  'P0001', 'not_found', 'ohne Antwort (null) keine Änderung'
);

reset role;
select is(
  (select count(*)::int from public.friendships
    where user_a = 'a6000000-0000-4000-8000-000000000001' and user_b = 'a6000000-0000-4000-8000-000000000002'),
  1, 'genau eine Freundschaftszeile'
);
select is(
  (select status from public.friend_requests where id = (select (result->>'request_id')::uuid from t_results where name = 'anna_benjamin')),
  'accepted', 'Anfrage ist angenommen'
);
set local role authenticated;

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(public.social_find_profile('benjamin')->>'relationship', 'friend', 'Beziehung: friend');
select is(public.social_find_profile('benjamin')->'request_id', 'null'::jsonb, 'Freund: request_id null');
select is(
  public.social_send_friend_request('b6000000-0000-4000-8000-000000000002'),
  '{"status": "already_friends", "request_id": null}'::jsonb, 'senden an Freund: already_friends'
);
select is(
  (select array_agg(e->>'username') from jsonb_array_elements(public.social_friends()) e),
  array['benjamin'], 'Freundesliste'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_friends()->0) k),
  array['display_name', 'friends_since', 'public_id', 'username'], 'Freundesliste: nur öffentliche Felder'
);
select is(
  (select array_agg(e->>'username') from jsonb_array_elements(public.social_friend_requests()) e),
  array['fred'], 'angenommene Anfrage ist nicht mehr offen'
);

-- =============================================================================================================
-- Gegenanfrage nimmt automatisch an
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000003","role":"authenticated"}';
insert into t_results select 'carla_dora', public.social_send_friend_request('b6000000-0000-4000-8000-000000000004');

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000004","role":"authenticated"}';
select is(
  public.social_send_friend_request('b6000000-0000-4000-8000-000000000003'),
  jsonb_build_object('status', 'accepted', 'request_id', (select result->'request_id' from t_results where name = 'carla_dora')),
  'Gegenanfrage: accepted mit der ID der offenen Anfrage'
);
select is(
  (select array_agg(e->>'username') from jsonb_array_elements(public.social_friends()) e),
  array['carla'], 'Gegenanfrage: Freundschaft besteht'
);

-- =============================================================================================================
-- Ablehnen, Cooldown, Zurückziehen
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
insert into t_results select 'anna_carla_1', public.social_send_friend_request('b6000000-0000-4000-8000-000000000003');

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000003","role":"authenticated"}';
select is(
  public.social_respond_friend_request((select (result->>'request_id')::uuid from t_results where name = 'anna_carla_1'), false),
  '{"status": "declined"}'::jsonb, 'ablehnen: declined'
);
select throws_ok(
  format('select public.social_respond_friend_request(%L, true)', (select result->>'request_id' from t_results where name = 'anna_carla_1')),
  'P0001', 'not_found', 'abgelehnte Anfrage ist nicht mehr offen'
);

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select throws_ok(
  $$select public.social_send_friend_request('b6000000-0000-4000-8000-000000000003')$$,
  'P0001', 'cooldown', 'nach Ablehnung 7 Tage Cooldown'
);

reset role;
update public.friend_requests set responded_at = now() - interval '8 days'
 where id = (select (result->>'request_id')::uuid from t_results where name = 'anna_carla_1');
set local role authenticated;

insert into t_results select 'anna_carla_2', public.social_send_friend_request('b6000000-0000-4000-8000-000000000003');
select is((select result->>'status' from t_results where name = 'anna_carla_2'), 'requested', 'nach dem Cooldown wieder möglich');
select lives_ok(
  format('select public.social_cancel_friend_request(%L)', (select result->>'request_id' from t_results where name = 'anna_carla_2')),
  'zurückziehen'
);
select throws_ok(
  format('select public.social_cancel_friend_request(%L)', (select result->>'request_id' from t_results where name = 'anna_carla_2')),
  'P0001', 'not_found', 'zweites Zurückziehen → not_found'
);
select is(public.social_find_profile('carla')->>'relationship', 'none', 'nach dem Zurückziehen: none');

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000003","role":"authenticated"}';
select throws_ok(
  format('select public.social_respond_friend_request(%L, true)', (select result->>'request_id' from t_results where name = 'anna_carla_2')),
  'P0001', 'not_found', 'zurückgezogene Anfrage nicht annehmbar'
);

-- =============================================================================================================
-- Fehlerfälle und Entfernen
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select throws_ok(
  $$select public.social_send_friend_request('b6000000-0000-4000-8000-000000000001')$$,
  'P0001', 'self_request', 'Anfrage an sich selbst'
);
select throws_ok(
  $$select public.social_send_friend_request('b6000000-0000-4000-8000-00000000ffff')$$,
  'P0001', 'not_found', 'unbekannte public_id'
);
select throws_ok(
  $$select public.social_remove_friend('b6000000-0000-4000-8000-000000000007')$$,
  'P0001', 'not_found', 'Entfernen ohne Freundschaft → not_found'
);
select lives_ok($$select public.social_remove_friend('b6000000-0000-4000-8000-000000000002')$$, 'Freund entfernen');
select throws_ok(
  $$select public.social_remove_friend('b6000000-0000-4000-8000-000000000002')$$,
  'P0001', 'not_found', 'zweites Entfernen → not_found'
);
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(public.social_friends(), '[]'::jsonb, 'Entfernen gilt für beide Seiten');

-- =============================================================================================================
-- Limits
-- =============================================================================================================

-- Rate-Limit: 20 neue Anfragen je 24 h (lena).
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000012","role":"authenticated"}';
do $$
begin
  for i in 101..120 loop
    perform public.social_send_friend_request(('b6000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid);
  end loop;
end
$$;
select is(
  (select count(*)::int from jsonb_array_elements(public.social_friend_requests())), 20, '20 Anfragen gesendet'
);
select throws_ok(
  $$select public.social_send_friend_request('b6000000-0000-4000-8000-000000000121')$$,
  'P0001', 'rate_limited', '21. Anfrage in 24 h: rate_limited'
);

-- Offene ausgehende Anfragen: max. 50 (karl).
reset role;
insert into public.friend_requests (requester_id, addressee_id)
select 'a6000000-0000-4000-8000-000000000011', ('a6000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
  from generate_series(151, 200) n;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000011","role":"authenticated"}';
select throws_ok(
  $$select public.social_send_friend_request('b6000000-0000-4000-8000-000000000201')$$,
  'P0001', 'limit_reached', 'mehr als 50 offene Anfragen: limit_reached'
);

-- Max. 200 Freunde, für beide Seiten geprüft (hugo hat 200 Freunde).
reset role;
insert into public.friendships (user_a, user_b)
select least('a6000000-0000-4000-8000-000000000008'::uuid, u), greatest('a6000000-0000-4000-8000-000000000008'::uuid, u)
  from (select ('a6000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as u from generate_series(201, 400) n) s;
insert into public.friend_requests (requester_id, addressee_id) values
  ('a6000000-0000-4000-8000-000000000009', 'a6000000-0000-4000-8000-000000000008'),  -- ida → hugo
  ('a6000000-0000-4000-8000-000000000008', 'a6000000-0000-4000-8000-000000000010');  -- hugo → jonas
insert into t_results
select 'ida_hugo', jsonb_build_object('request_id', id) from public.friend_requests
 where requester_id = 'a6000000-0000-4000-8000-000000000009' and status = 'pending'
union all
select 'hugo_jonas', jsonb_build_object('request_id', id) from public.friend_requests
 where requester_id = 'a6000000-0000-4000-8000-000000000008' and status = 'pending';
set local role authenticated;

set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000008","role":"authenticated"}';
select throws_ok(
  format('select public.social_respond_friend_request(%L, true)', (select result->>'request_id' from t_results where name = 'ida_hugo')),
  'P0001', 'limit_reached', 'Empfänger mit 200 Freunden: limit_reached'
);
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000010","role":"authenticated"}';
select throws_ok(
  format('select public.social_respond_friend_request(%L, true)', (select result->>'request_id' from t_results where name = 'hugo_jonas')),
  'P0001', 'limit_reached', 'Absender mit 200 Freunden: limit_reached'
);
select is(
  public.social_friend_requests()->0->>'username', 'hugo', 'Anfrage bleibt nach limit_reached offen'
);

-- Profilsuche: max. 30 Suchen je 10 Minuten (mia).
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000013","role":"authenticated"}';
do $$
begin
  for i in 1..30 loop
    perform public.social_find_profile('anna');
  end loop;
end
$$;
select throws_ok($$select public.social_find_profile('anna')$$, 'P0001', 'rate_limited', '31. Suche: rate_limited');
select throws_ok($$select public.social_find_profile('x')$$, 'P0001', 'rate_limited', 'auch ungültige Suchen zählen');

-- =============================================================================================================
-- Freundesranking und Freundesprofil
-- =============================================================================================================

reset role;
-- Stichtag: Freitag der Vorwoche (3–10 Tage zurück, im erlaubten Fenster).
create temporary table t_dates on commit drop as
select monday, monday + 4 as stichtag, utc_today
  from (select date_trunc('week', ((now() at time zone 'utc')::date - 7)::timestamp)::date as monday,
               (now() at time zone 'utc')::date as utc_today) d;
grant select on t_dates to authenticated;

-- anna ist mit benjamin, carla, dora und fred befreundet; greta ist Fremde.
insert into public.friendships (user_a, user_b) values
  ('a6000000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-000000000002'),
  ('a6000000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-000000000003'),
  ('a6000000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-000000000004'),
  ('a6000000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-000000000006');

insert into public.daily_activity (user_id, activity_date, competition_steps)
select ('a6000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid, d.monday + v.day_offset, v.steps
  from t_dates d,
       (values (1, 4, 8000),     -- anna, Freitag
               (1, 0, 10000),    -- anna, Montag
               (2, 4, 12000),    -- benjamin
               (2, -1, 99999),   -- benjamin, Sonntag der Woche davor
               (3, 4, 8000),     -- carla (Gleichstand mit anna, hatte den Wert früher)
               (6, 4, 0),        -- fred mit Tageswert 0; dora ohne Tageswert
               (7, 4, 50000)     -- greta, keine Freundin
       ) as v(n, day_offset, steps);

alter table public.daily_activity disable trigger daily_activity_maintain_timestamps;
update public.daily_activity set steps_changed_at = (select stichtag from t_dates) + time '08:00'
 where user_id = 'a6000000-0000-4000-8000-000000000003' and activity_date = (select stichtag from t_dates);
update public.daily_activity set steps_changed_at = (select stichtag from t_dates) + time '09:00'
 where user_id = 'a6000000-0000-4000-8000-000000000001' and activity_date = (select stichtag from t_dates);
alter table public.daily_activity enable trigger daily_activity_maintain_timestamps;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';

select is(
  (select array_agg(e->>'username' || ':' || (e->>'competition_steps') order by (e->>'rank')::int)
     from jsonb_array_elements(public.social_friend_ranking('daily', (select stichtag from t_dates))->'entries') e),
  array['benjamin:12000', 'carla:8000', 'anna:8000', 'fred:0', 'dora:0'],
  'Tagesranking: Schritte, Gleichstand nach Zeitpunkt, ohne Tageswert zuletzt'
);
select is(
  (public.social_friend_ranking('daily', (select stichtag from t_dates))->>'total_participants')::int, 5,
  'Teilnehmer: ich und alle Freunde, Fremde nicht'
);
select is(
  (select array_agg(e->>'username') from jsonb_array_elements(public.social_friend_ranking('daily', (select stichtag from t_dates))->'entries') e
    where (e->>'is_current_user')::boolean),
  array['anna'], 'genau der eigene Eintrag markiert'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_friend_ranking('daily', (select stichtag from t_dates))) k),
  array['entries', 'total_participants'], 'Antwort wie leaderboard_page'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_friend_ranking('daily', (select stichtag from t_dates))->'entries'->0) k),
  array['competition_steps', 'display_name', 'is_current_user', 'public_user_id', 'rank', 'username'],
  'Einträge wie leaderboard_page'
);
select is(
  (select array_agg(e->>'username' || ':' || (e->>'competition_steps') order by (e->>'rank')::int)
     from jsonb_array_elements(public.social_friend_ranking('weekly', (select stichtag from t_dates))->'entries') e),
  array['anna:18000', 'benjamin:12000', 'carla:8000', 'fred:0', 'dora:0'],
  'Wochenranking: Summe der ISO-Woche, Vorwoche zählt nicht'
);
select ok(
  public.social_friend_ranking('daily', (select stichtag from t_dates))::text not like '%a6000000-%',
  'Ranking: keine Auth-IDs'
);
select throws_ok(
  $$select public.social_friend_ranking('daily', (select utc_today - 15 from t_dates))$$,
  'P0001', 'invalid_date', 'Stichtag älter als 14 Tage'
);
select throws_ok(
  $$select public.social_friend_ranking('daily', (select utc_today + 2 from t_dates))$$,
  'P0001', 'invalid_date', 'Stichtag übermorgen'
);
select lives_ok($$select public.social_friend_ranking('weekly', (select utc_today from t_dates))$$, 'heute erlaubt');
select throws_ok(
  $$select public.social_friend_ranking('monthly', (select stichtag from t_dates))$$,
  'P0001', 'invalid_period', 'unbekannter Zeitraum'
);

select is(
  public.social_friend_profile('b6000000-0000-4000-8000-000000000002', (select stichtag from t_dates)) - 'friends_since',
  '{"public_id": "b6000000-0000-4000-8000-000000000002", "username": "benjamin", "display_name": "Benjamin", "steps_today": 12000, "steps_week": 12000}'::jsonb,
  'Freundesprofil: Tag und ISO-Woche'
);
select ok(
  public.social_friend_profile('b6000000-0000-4000-8000-000000000002', (select stichtag from t_dates))->>'friends_since' is not null,
  'Freundesprofil: friends_since'
);
select is(
  public.social_friend_profile('b6000000-0000-4000-8000-000000000004', (select stichtag from t_dates))->>'steps_today',
  '0', 'Freundesprofil: ohne Tageswert 0'
);
select throws_ok(
  $$select public.social_friend_profile('b6000000-0000-4000-8000-000000000007', (select stichtag from t_dates))$$,
  'P0001', 'not_found', 'Freundesprofil nur für Freunde'
);
select throws_ok(
  $$select public.social_friend_profile('b6000000-0000-4000-8000-000000000001', (select stichtag from t_dates))$$,
  'P0001', 'not_found', 'eigenes Profil ist kein Freundesprofil'
);
select throws_ok(
  $$select public.social_friend_profile('b6000000-0000-4000-8000-000000000002', (select utc_today - 15 from t_dates))$$,
  'P0001', 'invalid_date', 'Freundesprofil: Datumsfenster'
);

-- Sicht eines Freundes: nur er selbst und seine Freunde.
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  (select array_agg(e->>'username' order by (e->>'rank')::int)
     from jsonb_array_elements(public.social_friend_ranking('daily', (select stichtag from t_dates))->'entries') e),
  array['benjamin', 'anna'], 'Ranking aus Sicht von benjamin'
);

reset role;
select * from finish();
rollback;
