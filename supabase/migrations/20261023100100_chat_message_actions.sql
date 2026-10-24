-- =============================================================================================================
-- Pace – Nachrichtenaktionen (Antworten, Bearbeiten, Favoriten, Anpinnen) und Sprachnachrichten.
--
-- Nur additive, rückwärtskompatible Änderungen: neue Spalten (nullable), erweiterte Prüfregeln, neue Tabellen und
-- RPCs. chat_send bekommt zwei Parameter mit Standardwert (die alte Fassung wird ersetzt, damit PostgREST nicht
-- zwischen zwei Überladungen wählen muss) – Aufrufe älterer App-Versionen mit den bisherigen Parametern
-- funktionieren unverändert. Neue Felder in den Ausgaben ignorieren ältere Versionen.
--
-- * Antworten: chat_messages.reply_to_id verweist auf eine sichtbare, nicht gelöschte Nachricht derselben
--   Unterhaltung (beim Senden geprüft). chat_message_json liefert reply_to als kompakte Vorschau; ist das Original
--   inzwischen gelöscht oder von einer Person, die ich blockiert habe, nur {id, kind, is_deleted: true}.
-- * Bearbeiten (chat_edit_message): nur eigene, nicht gelöschte Textnachrichten in Unterhaltungen, in denen ich
--   noch schreiben darf; gleiche Längenregeln wie beim Senden; setzt edited_at. Echtzeit-Hinweis message_updated
--   an chat:<conversation_id> (und conversation an user:<public_id>) – weiterhin ohne Inhalt.
-- * Favoriten (chat_message_favorites): privat je Person, höchstens 1000; nie für andere sichtbar.
-- * Anpinnen (chat_message_pins): höchstens 5 je Unterhaltung. Gruppenchat: nur der Gruppen-Owner; Privatchat:
--   beide Teilnehmer, solange sie schreiben dürfen. Echtzeit-Hinweis pins_changed an chat:<conversation_id>. Pins
--   auf Nachrichten, die für mich verborgen sind (Absender von mir blockiert), zählen weiter zur Höchstzahl; wer
--   anpinnen darf, bekommt sie als Platzhalter ohne Inhalt und Absender (is_deleted: true) und kann sie lösen.
-- * Gelöschte Nachrichten verlieren Pins, Favoriten und ihre Dauer (Trigger).
-- * Sprachnachrichten: kind 'voice', Datei (AAC in .m4a bzw. .aac) im Bucket chat-media unter <conversation_id>/,
--   vom Absender hochgeladen (audio/mp4, audio/x-m4a oder audio/aac), Dauer 1 ms – 5 min (media_duration_ms).
--   Lesen/Schreiben/Löschen der Dateien wie bei Bildern; Beweissicherung gemeldeter Sprachnachrichten über
--   reports.evidence_path (media_path) wie bei Chat-Bildern. Bilder und GIFs müssen jetzt ausdrücklich einen
--   image/*-Typ haben.
-- * Fehler-Tokens: not_found, not_allowed, read_only, invalid_message, invalid_input, limit_reached,
--   pin_limit_reached, rate_limited.
-- =============================================================================================================

-- ---------------------------------------------------------------------------------------------------------------
-- Spalten und Prüfregeln
-- ---------------------------------------------------------------------------------------------------------------

alter table public.chat_messages
  add column reply_to_id uuid references public.chat_messages (id) on delete set null,
  add column edited_at timestamptz,
  add column media_duration_ms integer;

comment on column public.chat_messages.reply_to_id is
  'Nachricht, auf die geantwortet wird (gleiche Unterhaltung). Wird das Original endgültig gelöscht: null.';
comment on column public.chat_messages.edited_at is 'Zeitpunkt der letzten Bearbeitung (nur Textnachrichten).';
comment on column public.chat_messages.media_duration_ms is 'Dauer einer Sprachnachricht in Millisekunden (1–300000).';

-- Prüfregeln werden ohne Prüfung bestehender Zeilen angelegt und danach validiert (kürzere Sperre). Die neuen
-- Regeln sind Obermengen der alten bzw. betreffen nur neue Spalten – bestehende Zeilen erfüllen sie.
alter table public.chat_messages drop constraint chat_messages_kind_valid;
alter table public.chat_messages add constraint chat_messages_kind_valid
  check (kind in ('text', 'image', 'gif', 'profile', 'voice')) not valid;

alter table public.chat_messages drop constraint chat_messages_media_path_format;
alter table public.chat_messages add constraint chat_messages_media_path_format check (
  media_path is null
  or media_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|gif|heic|webp|m4a|aac)$'
) not valid;

alter table public.chat_messages add constraint chat_messages_media_duration_valid check (
  media_duration_ms is null or (kind = 'voice' and media_duration_ms between 1 and 300000)
) not valid;

-- Eine (nicht gelöschte) Sprachnachricht hat immer Datei und Dauer, aber weder Text noch geteiltes Profil.
alter table public.chat_messages add constraint chat_messages_voice_complete check (
  kind <> 'voice'
  or deleted_at is not null
  or (media_path is not null and media_duration_ms is not null and body is null and shared_profile_id is null)
) not valid;

alter table public.chat_messages add constraint chat_messages_reply_not_self check (reply_to_id <> id) not valid;

alter table public.chat_messages validate constraint chat_messages_kind_valid;
alter table public.chat_messages validate constraint chat_messages_media_path_format;
alter table public.chat_messages validate constraint chat_messages_media_duration_valid;
alter table public.chat_messages validate constraint chat_messages_voice_complete;
alter table public.chat_messages validate constraint chat_messages_reply_not_self;

-- Fremdschlüssel-Aktion beim endgültigen Löschen (Konto löschen) und Antworten auf eine Nachricht.
create index chat_messages_reply_to_idx on public.chat_messages (reply_to_id) where reply_to_id is not null;

-- ---------------------------------------------------------------------------------------------------------------
-- Favoriten und Pins
-- ---------------------------------------------------------------------------------------------------------------

create table public.chat_message_favorites (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  message_id uuid not null references public.chat_messages (id) on delete cascade,
  created_at timestamptz not null default now(),

  primary key (user_id, message_id)
);

comment on table public.chat_message_favorites is
  'Pace: private Favoriten (Stern) je Person und Nachricht. Kein Clientzugriff – nur über die chat_*-RPCs; nie für andere sichtbar.';

create index chat_message_favorites_message_idx on public.chat_message_favorites (message_id);

create table public.chat_message_pins (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  message_id      uuid not null references public.chat_messages (id) on delete cascade,
  pinned_by       uuid references public.profiles (id) on delete set null,
  pinned_at       timestamptz not null default clock_timestamp(),

  primary key (conversation_id, message_id)
);

comment on table public.chat_message_pins is
  'Pace: angepinnte Nachrichten je Unterhaltung (max. 5). Kein Clientzugriff – nur über chat_set_pinned/chat_pins.';

create index chat_message_pins_message_idx on public.chat_message_pins (message_id);
create index chat_message_pins_pinned_by_idx on public.chat_message_pins (pinned_by);

alter table public.chat_message_favorites enable row level security;
alter table public.chat_message_pins enable row level security;
revoke all on table public.chat_message_favorites from anon, authenticated;
revoke all on table public.chat_message_pins from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Storage: Sprachnachrichten im Bucket chat-media
-- ---------------------------------------------------------------------------------------------------------------

-- Gleiche Größengrenze (10 MB), zusätzlich AAC-Audio (Aufnahme in der App als AAC in .m4a).
update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/gif', 'image/heic', 'image/webp',
                                  'audio/mp4', 'audio/x-m4a', 'audio/aac']
 where id = 'chat-media';

-- Ordner (Unterhaltung) einer Chat-Datei: wie pace_access.object_folder, zusätzlich mit Audio-Endungen. Profil- und
-- Gruppenbilder prüfen weiter nur Bildendungen.
create function pace_access.chat_media_folder(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|gif|heic|webp|m4a|aac)$'
    then split_part(p_name, '/', 1)::uuid
  end;
$$;
revoke all on function pace_access.chat_media_folder(text) from public, anon;
grant execute on function pace_access.chat_media_folder(text) to authenticated;

-- Ersetzen die Fassungen aus 20261019100300_storage_realtime_access.sql (gleiche Regeln, Ordner mit Audio-Endungen).
-- Die Policies verweisen auf dieselben Funktionen und bleiben unverändert.
create or replace function pace_access.can_read_chat_media(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and private.can_read_conversation(pace_access.chat_media_folder(p_name), auth.uid());
$$;

create or replace function pace_access.can_write_chat_media(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and private.can_send_conversation(pace_access.chat_media_folder(p_name), auth.uid());
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Hilfsfunktionen (intern)
-- ---------------------------------------------------------------------------------------------------------------

-- Echtzeit-Hinweis ohne Inhalt nur an chat:<conversation_id> (z. B. pins_changed – die Chatliste ändert sich nicht).
create function private.notify_conversation_topic(p_conversation_id uuid, p_event text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is null then
    return;
  end if;
  perform realtime.send(
    jsonb_build_object('conversation_id', p_conversation_id, 'event', p_event),
    p_event,
    'chat:' || p_conversation_id::text,
    true
  );
end;
$$;
revoke all on function private.notify_conversation_topic(uuid, text) from public, anon, authenticated;

-- Sieht p_me die Nachricht? Nicht gelöscht und nicht von einer Person, die p_me blockiert hat (das Lesen der
-- Unterhaltung prüft der Aufrufer).
create function private.chat_message_visible(p_message public.chat_messages, p_me uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_message.id is not null
     and p_message.deleted_at is null
     and (p_message.sender_id is null or not private.has_blocked(p_me, p_message.sender_id));
$$;
revoke all on function private.chat_message_visible(public.chat_messages, uuid) from public, anon, authenticated;

-- Darf p_user_id in der Unterhaltung anpinnen? Gruppenchat: Owner der Gruppe; Privatchat: wer schreiben darf.
create function private.can_pin_conversation(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((
    select case c.kind
      when 'group' then private.group_role(c.group_id, p_user_id) = 'owner'
      else private.can_send_conversation(c.id, p_user_id)
    end
      from public.conversations c
     where c.id = p_conversation_id
  ), false);
$$;
revoke all on function private.can_pin_conversation(uuid, uuid) from public, anon, authenticated;

-- Kompakte Vorschau der Nachricht, auf die geantwortet wird (Text gekürzt auf 200 Zeichen). Gelöschte bzw. für p_me
-- nicht sichtbare Originale nur mit id, kind und is_deleted = true.
create function private.chat_reply_json(p_reply_to_id uuid, p_me uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select case when private.chat_message_visible(r, p_me) then
           jsonb_build_object(
             'id', r.id,
             'sender', (select private.profile_json(s) from public.profiles s where s.id = r.sender_id),
             'kind', r.kind,
             'text', case when r.kind = 'text' then left(r.body, 200) end,
             'media_duration_ms', r.media_duration_ms,
             'is_deleted', false
           )
         else
           jsonb_build_object(
             'id', r.id, 'sender', null, 'kind', r.kind, 'text', null, 'media_duration_ms', null, 'is_deleted', true
           )
         end
    from public.chat_messages r
   where r.id = p_reply_to_id;
$$;
revoke all on function private.chat_reply_json(uuid, uuid) from public, anon, authenticated;

-- Ersetzt die Fassung aus 20261019100200_chat.sql: zusätzlich media_duration_ms, reply_to, edited_at, is_favorite
-- (nur für p_me) und is_pinned.
create or replace function private.chat_message_json(p_message public.chat_messages, p_me uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_message.id,
    'conversation_id', p_message.conversation_id,
    -- Die Geräte-ID gehört nur dem Absender.
    'client_id', case when p_message.sender_id = p_me then p_message.client_id end,
    'sender', (select private.profile_json(s) from public.profiles s where s.id = p_message.sender_id),
    'is_own', coalesce(p_message.sender_id = p_me, false),
    'kind', p_message.kind,
    'body', p_message.body,
    'media_path', p_message.media_path,
    'media_duration_ms', p_message.media_duration_ms,
    'shared_profile', (
      select private.profile_json(sp)
        from public.profiles sp
       where sp.id = p_message.shared_profile_id
         and not private.is_blocked(p_me, sp.id)
    ),
    'reply_to', case when p_message.reply_to_id is not null then private.chat_reply_json(p_message.reply_to_id, p_me) end,
    'edited_at', p_message.edited_at,
    'is_favorite', exists (
      select 1 from public.chat_message_favorites f where f.user_id = p_me and f.message_id = p_message.id
    ),
    'is_pinned', exists (select 1 from public.chat_message_pins pn where pn.message_id = p_message.id),
    'created_at', p_message.created_at
  );
$$;

-- Ersetzt die Fassung aus 20261019100200_chat.sql: last_message mit sender_nickname (eigener Spitzname) und
-- media_duration_ms (Sprachnachricht), dazu can_pin.
create or replace function private.conversation_json(p_conversation public.conversations, p_me uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_peer public.profiles%rowtype;
  v_group public.groups%rowtype;
  v_last public.chat_messages%rowtype;
  v_last_read timestamptz;
  v_unread integer;
  v_member_count integer;
begin
  if p_conversation.kind = 'direct' then
    select * into v_peer
      from public.profiles p
     where p.id = case when p_conversation.user_a = p_me then p_conversation.user_b else p_conversation.user_a end;
    v_member_count := (p_conversation.user_a is not null)::integer + (p_conversation.user_b is not null)::integer;
  else
    select * into v_group from public.groups g where g.id = p_conversation.group_id;
    select count(*)::integer into v_member_count from public.group_members m where m.group_id = v_group.id;
  end if;

  -- Letzte sichtbare Nachricht: nicht gelöscht, nicht von Personen, die ich blockiert habe.
  select * into v_last
    from public.chat_messages m
   where m.conversation_id = p_conversation.id
     and m.deleted_at is null
     and (m.sender_id is null or not private.has_blocked(p_me, m.sender_id))
   order by m.created_at desc, m.id desc
   limit 1;

  select r.last_read_at into v_last_read
    from public.conversation_reads r
   where r.conversation_id = p_conversation.id and r.user_id = p_me;

  -- Ungelesen: höchstens 100 zählen (die App zeigt „99+“).
  select count(*)::integer into v_unread
    from (
      select 1
        from public.chat_messages m
       where m.conversation_id = p_conversation.id
         and m.deleted_at is null
         and m.sender_id is distinct from p_me
         and (v_last_read is null or m.created_at > v_last_read)
         and (m.sender_id is null or not private.has_blocked(p_me, m.sender_id))
       limit 100
    ) u;

  return jsonb_build_object(
    'id', p_conversation.id,
    'kind', p_conversation.kind,
    'title', case when p_conversation.kind = 'direct' then v_peer.display_name else v_group.name end,
    'peer', case when v_peer.id is not null then private.profile_json(v_peer) end,
    'group_id', p_conversation.group_id,
    'group_image_path', v_group.image_path,
    'member_count', v_member_count,
    'last_message', case when v_last.id is not null then jsonb_build_object(
      'kind', v_last.kind,
      'text', case when v_last.kind = 'text' then v_last.body end,
      'sender_name', case when v_last.sender_id is distinct from p_me then
        (select s.display_name from public.profiles s where s.id = v_last.sender_id) end,
      'sender_nickname', case when v_last.sender_id is distinct from p_me then
        private.friend_nickname(p_me, v_last.sender_id) end,
      'media_duration_ms', v_last.media_duration_ms,
      'is_own', coalesce(v_last.sender_id = p_me, false),
      'sent_at', v_last.created_at
    ) end,
    'unread_count', v_unread,
    'can_send', private.can_send_conversation(p_conversation.id, p_me),
    'can_pin', private.can_pin_conversation(p_conversation.id, p_me),
    'updated_at', coalesce(p_conversation.last_message_at, p_conversation.created_at)
  );
end;
$$;

-- Angepinnte Nachrichten einer Unterhaltung, zuletzt angepinnte zuerst. Für p_me sichtbare vollständig. Verborgene
-- (gelöscht oder von einer Person, die p_me blockiert hat) zählen weiter zur Höchstzahl der Unterhaltung; wer
-- anpinnen darf, bekommt sie deshalb als Platzhalter, um sie lösen zu können: gleiche Felder wie eine Nachricht, aber
-- ohne Inhalt und Absender (nur id, conversation_id, kind, created_at, is_pinned, is_deleted = true; pinned_by null).
-- Alle anderen sehen verborgene Pins gar nicht.
create function private.chat_pins_json(p_conversation_id uuid, p_me uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with pins as (
    select pn.message_id, pn.pinned_by, pn.pinned_at, m as message, private.chat_message_visible(m, p_me) as visible
      from public.chat_message_pins pn
      join public.chat_messages m on m.id = pn.message_id
     where pn.conversation_id = p_conversation_id
  )
  select coalesce(
           jsonb_agg(
             case when p.visible then
               jsonb_build_object(
                 'message', private.chat_message_json(p.message, p_me),
                 'pinned_by', (select private.profile_json(pb) from public.profiles pb where pb.id = p.pinned_by),
                 'pinned_at', p.pinned_at
               )
             else
               jsonb_build_object(
                 'message', jsonb_build_object(
                   'id', (p.message).id,
                   'conversation_id', (p.message).conversation_id,
                   'client_id', null,
                   'sender', null,
                   'is_own', false,
                   'kind', (p.message).kind,
                   'body', null,
                   'media_path', null,
                   'media_duration_ms', null,
                   'shared_profile', null,
                   'reply_to', null,
                   'edited_at', null,
                   'is_favorite', false,
                   'is_pinned', true,
                   'created_at', (p.message).created_at,
                   'is_deleted', true
                 ),
                 'pinned_by', null,
                 'pinned_at', p.pinned_at
               )
             end
             order by p.pinned_at desc, p.message_id
           ),
           '[]'::jsonb
         )
    from pins p
   where p.visible or private.can_pin_conversation(p_conversation_id, p_me);
$$;
revoke all on function private.chat_pins_json(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Trigger: gelöschte Nachrichten
-- ---------------------------------------------------------------------------------------------------------------

-- Beim Löschen (chat_delete_message) verschwindet mit dem Inhalt auch die Dauer einer Sprachnachricht.
create function private.clear_deleted_chat_message()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.media_duration_ms := null;
  return new;
end;
$$;
revoke all on function private.clear_deleted_chat_message() from public, anon, authenticated;

create trigger chat_messages_before_soft_delete
  before update of deleted_at on public.chat_messages
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function private.clear_deleted_chat_message();

-- Gelöschte Nachrichten sind weder Favorit noch angepinnt; ein entfernter Pin wird in Echtzeit gemeldet.
create function private.handle_chat_message_deleted_actions()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  delete from public.chat_message_favorites f where f.message_id = new.id;
  delete from public.chat_message_pins pn where pn.message_id = new.id;
  if found then
    perform private.notify_conversation_topic(new.conversation_id, 'pins_changed');
  end if;
  return null;
end;
$$;
revoke all on function private.handle_chat_message_deleted_actions() from public, anon, authenticated;

create trigger chat_messages_after_soft_delete_actions
  after update of deleted_at on public.chat_messages
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function private.handle_chat_message_deleted_actions();

-- ---------------------------------------------------------------------------------------------------------------
-- RPC: Senden (mit Antwort und Sprachnachricht)
-- ---------------------------------------------------------------------------------------------------------------

-- Ersetzt die Fassung aus 20261019100200_chat.sql. Die bisherigen Parameter bleiben gleich (ältere App-Versionen),
-- neu sind p_reply_to_id und p_media_duration_ms mit Standardwert null.
drop function public.chat_send(uuid, uuid, text, text, text, uuid);

create function public.chat_send(
  p_conversation_id uuid,
  p_client_id uuid,
  p_kind text,
  p_body text default null,
  p_media_path text default null,
  p_shared_profile_id uuid default null,
  p_reply_to_id uuid default null,
  p_media_duration_ms integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_message public.chat_messages%rowtype;
  v_body text;
  v_media_path text;
  v_shared_id uuid;
  v_mime text;
begin
  if p_client_id is null then
    raise exception 'invalid_input';
  end if;

  -- Wiederholung: Die Nachricht mit dieser client_id gibt es schon – unverändert zurückgeben.
  select * into v_message from public.chat_messages m where m.sender_id = v_me and m.client_id = p_client_id;
  if found then
    if v_message.conversation_id <> p_conversation_id then
      raise exception 'invalid_input';
    end if;
    return private.chat_message_json(v_message, v_me);
  end if;

  perform private.require_conversation(p_conversation_id, v_me);
  if not private.can_send_conversation(p_conversation_id, v_me) then
    raise exception 'read_only';
  end if;

  -- Eine Dauer gibt es nur bei Sprachnachrichten.
  if p_media_duration_ms is not null and p_kind is distinct from 'voice' then
    raise exception 'invalid_input';
  end if;

  case p_kind
    when 'text' then
      v_body := btrim(coalesce(p_body, ''), E' \t\n\r');
      if char_length(v_body) not between 1 and 2000 or translate(v_body, E'\n\t', '') ~ '[[:cntrl:]]' then
        raise exception 'invalid_message';
      end if;
      if p_media_path is not null or p_shared_profile_id is not null then
        raise exception 'invalid_input';
      end if;
    when 'image', 'gif', 'voice' then
      if p_body is not null or p_shared_profile_id is not null or p_media_path is null then
        raise exception 'invalid_input';
      end if;
      if p_kind = 'voice' and (p_media_duration_ms is null or p_media_duration_ms not between 1 and 300000) then
        raise exception 'invalid_input';
      end if;
      -- Nur eigene, bereits hochgeladene Dateien im Ordner dieser Unterhaltung mit passendem Typ: Bilder image/*,
      -- GIFs image/gif, Sprachnachrichten AAC-Audio.
      select o.metadata ->> 'mimetype' into v_mime
        from storage.objects o
       where o.bucket_id = 'chat-media'
         and o.name = p_media_path
         and o.owner_id = v_me::text
         and split_part(o.name, '/', 1) = p_conversation_id::text;
      if v_mime is null
         or (p_kind = 'image' and v_mime not like 'image/%')
         or (p_kind = 'gif' and v_mime <> 'image/gif')
         or (p_kind = 'voice' and v_mime not in ('audio/mp4', 'audio/x-m4a', 'audio/aac')) then
        raise exception 'invalid_input';
      end if;
      v_media_path := p_media_path;
    when 'profile' then
      if p_body is not null or p_media_path is not null or p_shared_profile_id is null then
        raise exception 'invalid_input';
      end if;
      select p.id into v_shared_id from public.profiles p where p.public_id = p_shared_profile_id;
      -- Nur Profile, die ich selbst sehen darf (wie social_public_profile) – sonst ließen sich beliebige public_ids
      -- über die Antwort (shared_profile) zu Namen auflösen.
      if v_shared_id is null
         or private.is_blocked(v_me, v_shared_id)
         or not private.can_view_profile(v_me, v_shared_id) then
        raise exception 'not_found';
      end if;
    else
      raise exception 'invalid_input';
  end case;

  -- Antwort nur auf eine Nachricht derselben Unterhaltung, die ich sehe (nicht gelöscht, nicht blockiert).
  if p_reply_to_id is not null and not exists (
    select 1 from public.chat_messages r
     where r.id = p_reply_to_id
       and r.conversation_id = p_conversation_id
       and private.chat_message_visible(r, v_me)
  ) then
    raise exception 'not_found';
  end if;

  perform private.consume_rate_limit(v_me, 'chat_send', 30, interval '1 minute');
  perform private.consume_rate_limit(v_me, 'chat_send_daily', 2000, interval '24 hours');

  begin
    insert into public.chat_messages (
      conversation_id, sender_id, client_id, kind, body, media_path, shared_profile_id, reply_to_id, media_duration_ms
    )
    values (
      p_conversation_id, v_me, p_client_id, p_kind, v_body, v_media_path, v_shared_id, p_reply_to_id,
      case when p_kind = 'voice' then p_media_duration_ms end
    )
    on conflict (sender_id, client_id) do nothing;
  exception
    when check_violation then
      raise exception 'invalid_message';
  end;

  -- Paralleler Versuch mit derselben client_id: die gespeicherte Nachricht liefern.
  select * into v_message
    from public.chat_messages m
   where m.sender_id = v_me and m.client_id = p_client_id;
  if v_message.conversation_id <> p_conversation_id then
    raise exception 'invalid_input';
  end if;
  return private.chat_message_json(v_message, v_me);
end;
$$;

revoke all on function public.chat_send(uuid, uuid, text, text, text, uuid, uuid, integer) from public, anon;
grant execute on function public.chat_send(uuid, uuid, text, text, text, uuid, uuid, integer) to authenticated;
comment on function public.chat_send(uuid, uuid, text, text, text, uuid, uuid, integer) is
  'Pace: Nachricht senden (idempotent per client_id): text, image, gif, profile oder voice (Datei + Dauer ≤ 5 min), optional als Antwort auf eine sichtbare Nachricht derselben Unterhaltung. read_only, wenn nicht mehr geschrieben werden kann. Max. 30 je Minute.';

-- ---------------------------------------------------------------------------------------------------------------
-- RPC: Bearbeiten
-- ---------------------------------------------------------------------------------------------------------------

create function public.chat_edit_message(p_message_id uuid, p_text text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_message public.chat_messages%rowtype;
  v_body text;
begin
  select * into v_message
    from public.chat_messages m
   where m.id = p_message_id and m.sender_id = v_me and m.deleted_at is null
     for update;
  if not found then
    raise exception 'not_found';
  end if;
  perform private.require_conversation(v_message.conversation_id, v_me);
  if v_message.kind <> 'text' then
    raise exception 'invalid_input';
  end if;
  if not private.can_send_conversation(v_message.conversation_id, v_me) then
    raise exception 'read_only';
  end if;

  v_body := btrim(coalesce(p_text, ''), E' \t\n\r');
  if char_length(v_body) not between 1 and 2000 or translate(v_body, E'\n\t', '') ~ '[[:cntrl:]]' then
    raise exception 'invalid_message';
  end if;
  -- Unveränderter Text: nichts zu tun (kein „Bearbeitet“, kein Hinweis).
  if v_body = v_message.body then
    return private.chat_message_json(v_message, v_me);
  end if;

  perform private.consume_rate_limit(v_me, 'chat_edit', 30, interval '1 minute');

  begin
    update public.chat_messages m
       set body = v_body, edited_at = clock_timestamp()
     where m.id = p_message_id
    returning * into v_message;
  exception
    when check_violation then
      raise exception 'invalid_message';
  end;

  perform private.notify_conversation(v_message.conversation_id, 'message_updated');
  return private.chat_message_json(v_message, v_me);
end;
$$;

revoke all on function public.chat_edit_message(uuid, text) from public, anon;
grant execute on function public.chat_edit_message(uuid, text) to authenticated;
comment on function public.chat_edit_message(uuid, text) is
  'Pace: eigene, nicht gelöschte Textnachricht bearbeiten (1–2000 Zeichen, setzt edited_at, Echtzeit-Hinweis message_updated). invalid_input bei anderen Arten, read_only ohne Schreibrecht. Max. 30 je Minute.';

-- ---------------------------------------------------------------------------------------------------------------
-- RPCs: Favoriten
-- ---------------------------------------------------------------------------------------------------------------

create function public.chat_set_favorite(p_message_id uuid, p_favorite boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_message public.chat_messages%rowtype;
begin
  if p_favorite is null then
    raise exception 'invalid_input';
  end if;

  -- Entfernen geht immer (idempotent), auch wenn die Nachricht nicht mehr sichtbar ist.
  if not p_favorite then
    delete from public.chat_message_favorites f where f.user_id = v_me and f.message_id = p_message_id;
    return;
  end if;

  -- Die Nachricht bis zum Ende der Transaktion gegen paralleles Löschen sperren (for share): chat_delete_message
  -- wartet dann, bis der Favorit steht, und sein Trigger entfernt ihn wieder. Läuft das Löschen schon, wartet diese
  -- Abfrage und findet die Nachricht danach nicht mehr (deleted_at is null wird neu geprüft).
  select * into v_message
    from public.chat_messages m
   where m.id = p_message_id and m.deleted_at is null
     for share;
  if not found
     or not private.chat_message_visible(v_message, v_me)
     or not private.can_read_conversation(v_message.conversation_id, v_me) then
    raise exception 'not_found';
  end if;
  if exists (select 1 from public.chat_message_favorites f where f.user_id = v_me and f.message_id = p_message_id) then
    return;
  end if;

  perform private.lock_users(array[v_me]);
  if (select count(*) from public.chat_message_favorites f where f.user_id = v_me) >= 1000 then
    raise exception 'limit_reached';
  end if;
  perform private.consume_rate_limit(v_me, 'chat_favorite', 60, interval '1 minute');

  insert into public.chat_message_favorites (user_id, message_id)
  values (v_me, p_message_id)
  on conflict (user_id, message_id) do nothing;
end;
$$;

revoke all on function public.chat_set_favorite(uuid, boolean) from public, anon;
grant execute on function public.chat_set_favorite(uuid, boolean) to authenticated;
comment on function public.chat_set_favorite(uuid, boolean) is
  'Pace: Nachricht privat als Favorit markieren bzw. entfernen (idempotent). Nur sichtbare Nachrichten lesbarer Unterhaltungen; max. 1000 Favoriten, 60 je Minute.';

create function public.chat_favorites(p_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.require_conversation(p_conversation_id, v_me);

  -- Neueste Nachrichten zuerst, ohne gelöschte und ohne Nachrichten von Personen, die ich blockiert habe.
  return (
    select coalesce(jsonb_agg(private.chat_message_json(x.message, v_me) order by x.created_at desc, x.id desc), '[]'::jsonb)
      from (
        select m as message, m.created_at, m.id
          from public.chat_message_favorites f
          join public.chat_messages m on m.id = f.message_id
         where f.user_id = v_me
           and m.conversation_id = p_conversation_id
           and private.chat_message_visible(m, v_me)
         order by m.created_at desc, m.id desc
         limit 500
      ) x
  );
end;
$$;

revoke all on function public.chat_favorites(uuid) from public, anon;
grant execute on function public.chat_favorites(uuid) to authenticated;
comment on function public.chat_favorites(uuid) is
  'Pace: eigene Favoriten einer lesbaren Unterhaltung (Form wie chat_messages), neueste Nachricht zuerst, max. 500.';

-- ---------------------------------------------------------------------------------------------------------------
-- RPCs: Anpinnen
-- ---------------------------------------------------------------------------------------------------------------

create function public.chat_set_pinned(p_message_id uuid, p_pinned boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_message public.chat_messages%rowtype;
  v_conversation public.conversations%rowtype;
begin
  if p_pinned is null then
    raise exception 'invalid_input';
  end if;

  if p_pinned then
    -- Anpinnen nur nicht gelöschte Nachrichten, bis zum Ende der Transaktion gegen paralleles Löschen gesperrt
    -- (for share): chat_delete_message wartet dann, bis der Pin steht, und sein Trigger entfernt ihn wieder. Läuft
    -- das Löschen schon, wartet diese Abfrage und findet die Nachricht danach nicht mehr (deleted_at is null wird
    -- neu geprüft) – so bleibt kein Pin an einer gelöschten Nachricht hängen.
    select * into v_message
      from public.chat_messages m
     where m.id = p_message_id and m.deleted_at is null
       for share;
  else
    -- Lösen auch, wenn die Nachricht für mich verborgen ist (z. B. blockierter Absender).
    select * into v_message from public.chat_messages m where m.id = p_message_id;
  end if;
  if not found then
    raise exception 'not_found';
  end if;
  v_conversation := private.require_conversation(v_message.conversation_id, v_me);
  -- Anpinnen nur Nachrichten, die ich sehe (geprüft nach der Sperre).
  if p_pinned and not private.chat_message_visible(v_message, v_me) then
    raise exception 'not_found';
  end if;
  if not private.can_pin_conversation(v_conversation.id, v_me) then
    if v_conversation.kind = 'group' then
      raise exception 'not_allowed';
    end if;
    raise exception 'read_only';
  end if;

  -- Pins einer Unterhaltung nacheinander ändern (Höchstzahl prüfen, dann einfügen). Advisory-Lock je Unterhaltung
  -- statt einer Zeilensperre auf conversations: Eine Sperre „for no key update“ kollidierte mit dem
  -- UPDATE conversations (last_message_at) im Insert-Trigger von chat_send – Senden müsste warten.
  perform pg_advisory_xact_lock(hashtextextended('pace.chat_pins:' || v_conversation.id::text, 0));

  if p_pinned then
    if not exists (
      select 1 from public.chat_message_pins pn
       where pn.conversation_id = v_conversation.id and pn.message_id = p_message_id
    ) then
      if (select count(*) from public.chat_message_pins pn where pn.conversation_id = v_conversation.id) >= 5 then
        raise exception 'pin_limit_reached';
      end if;
      perform private.consume_rate_limit(v_me, 'chat_pin', 30, interval '1 minute');
      insert into public.chat_message_pins (conversation_id, message_id, pinned_by)
      values (v_conversation.id, p_message_id, v_me);
      perform private.notify_conversation_topic(v_conversation.id, 'pins_changed');
    end if;
  else
    delete from public.chat_message_pins pn
     where pn.conversation_id = v_conversation.id and pn.message_id = p_message_id;
    if found then
      perform private.consume_rate_limit(v_me, 'chat_pin', 30, interval '1 minute');
      perform private.notify_conversation_topic(v_conversation.id, 'pins_changed');
    end if;
  end if;

  return private.chat_pins_json(v_conversation.id, v_me);
end;
$$;

revoke all on function public.chat_set_pinned(uuid, boolean) from public, anon;
grant execute on function public.chat_set_pinned(uuid, boolean) to authenticated;
comment on function public.chat_set_pinned(uuid, boolean) is
  'Pace: Nachricht anpinnen bzw. lösen (idempotent) und alle Pins der Unterhaltung liefern. Gruppenchat nur Owner (not_allowed), Privatchat beide Teilnehmer mit Schreibrecht (read_only); max. 5 Pins (pin_limit_reached), 30 Änderungen je Minute.';

create function public.chat_pins(p_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.require_conversation(p_conversation_id, v_me);
  return private.chat_pins_json(p_conversation_id, v_me);
end;
$$;

revoke all on function public.chat_pins(uuid) from public, anon;
grant execute on function public.chat_pins(uuid) to authenticated;
comment on function public.chat_pins(uuid) is
  'Pace: angepinnte Nachrichten einer lesbaren Unterhaltung ({message, pinned_by, pinned_at}), zuletzt angepinnte zuerst. Verborgene Nachrichten (gelöscht bzw. Absender blockiert) nur für Personen, die anpinnen dürfen, als Platzhalter ohne Inhalt und Absender (message.is_deleted = true).';

-- ---------------------------------------------------------------------------------------------------------------
-- Datenschutz: Auskunft mit Antworten, Bearbeitungen, Sprachnachrichten, Favoriten und Pins
-- ---------------------------------------------------------------------------------------------------------------

-- Ersetzt die Fassung aus 20261023100000_friend_nicknames.sql: chat_messages mit reply_to_id, edited_at und
-- media_duration_ms; dazu chat_message_favorites und chat_message_pins (von mir angepinnt).
create or replace function public.account_export()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.consume_rate_limit(v_me, 'account_export', 5, interval '1 hour');

  return jsonb_build_object(
    'exported_at', now(),
    'profile', (
      select to_jsonb(p) - 'id' || jsonb_build_object('auth_user_id', p.id)
        from public.profiles p where p.id = v_me
    ),
    'daily_activity', (
      select coalesce(jsonb_agg(to_jsonb(a) - 'user_id' order by a.activity_date), '[]'::jsonb)
        from public.daily_activity a where a.user_id = v_me
    ),
    'friends', (
      select coalesce(jsonb_agg(private.profile_json(p) || jsonb_build_object('friends_since', f.friends_since)
                                order by f.friends_since), '[]'::jsonb)
        from private.friends_of(v_me) f join public.profiles p on p.id = f.friend_id
    ),
    'friend_nicknames', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'friend', private.profile_json(p),
               'nickname', n.nickname,
               'updated_at', n.updated_at
             ) order by n.updated_at), '[]'::jsonb)
        from public.friend_nicknames n join public.profiles p on p.id = n.target_id
       where n.owner_id = v_me
    ),
    'friend_requests', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', r.id,
               'direction', case when r.requester_id = v_me then 'outgoing' else 'incoming' end,
               'other', (select private.profile_json(o) from public.profiles o
                          where o.id = case when r.requester_id = v_me then r.addressee_id else r.requester_id end),
               'status', r.status,
               'created_at', r.created_at,
               'responded_at', r.responded_at
             ) order by r.created_at), '[]'::jsonb)
        from public.friend_requests r
       where r.requester_id = v_me or r.addressee_id = v_me
    ),
    'blocked_users', (
      select coalesce(jsonb_agg(private.profile_json(p) || jsonb_build_object('blocked_at', b.created_at)
                                order by b.created_at), '[]'::jsonb)
        from public.user_blocks b join public.profiles p on p.id = b.blocked_id
       where b.blocker_id = v_me
    ),
    'groups', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'group_id', g.id,
               'name', g.name,
               'description', g.description,
               'kind', g.kind,
               'privacy', g.privacy,
               'image_path', g.image_path,
               'role', m.role,
               'joined_at', m.joined_at,
               'created_by_me', g.created_by = v_me
             ) order by m.joined_at), '[]'::jsonb)
        from public.group_members m join public.groups g on g.id = m.group_id
       where m.user_id = v_me
    ),
    'group_membership_periods', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'group_id', mp.group_id, 'joined_at', mp.joined_at, 'left_at', mp.left_at
             ) order by mp.joined_at), '[]'::jsonb)
        from public.group_membership_periods mp where mp.user_id = v_me
    ),
    'group_invitations', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', i.id,
               'group_id', i.group_id,
               'direction', case when i.inviter_id = v_me then 'sent' else 'received' end,
               'other', (select private.profile_json(o) from public.profiles o
                          where o.id = case when i.inviter_id = v_me then i.invitee_id else i.inviter_id end),
               'status', i.status,
               'created_at', i.created_at,
               'responded_at', i.responded_at
             ) order by i.created_at), '[]'::jsonb)
        from public.group_invitations i
       where i.inviter_id = v_me or i.invitee_id = v_me
    ),
    'chat_messages', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', m.id,
               'conversation_id', m.conversation_id,
               'kind', m.kind,
               'body', m.body,
               'media_path', m.media_path,
               'media_duration_ms', m.media_duration_ms,
               'shared_profile', (select private.profile_json(s) from public.profiles s where s.id = m.shared_profile_id),
               'reply_to_id', m.reply_to_id,
               'created_at', m.created_at,
               'edited_at', m.edited_at,
               'deleted_at', m.deleted_at
             ) order by m.created_at), '[]'::jsonb)
        from public.chat_messages m where m.sender_id = v_me
    ),
    'chat_message_favorites', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'message_id', f.message_id, 'conversation_id', m.conversation_id, 'created_at', f.created_at
             ) order by f.created_at), '[]'::jsonb)
        from public.chat_message_favorites f join public.chat_messages m on m.id = f.message_id
       where f.user_id = v_me
    ),
    'chat_message_pins', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'conversation_id', pn.conversation_id, 'message_id', pn.message_id, 'pinned_at', pn.pinned_at
             ) order by pn.pinned_at), '[]'::jsonb)
        from public.chat_message_pins pn where pn.pinned_by = v_me
    ),
    'conversation_reads', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'conversation_id', r.conversation_id, 'last_read_at', r.last_read_at
             ) order by r.last_read_at), '[]'::jsonb)
        from public.conversation_reads r where r.user_id = v_me
    ),
    'reports', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', r.id,
               'target_type', r.target_type,
               'target_id', r.target_id,
               'reason', r.reason,
               'details', r.details,
               'status', r.status,
               'created_at', r.created_at
             ) order by r.created_at), '[]'::jsonb)
        from public.reports r where r.reporter_id = v_me
    ),
    'feedback', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'kind', f.kind, 'message', f.message, 'app_version', f.app_version, 'created_at', f.created_at
             ) order by f.created_at), '[]'::jsonb)
        from public.feedback f where f.user_id = v_me
    ),
    'media', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'bucket', o.bucket_id, 'path', o.name, 'created_at', o.created_at
             ) order by o.created_at), '[]'::jsonb)
        from storage.objects o
       where o.owner_id = v_me::text and o.bucket_id in ('avatars', 'group-images', 'chat-media')
    )
  );
end;
$$;

comment on function public.account_export() is
  'Pace: alle personenbezogenen Serverdaten des eigenen Kontos als JSON (Auskunft/Datenübertragbarkeit), inkl. Spitznamen, Favoriten und Pins. Max. 5 je Stunde.';
