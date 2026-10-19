-- Pace: Gruppen – Privatsphäre, Erstellen mit Einladungen, Details ändern, Gruppenbild.
begin;
select plan(33);

-- 1 ole, 2 pia, 3 quirin, 4 ronja, 5 sami (Fremde), 6 theo; 101–160 Statisten (Freunde von ole für Limits).
insert into auth.users (id, aud, role, is_anonymous)
select ('aa000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from (select generate_series(1, 6) union all select generate_series(101, 160)) as s(n);

insert into public.profiles (id, public_id, username, display_name)
select ('aa000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('ba000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'ole', 'Ole'), (2, 'pia', 'Pia'), (3, 'quirin', 'Quirin'), (4, 'ronja', 'Ronja'),
               (5, 'sami', 'Sami'), (6, 'theo', 'Theo')) as v(n, username, display_name)
union all
select ('aa000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       ('ba000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'statist_' || n, 'Statist ' || n
  from generate_series(101, 160) n;

-- Freunde von ole: pia, quirin, ronja, theo und alle Statisten.
insert into public.friendships (user_a, user_b)
select least(a, b), greatest(a, b)
  from (select 1 as x, y from (select unnest(array[2, 3, 4, 6]) union all select generate_series(101, 160)) as f(y)) v,
       lateral (select ('aa000000-0000-4000-8000-' || lpad(v.x::text, 12, '0'))::uuid as a,
                       ('aa000000-0000-4000-8000-' || lpad(v.y::text, 12, '0'))::uuid as b) ids;

create temporary table t_results (name text primary key, result jsonb) on commit drop;
grant select, insert on t_results to authenticated;
create function pg_temp.result(p_name text) returns jsonb language sql stable as $$
  select r.result from t_results r where r.name = p_name;
$$;
create function pg_temp.gid(p_name text) returns uuid language sql stable as $$
  select (r.result->>'group_id')::uuid from t_results r where r.name = p_name;
$$;
create function pg_temp.pid(n int) returns uuid language sql immutable as $$
  select ('ba000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aa000000-0000-4000-8000-000000000001","role":"authenticated"}';

-- =============================================================================================================
-- Erstellen mit Einladungen
-- =============================================================================================================

select throws_ok(
  format('select public.social_create_group(%L, %L, %L, 8000, null, %L, array[%L]::uuid[])', 'Lauftreff', '', 'friends', 'invite_only', pg_temp.pid(5)),
  'P0001', 'not_found', 'nur Freunde einladbar (Fremde → not_found)'
);
reset role;
select is(
  (select count(*)::int from public.groups where created_by = 'aa000000-0000-4000-8000-000000000001'), 0,
  'fehlgeschlagene Erstellung legt keine Gruppe an (eine Transaktion)'
);
set local role authenticated;
select throws_ok(
  $$select public.social_create_group('Lauftreff', '', 'friends', 8000, null, 'invite_only', array['ba000000-0000-4000-8000-00000000dead']::uuid[])$$,
  'P0001', 'not_found', 'unbekannte ID → not_found'
);
select throws_ok(
  $$select public.social_create_group('Lauftreff', '', 'friends', 8000, null, 'secret', '{}'::uuid[])$$,
  'P0001', 'invalid_privacy', 'unbekannte Privatsphäre'
);
select throws_ok(
  format('select public.social_create_group(%L, %L, %L, 8000, null, %L, %L::uuid[])', 'Lauftreff', '', 'friends', 'code',
         (select array_agg(pg_temp.pid(n)) from generate_series(101, 150) n)),
  'P0001', 'limit_reached', 'höchstens 49 Einladungen'
);

insert into t_results select 'g1', public.social_create_group(
  '  Morgenrunde ', 'Früh am See', 'friends', 9000, 'Europe/Berlin', 'invite_only',
  array[pg_temp.pid(2), pg_temp.pid(3), pg_temp.pid(2), pg_temp.pid(1)]::uuid[]
);
select is(
  pg_temp.result('g1') - 'group_id' - 'invite_code' - 'created_at' - 'group_today',
  jsonb_build_object(
    'name', 'Morgenrunde', 'description', 'Früh am See', 'kind', 'friends', 'role', 'owner', 'member_count', 1,
    'daily_goal', 9000, 'next_daily_goal', null, 'time_zone', 'Europe/Berlin', 'current_streak', 0, 'best_streak', 0,
    'today_reached_count', 0, 'today_required_count', 1, 'today_complete', false, 'image_path', null,
    'privacy', 'invite_only'
  ),
  'erstellt mit Privatsphäre invite_only'
);
select is(
  (select array_agg(e->>'username' order by e->>'username')
     from jsonb_array_elements(public.social_group_outgoing_invitations(pg_temp.gid('g1'))) e),
  array['pia', 'quirin'], 'Einladungen angelegt (ohne Doppelte, ohne mich selbst)'
);
select ok(
  exists (select 1 from public.chat_group_conversation(pg_temp.gid('g1')) c where c->>'kind' = 'group'),
  'Gruppenchat wird mit der Gruppe angelegt'
);

-- Alte Fassung (5 Parameter) erstellt weiterhin Gruppen mit Code.
insert into t_results select 'g_alt', public.social_create_group('Alte Fassung', '', 'work', 8000, null);
select is(pg_temp.result('g_alt')->>'privacy', 'code', 'alte Fassung: privacy = code');

-- =============================================================================================================
-- Beitritt: invite_only nur auf Einladung
-- =============================================================================================================

set local request.jwt.claims = '{"sub":"aa000000-0000-4000-8000-000000000005","role":"authenticated"}';
select is(
  public.social_join_group(pg_temp.result('g1')->>'invite_code'),
  '{"code": "P0001", "message": "invalid_invite_code", "details": null, "hint": null}'::jsonb,
  'invite_only: Code wird wie ein falscher Code abgelehnt'
);
select is(current_setting('response.status', true), '400', 'invite_only: HTTP 400');
select ok(
  public.social_join_group(pg_temp.result('g_alt')->>'invite_code') ? 'group_id',
  'privacy code: Beitritt per Code möglich'
);

set local request.jwt.claims = '{"sub":"aa000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  (select e->>'group_privacy' from jsonb_array_elements(public.social_group_invitations()) e
    where (e->>'group_id')::uuid = pg_temp.gid('g1')),
  'invite_only', 'Einladung zeigt die Privatsphäre'
);
select is(
  (public.social_respond_group_invitation(
     (select (e->>'invitation_id')::uuid from jsonb_array_elements(public.social_group_invitations()) e
       where (e->>'group_id')::uuid = pg_temp.gid('g1')), true)->'group'->>'member_count')::int,
  2, 'invite_only: Beitritt über Einladung'
);

