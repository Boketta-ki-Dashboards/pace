-- Pace: Nachrichtenaktionen – Sprachnachrichten, Antworten, Bearbeiten, Favoriten, Pins; Rechte, Privatsphäre,
-- Echtzeit-Hinweise und Storage-Zugriff auf Audio.
begin;
select plan(111);

-- =============================================================================================================
-- Struktur
-- =============================================================================================================

select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
    where c.oid in ('public.chat_message_favorites'::regclass, 'public.chat_message_pins'::regclass) and c.relrowsecurity),
  array['chat_message_favorites', 'chat_message_pins'], 'RLS auf Favoriten und Pins'
);
select is(
  (select count(*)::int from pg_policy p
    where p.polrelid in ('public.chat_message_favorites'::regclass, 'public.chat_message_pins'::regclass)),
  0, 'keine Policies: Zugriff nur über RPCs'
);
select is(
  (select array_agg(format('%s %s %s', r.role_name, t.table_name, pr.privilege) order by 1)
     from unnest(array['anon', 'authenticated']) as r(role_name)
    cross join unnest(array['public.chat_message_favorites', 'public.chat_message_pins']) as t(table_name)
    cross join unnest(array['select', 'insert', 'update', 'delete']) as pr(privilege)
    where has_table_privilege(r.role_name, t.table_name, pr.privilege)),
  null, 'anon/authenticated ohne Rechte auf Favoriten und Pins'
);
select is(
  (select array_agg(p.oid::regprocedure::text) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_send'),
  array['chat_send(uuid,uuid,text,text,text,uuid,uuid,integer)'],
  'chat_send: genau eine Fassung (keine Überladung für PostgREST)'
);
select is(
  (select array_agg(c.column_name || ':' || c.data_type order by c.column_name) from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'chat_messages'
      and c.column_name in ('reply_to_id', 'edited_at', 'media_duration_ms')),
  array['edited_at:timestamp with time zone', 'media_duration_ms:integer', 'reply_to_id:uuid'],
  'neue Spalten in chat_messages'
);
select ok(
  not has_function_privilege('authenticated', 'private.chat_reply_json(uuid, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'private.can_pin_conversation(uuid, uuid)', 'execute'),
  'neue private-Helfer für Clients nicht ausführbar'
);

-- =============================================================================================================
-- Testdaten
-- =============================================================================================================

-- 1 anna (Owner der Gruppe), 2 ben (Freund von anna), 3 cara, 4 dirk (Fremder), 5 emma (von anna blockiert),
-- 6 fritz (tritt aus). Gruppe: anna, ben, cara, emma, fritz.
insert into auth.users (id, aud, role, is_anonymous)
select ('af000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 6) n;
insert into public.profiles (id, public_id, username, display_name)
select ('af000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('bf000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'anna_a', 'Anna'), (2, 'ben_b', 'Ben'), (3, 'cara_c', 'Cara'), (4, 'dirk_d', 'Dirk'),
               (5, 'emma_e', 'Emma'), (6, 'fritz_f', 'Fritz')) as v(n, username, display_name);
insert into public.friendships (user_a, user_b)
values ('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000002');
insert into public.groups (id, name, kind, invite_code, created_by)
values ('cf000000-0000-4000-8000-000000000001', 'Aktionsgruppe', 'friends', 'AKTXNEVW', 'af000000-0000-4000-8000-000000000001');
insert into public.group_goal_history (group_id, effective_from, daily_goal)
values ('cf000000-0000-4000-8000-000000000001', current_date - 3, 6000);
insert into public.group_members (group_id, user_id, role)
select 'cf000000-0000-4000-8000-000000000001', ('af000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       case when n = 1 then 'owner' else 'member' end
  from unnest(array[1, 2, 3, 5, 6]) n;
insert into public.user_blocks (blocker_id, blocked_id)
values ('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000005');

create temporary table t_r (name text primary key, result jsonb) on commit drop;
grant select, insert, update on t_r to authenticated;
create function pg_temp.r(p_name text) returns jsonb language sql stable as $$
  select r.result from t_r r where r.name = p_name;
$$;
create function pg_temp.id(p_name text) returns uuid language sql stable as $$
  select (r.result->>'id')::uuid from t_r r where r.name = p_name;
$$;
create function pg_temp.pid(n int) returns uuid language sql immutable as $$
  select ('bf000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;
create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claims',
                    format('{"sub":"af000000-0000-4000-8000-%s","role":"authenticated"}', lpad(n::text, 12, '0')), true);
$$;
-- Hochladen wie die Storage-API: als authenticated, owner_id = Nutzer, Inhaltstyp in metadata.
create function pg_temp.upload(p_name text, p_mime text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('chat-media', p_name, auth.uid()::text, jsonb_build_object('mimetype', p_mime));
$$;
create function pg_temp.visible(p_name text) returns boolean language sql as $$
  select exists (select 1 from storage.objects o where o.bucket_id = 'chat-media' and o.name = p_name);
$$;
create function pg_temp.delete_file(p_name text) returns integer language plpgsql as $$
declare
  v_count integer;
begin
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects o where o.bucket_id = 'chat-media' and o.name = p_name;
  get diagnostics v_count = row_count;
  perform set_config('storage.allow_delete_query', 'false', true);
  return v_count;
end;
$$;
create function pg_temp.send(p_name text, p_conversation uuid, p_kind text, p_body text default null,
                             p_media_path text default null, p_reply_to uuid default null, p_duration integer default null)
returns jsonb language sql as $$
  insert into t_r (name, result)
  values (p_name, public.chat_send(p_conversation, gen_random_uuid(), p_kind, p_body, p_media_path, null, p_reply_to, p_duration))
  returning result;
$$;

set local role authenticated;
select pg_temp.as_user(1);
insert into t_r select 'direct', public.chat_open_direct(pg_temp.pid(2));
insert into t_r select 'group', public.chat_group_conversation('cf000000-0000-4000-8000-000000000001');

-- =============================================================================================================
-- Sprachnachrichten und Storage
-- =============================================================================================================

select lives_ok(
  format('select pg_temp.upload(%L, %L)', pg_temp.id('direct') || '/sprache.m4a', 'audio/mp4'),
  'Audio: Teilnehmerin lädt .m4a in den Ordner der Unterhaltung'
);
select lives_ok(format('select pg_temp.upload(%L, %L)', pg_temp.id('direct') || '/kurz.aac', 'audio/aac'), 'Audio: .aac erlaubt');
select lives_ok(format('select pg_temp.upload(%L, %L)', pg_temp.id('direct') || '/bild.jpg', 'image/jpeg'), 'Bild hochladen');
select lives_ok(format('select pg_temp.upload(%L, %L)', pg_temp.id('group') || '/gruppe.m4a', 'audio/x-m4a'), 'Audio im Gruppenordner');
select throws_ok(
  format('select pg_temp.upload(%L, %L)', pg_temp.id('direct') || '/sprache.mp3', 'audio/mpeg'),
  '42501', null, 'Audio: andere Endungen verboten'
);

select is(
  pg_temp.send('voice', pg_temp.id('direct'), 'voice', null, pg_temp.id('direct') || '/sprache.m4a', null, 18000)
    - 'id' - 'created_at' - 'client_id' - 'sender' - 'conversation_id',
  jsonb_build_object('is_own', true, 'kind', 'voice', 'body', null, 'media_path', pg_temp.id('direct') || '/sprache.m4a',
                     'media_duration_ms', 18000, 'shared_profile', null, 'reply_to', null, 'edited_at', null,
                     'is_favorite', false, 'is_pinned', false),
  'Sprachnachricht gesendet: Datei und Dauer'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L)', pg_temp.id('direct'), 'voice', pg_temp.id('direct') || '/kurz.aac'),
  'P0001', 'invalid_input', 'Sprachnachricht ohne Dauer'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L, null, null, 0)', pg_temp.id('direct'), 'voice', pg_temp.id('direct') || '/kurz.aac'),
  'P0001', 'invalid_input', 'Dauer 0'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L, null, null, 300001)', pg_temp.id('direct'), 'voice', pg_temp.id('direct') || '/kurz.aac'),
  'P0001', 'invalid_input', 'Dauer über 5 Minuten'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, %L, null, null, null, 1000)', pg_temp.id('direct'), 'text', 'Hallo'),
  'P0001', 'invalid_input', 'Dauer nur bei Sprachnachrichten'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L, null, null, 1000)', pg_temp.id('direct'), 'voice', pg_temp.id('direct') || '/bild.jpg'),
  'P0001', 'invalid_input', 'Sprachnachricht mit Bilddatei'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L)', pg_temp.id('direct'), 'image', pg_temp.id('direct') || '/kurz.aac'),
  'P0001', 'invalid_input', 'Bild mit Audiodatei'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L, null, null, 1000)', pg_temp.id('direct'), 'voice', pg_temp.id('group') || '/gruppe.m4a'),
  'P0001', 'invalid_input', 'Sprachnachricht mit Datei einer anderen Unterhaltung'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L, null, null, 1000)', pg_temp.id('direct'), 'voice', pg_temp.id('direct') || '/fehlt.m4a'),
  'P0001', 'invalid_input', 'Sprachnachricht ohne hochgeladene Datei'
);
select is(
  public.chat_send(p_conversation_id => pg_temp.id('direct'), p_client_id => gen_random_uuid(), p_kind => 'text',
                   p_body => 'Alte App', p_media_path => null, p_shared_profile_id => null)->>'body',
  'Alte App', 'bisherige Parameter (ältere App-Versionen) funktionieren weiter'
);

