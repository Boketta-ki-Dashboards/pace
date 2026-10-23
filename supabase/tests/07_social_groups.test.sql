-- Pace: Social – Gruppen: Erstellen, Beitritt per Code, Rechte, Limits, Eigentümerwechsel, Einladungen, Ranking.
begin;
select plan(127);

-- 1 olga, 2 paul, 3 quinn, 4 rosa, 5 sven, 6 tina (Fremde), 7 uwe, 8 vera, 9 willi, 10 xaver, 11 yara, 12 zoe;
-- 101–199 Statisten für die Limits.
insert into auth.users (id, aud, role, is_anonymous)
select ('a7000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 199) n;

insert into public.profiles (id, public_id, username, display_name)
select ('a7000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('b7000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'olga', 'Olga'), (2, 'paul', 'Paul'), (3, 'quinn', 'Quinn'), (4, 'rosa', 'Rosa'),
               (5, 'sven', 'Sven'), (6, 'tina', 'Tina'), (7, 'uwe', 'Uwe'), (8, 'vera', 'Vera'),
               (9, 'willi', 'Willi'), (10, 'xaver', 'Xaver'), (11, 'yara', 'Yara'), (12, 'zoe', 'Zoe')
       ) as v(n, username, display_name)
union all
select ('a7000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       ('b7000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'statist_' || n, 'Statist ' || n
  from generate_series(101, 199) n;

-- Freundschaften für Einladungen: olga–paul, olga–sven, olga–willi, olga–uwe, paul–sven, paul–quinn, sven–uwe,
-- xaver–150.
insert into public.friendships (user_a, user_b)
select least(a, b), greatest(a, b)
  from (values (1, 2), (1, 5), (1, 9), (1, 7), (2, 5), (2, 3), (5, 7), (10, 150)) as v(x, y),
       lateral (select ('a7000000-0000-4000-8000-' || lpad(v.x::text, 12, '0'))::uuid as a,
                       ('a7000000-0000-4000-8000-' || lpad(v.y::text, 12, '0'))::uuid as b) ids;

-- Ergebnisse von RPCs, auf die spätere Tests zugreifen.
create temporary table t_results (name text primary key, result jsonb) on commit drop;
grant select, insert on t_results to authenticated;
create function pg_temp.result(p_name text) returns jsonb language sql stable as $$
  select r.result from t_results r where r.name = p_name;
$$;
create function pg_temp.group_id(p_name text) returns uuid language sql stable as $$
  select (coalesce(r.result->'group', r.result)->>'group_id')::uuid from t_results r where r.name = p_name;
$$;

-- =============================================================================================================
-- Erstellen und Validierung (olga)
-- =============================================================================================================

set local role authenticated;
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}';

select throws_ok($$select public.social_create_group('ab', '', 'club', 10000, null)$$, 'P0001', 'invalid_name', 'Name zu kurz');
select throws_ok($$select public.social_create_group('   ', '', 'club', 10000, null)$$, 'P0001', 'invalid_name', 'Name nur Leerzeichen');
select throws_ok($$select public.social_create_group(repeat('a', 41), '', 'club', 10000, null)$$, 'P0001', 'invalid_name', 'Name zu lang');
select throws_ok($$select public.social_create_group(E'Lauf\u200Btreff', '', 'club', 10000, null)$$, 'P0001', 'invalid_name', 'Name mit unsichtbarem Zeichen');
select throws_ok($$select public.social_create_group(E'Lauf\ttreff', '', 'club', 10000, null)$$, 'P0001', 'invalid_name', 'Name mit Steuerzeichen');
select throws_ok($$select public.social_create_group(null, '', 'club', 10000, null)$$, 'P0001', 'invalid_name', 'Name fehlt');
select throws_ok($$select public.social_create_group('Lauftreff', repeat('x', 201), 'club', 10000, null)$$, 'P0001', 'invalid_description', 'Beschreibung zu lang');
select throws_ok($$select public.social_create_group('Lauftreff', E'mit\tTab', 'club', 10000, null)$$, 'P0001', 'invalid_description', 'Beschreibung mit Steuerzeichen');
select throws_ok($$select public.social_create_group('Lauftreff', E'Rich\u202Etung', 'club', 10000, null)$$, 'P0001', 'invalid_description', 'Beschreibung mit Richtungswechsel');
select throws_ok($$select public.social_create_group('Lauftreff', '', 'school', 10000, null)$$, 'P0001', 'invalid_kind', 'unbekannte Art');
select throws_ok($$select public.social_create_group('Lauftreff', '', null, 10000, null)$$, 'P0001', 'invalid_kind', 'Art fehlt');
select throws_ok($$select public.social_create_group('Lauftreff', '', 'club', 999, null)$$, 'P0001', 'invalid_goal', 'Ziel unter 1000');
select throws_ok($$select public.social_create_group('Lauftreff', '', 'club', 100001, null)$$, 'P0001', 'invalid_goal', 'Ziel über 100000');
select throws_ok($$select public.social_create_group('Lauftreff', '', 'club', null, null)$$, 'P0001', 'invalid_goal', 'Ziel fehlt');
select throws_ok($$select public.social_create_group('Lauftreff', '', 'club', 10000, 'Mars/Olympus')$$, 'P0001', 'invalid_time_zone', 'unbekannte Zeitzone');

