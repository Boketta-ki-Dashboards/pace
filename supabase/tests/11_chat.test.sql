-- Pace: Chats – Privatchats, Gruppenchats, Senden (idempotent), Lesestand, Löschen, Zugriff, Echtzeit-Hinweise.
begin;
select plan(91);

-- =============================================================================================================
-- Struktur
-- =============================================================================================================

select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
    where c.oid in ('public.conversations'::regclass, 'public.chat_messages'::regclass, 'public.conversation_reads'::regclass)
      and c.relrowsecurity),
  array['chat_messages', 'conversation_reads', 'conversations'], 'RLS auf allen Chat-Tabellen'
);
select is(
  (select count(*)::int from pg_policy p
    where p.polrelid in ('public.conversations'::regclass, 'public.chat_messages'::regclass, 'public.conversation_reads'::regclass)),
  0, 'keine Policies: Zugriff nur über RPCs'
);
select is(
  (select array_agg(format('%s %s %s', r.role_name, t.table_name, pr.privilege) order by 1)
     from unnest(array['anon', 'authenticated']) as r(role_name)
    cross join unnest(array['public.conversations', 'public.chat_messages', 'public.conversation_reads']) as t(table_name)
    cross join unnest(array['select', 'insert', 'update', 'delete']) as pr(privilege)
    where has_table_privilege(r.role_name, t.table_name, pr.privilege)),
  null, 'anon/authenticated ohne Rechte auf Chat-Tabellen'
);
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname like 'chat\_%'),
  array['chat_conversations', 'chat_delete_message', 'chat_edit_message', 'chat_favorites', 'chat_group_conversation',
        'chat_mark_read', 'chat_messages', 'chat_open_direct', 'chat_pins', 'chat_send', 'chat_set_favorite',
        'chat_set_pinned'],
  'alle Chat-RPCs vorhanden'
);
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname like 'chat\_%'
      and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute')
           or not has_function_privilege('authenticated', p.oid, 'execute')
           or not p.prosecdef or p.proconfig is distinct from array['search_path=""']
           or obj_description(p.oid, 'pg_proc') is null)),
  null, 'Chat-RPCs: nur authenticated, security definer, leerer search_path, Kommentar'
);

-- =============================================================================================================
-- Testdaten
-- =============================================================================================================

-- 1 mara, 2 nils, 3 olli (Fremder), 4 paula, 5 quentin.
insert into auth.users (id, aud, role, is_anonymous)
select ('ab000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 5) n;
insert into public.profiles (id, public_id, username, display_name)
select ('ab000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('bb000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'mara', 'Mara'), (2, 'nils', 'Nils'), (3, 'olli', 'Olli'), (4, 'paula', 'Paula'),
               (5, 'quentin', 'Quentin')) as v(n, username, display_name);

-- Freunde: mara–nils, mara–paula.
insert into public.friendships (user_a, user_b)
values (least('ab000000-0000-4000-8000-000000000001'::uuid, 'ab000000-0000-4000-8000-000000000002'::uuid),
        greatest('ab000000-0000-4000-8000-000000000001'::uuid, 'ab000000-0000-4000-8000-000000000002'::uuid)),
       (least('ab000000-0000-4000-8000-000000000001'::uuid, 'ab000000-0000-4000-8000-000000000004'::uuid),
        greatest('ab000000-0000-4000-8000-000000000001'::uuid, 'ab000000-0000-4000-8000-000000000004'::uuid));

-- Gruppe von mara mit nils, paula und quentin. Die Unterhaltung legt der Trigger an.
insert into public.groups (id, name, kind, invite_code, created_by)
values ('cb000000-0000-4000-8000-000000000001', 'Laufgruppe', 'friends', 'CHATCHAT', 'ab000000-0000-4000-8000-000000000001');
insert into public.group_goal_history (group_id, effective_from, daily_goal)
values ('cb000000-0000-4000-8000-000000000001', current_date - 10, 8000);
insert into public.group_members (group_id, user_id, role)
values ('cb000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000001', 'owner'),
       ('cb000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000002', 'member'),
       ('cb000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000004', 'member'),
       ('cb000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000005', 'member');

create temporary table t_results (name text primary key, result jsonb) on commit drop;
grant select, insert on t_results to authenticated;
create function pg_temp.result(p_name text) returns jsonb language sql stable as $$
  select r.result from t_results r where r.name = p_name;