select pg_temp.as_user(2);
select ok(pg_temp.visible(pg_temp.id('direct') || '/sprache.m4a'), 'Audio: anderer Teilnehmer liest');
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, null, %L, null, null, 1000)', pg_temp.id('direct'), 'voice', pg_temp.id('direct') || '/kurz.aac'),
  'P0001', 'invalid_input', 'Sprachnachricht mit fremder Datei'
);
select is(pg_temp.delete_file(pg_temp.id('direct') || '/sprache.m4a'), 0, 'Audio: nur wer hochgeladen hat, löscht');
select is(
  (select (e->'last_message') - 'sent_at' from jsonb_array_elements(public.chat_conversations()) e where e->>'kind' = 'direct'),
  jsonb_build_object('kind', 'text', 'text', 'Alte App', 'sender_name', 'Anna', 'sender_nickname', null,
                     'media_duration_ms', null, 'is_own', false),
  'Chatliste: letzte Nachricht'
);
select pg_temp.as_user(4);
select ok(not pg_temp.visible(pg_temp.id('direct') || '/sprache.m4a'), 'Audio: Fremder liest nicht');
select throws_ok(
  format('select pg_temp.upload(%L, %L)', pg_temp.id('direct') || '/fremd.m4a', 'audio/mp4'),
  '42501', null, 'Audio: Fremder lädt nicht hoch'
);

