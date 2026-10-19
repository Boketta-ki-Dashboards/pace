-- Pace: Storage-Buckets und -Policies (Profilbilder, Gruppenbilder, Chat-Medien) und Realtime-Zugriff.
begin;
select plan(39);

-- =============================================================================================================
-- Struktur
-- =============================================================================================================

select is(
  (select array_agg(format('%s:%s:%s:%s', b.id, b.public, b.file_size_limit, array_to_string(b.allowed_mime_types, ',')) order by b.id)
     from storage.buckets b where b.id in ('avatars', 'group-images', 'chat-media')),
  array['avatars:f:5242880:image/jpeg,image/png,image/gif,image/heic,image/webp',
        'chat-media:f:10485760:image/jpeg,image/png,image/gif,image/heic,image/webp',
        'group-images:f:5242880:image/jpeg,image/png,image/gif,image/heic,image/webp'],
  'drei private Buckets mit Größen- und Formatgrenzen wie MediaRules'
);
select is(
  (select array_agg(p.polname::text || ':' || p.polcmd::text order by p.polname) from pg_policy p
    where p.polrelid = 'storage.objects'::regclass and p.polname like 'pace\_%'),
  array['pace_avatars_delete:d', 'pace_avatars_insert:a', 'pace_avatars_select:r', 'pace_chat_media_delete:d',
        'pace_chat_media_insert:a', 'pace_chat_media_select:r', 'pace_group_images_delete:d',
        'pace_group_images_insert:a', 'pace_group_images_select:r'],
  'Storage-Policies: lesen, hochladen, löschen – kein Überschreiben'
);
select is(
  (select array_agg(p.polname::text || ':' || p.polcmd::text order by p.polname) from pg_policy p
    where p.polrelid = 'realtime.messages'::regclass and p.polname like 'pace\_%'),
  array['pace_realtime_receive:r'], 'Realtime: nur Empfangen (keine insert-Policy)'
);
select is(
  (select array_agg(p.oid::regprocedure::text order by 1) from pg_proc p
    where p.pronamespace = 'pace_access'::regnamespace
      and (p.proconfig is distinct from array['search_path=""']
           or has_function_privilege('anon', p.oid, 'execute')
           or has_function_privilege('public', p.oid, 'execute')
           or not has_function_privilege('authenticated', p.oid, 'execute')
           or (not p.prosecdef and p.proname <> 'object_folder'))),
  null, 'pace_access: security definer, leerer search_path, nur authenticated'
);
select ok(
  not has_schema_privilege('anon', 'pace_access', 'usage') and has_schema_privilege('authenticated', 'pace_access', 'usage'),
  'pace_access: nur authenticated hat usage'
);
select ok(
  not exists (select 1 from regexp_split_to_table(current_setting('pgrst.db_schemas', true), ',') s where btrim(s) = 'pace_access'),
  'pace_access ist nicht über die Data API erreichbar'
);

-- =============================================================================================================
-- Testdaten
-- =============================================================================================================