$$;
create function pg_temp.cid(p_name text) returns uuid language sql stable as $$
  select (r.result->>'id')::uuid from t_results r where r.name = p_name;
$$;
create function pg_temp.pid(n int) returns uuid language sql immutable as $$
  select ('bb000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;
create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claims',
                    format('{"sub":"ab000000-0000-4000-8000-%s","role":"authenticated"}', lpad(n::text, 12, '0')), true);
$$;
create function pg_temp.bodies(p_messages jsonb) returns text[] language sql immutable as $$
  select array_agg(coalesce(e->>'body', e->>'kind') order by ord) from jsonb_array_elements(p_messages) with ordinality as x(e, ord);
$$;

select ok(
  exists (select 1 from public.conversations c where c.group_id = 'cb000000-0000-4000-8000-000000000001' and c.kind = 'group'),
  'Trigger legt den Gruppenchat an'
);

-- =============================================================================================================
-- Privatchat öffnen (mara)
-- =============================================================================================================

set local role authenticated;
select pg_temp.as_user(1);

insert into t_results select 'direct', public.chat_open_direct(pg_temp.pid(2));
select is(
  pg_temp.result('direct') - 'id' - 'updated_at',
  jsonb_build_object(
    'kind', 'direct', 'title', 'Nils',
    'peer', jsonb_build_object('public_id', pg_temp.pid(2), 'username', 'nils', 'display_name', 'Nils', 'avatar_path', null,
                               'nickname', null),
    'group_id', null, 'group_image_path', null, 'member_count', 2, 'last_message', null, 'unread_count', 0,
    'can_send', true, 'can_pin', true
  ),
  'Privatchat mit einem Freund: Form wie ConversationSummary'
);
select is((public.chat_open_direct(pg_temp.pid(2))->>'id')::uuid, pg_temp.cid('direct'), 'erneut öffnen: dieselbe Unterhaltung');
select throws_ok(format('select public.chat_open_direct(%L)', pg_temp.pid(3)), 'P0001', 'not_found', 'Fremde Person: not_found');
select throws_ok(format('select public.chat_open_direct(%L)', pg_temp.pid(1)), 'P0001', 'self_request', 'mit mir selbst: self_request');
select throws_ok($$select public.chat_open_direct('bb000000-0000-4000-8000-00000000dead')$$, 'P0001', 'not_found', 'unbekannt: not_found');
select is(
  (select array_agg(e->>'kind' order by e->>'kind') from jsonb_array_elements(public.chat_conversations()) e),
  array['group'], 'Liste: Privatchat ohne Nachrichten erscheint nicht, Gruppenchat schon'
);

-- =============================================================================================================
-- Senden und Validierung
-- =============================================================================================================

insert into t_results select 'm1', public.chat_send(pg_temp.cid('direct'), 'db000000-0000-4000-8000-000000000001', 'text', '  Hallo Nils!  ');
select is(
  pg_temp.result('m1') - 'id' - 'created_at',
  jsonb_build_object(
    'conversation_id', pg_temp.cid('direct'), 'client_id', 'db000000-0000-4000-8000-000000000001',
    'sender', jsonb_build_object('public_id', pg_temp.pid(1), 'username', 'mara', 'display_name', 'Mara', 'avatar_path', null,
                                 'nickname', null),
    'is_own', true, 'kind', 'text', 'body', 'Hallo Nils!', 'media_path', null, 'shared_profile', null,
    'media_duration_ms', null, 'reply_to', null, 'edited_at', null, 'is_favorite', false, 'is_pinned', false
  ),
  'Text gesendet (getrimmt), Form wie ChatMessage'
);
select is(
  public.chat_send(pg_temp.cid('direct'), 'db000000-0000-4000-8000-000000000001', 'text', 'anderer Text')->>'id',
  pg_temp.result('m1')->>'id', 'Wiederholung mit derselben client_id: dieselbe Nachricht'
);
select throws_ok(
  format('select public.chat_send(%L, %L, %L, %L)', (select (c->>'id') from public.chat_group_conversation('cb000000-0000-4000-8000-000000000001') c),
         'db000000-0000-4000-8000-000000000001', 'text', 'x'),
  'P0001', 'invalid_input', 'dieselbe client_id in einer anderen Unterhaltung'
);
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('direct'), 'text', '   '), 'P0001', 'invalid_message', 'leerer Text');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('direct'), 'text', repeat('a', 2001)), 'P0001', 'invalid_message', 'Text über 2000 Zeichen');
select lives_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('direct'), 'text', repeat('ä', 2000)), 'Text mit 2000 Zeichen');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('direct'), 'text', E'a\u0007b'), 'P0001', 'invalid_message', 'Steuerzeichen');
select lives_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('direct'), 'text', E'Zeile 1\nZeile 2 👩‍👩‍👧'), 'Zeilenumbruch und Emoji mit ZWJ');
select throws_ok(format('select public.chat_send(%L, null, %L, %L)', pg_temp.cid('direct'), 'text', 'x'), 'P0001', 'invalid_input', 'client_id fehlt');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('direct'), 'video', 'x'), 'P0001', 'invalid_input', 'unbekannte Art');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L, %L)', pg_temp.cid('direct'), 'text', 'x', 'a/b.jpg'), 'P0001', 'invalid_input', 'Text mit Datei');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L)', gen_random_uuid(), 'text'), 'P0001', 'not_found', 'unbekannte Unterhaltung');