-- =============================================================================================================
-- Antworten
-- =============================================================================================================

select pg_temp.as_user(1);
select pg_temp.send('m1', pg_temp.id('direct'), 'text', 'Treffen wir uns um sieben?');
select pg_temp.send('long', pg_temp.id('direct'), 'text', repeat('x', 250));
select pg_temp.as_user(2);
select is(
  pg_temp.send('reply1', pg_temp.id('direct'), 'text', 'Ja, gern!', null, pg_temp.id('m1'))->'reply_to',
  jsonb_build_object('id', pg_temp.id('m1'),
                     'sender', jsonb_build_object('public_id', pg_temp.pid(1), 'username', 'anna_a', 'display_name', 'Anna',
                                                  'avatar_path', null, 'nickname', null),
                     'kind', 'text', 'text', 'Treffen wir uns um sieben?', 'media_duration_ms', null, 'is_deleted', false),
  'Antwort: kompakte Vorschau des Originals'
);
select is(
  (pg_temp.send('reply_voice', pg_temp.id('direct'), 'text', 'Gehört', null, pg_temp.id('voice'))->'reply_to') - 'sender',
  jsonb_build_object('id', pg_temp.id('voice'), 'kind', 'voice', 'text', null, 'media_duration_ms', 18000, 'is_deleted', false),
  'Antwort auf Sprachnachricht: Art und Dauer'
);
select is(
  char_length(pg_temp.send('reply_long', pg_temp.id('direct'), 'text', 'Lang', null, pg_temp.id('long'))->'reply_to'->>'text'),
  200, 'Vorschau gekürzt auf 200 Zeichen'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, %L, null, null, %L)', pg_temp.id('group'), 'text', 'Falsch', pg_temp.id('m1')),
  'P0001', 'not_found', 'Antwort auf Nachricht einer anderen Unterhaltung'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, %L, null, null, %L)', pg_temp.id('direct'), 'text', 'X', 'df000000-0000-4000-8000-00000000dead'),
  'P0001', 'not_found', 'Antwort auf unbekannte Nachricht'
);
select is(
  (select e->'reply_to'->>'id' from jsonb_array_elements(public.chat_messages(pg_temp.id('direct'))) e
    where e->>'id' = pg_temp.id('reply1')::text),
  pg_temp.id('m1')::text, 'Verlauf: Antwort mit Verweis'
);
select pg_temp.as_user(1);
select lives_ok(format('select public.chat_delete_message(%L)', pg_temp.id('m1')), 'Original löschen');
select is(
  (select e->'reply_to' from jsonb_array_elements(public.chat_messages(pg_temp.id('direct'))) e
    where e->>'id' = pg_temp.id('reply1')::text),
  jsonb_build_object('id', pg_temp.id('m1'), 'sender', null, 'kind', 'text', 'text', null, 'media_duration_ms', null,
                     'is_deleted', true),
  'gelöschtes Original: nur id, Art und is_deleted'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, %L, null, null, %L)', pg_temp.id('direct'), 'text', 'X', pg_temp.id('m1')),
  'P0001', 'not_found', 'Antwort auf gelöschte Nachricht'
);

