-- =============================================================================================================
-- Pace – Storage (Profilbilder, Gruppenbilder, Chat-Medien) und Zugriffsprüfung für Realtime.
--
-- * Drei private Buckets mit Größen- und Formatgrenzen wie MediaRules in PaceCore. Dateinamen sind zufällig:
--   <Ordner>/<Name>.<jpg|jpeg|png|gif|heic|webp>. Überschreiben ist nicht vorgesehen (keine update-Policies).
-- * Policies auf storage.objects und realtime.messages rufen Security-Definer-Funktionen im Schema pace_access auf.
--   Das Schema ist nicht über die Data API erreichbar (nicht in [api].schemas); authenticated darf nur diese
--   Prüffunktionen ausführen. Die Funktionen lesen die Social-Tabellen, auf die Clients selbst keinen Zugriff haben.
--     avatars       lesen: alle Angemeldeten mit Profil, außer die Besitzerin des Ordners hat sie blockiert;
--                   schreiben/löschen: nur im Ordner der eigenen public_id.
--     group-images  lesen: Mitglieder und Personen mit offener Einladung; schreiben: owner der Gruppe;
--                   löschen: owner der Gruppe oder wer die Datei hochgeladen hat.
--     chat-media    lesen: wer die Unterhaltung lesen darf; schreiben: wer in ihr schreiben darf;
--                   löschen: wer die Datei hochgeladen hat.
-- * Realtime: Private Broadcast-Topics chat:<conversation_id> (wer die Unterhaltung lesen darf) und
--   user:<public_id> (nur die Person selbst). Nur Empfangen – Clients senden keine Broadcasts (keine insert-Policy).
-- =============================================================================================================

create schema if not exists pace_access;
revoke all on schema pace_access from public;
grant usage on schema pace_access to authenticated;
comment on schema pace_access is
  'Pace: Prüffunktionen für Storage- und Realtime-Policies. Nicht über die Data API erreichbar.';

-- ---------------------------------------------------------------------------------------------------------------
-- Buckets
-- ---------------------------------------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', false, 5242880, array['image/jpeg', 'image/png', 'image/gif', 'image/heic', 'image/webp']),
  ('group-images', 'group-images', false, 5242880, array['image/jpeg', 'image/png', 'image/gif', 'image/heic', 'image/webp']),
  ('chat-media', 'chat-media', false, 10485760, array['image/jpeg', 'image/png', 'image/gif', 'image/heic', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------------------------------------------
-- Prüffunktionen
-- ---------------------------------------------------------------------------------------------------------------

-- Ordner (erstes Pfadsegment) als UUID; null, wenn der Pfad nicht die erwartete Form hat.
create function pace_access.object_folder(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|gif|heic|webp)$'
    then split_part(p_name, '/', 1)::uuid
  end;
$$;
revoke all on function pace_access.object_folder(text) from public, anon;
grant execute on function pace_access.object_folder(text) to authenticated;

create function pace_access.can_read_avatar(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.profiles me, public.profiles owner
     where me.id = auth.uid()
       and owner.public_id = pace_access.object_folder(p_name)
       and not private.has_blocked(owner.id, me.id)
  );
$$;
revoke all on function pace_access.can_read_avatar(text) from public, anon;
grant execute on function pace_access.can_read_avatar(text) to authenticated;

create function pace_access.can_write_avatar(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles me
     where me.id = auth.uid() and me.public_id = pace_access.object_folder(p_name)
  );
$$;
revoke all on function pace_access.can_write_avatar(text) from public, anon;
grant execute on function pace_access.can_write_avatar(text) to authenticated;

create function pace_access.can_read_group_image(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and (
       private.group_role(pace_access.object_folder(p_name), auth.uid()) is not null
       or exists (
         select 1 from public.group_invitations i
          where i.group_id = pace_access.object_folder(p_name)
            and i.invitee_id = auth.uid()
            and i.status = 'pending'
       )
     );
$$;
revoke all on function pace_access.can_read_group_image(text) from public, anon;
grant execute on function pace_access.can_read_group_image(text) to authenticated;

create function pace_access.can_write_group_image(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.group_role(pace_access.object_folder(p_name), auth.uid()) = 'owner', false);
$$;
revoke all on function pace_access.can_write_group_image(text) from public, anon;
grant execute on function pace_access.can_write_group_image(text) to authenticated;

create function pace_access.can_read_chat_media(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and private.can_read_conversation(pace_access.object_folder(p_name), auth.uid());
$$;
revoke all on function pace_access.can_read_chat_media(text) from public, anon;
grant execute on function pace_access.can_read_chat_media(text) to authenticated;

create function pace_access.can_write_chat_media(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and private.can_send_conversation(pace_access.object_folder(p_name), auth.uid());
$$;
revoke all on function pace_access.can_write_chat_media(text) from public, anon;
grant execute on function pace_access.can_write_chat_media(text) to authenticated;

-- Realtime-Topic empfangen: chat:<conversation_id> oder user:<public_id> (siehe Kopf).
create function pace_access.can_receive_topic(p_topic text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_id text := substring(p_topic from '^(?:chat|user):([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$');
begin
  if v_me is null or v_id is null then
    return false;
  end if;
  if starts_with(p_topic, 'chat:') then
    return private.can_read_conversation(v_id::uuid, v_me);
  end if;
  return exists (select 1 from public.profiles p where p.id = v_me and p.public_id = v_id::uuid);
end;
$$;
revoke all on function pace_access.can_receive_topic(text) from public, anon;
grant execute on function pace_access.can_receive_topic(text) to authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Policies: Storage
-- ---------------------------------------------------------------------------------------------------------------

create policy pace_avatars_select on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and pace_access.can_read_avatar(name));

create policy pace_avatars_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and pace_access.can_write_avatar(name));

create policy pace_avatars_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and pace_access.can_write_avatar(name));

create policy pace_group_images_select on storage.objects
  for select to authenticated
  using (bucket_id = 'group-images' and pace_access.can_read_group_image(name));

create policy pace_group_images_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'group-images' and pace_access.can_write_group_image(name));

create policy pace_group_images_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'group-images'
    and (owner_id = (select auth.uid())::text or pace_access.can_write_group_image(name))
  );

create policy pace_chat_media_select on storage.objects
  for select to authenticated
  using (bucket_id = 'chat-media' and pace_access.can_read_chat_media(name));

create policy pace_chat_media_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'chat-media' and pace_access.can_write_chat_media(name));

create policy pace_chat_media_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'chat-media' and owner_id = (select auth.uid())::text);

-- ---------------------------------------------------------------------------------------------------------------
-- Policy: Realtime (private Broadcast-Kanäle)
-- ---------------------------------------------------------------------------------------------------------------

create policy pace_realtime_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and pace_access.can_receive_topic((select realtime.topic())));