-- Bilder und GIFs: nur eigene Dateien im Ordner der Unterhaltung.
reset role;
insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('chat-media', pg_temp.cid('direct') || '/foto.jpg', 'ab000000-0000-4000-8000-000000000001', '{"mimetype":"image/jpeg"}'),
       ('chat-media', pg_temp.cid('direct') || '/anim.gif', 'ab000000-0000-4000-8000-000000000001', '{"mimetype":"image/gif"}'),
       ('chat-media', pg_temp.cid('direct') || '/vonnils.jpg', 'ab000000-0000-4000-8000-000000000002', '{"mimetype":"image/jpeg"}');
set local role authenticated;

select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L)', pg_temp.cid('direct'), 'image', pg_temp.cid('direct') || '/fehlt.jpg'), 'P0001', 'invalid_input', 'Bild: Datei muss hochgeladen sein');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L)', pg_temp.cid('direct'), 'image', pg_temp.cid('direct') || '/vonnils.jpg'), 'P0001', 'invalid_input', 'Bild: nur eigene Uploads');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L)', pg_temp.cid('direct'), 'gif', pg_temp.cid('direct') || '/foto.jpg'), 'P0001', 'invalid_input', 'GIF muss image/gif sein');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L, %L)', pg_temp.cid('direct'), 'image', 'Text', pg_temp.cid('direct') || '/foto.jpg'), 'P0001', 'invalid_input', 'Bild ohne Text');
insert into t_results select 'img', public.chat_send(pg_temp.cid('direct'), gen_random_uuid(), 'image', null, pg_temp.cid('direct') || '/foto.jpg');
select is(pg_temp.result('img')->>'media_path', pg_temp.cid('direct') || '/foto.jpg', 'Bild gesendet');
select is(
  public.chat_send(pg_temp.cid('direct'), gen_random_uuid(), 'gif', null, pg_temp.cid('direct') || '/anim.gif')->>'kind',
  'gif', 'GIF gesendet'
);

-- Profil teilen (über die public_id).
select is(
  public.chat_send(pg_temp.cid('direct'), gen_random_uuid(), 'profile', null, null, pg_temp.pid(4))->'shared_profile'->>'username',
  'paula', 'Profil geteilt'
);
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, null, null, %L)', pg_temp.cid('direct'), 'profile', 'bb000000-0000-4000-8000-00000000dead'), 'P0001', 'not_found', 'unbekanntes Profil');

-- Echtzeit-Hinweise ohne Inhalt.
reset role;
select ok(
  (select count(*) from realtime.messages m where m.topic = 'chat:' || pg_temp.cid('direct') and m.private) > 0,
  'Hinweis an chat:<conversation_id> (privat)'
);
select ok(
  (select count(*) from realtime.messages m where m.topic = 'user:' || pg_temp.pid(2) and m.event = 'conversation') > 0,
  'Hinweis an user:<public_id> des Empfängers'
);
select ok(
  not exists (select 1 from realtime.messages m where m.topic like 'chat:%' and m.payload::text like '%Hallo%'),
  'Hinweise enthalten keinen Nachrichteninhalt'
);
set local role authenticated;

-- =============================================================================================================
-- Empfangen, Verlauf, Lesestand (nils)
-- =============================================================================================================