-- Gruppe: emma ist von anna blockiert.
select pg_temp.as_user(5);
select pg_temp.send('emma1', pg_temp.id('group'), 'text', 'Hallo von Emma');
select pg_temp.as_user(2);
select pg_temp.send('reply_emma', pg_temp.id('group'), 'text', 'Hi Emma', null, pg_temp.id('emma1'));
select pg_temp.as_user(1);
select is(
  (select e->'reply_to'->>'is_deleted' from jsonb_array_elements(public.chat_messages(pg_temp.id('group'))) e
    where e->>'id' = pg_temp.id('reply_emma')::text),
  'true', 'Antwort auf Nachricht einer blockierten Person: Original verborgen'
);
select ok(
  public.chat_messages(pg_temp.id('group'))::text not like '%Hallo von Emma%',
  'blockierte Person: auch über die Antwort kein Inhalt'
);
select throws_ok(
  format('select public.chat_send(%L, gen_random_uuid(), %L, %L, null, null, %L)', pg_temp.id('group'), 'text', 'X', pg_temp.id('emma1')),
  'P0001', 'not_found', 'Antwort auf Nachricht einer blockierten Person'
);

-- =============================================================================================================
-- Bearbeiten
-- =============================================================================================================

select pg_temp.as_user(1);
select pg_temp.send('e1', pg_temp.id('direct'), 'text', 'Bis spöter');
reset role;
delete from realtime.messages m where m.topic = 'chat:' || pg_temp.id('direct');
set local role authenticated;
select pg_temp.as_user(1);
select isnt(public.chat_edit_message(pg_temp.id('e1'), 'Bis später')->>'edited_at', null, 'Bearbeiten liefert edited_at');
select is(
  (select e->>'body' from jsonb_array_elements(public.chat_messages(pg_temp.id('direct'))) e where e->>'id' = pg_temp.id('e1')::text),
  'Bis später', 'bearbeiteter Text im Verlauf'
);
select ok(
  (select e->>'edited_at' from jsonb_array_elements(public.chat_messages(pg_temp.id('direct'))) e where e->>'id' = pg_temp.id('e1')::text) is not null,
  'edited_at im Verlauf'
);
reset role;
select ok(
  exists (select 1 from realtime.messages m where m.topic = 'chat:' || (select (result->>'id') from t_r where name = 'direct')
            and m.event = 'message_updated' and m.private),
  'Echtzeit: message_updated an chat:<conversation_id>'
);
select ok(
  not exists (select 1 from realtime.messages m where m.payload::text like '%Bis sp%'),
  'Echtzeit-Hinweis ohne Inhalt'
);
set local role authenticated;
select pg_temp.as_user(1);
select pg_temp.send('e2', pg_temp.id('direct'), 'text', 'Unverändert');
select is(
  public.chat_edit_message(pg_temp.id('e2'), '  Unverändert ')->'edited_at', 'null'::jsonb,
  'gleicher Text: kein „Bearbeitet“'
);
select throws_ok(format('select public.chat_edit_message(%L, %L)', pg_temp.id('e2'), '   '), 'P0001', 'invalid_message', 'leerer Text');
select throws_ok(format('select public.chat_edit_message(%L, %L)', pg_temp.id('e2'), repeat('y', 2001)), 'P0001', 'invalid_message', 'zu langer Text');
select throws_ok(format('select public.chat_edit_message(%L, %L)', pg_temp.id('voice'), 'Text'), 'P0001', 'invalid_input', 'Sprachnachricht nicht bearbeitbar');
select throws_ok(format('select public.chat_edit_message(%L, %L)', pg_temp.id('m1'), 'Wieder da'), 'P0001', 'not_found', 'gelöschte Nachricht nicht bearbeitbar');
select pg_temp.as_user(2);
select throws_ok(format('select public.chat_edit_message(%L, %L)', pg_temp.id('e2'), 'Gehackt'), 'P0001', 'not_found', 'fremde Nachricht: not_found');
select pg_temp.as_user(4);
select throws_ok(format('select public.chat_edit_message(%L, %L)', pg_temp.id('e2'), 'Gehackt'), 'P0001', 'not_found', 'Fremder: not_found');