-- 1 ella, 2 felix, 3 greg (Fremder, von ella blockiert), 4 hilde (eingeladen).
insert into auth.users (id, aud, role, is_anonymous)
select ('ac000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', true
  from generate_series(1, 4) n;
insert into public.profiles (id, public_id, username, display_name)
select ('ac000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       ('bc000000-0000-4000-8000-' || lpad(v.n::text, 12, '0'))::uuid,
       v.username, v.display_name
  from (values (1, 'ella', 'Ella'), (2, 'felix', 'Felix'), (3, 'greg', 'Greg'), (4, 'hilde', 'Hilde')) as v(n, username, display_name);
insert into public.friendships (user_a, user_b)
values ('ac000000-0000-4000-8000-000000000001', 'ac000000-0000-4000-8000-000000000002'),
       ('ac000000-0000-4000-8000-000000000001', 'ac000000-0000-4000-8000-000000000004');
insert into public.user_blocks (blocker_id, blocked_id)
values ('ac000000-0000-4000-8000-000000000001', 'ac000000-0000-4000-8000-000000000003');

-- Gruppe von ella mit felix; hilde ist eingeladen.
insert into public.groups (id, name, kind, invite_code, created_by)
values ('cc000000-0000-4000-8000-000000000001', 'Bildgruppe', 'friends', 'STRAGEXY', 'ac000000-0000-4000-8000-000000000001');
insert into public.group_goal_history (group_id, effective_from, daily_goal)
values ('cc000000-0000-4000-8000-000000000001', current_date - 5, 8000);
insert into public.group_members (group_id, user_id, role)
values ('cc000000-0000-4000-8000-000000000001', 'ac000000-0000-4000-8000-000000000001', 'owner'),
       ('cc000000-0000-4000-8000-000000000001', 'ac000000-0000-4000-8000-000000000002', 'member');
insert into public.group_invitations (group_id, inviter_id, invitee_id)
values ('cc000000-0000-4000-8000-000000000001', 'ac000000-0000-4000-8000-000000000001', 'ac000000-0000-4000-8000-000000000004');

-- Privatchat ella–felix.
insert into public.conversations (id, kind, user_a, user_b)
values ('dc000000-0000-4000-8000-000000000001', 'direct', 'ac000000-0000-4000-8000-000000000001', 'ac000000-0000-4000-8000-000000000002');

create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claims',
                    format('{"sub":"ac000000-0000-4000-8000-%s","role":"authenticated"}', lpad(n::text, 12, '0')), true);
$$;
-- Einfügen wie die Storage-API: als authenticated, owner_id = Nutzer.
create function pg_temp.upload(p_bucket text, p_name text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values (p_bucket, p_name, auth.uid()::text, '{"mimetype":"image/jpeg"}');
$$;
create function pg_temp.visible(p_bucket text, p_name text) returns boolean language sql as $$
  select exists (select 1 from storage.objects o where o.bucket_id = p_bucket and o.name = p_name);
$$;

-- Löschen wie die Storage-API (die direkte Löschsperre von Supabase ist dafür aufgehoben); Policies greifen.
create function pg_temp.delete_all(p_bucket text) returns integer language plpgsql as $$
declare
  v_count integer;
begin
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects o where o.bucket_id = p_bucket;
  get diagnostics v_count = row_count;
  perform set_config('storage.allow_delete_query', 'false', true);
  return v_count;
end;
$$;

set local role authenticated;

-- =============================================================================================================
-- avatars
-- =============================================================================================================

select pg_temp.as_user(1);
select lives_ok($$select pg_temp.upload('avatars', 'bc000000-0000-4000-8000-000000000001/ich.jpg')$$, 'avatars: Upload in den eigenen Ordner');
select throws_ok($$select pg_temp.upload('avatars', 'bc000000-0000-4000-8000-000000000002/fremd.jpg')$$, '42501', null, 'avatars: fremder Ordner verboten');
select throws_ok($$select pg_temp.upload('avatars', 'bc000000-0000-4000-8000-000000000001/../x.jpg')$$, '42501', null, 'avatars: ungültiger Pfad verboten');
select throws_ok($$select pg_temp.upload('avatars', 'ich.jpg')$$, '42501', null, 'avatars: ohne Ordner verboten');
select ok(pg_temp.visible('avatars', 'bc000000-0000-4000-8000-000000000001/ich.jpg'), 'avatars: eigenes Bild lesbar');
select pg_temp.as_user(2);
select ok(pg_temp.visible('avatars', 'bc000000-0000-4000-8000-000000000001/ich.jpg'), 'avatars: andere Angemeldete lesen');
select pg_temp.as_user(3);
select ok(not pg_temp.visible('avatars', 'bc000000-0000-4000-8000-000000000001/ich.jpg'), 'avatars: Blockierte lesen nicht');
select is(
  pg_temp.delete_all('avatars'),
  0, 'avatars: fremde Bilder nicht löschbar'
);
select pg_temp.as_user(1);
select is(
  pg_temp.delete_all('avatars'),
  1, 'avatars: eigenes Bild löschbar'
);

-- =============================================================================================================
-- group-images
-- =============================================================================================================

select lives_ok($$select pg_temp.upload('group-images', 'cc000000-0000-4000-8000-000000000001/titel.jpg')$$, 'group-images: owner lädt hoch');
select pg_temp.as_user(2);
select throws_ok($$select pg_temp.upload('group-images', 'cc000000-0000-4000-8000-000000000001/mitglied.jpg')$$, '42501', null, 'group-images: Mitglied darf nicht hochladen');
select ok(pg_temp.visible('group-images', 'cc000000-0000-4000-8000-000000000001/titel.jpg'), 'group-images: Mitglied liest');
select pg_temp.as_user(4);
select ok(pg_temp.visible('group-images', 'cc000000-0000-4000-8000-000000000001/titel.jpg'), 'group-images: Eingeladene liest');
select pg_temp.as_user(3);
select ok(not pg_temp.visible('group-images', 'cc000000-0000-4000-8000-000000000001/titel.jpg'), 'group-images: Fremder liest nicht');
select pg_temp.as_user(2);
select is(
  pg_temp.delete_all('group-images'),
  0, 'group-images: Mitglied löscht nicht'
);

-- =============================================================================================================
-- chat-media
-- =============================================================================================================

select pg_temp.as_user(2);
select lives_ok($$select pg_temp.upload('chat-media', 'dc000000-0000-4000-8000-000000000001/foto.jpg')$$, 'chat-media: Teilnehmer lädt hoch');
select pg_temp.as_user(1);
select ok(pg_temp.visible('chat-media', 'dc000000-0000-4000-8000-000000000001/foto.jpg'), 'chat-media: anderer Teilnehmer liest');
select pg_temp.as_user(3);
select ok(not pg_temp.visible('chat-media', 'dc000000-0000-4000-8000-000000000001/foto.jpg'), 'chat-media: Fremder liest nicht');
select throws_ok($$select pg_temp.upload('chat-media', 'dc000000-0000-4000-8000-000000000001/fremd.jpg')$$, '42501', null, 'chat-media: Fremder lädt nicht hoch');
select pg_temp.as_user(1);
select is(
  pg_temp.delete_all('chat-media'),
  0, 'chat-media: nur wer hochgeladen hat, löscht'
);
select pg_temp.as_user(2);
select is(
  pg_temp.delete_all('chat-media'),
  1, 'chat-media: eigene Datei löschbar'
);

-- Nach Ende der Freundschaft: lesen ja, hochladen nein.
reset role;
delete from public.friendships where user_a = 'ac000000-0000-4000-8000-000000000001' and user_b = 'ac000000-0000-4000-8000-000000000002';
insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('chat-media', 'dc000000-0000-4000-8000-000000000001/alt.jpg', 'ac000000-0000-4000-8000-000000000001', '{"mimetype":"image/jpeg"}');
set local role authenticated;
select pg_temp.as_user(2);
select ok(pg_temp.visible('chat-media', 'dc000000-0000-4000-8000-000000000001/alt.jpg'), 'chat-media: Verlauf bleibt lesbar');
select throws_ok($$select pg_temp.upload('chat-media', 'dc000000-0000-4000-8000-000000000001/neu.jpg')$$, '42501', null, 'chat-media: ohne Freundschaft kein Upload');

-- Ohne Anmeldung nichts.
set local role anon;
select is((select count(*)::int from storage.objects o where o.bucket_id in ('avatars', 'group-images', 'chat-media')), 0, 'anon liest nichts');

-- =============================================================================================================
-- Realtime: private Topics
-- =============================================================================================================

reset role;
select realtime.send('{"conversation_id":"dc000000-0000-4000-8000-000000000001"}'::jsonb, 'message', 'chat:dc000000-0000-4000-8000-000000000001', true);
select realtime.send('{"x":1}'::jsonb, 'conversation', 'user:bc000000-0000-4000-8000-000000000001', true);
create function pg_temp.receives(p_topic text) returns boolean language plpgsql as $$
begin
  perform set_config('realtime.topic', p_topic, true);
  return exists (select 1 from realtime.messages m where m.topic = p_topic and m.extension = 'broadcast');
end;
$$;

set local role authenticated;
select pg_temp.as_user(1);
select ok(pg_temp.receives('chat:dc000000-0000-4000-8000-000000000001'), 'Teilnehmer empfängt chat:<id>');
select ok(pg_temp.receives('user:bc000000-0000-4000-8000-000000000001'), 'eigenes user:<public_id>');
select pg_temp.as_user(2);
select ok(not pg_temp.receives('user:bc000000-0000-4000-8000-000000000001'), 'fremdes user:<public_id> nicht');
select ok(pg_temp.receives('chat:dc000000-0000-4000-8000-000000000001'), 'Teilnehmer nach Ende der Freundschaft: Verlauf lesbar, Hinweise auch');
select pg_temp.as_user(3);
select ok(not pg_temp.receives('chat:dc000000-0000-4000-8000-000000000001'), 'Fremder empfängt chat:<id> nicht');
select ok(not pg_temp.receives('chat:kein-uuid'), 'ungültiges Topic: kein Zugriff');
select throws_ok(
  $$insert into realtime.messages (topic, extension, payload, event, private) values ('chat:dc000000-0000-4000-8000-000000000001', 'broadcast', '{}', 'x', true)$$,
  '42501', null, 'Clients senden keine Broadcasts'
);

-- Blockierung: Privatchat-Topic für beide gesperrt.
reset role;
insert into public.user_blocks (blocker_id, blocked_id)
values ('ac000000-0000-4000-8000-000000000002', 'ac000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.as_user(1);
select ok(not pg_temp.receives('chat:dc000000-0000-4000-8000-000000000001'), 'nach Blockierung: kein Empfang');
select ok(not pg_temp.visible('chat-media', 'dc000000-0000-4000-8000-000000000001/alt.jpg'), 'nach Blockierung: Chat-Medien nicht lesbar');

select * from finish();
rollback;