select pg_temp.as_user(2);
select is(
  (select e - 'id' - 'updated_at' - 'last_message' - 'peer' from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'direct'),
  jsonb_build_object('kind', 'direct', 'title', 'Mara', 'group_id', null, 'group_image_path', null, 'member_count', 2,
                     'unread_count', 6, 'can_send', true, 'can_pin', true),
  'Empfänger: Privatchat erscheint mit Ungelesen-Zähler'
);
select is(
  (select (e->'last_message') - 'sent_at' from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'direct'),
  '{"kind": "profile", "text": null, "sender_name": "Mara", "sender_nickname": null, "media_duration_ms": null, "is_own": false}'::jsonb,
  'letzte Nachricht mit Absendername'
);
insert into t_results select 'verlauf', public.chat_messages(pg_temp.cid('direct'));
select is(
  pg_temp.bodies(pg_temp.result('verlauf')),
  array['Hallo Nils!', repeat('ä', 2000), E'Zeile 1\nZeile 2 👩‍👩‍👧', 'image', 'gif', 'profile'],
  'Verlauf aufsteigend'
);
select is(pg_temp.result('verlauf')->0->'client_id', 'null'::jsonb, 'fremde client_id wird nicht ausgeliefert');
select is(pg_temp.result('verlauf')->0->>'is_own', 'false', 'is_own aus Sicht des Empfängers');

insert into t_results select 'antwort', public.chat_send(pg_temp.cid('direct'), gen_random_uuid(), 'text', 'Hi Mara');
select is(
  pg_temp.bodies(public.chat_messages(pg_temp.cid('direct'), null, 2)), array['profile', 'Hi Mara'],
  'Limit: die neuesten Nachrichten, aufsteigend'
);
select is(
  pg_temp.bodies(public.chat_messages(pg_temp.cid('direct'), (pg_temp.result('verlauf')->2->>'created_at')::timestamptz, 40)),
  array['Hallo Nils!', repeat('ä', 2000)], 'Seite vor einem Zeitpunkt'
);
select lives_ok(
  format('select public.chat_mark_read(%L, %L)', pg_temp.cid('direct'), pg_temp.result('verlauf')->2->>'created_at'),
  'bis zur dritten Nachricht gelesen'
);
select is(
  (select (e->>'unread_count')::int from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'direct'),
  3, 'Ungelesen nach teilweisem Lesen'
);
select lives_ok(format('select public.chat_mark_read(%L, %L)', pg_temp.cid('direct'), '2100-01-01'), 'Zeitpunkt in der Zukunft wird begrenzt');
select is(
  (select (e->>'unread_count')::int from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'direct'),
  0, 'alles gelesen'
);
select lives_ok(
  format('select public.chat_mark_read(%L, %L)', pg_temp.cid('direct'), pg_temp.result('verlauf')->0->>'created_at'),
  'Lesestand geht nicht zurück'
);
select is(
  (select (e->>'unread_count')::int from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'direct'),
  0, 'weiterhin alles gelesen'
);

-- Löschen: nur eigene Nachrichten.
select throws_ok(format('select public.chat_delete_message(%L)', pg_temp.result('img')->>'id'), 'P0001', 'not_found', 'fremde Nachricht löschen: not_found');
select pg_temp.as_user(1);
select is(
  public.chat_delete_message((pg_temp.result('img')->>'id')::uuid),
  jsonb_build_object('media_path', pg_temp.cid('direct') || '/foto.jpg'), 'eigene Nachricht gelöscht, Pfad zum Entfernen der Datei'
);
select ok(
  not (pg_temp.bodies(public.chat_messages(pg_temp.cid('direct'))) @> array['image']), 'gelöschte Nachricht verschwindet'
);
select throws_ok(format('select public.chat_delete_message(%L)', pg_temp.result('img')->>'id'), 'P0001', 'not_found', 'zweimal löschen: not_found');
reset role;
select is(
  (select row(body, media_path, deleted_at is not null)::text from public.chat_messages where id = (pg_temp.result('img')->>'id')::uuid),
  '(,,t)', 'gelöschte Nachricht ohne Inhalt'
);
set local role authenticated;