-- Rate Limit: 30 Bearbeitungen je Minute.
select pg_temp.as_user(1);
select is(
  (select count(*)::int from generate_series(1, 29) s cross join lateral public.chat_edit_message(pg_temp.id('e2'), 'Version ' || s) r),
  29, 'weitere 29 Bearbeitungen in der Minute erlaubt'
);
select throws_ok(format('select public.chat_edit_message(%L, %L)', pg_temp.id('e2'), 'Version 31'), 'P0001', 'rate_limited', '31. Bearbeitung: rate_limited');

-- =============================================================================================================
-- Favoriten (privat)
-- =============================================================================================================

select pg_temp.as_user(2);
select lives_ok(format('select public.chat_set_favorite(%L, true)', pg_temp.id('e1')), 'ben markiert annas Nachricht als Favorit');
select lives_ok(format('select public.chat_set_favorite(%L, true)', pg_temp.id('e1')), 'erneut markieren: idempotent');
select is(
  (select array_agg(e->>'id') from jsonb_array_elements(public.chat_favorites(pg_temp.id('direct'))) e),
  array[pg_temp.id('e1')::text], 'ben: Favoriten der Unterhaltung'
);
select is(
  (select e->>'is_favorite' from jsonb_array_elements(public.chat_messages(pg_temp.id('direct'))) e where e->>'id' = pg_temp.id('e1')::text),
  'true', 'ben: is_favorite im Verlauf'
);
select pg_temp.as_user(1);
select is(
  (select e->>'is_favorite' from jsonb_array_elements(public.chat_messages(pg_temp.id('direct'))) e where e->>'id' = pg_temp.id('e1')::text),
  'false', 'anna sieht bens Favoriten nicht'
);
select is(public.chat_favorites(pg_temp.id('direct')), '[]'::jsonb, 'anna: keine Favoriten');
select throws_ok(format('select public.chat_set_favorite(%L, true)', pg_temp.id('emma1')), 'P0001', 'not_found', 'Nachricht einer blockierten Person: not_found');
select throws_ok(format('select public.chat_set_favorite(%L, null)', pg_temp.id('e1')), 'P0001', 'invalid_input', 'Favorit ohne Angabe');
select lives_ok(format('select public.chat_set_favorite(%L, true)', pg_temp.id('voice')), 'anna: eigene Sprachnachricht als Favorit');
select pg_temp.as_user(4);
select throws_ok(format('select public.chat_set_favorite(%L, true)', pg_temp.id('e1')), 'P0001', 'not_found', 'Fremder: not_found');
select throws_ok(format('select public.chat_favorites(%L)', pg_temp.id('direct')), 'P0001', 'not_found', 'Fremder: Favoritenliste not_found');
select pg_temp.as_user(2);
select lives_ok(format('select public.chat_set_favorite(%L, false)', pg_temp.id('e1')), 'ben entfernt den Favoriten');
select lives_ok(format('select public.chat_set_favorite(%L, false)', pg_temp.id('e1')), 'erneut entfernen: idempotent');
select is(public.chat_favorites(pg_temp.id('direct')), '[]'::jsonb, 'ben: Favoriten leer');