insert into t_results
select 'g1', public.social_create_group('  Lauftreff Nord  ', E'Jeden Morgen\nam See', 'club', 10000, null);

select is(
  (select array_agg(k order by k) from jsonb_object_keys(pg_temp.result('g1')) k),
  array['best_streak', 'created_at', 'current_streak', 'daily_goal', 'description', 'group_id', 'group_today',
        'image_path', 'invite_code', 'kind', 'member_count', 'name', 'next_daily_goal', 'privacy', 'role',
        'time_zone', 'today_complete', 'today_reached_count', 'today_required_count'],
  'summary: genau die vereinbarten Felder'
);
select is(
  pg_temp.result('g1') - 'group_id' - 'invite_code' - 'created_at' - 'group_today',
  jsonb_build_object(
    'name', 'Lauftreff Nord', 'description', E'Jeden Morgen\nam See', 'kind', 'club', 'role', 'owner',
    'member_count', 1, 'daily_goal', 10000, 'next_daily_goal', null, 'time_zone', 'Europe/Berlin',
    'current_streak', 0, 'best_streak', 0, 'today_reached_count', 0, 'today_required_count', 1,
    'today_complete', false, 'image_path', null, 'privacy', 'code'
  ),
  'erstellt: Name getrimmt, Zeitzone Standard Europe/Berlin, Ersteller ist owner'
);
select is(
  (pg_temp.result('g1')->>'group_today')::date, (now() at time zone 'Europe/Berlin')::date,
  'group_today = heute in der Gruppenzeitzone'
);
select matches(pg_temp.result('g1')->>'invite_code', '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$', 'Einladungscode: 8 Zeichen');
select ok(pg_temp.result('g1')::text not like '%a7000000-%', 'summary: keine Auth-IDs');
select is(
  public.social_create_group('Pazifik', '', 'other', 5000, 'Pacific/Kiritimati')->>'time_zone',
  'Pacific/Kiritimati', 'Zeitzone übernommen'
);