-- =============================================================================================================
-- Details ändern (nur owner)
-- =============================================================================================================

select throws_ok(
  format('select public.social_update_group_details(%L, null, null, null, %L)', pg_temp.gid('g1'), 'code'),
  'P0001', 'not_allowed', 'Mitglied darf Details nicht ändern'
);
set local request.jwt.claims = '{"sub":"aa000000-0000-4000-8000-000000000005","role":"authenticated"}';
select throws_ok(
  format('select public.social_update_group_details(%L, %L, null, null, null)', pg_temp.gid('g1'), 'Neu'),
  'P0001', 'not_found', 'Nichtmitglied: not_found'
);

set local request.jwt.claims = '{"sub":"aa000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(
  public.social_update_group_details(pg_temp.gid('g1'), ' Abendrunde ', null, 'work', 'code')
    - 'group_id' - 'invite_code' - 'created_at' - 'group_today' - 'current_streak' - 'best_streak'
    - 'today_reached_count' - 'today_required_count' - 'today_complete' - 'next_daily_goal' - 'time_zone' - 'image_path',
  jsonb_build_object(
    'name', 'Abendrunde', 'description', 'Früh am See', 'kind', 'work', 'role', 'owner', 'member_count', 2,
    'daily_goal', 9000, 'privacy', 'code'
  ),
  'owner ändert Name, Art und Privatsphäre (null = unverändert)'
);
select throws_ok(
  format('select public.social_update_group_details(%L, null, null, null, %L)', pg_temp.gid('g1'), 'public'),
  'P0001', 'invalid_privacy', 'ungültige Privatsphäre'
);
select throws_ok(
  format('select public.social_update_group_details(%L, %L, null, null, null)', pg_temp.gid('g1'), 'x'),
  'P0001', 'invalid_name', 'ungültiger Name'
);