-- =============================================================================================================
-- Pins
-- =============================================================================================================

select pg_temp.as_user(3);
select pg_temp.send('c1', pg_temp.id('group'), 'text', 'Wichtig: Treffpunkt Brunnen');
select throws_ok(format('select public.chat_set_pinned(%L, true)', pg_temp.id('c1')), 'P0001', 'not_allowed', 'Gruppenmitglied ohne Owner-Rolle: not_allowed');
select is(public.chat_group_conversation('cf000000-0000-4000-8000-000000000001')->>'can_pin', 'false', 'Mitglied: can_pin false');
select pg_temp.as_user(1);
select is(public.chat_group_conversation('cf000000-0000-4000-8000-000000000001')->>'can_pin', 'true', 'Owner: can_pin true');
reset role;
delete from realtime.messages m where m.event = 'pins_changed';
set local role authenticated;
select pg_temp.as_user(1);
insert into t_r select 'pins', public.chat_set_pinned(pg_temp.id('c1'), true);
select is(
  (select jsonb_build_object('message', e->'message'->>'id', 'pinned_by', e->'pinned_by'->>'username', 'is_pinned', e->'message'->>'is_pinned')
     from jsonb_array_elements(pg_temp.r('pins')) e),
  jsonb_build_object('message', pg_temp.id('c1'), 'pinned_by', 'anna_a', 'is_pinned', 'true'),
  'Owner pinnt: Liste mit Nachricht, pinned_by und pinned_at'
);
select ok((pg_temp.r('pins')->0->>'pinned_at') is not null, 'pinned_at gesetzt');
select is(jsonb_array_length(public.chat_set_pinned(pg_temp.id('c1'), true)), 1, 'erneut anpinnen: idempotent');
reset role;
select is(
  (select count(*)::int from realtime.messages m where m.event = 'pins_changed' and m.private
      and m.topic = 'chat:' || (select result->>'id' from t_r where name = 'group')),
  1, 'Echtzeit: genau ein pins_changed an chat:<conversation_id>'
);
set local role authenticated;
select pg_temp.as_user(3);
select is(
  (select array_agg(e->'message'->>'id') from jsonb_array_elements(public.chat_pins(pg_temp.id('group'))) e),
  array[pg_temp.id('c1')::text], 'Mitglied sieht die Pins'
);
select is(
  (select e->>'is_pinned' from jsonb_array_elements(public.chat_messages(pg_temp.id('group'))) e where e->>'id' = pg_temp.id('c1')::text),
  'true', 'is_pinned im Verlauf für alle'
);