-- Fremde haben keinen Zugriff.
select pg_temp.as_user(3);
select throws_ok(format('select public.chat_messages(%L)', pg_temp.cid('direct')), 'P0001', 'not_found', 'Fremder: Verlauf not_found');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('direct'), 'text', 'x'), 'P0001', 'not_found', 'Fremder: senden not_found');
select throws_ok(format('select public.chat_mark_read(%L, now())', pg_temp.cid('direct')), 'P0001', 'not_found', 'Fremder: gelesen markieren not_found');
select is(public.chat_conversations(), '[]'::jsonb, 'Fremder: keine Unterhaltungen');

-- =============================================================================================================
-- Gruppenchat
-- =============================================================================================================

select pg_temp.as_user(4);
insert into t_results select 'gruppe', public.chat_group_conversation('cb000000-0000-4000-8000-000000000001');
select is(
  pg_temp.result('gruppe') - 'id' - 'updated_at',
  jsonb_build_object('kind', 'group', 'title', 'Laufgruppe', 'peer', null, 'group_id', 'cb000000-0000-4000-8000-000000000001',
                     'group_image_path', null, 'member_count', 4, 'last_message', null, 'unread_count', 0, 'can_send', true,
                     'can_pin', false),
  'Gruppenchat: Form wie ConversationSummary (Mitglied ohne Owner-Rolle: can_pin false)'
);
select lives_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('gruppe'), 'text', 'Wer läuft heute?'), 'Mitglied sendet');
select pg_temp.as_user(1);
select lives_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('gruppe'), 'text', 'Ich!'), 'owner sendet');
select pg_temp.as_user(2);
select is(pg_temp.bodies(public.chat_messages(pg_temp.cid('gruppe'))), array['Wer läuft heute?', 'Ich!'], 'Mitglied liest den Gruppenchat');
select pg_temp.as_user(3);
select throws_ok(format('select public.chat_group_conversation(%L)', 'cb000000-0000-4000-8000-000000000001'), 'P0001', 'not_found', 'Nichtmitglied: Gruppenchat not_found');
select throws_ok(format('select public.chat_messages(%L)', pg_temp.cid('gruppe')), 'P0001', 'not_found', 'Nichtmitglied: Verlauf not_found');

-- Austritt entzieht den Zugriff.
select pg_temp.as_user(4);
select lives_ok($$select public.social_leave_group('cb000000-0000-4000-8000-000000000001')$$, 'paula verlässt die Gruppe');
select throws_ok(format('select public.chat_messages(%L)', pg_temp.cid('gruppe')), 'P0001', 'not_found', 'nach Austritt: kein Lesen');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('gruppe'), 'text', 'x'), 'P0001', 'not_found', 'nach Austritt: kein Senden');
select ok(
  not exists (select 1 from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'group'),
  'nach Austritt: Gruppenchat nicht mehr in der Liste'
);

-- =============================================================================================================
-- Ende der Freundschaft und Blockierung
-- =============================================================================================================

select pg_temp.as_user(1);
select lives_ok(format('select public.social_remove_friend(%L)', pg_temp.pid(2)), 'mara beendet die Freundschaft mit nils');
select is(public.chat_open_direct(pg_temp.pid(2))->>'can_send', 'false', 'nach Ende der Freundschaft: lesbar, can_send = false');
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('direct'), 'text', 'x'), 'P0001', 'read_only', 'nach Ende der Freundschaft: read_only');
select ok(jsonb_array_length(public.chat_messages(pg_temp.cid('direct'))) > 0, 'Verlauf bleibt lesbar');

select pg_temp.as_user(2);
select lives_ok(format('select public.social_block_user(%L)', pg_temp.pid(1)), 'nils blockiert mara');
select throws_ok(format('select public.chat_messages(%L)', pg_temp.cid('direct')), 'P0001', 'not_found', 'Blockierung: Privatchat für den Blockierenden verborgen');
select throws_ok(format('select public.chat_open_direct(%L)', pg_temp.pid(1)), 'P0001', 'blocked', 'Blockierender öffnet: blocked');
select is(pg_temp.bodies(public.chat_messages(pg_temp.cid('gruppe'))), array['Wer läuft heute?'], 'Gruppenchat: Nachrichten Blockierter ausgeblendet');
select ok(
  not exists (select 1 from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'direct'),
  'Blockierung: Privatchat nicht in der Liste'
);
select pg_temp.as_user(1);
select throws_ok(format('select public.chat_open_direct(%L)', pg_temp.pid(2)), 'P0001', 'not_found', 'Blockierte Person öffnet: not_found');
select throws_ok(format('select public.chat_messages(%L)', pg_temp.cid('direct')), 'P0001', 'not_found', 'Blockierung: Privatchat auch für die Blockierte verborgen');
select is(pg_temp.bodies(public.chat_messages(pg_temp.cid('gruppe'))), array['Wer läuft heute?', 'Ich!'], 'Gruppenchat bleibt für beide nutzbar');