-- =============================================================================================================
-- Gruppenbild
-- =============================================================================================================

reset role;
insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('group-images', pg_temp.gid('g1') || '/titel.png', 'aa000000-0000-4000-8000-000000000001', '{"mimetype":"image/png"}'),
       ('group-images', pg_temp.gid('g_alt') || '/andere.png', 'aa000000-0000-4000-8000-000000000001', '{"mimetype":"image/png"}');
set local role authenticated;

select throws_ok(
  format('select public.social_set_group_image(%L, %L)', pg_temp.gid('g1'), pg_temp.gid('g1') || '/fehlt.png'),
  'P0001', 'invalid_image_path', 'Gruppenbild: Datei muss existieren'
);
select throws_ok(
  format('select public.social_set_group_image(%L, %L)', pg_temp.gid('g1'), pg_temp.gid('g_alt') || '/andere.png'),
  'P0001', 'invalid_image_path', 'Gruppenbild: nur im Ordner der eigenen Gruppe'
);
select throws_ok(
  format('select public.social_set_group_image(%L, %L)', pg_temp.gid('g1'), 'titel.png'),
  'P0001', 'invalid_image_path', 'Gruppenbild: Pfadformat'
);
select is(
  public.social_set_group_image(pg_temp.gid('g1'), pg_temp.gid('g1') || '/titel.png')->>'image_path',
  pg_temp.gid('g1') || '/titel.png', 'Gruppenbild gesetzt'
);
select is(
  (select e->>'image_path' from jsonb_array_elements(public.social_my_groups()) e
    where (e->>'group_id')::uuid = pg_temp.gid('g1')),
  pg_temp.gid('g1') || '/titel.png', 'Gruppenbild in der Gruppenliste'
);
select is(
  public.chat_group_conversation(pg_temp.gid('g1'))->>'group_image_path', pg_temp.gid('g1') || '/titel.png',
  'Gruppenbild im Gruppenchat'
);

set local request.jwt.claims = '{"sub":"aa000000-0000-4000-8000-000000000002","role":"authenticated"}';
select throws_ok(
  format('select public.social_set_group_image(%L, null)', pg_temp.gid('g1')),
  'P0001', 'not_allowed', 'Mitglied darf das Gruppenbild nicht ändern'
);

set local request.jwt.claims = '{"sub":"aa000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(
  public.social_set_group_image(pg_temp.gid('g1'), null)->'image_path', 'null'::jsonb, 'Gruppenbild entfernt'
);

-- =============================================================================================================
-- Einladungen beim Erstellen zählen zum Einladungs-Limit (30 je 24 h)
-- =============================================================================================================

-- Bisher 2 Einladungen gezählt; 28 weitere sind erlaubt, die 29. nicht.
select ok(
  public.social_create_group('Großgruppe', '', 'club', 8000, null, 'code',
    (select array_agg(pg_temp.pid(n)) from generate_series(101, 128) n)) ? 'group_id',
  '28 weitere Einladungen beim Erstellen'
);
select throws_ok(
  format('select public.social_create_group(%L, %L, %L, 8000, null, %L, array[%L]::uuid[])', 'Noch eine', '', 'club', 'code', pg_temp.pid(129)),
  'P0001', 'rate_limited', 'Einladungs-Limit greift auch beim Erstellen'
);
reset role;
select is(
  (select count(*)::int from public.group_invitations i join public.groups g on g.id = i.group_id where g.name = 'Großgruppe'),
  28, 'alle Einladungen der Großgruppe angelegt'
);
set local role authenticated;

-- Gruppen-Limit: 5 neue Gruppen je 24 h (bisher 3).
select lives_ok($$select public.social_create_group('Vierte', '', 'club', 8000, null, 'code', '{}'::uuid[])$$, 'vierte Gruppe');
select lives_ok($$select public.social_create_group('Fünfte', '', 'club', 8000, null, 'code', null)$$, 'fünfte Gruppe (null = keine Einladungen)');
select throws_ok(
  $$select public.social_create_group('Sechste', '', 'club', 8000, null, 'code', '{}'::uuid[])$$,
  'P0001', 'rate_limited', 'sechste Gruppe in 24 h'
);

select * from finish();
rollback;