-- Höchstens 5 Pins.
select pg_temp.as_user(1);
select pg_temp.send('p' || n, pg_temp.id('group'), 'text', 'Pin ' || n) from generate_series(2, 6) n;
select is(
  (select max(jsonb_array_length(public.chat_set_pinned(pg_temp.id('p' || n), true)))::int from generate_series(2, 5) n),
  5, 'bis zu 5 Pins'
);
select throws_ok(format('select public.chat_set_pinned(%L, true)', pg_temp.id('p6')), 'P0001', 'pin_limit_reached', '6. Pin: pin_limit_reached');
select is(jsonb_array_length(public.chat_set_pinned(pg_temp.id('p5'), false)), 4, 'lösen');
select is(jsonb_array_length(public.chat_set_pinned(pg_temp.id('p5'), false)), 4, 'erneut lösen: idempotent');
select throws_ok(format('select public.chat_set_pinned(%L, true)', pg_temp.id('emma1')), 'P0001', 'not_found', 'Nachricht einer blockierten Person nicht anpinnbar');
select throws_ok(format('select public.chat_set_pinned(%L, null)', pg_temp.id('p6')), 'P0001', 'invalid_input', 'Pin ohne Angabe');

-- Gelöschte Nachricht verliert Pin (mit Hinweis) und Favoriten.
select pg_temp.as_user(3);
select lives_ok(format('select public.chat_set_favorite(%L, true)', pg_temp.id('c1')), 'cara: eigene Nachricht als Favorit');
reset role;
delete from realtime.messages m where m.event = 'pins_changed';
set local role authenticated;
select pg_temp.as_user(3);
select lives_ok(format('select public.chat_delete_message(%L)', pg_temp.id('c1')), 'cara löscht die angepinnte Nachricht');
reset role;
select is(
  (select count(*)::int from public.chat_message_pins pn where pn.message_id = (select (result->>'id')::uuid from t_r where name = 'c1'))
  + (select count(*)::int from public.chat_message_favorites f where f.message_id = (select (result->>'id')::uuid from t_r where name = 'c1')),
  0, 'Löschen entfernt Pin und Favoriten'
);
select ok(exists (select 1 from realtime.messages m where m.event = 'pins_changed'), 'Echtzeit: pins_changed nach dem Löschen');
set local role authenticated;

-- Blockierte Absender: Pins anderer bleiben, sind für die blockierende Person aber verborgen.
select pg_temp.as_user(1);
select pg_temp.send('anna_pin', pg_temp.id('group'), 'text', 'Annas Hinweis');
select pg_temp.as_user(3);
select pg_temp.send('cara_pin', pg_temp.id('group'), 'text', 'Caras Hinweis');
select pg_temp.as_user(1);
select lives_ok(format('select public.chat_set_pinned(%L, true)', pg_temp.id('cara_pin')), 'Owner pinnt caras Nachricht');
select lives_ok(format('select public.social_block_user(%L)', pg_temp.pid(3)), 'anna blockiert cara');
select ok(
  not exists (select 1 from jsonb_array_elements(public.chat_pins(pg_temp.id('group'))) e where e->'message'->>'id' = pg_temp.id('cara_pin')::text),
  'blockierende Person sieht den Pin nicht'
);
select is(
  jsonb_array_length(public.chat_set_pinned(pg_temp.id('cara_pin'), false)) >= 0, true,
  'Owner kann den verborgenen Pin trotzdem lösen'
);
select pg_temp.as_user(2);
select ok(
  not exists (select 1 from jsonb_array_elements(public.chat_pins(pg_temp.id('group'))) e where e->'message'->>'id' = pg_temp.id('cara_pin')::text),
  'gelöster Pin ist für alle weg'
);

-- Privatchat: beide Teilnehmer dürfen anpinnen, Fremde nicht.
select pg_temp.as_user(2);
select is(public.chat_open_direct(pg_temp.pid(1))->>'can_pin', 'true', 'Privatchat: can_pin true');
select is(jsonb_array_length(public.chat_set_pinned(pg_temp.id('e1'), true)), 1, 'Privatchat: ben pinnt annas Nachricht');
select pg_temp.as_user(1);
select is(jsonb_array_length(public.chat_set_pinned(pg_temp.id('reply1'), true)), 2, 'Privatchat: anna pinnt bens Nachricht');
select pg_temp.as_user(4);
select throws_ok(format('select public.chat_set_pinned(%L, true)', pg_temp.id('e1')), 'P0001', 'not_found', 'Fremder: Pin not_found');
select throws_ok(format('select public.chat_pins(%L)', pg_temp.id('direct')), 'P0001', 'not_found', 'Fremder: Pinliste not_found');