-- =============================================================================================================
-- Rate Limit: 30 Nachrichten je Minute
-- =============================================================================================================

select pg_temp.as_user(5);
select is(
  (select count(*)::int from generate_series(1, 30) s
     cross join lateral public.chat_send(pg_temp.cid('gruppe'), gen_random_uuid(), 'text', 'Nachricht ' || s) m),
  30, '30 Nachrichten je Minute erlaubt'
);
select throws_ok(format('select public.chat_send(%L, gen_random_uuid(), %L, %L)', pg_temp.cid('gruppe'), 'text', 'zu viel'), 'P0001', 'rate_limited', '31. Nachricht: rate_limited');

-- =============================================================================================================
-- Nicht auffindbare Profile teilen und öffnen (olli ist nicht auffindbar und mit niemandem verbunden)
-- =============================================================================================================

reset role;
update public.profiles set is_discoverable = false where username = 'olli';
create function pg_temp.profile_of(n int) returns text language sql as $$
  select public.social_public_profile(pg_temp.pid(n), (now() at time zone 'utc')::date)->>'username';
$$;
set local role authenticated;

select pg_temp.as_user(1);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, null, null, %L)', pg_temp.cid('gruppe'), 'profile', pg_temp.pid(3)),
  'P0001', 'not_found', 'nicht sichtbares Profil lässt sich nicht teilen (keine Auflösung beliebiger public_ids)'
);
select is(public.social_find_profile('olli')->>'username', 'olli', 'mara findet olli exakt per Benutzernamen');
insert into t_results select 'olli_geteilt', public.chat_send(pg_temp.cid('gruppe'), gen_random_uuid(), 'profile', null, null, pg_temp.pid(3));
select is(pg_temp.result('olli_geteilt')->'shared_profile'->>'username', 'olli', 'nach exaktem Fund: teilen erlaubt');

select pg_temp.as_user(5);
select is(pg_temp.profile_of(3), 'olli', 'im Gruppenchat geteiltes Profil: für Mitglieder sichtbar');
select pg_temp.as_user(2);
select throws_ok(
  format('select public.social_public_profile(%L, %L)', pg_temp.pid(3), (now() at time zone 'utc')::date),
  'P0001', 'not_found', 'von einer blockierten Person geteilt (ausgeblendet): kein Kontext'
);
select pg_temp.as_user(4);
select throws_ok(
  format('select public.social_public_profile(%L, %L)', pg_temp.pid(3), (now() at time zone 'utc')::date),
  'P0001', 'not_found', 'ohne Zugriff auf den Chat: kein Kontext'
);

select pg_temp.as_user(1);
select lives_ok(format('select public.chat_delete_message(%L)', pg_temp.cid('olli_geteilt')), 'geteiltes Profil löschen');
select pg_temp.as_user(5);
select throws_ok(
  format('select public.social_public_profile(%L, %L)', pg_temp.pid(3), (now() at time zone 'utc')::date),
  'P0001', 'not_found', 'gelöschte Nachricht: kein Kontext mehr'
);

-- Privatchat bleibt Kontext, auch nach Ende der Freundschaft (paula ist nicht in einer Gruppe mit olli).
reset role;
insert into public.friendships (user_a, user_b)
values ('ab000000-0000-4000-8000-000000000003', 'ab000000-0000-4000-8000-000000000004');
set local role authenticated;
select pg_temp.as_user(4);
select lives_ok(format('select public.chat_open_direct(%L)', pg_temp.pid(3)), 'paula öffnet einen Privatchat mit olli');
reset role;
delete from public.friendships
 where user_a = 'ab000000-0000-4000-8000-000000000003' and user_b = 'ab000000-0000-4000-8000-000000000004';
set local role authenticated;
select pg_temp.as_user(4);
select is(pg_temp.profile_of(3), 'olli', 'Privatchat: Profil auch ohne Freundschaft sichtbar');

select * from finish();
rollback;