-- =============================================================================================================
-- Beitritt per Code
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  (select r->>'role' || ':' || (r->>'member_count')
     from (select public.social_join_group(
             ' ' || lower(substr(pg_temp.result('g1')->>'invite_code', 1, 4)) || '-'
                 || lower(substr(pg_temp.result('g1')->>'invite_code', 5)) || ' ') as r) j),
  'member:2', 'Beitritt: Code normalisiert (Kleinbuchstaben, Leerzeichen, Bindestrich)'
);
select is(
  (select r->>'role' || ':' || (r->>'member_count')
     from (select public.social_join_group(pg_temp.result('g1')->>'invite_code') as r) j),
  'member:2', 'erneuter Beitritt ist idempotent'
);

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000003","role":"authenticated"}';
select is(
  public.social_join_group('ZZZZ-ZZZZ'),
  '{"code": "P0001", "message": "invalid_invite_code", "details": null, "hint": null}'::jsonb,
  'falscher Code: invalid_invite_code (PostgREST-Fehlerformat)'
);
select is(current_setting('response.status', true), '400', 'falscher Code: HTTP 400');
select throws_ok(format('select public.social_group(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'falscher Code tritt nicht bei');

-- Versuchslimit: 20 je Stunde, auch Fehlversuche zählen (hier 1 + 19), danach scheitert sogar der richtige Code.
do $$
begin
  for i in 1..19 loop
    perform public.social_join_group('ABCD2345');
  end loop;
end
$$;
select throws_ok(
  format('select public.social_join_group(%L)', pg_temp.result('g1')->>'invite_code'),
  'P0001', 'rate_limited', '21. Beitrittsversuch: rate_limited'
);
reset role;
select is(
  (select count(*)::int from private.rate_limit_events
    where user_id = 'a7000000-0000-4000-8000-000000000003' and action = 'group_join'),
  20, 'Fehlversuche bleiben gezählt'
);
delete from private.rate_limit_events where action = 'group_join';
set local role authenticated;

-- =============================================================================================================
-- Nichtmitglieder sehen nichts (tina)
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000006","role":"authenticated"}';
select throws_ok(format('select public.social_group(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'Nichtmitglied: summary');
select throws_ok(format('select public.social_group_ranking(%L, %L)', pg_temp.group_id('g1'), 'daily'), 'P0001', 'not_found', 'Nichtmitglied: Ranking');
select throws_ok(format('select public.social_group_days(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'Nichtmitglied: Gruppentage');
select throws_ok(format('select public.social_group_outgoing_invitations(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'Nichtmitglied: Einladungen');
select throws_ok(format('select public.social_invite_to_group(%L, %L)', pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000005'), 'P0001', 'not_found', 'Nichtmitglied: einladen');
select throws_ok(format('select public.social_leave_group(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'Nichtmitglied: verlassen');
select throws_ok(format('select public.social_update_group(%L, %L, null, null)', pg_temp.group_id('g1'), 'Gekapert'), 'P0001', 'not_found', 'Nichtmitglied: ändern');
select throws_ok(format('select public.social_set_group_goal(%L, 5000)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'Nichtmitglied: Ziel');
select throws_ok(format('select public.social_regenerate_invite_code(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'Nichtmitglied: Code');
select throws_ok(format('select public.social_delete_group(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'Nichtmitglied: löschen');
select throws_ok(format('select public.social_remove_group_member(%L, %L)', pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000002'), 'P0001', 'not_found', 'Nichtmitglied: entfernen');
select throws_ok($$select public.social_group('c7000000-0000-4000-8000-000000000000')$$, 'P0001', 'not_found', 'unbekannte Gruppe: ebenfalls not_found');
select ok(public.social_my_groups()::text not like '%Lauftreff%', 'Nichtmitglied: nicht in eigenen Gruppen');

-- =============================================================================================================
-- Nur der Eigentümer darf ändern (paul ist Mitglied)
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000002","role":"authenticated"}';
select throws_ok(format('select public.social_update_group(%L, %L, null, null)', pg_temp.group_id('g1'), 'Neu'), 'P0001', 'not_allowed', 'Mitglied: ändern');
select throws_ok(format('select public.social_set_group_goal(%L, 5000)', pg_temp.group_id('g1')), 'P0001', 'not_allowed', 'Mitglied: Ziel');
select throws_ok(format('select public.social_regenerate_invite_code(%L)', pg_temp.group_id('g1')), 'P0001', 'not_allowed', 'Mitglied: Code');
select throws_ok(format('select public.social_delete_group(%L)', pg_temp.group_id('g1')), 'P0001', 'not_allowed', 'Mitglied: löschen');
select throws_ok(format('select public.social_remove_group_member(%L, %L)', pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000001'), 'P0001', 'not_allowed', 'Mitglied: entfernen');
select is(public.social_group(pg_temp.group_id('g1'))->>'role', 'member', 'Mitglied sieht summary mit Rolle member');

-- =============================================================================================================
-- Eigentümer ändert Gruppe, Ziel und Code
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(
  (select r->>'name' || '|' || (r->>'description') || '|' || (r->>'kind')
     from (select public.social_update_group(pg_temp.group_id('g1'), ' Lauftreff Süd ', null, 'friends') as r) u),
  E'Lauftreff Süd|Jeden Morgen\nam See|friends', 'ändern: null lässt die Beschreibung unverändert'
);
select is(
  public.social_update_group(pg_temp.group_id('g1'), null, '', null)->>'description', '', 'Beschreibung leeren'
);
select throws_ok(format('select public.social_update_group(%L, %L, null, null)', pg_temp.group_id('g1'), 'x'), 'P0001', 'invalid_name', 'ändern: ungültiger Name');
select throws_ok(format('select public.social_update_group(%L, null, null, %L)', pg_temp.group_id('g1'), 'firma'), 'P0001', 'invalid_kind', 'ändern: ungültige Art');
select is(
  (select r->>'daily_goal' || ':' || (r->>'next_daily_goal')
     from (select public.social_set_group_goal(pg_temp.group_id('g1'), 12000) as r) s),
  '10000:12000', 'Zieländerung gilt erst ab morgen'
);
select throws_ok(format('select public.social_set_group_goal(%L, 500)', pg_temp.group_id('g1')), 'P0001', 'invalid_goal', 'ungültiges Ziel');
select is(
  public.social_set_group_goal(pg_temp.group_id('g1'), 10000)->'next_daily_goal', 'null'::jsonb,
  'gleiches Ziel für morgen: kein abweichendes next_daily_goal'
);

insert into t_results select 'g1_new_code', public.social_regenerate_invite_code(pg_temp.group_id('g1'));
select isnt(
  pg_temp.result('g1_new_code')->>'invite_code', pg_temp.result('g1')->>'invite_code', 'neuer Einladungscode'
);

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000004","role":"authenticated"}';
select is(
  public.social_join_group(pg_temp.result('g1')->>'invite_code')->>'message', 'invalid_invite_code',
  'alter Code ist ungültig'
);
select is(
  public.social_join_group(pg_temp.result('g1_new_code')->>'invite_code')->>'member_count', '3',
  'Beitritt mit neuem Code'
);

-- =============================================================================================================
-- Gruppenranking (olga, paul, rosa)
-- =============================================================================================================

reset role;
create temporary table t_dates on commit drop as
select today, monday, case when today = monday then monday + 1 else monday end as other_day
  from (select (now() at time zone 'Europe/Berlin')::date as today,
               date_trunc('week', (now() at time zone 'Europe/Berlin')::date::timestamp)::date as monday) d;
grant select on t_dates to authenticated;

insert into public.daily_activity (user_id, activity_date, competition_steps)
select v.user_id::uuid, v.day, v.steps
  from t_dates d,
       lateral (values ('a7000000-0000-4000-8000-000000000001', d.today, 11000),
                       ('a7000000-0000-4000-8000-000000000002', d.today, 9000),
                       ('a7000000-0000-4000-8000-000000000002', d.other_day, 5000),
                       ('a7000000-0000-4000-8000-000000000006', d.today, 50000)) as v(user_id, day, steps);
set local role authenticated;

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  (select array_agg(e->>'username' || ':' || (e->>'competition_steps') || ':' || (e->>'role') || ':' || (e->>'reached_goal_today')
                    order by (e->>'rank')::int)
     from jsonb_array_elements(public.social_group_ranking(pg_temp.group_id('g1'), 'daily')->'entries') e),
  array['olga:11000:owner:true', 'paul:9000:member:false', 'rosa:0:member:false'],
  'Tagesranking: alle aktuellen Mitglieder, Rolle, Ziel erreicht'
);
select is(
  public.social_group_ranking(pg_temp.group_id('g1'), 'daily') - 'entries',
  jsonb_build_object('total_participants', 3, 'group_today', (select today from t_dates), 'daily_goal', 10000),
  'Ranking: Teilnehmerzahl, Gruppentag, Tagesziel'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_group_ranking(pg_temp.group_id('g1'), 'daily')->'entries'->0) k),
  array['avatar_path', 'competition_steps', 'display_name', 'is_current_user', 'nickname', 'public_user_id', 'rank',
        'reached_goal_today', 'role', 'username'],
  'Ranking-Einträge: nur öffentliche Felder'
);
select is(
  (select array_agg(e->>'username' || ':' || (e->>'competition_steps') || ':' || (e->>'reached_goal_today')
                    order by (e->>'rank')::int)
     from jsonb_array_elements(public.social_group_ranking(pg_temp.group_id('g1'), 'weekly')->'entries') e),
  array['paul:14000:false', 'olga:11000:true', 'rosa:0:false'],
  'Wochenranking: ISO-Woche des Gruppentags, Ziel weiterhin für heute'
);
select is(
  (select array_agg(e->>'username') from jsonb_array_elements(public.social_group_ranking(pg_temp.group_id('g1'), 'daily')->'entries') e
    where (e->>'is_current_user')::boolean),
  array['paul'], 'eigener Eintrag markiert'
);
select throws_ok(format('select public.social_group_ranking(%L, %L)', pg_temp.group_id('g1'), 'monthly'), 'P0001', 'invalid_period', 'Ranking: unbekannter Zeitraum');

-- =============================================================================================================
-- Einladungen
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}';
select throws_ok(format('select public.social_invite_to_group(%L, %L)', pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000006'), 'P0001', 'not_found', 'nur Freunde einladbar');
select is(
  public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000002'),
  '{"status": "already_member", "invitation_id": null}'::jsonb, 'Mitglied: already_member'
);
select is(
  public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000001')->>'status',
  'already_member', 'sich selbst: already_member'
);
insert into t_results select 'inv_sven', public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000005');
select is(pg_temp.result('inv_sven')->>'status', 'invited', 'Freund eingeladen');
select is(
  public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000005'),
  jsonb_build_object('status', 'already_invited', 'invitation_id', pg_temp.result('inv_sven')->'invitation_id'),
  'erneut: already_invited'
);

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000005')->>'status',
  'already_invited', 'andere Person, gleiche Einladung: already_invited'
);
insert into t_results select 'inv_quinn', public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000003');
select is(pg_temp.result('inv_quinn')->>'status', 'invited', 'Mitglied lädt eigenen Freund ein');
select is(
  (select array_agg(e->>'username') from jsonb_array_elements(public.social_group_outgoing_invitations(pg_temp.group_id('g1'))) e),
  array['quinn'], 'Mitglied sieht nur eigene Einladungen'
);

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(
  (select array_agg(e->>'username' order by e->>'username') from jsonb_array_elements(public.social_group_outgoing_invitations(pg_temp.group_id('g1'))) e),
  array['quinn', 'sven'], 'Eigentümer sieht alle offenen Einladungen'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_group_outgoing_invitations(pg_temp.group_id('g1'))->0) k),
  array['avatar_path', 'created_at', 'display_name', 'invitation_id', 'nickname', 'public_id', 'username'], 'ausgehende Einladungen: Felder'
);

-- sven lehnt ab, wird erneut eingeladen und nimmt an.
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000005","role":"authenticated"}';
select is(
  public.social_group_invitations() #- '{0,invitation_id}' #- '{0,group_id}' #- '{0,created_at}',
  '[{"group_name": "Lauftreff Süd", "group_kind": "friends", "group_image_path": null, "group_privacy": "code", "member_count": 3, "inviter_public_id": "b7000000-0000-4000-8000-000000000001", "inviter_username": "olga", "inviter_display_name": "Olga", "inviter_avatar_path": null, "inviter_nickname": null}]'::jsonb,
  'eingehende Einladung mit Gruppe und einladender Person'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.social_group_invitations()->0) k),
  array['created_at', 'group_id', 'group_image_path', 'group_kind', 'group_name', 'group_privacy',
        'invitation_id', 'inviter_avatar_path', 'inviter_display_name', 'inviter_nickname', 'inviter_public_id',
        'inviter_username', 'member_count'],
  'eingehende Einladungen: Felder'
);
select is(
  public.social_respond_group_invitation((pg_temp.result('inv_sven')->>'invitation_id')::uuid, false),
  '{"status": "declined", "group": null}'::jsonb, 'ablehnen: declined ohne Gruppe'
);
select throws_ok(format('select public.social_respond_group_invitation(%L, true)', pg_temp.result('inv_sven')->>'invitation_id'), 'P0001', 'not_found', 'abgelehnte Einladung nicht mehr offen');
select is(public.social_group_invitations(), '[]'::jsonb, 'keine offenen Einladungen mehr');

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}';
insert into t_results select 'inv_sven_2', public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000005');
select is(pg_temp.result('inv_sven_2')->>'status', 'invited', 'nach Ablehnung erneut einladbar');

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000006","role":"authenticated"}';
select throws_ok(format('select public.social_respond_group_invitation(%L, true)', pg_temp.result('inv_sven_2')->>'invitation_id'), 'P0001', 'not_found', 'fremde Einladung nicht annehmbar');
select throws_ok(format('select public.social_cancel_group_invitation(%L)', pg_temp.result('inv_sven_2')->>'invitation_id'), 'P0001', 'not_found', 'fremde Einladung nicht zurückziehbar');

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000005","role":"authenticated"}';
insert into t_results select 'sven_accept', public.social_respond_group_invitation((pg_temp.result('inv_sven_2')->>'invitation_id')::uuid, true);
select is(
  (select r->>'status' || ':' || (r->'group'->>'role') || ':' || (r->'group'->>'member_count')
     from (select pg_temp.result('sven_accept') as r) x),
  'accepted:member:4', 'annehmen: accepted mit summary'
);
select throws_ok(format('select public.social_respond_group_invitation(%L, true)', pg_temp.result('inv_sven_2')->>'invitation_id'), 'P0001', 'not_found', 'angenommene Einladung nicht mehr offen');

-- Zurückziehen: Fremdes Mitglied darf nicht, Eigentümer und Einladender dürfen.
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000004","role":"authenticated"}';
select throws_ok(format('select public.social_cancel_group_invitation(%L)', pg_temp.result('inv_quinn')->>'invitation_id'), 'P0001', 'not_found', 'anderes Mitglied darf nicht zurückziehen');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}';
select lives_ok(format('select public.social_cancel_group_invitation(%L)', pg_temp.result('inv_quinn')->>'invitation_id'), 'Eigentümer zieht zurück');
select throws_ok(format('select public.social_cancel_group_invitation(%L)', pg_temp.result('inv_quinn')->>'invitation_id'), 'P0001', 'not_found', 'zweites Zurückziehen → not_found');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000002","role":"authenticated"}';
insert into t_results select 'inv_quinn_2', public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000003');
select lives_ok(format('select public.social_cancel_group_invitation(%L)', pg_temp.result('inv_quinn_2')->>'invitation_id'), 'Einladender zieht zurück');

-- Beitritt per Code nimmt eine offene Einladung an.
insert into t_results select 'inv_quinn_3', public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000003');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000003","role":"authenticated"}';
select is(
  public.social_join_group(pg_temp.result('g1_new_code')->>'invite_code')->>'member_count', '5', 'quinn tritt per Code bei'
);
reset role;
select is(
  (select status from public.group_invitations where id = (pg_temp.result('inv_quinn_3')->>'invitation_id')::uuid),
  'accepted', 'Beitritt per Code: offene Einladung ist angenommen'
);
set local role authenticated;

-- Endet die Freundschaft, werden offene Einladungen zwischen beiden zurückgezogen.
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}';
insert into t_results select 'inv_willi', public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000009');
select lives_ok($$select public.social_remove_friend('b7000000-0000-4000-8000-000000000009')$$, 'Freundschaft olga–willi beendet');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000009","role":"authenticated"}';
select is(public.social_group_invitations(), '[]'::jsonb, 'Einladung nach Ende der Freundschaft zurückgezogen');

-- =============================================================================================================
-- Austritt mit Eigentümerwechsel, Entfernen, letzte Person, Profillöschung, Löschen
-- =============================================================================================================

-- Beitrittsreihenfolge: rosa vor paul vor sven vor quinn (rosa hat die größere ID als paul).
reset role;
update public.group_members set joined_at = now() - interval '3 days'
 where group_id = pg_temp.group_id('g1') and user_id = 'a7000000-0000-4000-8000-000000000004';
update public.group_members set joined_at = now() - interval '2 days'
 where group_id = pg_temp.group_id('g1') and user_id = 'a7000000-0000-4000-8000-000000000002';
update public.group_members set joined_at = now() - interval '1 day'
 where group_id = pg_temp.group_id('g1') and user_id = 'a7000000-0000-4000-8000-000000000005';
set local role authenticated;

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(
  public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000007')->>'status', 'invited',
  'olga lädt uwe ein'
);
select lives_ok(format('select public.social_leave_group(%L)', pg_temp.group_id('g1')), 'Eigentümer verlässt die Gruppe');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000007","role":"authenticated"}';
select is(public.social_group_invitations(), '[]'::jsonb, 'Austritt zieht die offenen Einladungen der Person zurück');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}';
select throws_ok(format('select public.social_group(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'nach dem Austritt nicht mehr sichtbar');
select throws_ok(format('select public.social_leave_group(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'zweiter Austritt → not_found');

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000004","role":"authenticated"}';
select is(
  (select r->>'role' || ':' || (r->>'member_count') from (select public.social_group(pg_temp.group_id('g1')) as r) x),
  'owner:4', 'am längsten beigetretenes Mitglied wird Eigentümer'
);
select throws_ok(format('select public.social_remove_group_member(%L, %L)', pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000004'), 'P0001', 'not_allowed', 'Eigentümer kann sich nicht selbst entfernen');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000005","role":"authenticated"}';
select is(
  public.social_invite_to_group(pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000007')->>'status', 'invited',
  'sven lädt uwe ein'
);
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000004","role":"authenticated"}';
select lives_ok(format('select public.social_remove_group_member(%L, %L)', pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000005'), 'Mitglied entfernen');
select throws_ok(format('select public.social_remove_group_member(%L, %L)', pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-000000000005'), 'P0001', 'not_found', 'Nichtmitglied entfernen → not_found');
select throws_ok(format('select public.social_remove_group_member(%L, %L)', pg_temp.group_id('g1'), 'b7000000-0000-4000-8000-00000000ffff'), 'P0001', 'not_found', 'unbekannte Person entfernen → not_found');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000007","role":"authenticated"}';
select is(public.social_group_invitations(), '[]'::jsonb, 'Entfernen zieht die offenen Einladungen der Person zurück');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000005","role":"authenticated"}';
select throws_ok(format('select public.social_group(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'entferntes Mitglied sieht die Gruppe nicht mehr');

-- Letzte Person verlässt die Gruppe → Gruppe gelöscht.
insert into t_results select 'solo', public.social_create_group('Solo', '', 'other', 8000, null);
select lives_ok(format('select public.social_leave_group(%L)', pg_temp.group_id('solo')), 'letzte Person verlässt die Gruppe');
reset role;
select is(
  (select count(*)::int from public.groups where id = pg_temp.group_id('solo'))
  + (select count(*)::int from public.group_membership_periods where group_id = pg_temp.group_id('solo'))
  + (select count(*)::int from public.group_goal_history where group_id = pg_temp.group_id('solo')),
  0, 'leere Gruppe samt Historie gelöscht'
);

-- Profillöschung des Eigentümers (rosa) → paul (vor quinn beigetreten) wird Eigentümer.
delete from auth.users where id = 'a7000000-0000-4000-8000-000000000004';
select is(
  (select array_agg(p.username || ':' || m.role order by p.username) from public.group_members m
     join public.profiles p on p.id = m.user_id where m.group_id = pg_temp.group_id('g1')),
  array['paul:owner', 'quinn:member'], 'Profillöschung des Eigentümers: Nachfolger wird Eigentümer'
);
select is(
  (select count(*)::int from public.group_membership_periods where user_id = 'a7000000-0000-4000-8000-000000000004'),
  0, 'Mitgliedschaftshistorie des gelöschten Profils entfernt'
);

-- Profillöschung der letzten Person → Gruppe gelöscht.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000006","role":"authenticated"}';
insert into t_results select 'tina_solo', public.social_create_group('Tinas Gruppe', '', 'other', 8000, null);
reset role;
delete from auth.users where id = 'a7000000-0000-4000-8000-000000000006';
select is((select count(*)::int from public.groups where id = pg_temp.group_id('tina_solo')), 0, 'Profillöschung der letzten Person: Gruppe gelöscht');

-- Eigentümer löscht die Gruppe.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000002","role":"authenticated"}';
select lives_ok(format('select public.social_delete_group(%L)', pg_temp.group_id('g1')), 'Eigentümer löscht die Gruppe');
reset role;
select is(
  (select count(*)::int from public.groups where id = pg_temp.group_id('g1'))
  + (select count(*)::int from public.group_members where group_id = pg_temp.group_id('g1'))
  + (select count(*)::int from public.group_membership_periods where group_id = pg_temp.group_id('g1'))
  + (select count(*)::int from public.group_goal_history where group_id = pg_temp.group_id('g1'))
  + (select count(*)::int from public.group_invitations where group_id = pg_temp.group_id('g1')),
  0, 'Gruppe mit Mitgliedern, Historie und Einladungen gelöscht'
);
set local role authenticated;
select throws_ok(format('select public.social_group(%L)', pg_temp.group_id('g1')), 'P0001', 'not_found', 'gelöschte Gruppe: not_found');

-- =============================================================================================================
-- Limits
-- =============================================================================================================

-- Mitgliederlimit 50: xaver + 49 Statisten; dazu eine Einladung an 151 aus der Zeit, bevor die Gruppe voll war.
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000010","role":"authenticated"}';
insert into t_results select 'big', public.social_create_group('Großgruppe', '', 'work', 6000, null);
reset role;
insert into public.group_members (group_id, user_id)
select pg_temp.group_id('big'), ('a7000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
  from generate_series(101, 149) n;
insert into public.group_invitations (group_id, inviter_id, invitee_id)
values (pg_temp.group_id('big'), 'a7000000-0000-4000-8000-000000000010', 'a7000000-0000-4000-8000-000000000151');
insert into t_results select 'inv_151', jsonb_build_object('invitation_id', id) from public.group_invitations
 where invitee_id = 'a7000000-0000-4000-8000-000000000151';
set local role authenticated;

select is(public.social_group(pg_temp.group_id('big'))->>'member_count', '50', '50 Mitglieder');
select throws_ok(format('select public.social_invite_to_group(%L, %L)', pg_temp.group_id('big'), 'b7000000-0000-4000-8000-000000000150'), 'P0001', 'limit_reached', 'volle Gruppe: Einladen → limit_reached');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000150","role":"authenticated"}';
select throws_ok(format('select public.social_join_group(%L)', pg_temp.result('big')->>'invite_code'), 'P0001', 'limit_reached', '51. Mitglied: limit_reached');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000151","role":"authenticated"}';
select throws_ok(format('select public.social_respond_group_invitation(%L, true)', pg_temp.result('inv_151')->>'invitation_id'), 'P0001', 'limit_reached', 'Einladung annehmen in voller Gruppe: limit_reached');
select is(public.social_group_invitations()->0->>'group_name', 'Großgruppe', 'Einladung bleibt nach limit_reached offen');

-- Mitgliedschaftslimit 20 (yara ist in 20 Gruppen) und Eigentümerlimit 10 (zoe besitzt 10 Gruppen).
reset role;
insert into public.groups (name, kind, invite_code, created_by)
select 'Limit ' || n, 'other', private.generate_invite_code(), 'a7000000-0000-4000-8000-000000000012'
  from generate_series(1, 20) n;
insert into public.group_members (group_id, user_id, role)
select g.id, case when g.name in (select 'Limit ' || n from generate_series(1, 10) n)
                  then 'a7000000-0000-4000-8000-000000000012'::uuid
                  else 'a7000000-0000-4000-8000-000000000199'::uuid end, 'owner'
  from public.groups g
 where g.created_by = 'a7000000-0000-4000-8000-000000000012';
insert into public.group_members (group_id, user_id)
select g.id, 'a7000000-0000-4000-8000-000000000011' from public.groups g
 where g.created_by = 'a7000000-0000-4000-8000-000000000012';
set local role authenticated;

set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000008","role":"authenticated"}';
insert into t_results select 'g_open', public.social_create_group('Offen', '', 'club', 7000, null);
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000011","role":"authenticated"}';
select throws_ok(format('select public.social_join_group(%L)', pg_temp.result('g_open')->>'invite_code'), 'P0001', 'limit_reached', '21. Mitgliedschaft: limit_reached');
select throws_ok($$select public.social_create_group('Noch eine', '', 'club', 7000, null)$$, 'P0001', 'limit_reached', 'Erstellen mit 20 Mitgliedschaften: limit_reached');
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000012","role":"authenticated"}';
select throws_ok($$select public.social_create_group('Elfte', '', 'club', 7000, null)$$, 'P0001', 'limit_reached', '11. Gruppe als Eigentümer: limit_reached');

-- Einladungen: max. 30 neue je 24 h (vera lädt 31 Freunde in ihre Gruppe ein).
reset role;
insert into public.friendships (user_a, user_b)
select 'a7000000-0000-4000-8000-000000000008', ('a7000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
  from generate_series(101, 131) n;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000008","role":"authenticated"}';
do $$
begin
  for i in 101..130 loop
    perform public.social_invite_to_group(
      (select (r.result->>'group_id')::uuid from t_results r where r.name = 'g_open'),
      ('b7000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid
    );
  end loop;
end
$$;
select is(jsonb_array_length(public.social_group_outgoing_invitations(pg_temp.group_id('g_open'))), 30, '30 Einladungen gesendet');
select throws_ok(format('select public.social_invite_to_group(%L, %L)', pg_temp.group_id('g_open'), 'b7000000-0000-4000-8000-000000000131'), 'P0001', 'rate_limited', '31. Einladung in 24 h: rate_limited');

-- Erstellen: max. 5 je 24 h (olga hat bereits 2 erstellt); eigene Gruppen nach Name sortiert.
set local request.jwt.claims = '{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}';
select lives_ok($$select public.social_create_group('zeta-Lauf', '', 'friends', 7000, null)$$, '3. Gruppe');
select lives_ok($$select public.social_create_group('abendrunde', '', 'friends', 7000, null)$$, '4. Gruppe');
select lives_ok($$select public.social_create_group('Mittagspause', '', 'work', 7000, null)$$, '5. Gruppe');
select throws_ok($$select public.social_create_group('Sechste', '', 'club', 7000, null)$$, 'P0001', 'rate_limited', '6. Gruppe in 24 h: rate_limited');
select is(
  (select array_agg(e->>'name' order by ord) from jsonb_array_elements(public.social_my_groups()) with ordinality as x(e, ord)),
  array['abendrunde', 'Mittagspause', 'Pazifik', 'zeta-Lauf'], 'eigene Gruppen nach Name (ohne Groß-/Kleinschreibung)'
);

reset role;
select * from finish();
rollback;