-- Ausgetretene Mitglieder verlieren den Zugriff.
select pg_temp.as_user(6);
select pg_temp.send('fritz1', pg_temp.id('group'), 'text', 'Tschüss');
select lives_ok($$select public.social_leave_group('cf000000-0000-4000-8000-000000000001')$$, 'fritz tritt aus');
select throws_ok(format('select public.chat_edit_message(%L, %L)', pg_temp.id('fritz1'), 'Doch nicht'), 'P0001', 'not_found', 'nach Austritt: Bearbeiten not_found');
select throws_ok(format('select public.chat_pins(%L)', pg_temp.id('group')), 'P0001', 'not_found', 'nach Austritt: Pins not_found');
select throws_ok(format('select public.chat_favorites(%L)', pg_temp.id('group')), 'P0001', 'not_found', 'nach Austritt: Favoriten not_found');

-- Ende der Freundschaft: Verlauf lesbar, aber kein Bearbeiten/Anpinnen mehr.
select pg_temp.as_user(1);
select lives_ok(format('select public.social_remove_friend(%L)', pg_temp.pid(2)), 'anna beendet die Freundschaft');
select throws_ok(format('select public.chat_edit_message(%L, %L)', pg_temp.id('e1'), 'Neu'), 'P0001', 'read_only', 'schreibgeschützt: Bearbeiten read_only');
select throws_ok(format('select public.chat_set_pinned(%L, false)', pg_temp.id('e1')), 'P0001', 'read_only', 'schreibgeschützt: Pins read_only');
select is(jsonb_array_length(public.chat_pins(pg_temp.id('direct'))), 2, 'schreibgeschützt: Pins weiter lesbar');

-- =============================================================================================================
-- Beweissicherung gemeldeter Sprachnachrichten, Auskunft
-- =============================================================================================================

select pg_temp.as_user(1);
select lives_ok(format('select pg_temp.upload(%L, %L)', pg_temp.id('group') || '/beweis.m4a', 'audio/mp4'), 'Audio für die Gruppe');
select pg_temp.send('report_me', pg_temp.id('group'), 'voice', null, pg_temp.id('group') || '/beweis.m4a', null, 4200);
select pg_temp.as_user(2);
select lives_ok(format('select public.social_report(%L, %L, %L)', 'message', pg_temp.id('report_me'), 'harassment'), 'ben meldet die Sprachnachricht');
select pg_temp.as_user(1);
select is(public.chat_delete_message(pg_temp.id('report_me'))->'media_path', 'null'::jsonb, 'gemeldete Sprachnachricht: Datei wird nicht zum Löschen freigegeben');
select is(pg_temp.delete_file(pg_temp.id('group') || '/beweis.m4a'), 0, 'gemeldete Audiodatei bleibt bis zur Moderation');
reset role;
select is(
  (select m.media_duration_ms from public.chat_messages m where m.id = (select (result->>'id')::uuid from t_r where name = 'report_me')),
  null, 'gelöschte Sprachnachricht ohne Dauer'
);
set local role authenticated;
select pg_temp.as_user(1);
insert into t_r select 'export', public.account_export();
select is(
  (select jsonb_build_object('favorites', jsonb_array_length(result->'chat_message_favorites'), 'pins', jsonb_array_length(result->'chat_message_pins'))
     from t_r where name = 'export'),
  jsonb_build_object('favorites', 1, 'pins', 4),
  'Export: eigene Favoriten und von mir gesetzte Pins'
);
select ok(
  (select bool_and(e ? 'reply_to_id' and e ? 'edited_at' and e ? 'media_duration_ms')
     from t_r, jsonb_array_elements(result->'chat_messages') e where name = 'export'),
  'Export: Nachrichten mit reply_to_id, edited_at, media_duration_ms'
);

select * from finish();
rollback;
