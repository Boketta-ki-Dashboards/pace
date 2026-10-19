-- =============================================================================================================
-- Pace – Chats: Privatchats unter Freunden und Gruppenchats.
--
-- * Kein direkter Tabellenzugriff für Clients (RLS ohne Policies, keine Rechte). Alles läuft über die chat_*-RPCs,
--   die auth.uid() und ein Profil voraussetzen.
-- * Privatchat: genau eine Unterhaltung je Paar. Anlegen nur unter Freunden ohne Blockierung. Endet die
--   Freundschaft, bleibt der Verlauf lesbar, Schreiben ist nicht mehr möglich (can_send = false). Besteht eine
--   Blockierung (gleich in welcher Richtung), ist der Privatchat für beide nicht sichtbar.
-- * Gruppenchat: eine Unterhaltung je Gruppe (per Trigger angelegt). Lesen und Schreiben nur für aktuelle
--   Mitglieder; nach Austritt oder Entfernen besteht kein Zugriff mehr. Nachrichten von Personen, die ich blockiert
--   habe, liefert der Server mir nicht aus (der Gruppenchat bleibt für beide nutzbar).
-- * Nachrichten: text (1–2000 Zeichen), image/gif (Datei im Bucket chat-media unter <conversation_id>/, vom
--   Absender hochgeladen) oder profile (geteiltes Profil über dessen public_id). client_id macht Wiederholungen
--   idempotent. Gelöschte Nachrichten verlieren ihren Inhalt und werden nicht mehr ausgeliefert.
-- * Echtzeit: Nach jeder neuen oder gelöschten Nachricht ein privater Broadcast an chat:<conversation_id> und
--   user:<public_id> jedes Teilnehmers – ohne Inhalt, nur „es gibt Neues“. Wer das Topic empfangen darf, prüft eine
--   Policy auf realtime.messages (20261019100300_storage_realtime_access.sql).
-- * Fehler-Tokens: not_found, blocked, read_only, invalid_message, invalid_input, rate_limited.
-- =============================================================================================================

-- ---------------------------------------------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------------------------------------------

create table public.conversations (
  id              uuid primary key default gen_random_uuid(),
  kind            text not null,
  group_id        uuid references public.groups (id) on delete cascade,
  -- Privatchat: die beiden Personen, kleinere ID zuerst. Wird ein Konto gelöscht, bleibt der Verlauf für die andere
  -- Person erhalten (null). Sind beide gelöscht, entfernt ein Trigger die Unterhaltung.
  user_a          uuid references public.profiles (id) on delete set null,
  user_b          uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz,

  constraint conversations_kind_valid check (kind in ('direct', 'group')),
  constraint conversations_shape check (
    (kind = 'group' and group_id is not null and user_a is null and user_b is null)
    or (kind = 'direct' and group_id is null and (user_a is null or user_b is null or user_a < user_b))
  )
);

comment on table public.conversations is
  'Pace: Unterhaltungen (direct je Paar, group je Gruppe). Kein Clientzugriff – nur über die chat_*-RPCs.';

create unique index conversations_group_key on public.conversations (group_id) where kind = 'group';
create unique index conversations_direct_pair_key on public.conversations (user_a, user_b) where kind = 'direct';
create index conversations_user_b_idx on public.conversations (user_b);

create table public.chat_messages (
  id                uuid primary key default gen_random_uuid(),
  conversation_id   uuid not null references public.conversations (id) on delete cascade,
  sender_id         uuid references public.profiles (id) on delete set null,
  client_id         uuid not null,
  kind              text not null,
  body              text,
  media_path        text,
  shared_profile_id uuid references public.profiles (id) on delete set null,
  -- clock_timestamp(): mehrere Nachrichten einer Transaktion bekommen trotzdem eine eindeutige Reihenfolge.
  created_at        timestamptz not null default clock_timestamp(),
  deleted_at        timestamptz,

  constraint chat_messages_kind_valid check (kind in ('text', 'image', 'gif', 'profile')),
  -- 1–2000 Zeichen ohne Rand-Leerraum; Zeilenumbrüche und Tabulatoren erlaubt, sonst keine Steuerzeichen.
  constraint chat_messages_body_valid check (
    body is null
    or (char_length(body) between 1 and 2000
        and body = btrim(body, E' \t\n\r')
        and translate(body, E'\n\t', '') !~ '[[:cntrl:]]')
  ),
  constraint chat_messages_media_path_format check (
    media_path is null
    or media_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|gif|heic|webp)$'
  ),
  -- Gelöschte Nachrichten behalten keinen Inhalt.
  constraint chat_messages_deleted_empty check (
    deleted_at is null or (body is null and media_path is null and shared_profile_id is null)
  )
);

comment on table public.chat_messages is
  'Pace: Chatnachrichten. Kein Clientzugriff – nur über die chat_*-RPCs. Gelöschte Nachrichten ohne Inhalt.';

-- Idempotentes Senden: dieselbe client_id desselben Absenders wird nur einmal gespeichert.
create unique index chat_messages_client_key on public.chat_messages (sender_id, client_id);
-- Verlauf (neueste zuerst, Seiten mit „before“) und letzte Nachricht.
create index chat_messages_conversation_idx on public.chat_messages (conversation_id, created_at desc, id desc);
create index chat_messages_shared_profile_idx on public.chat_messages (shared_profile_id)
  where shared_profile_id is not null;

create table public.conversation_reads (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references public.profiles (id) on delete cascade,
  last_read_at    timestamptz not null,

  primary key (conversation_id, user_id)
);

comment on table public.conversation_reads is
  'Pace: Lesestand je Unterhaltung und Person. Kein Clientzugriff – nur über die chat_*-RPCs.';

create index conversation_reads_user_idx on public.conversation_reads (user_id);

alter table public.conversations enable row level security;
alter table public.chat_messages enable row level security;
alter table public.conversation_reads enable row level security;

revoke all on table public.conversations from anon, authenticated;
revoke all on table public.chat_messages from anon, authenticated;
revoke all on table public.conversation_reads from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Trigger
-- ---------------------------------------------------------------------------------------------------------------

-- Jede Gruppe hat genau eine Unterhaltung.
create function private.create_group_conversation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.conversations (kind, group_id) values ('group', new.id)
  on conflict (group_id) where kind = 'group' do nothing;
  return null;
end;
$$;
revoke all on function private.create_group_conversation() from public, anon, authenticated;

create trigger groups_create_conversation
  after insert on public.groups
  for each row execute function private.create_group_conversation();

-- Bestehende Gruppen bekommen ihre Unterhaltung (rein additiv).
insert into public.conversations (kind, group_id)
select 'group', g.id from public.groups g
on conflict (group_id) where kind = 'group' do nothing;

-- Privatchat ohne verbleibende Teilnehmer (beide Konten gelöscht) entfernen.
create function private.delete_orphaned_conversation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  delete from public.conversations c where c.id = new.id;
  return null;
end;
$$;
revoke all on function private.delete_orphaned_conversation() from public, anon, authenticated;

create trigger conversations_delete_orphaned
  after update of user_a, user_b on public.conversations
  for each row
  when (new.kind = 'direct' and new.user_a is null and new.user_b is null)
  execute function private.delete_orphaned_conversation();

-- ---------------------------------------------------------------------------------------------------------------
-- Hilfsfunktionen (intern)
-- ---------------------------------------------------------------------------------------------------------------

-- Darf p_user_id die Unterhaltung lesen? Privatchat: Teilnehmer ohne Blockierung; Gruppenchat: aktuelles Mitglied.
create function private.can_read_conversation(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((
    select case c.kind
      when 'direct' then
        p_user_id in (c.user_a, c.user_b)
        and not private.is_blocked(c.user_a, c.user_b)
      else
        private.group_role(c.group_id, p_user_id) is not null
    end
      from public.conversations c
     where c.id = p_conversation_id
  ), false);
$$;
revoke all on function private.can_read_conversation(uuid, uuid) from public, anon, authenticated;

-- Darf p_user_id schreiben? Privatchat: beide Konten bestehen, befreundet, keine Blockierung; Gruppenchat: Mitglied.
create function private.can_send_conversation(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((
    select case c.kind
      when 'direct' then
        p_user_id in (c.user_a, c.user_b)
        and c.user_a is not null
        and c.user_b is not null
        and private.are_friends(c.user_a, c.user_b)
        and not private.is_blocked(c.user_a, c.user_b)
      else
        private.group_role(c.group_id, p_user_id) is not null
    end
      from public.conversations c
     where c.id = p_conversation_id
  ), false);
$$;
revoke all on function private.can_send_conversation(uuid, uuid) from public, anon, authenticated;

-- Liefert die Unterhaltung oder wirft not_found, wenn p_user_id sie nicht lesen darf (Existenz bleibt verborgen).
create function private.require_conversation(p_conversation_id uuid, p_user_id uuid)
returns public.conversations
language plpgsql
stable
set search_path = ''
as $$
declare
  v_conversation public.conversations%rowtype;
begin
  if not private.can_read_conversation(p_conversation_id, p_user_id) then
    raise exception 'not_found';
  end if;
  select * into v_conversation from public.conversations c where c.id = p_conversation_id;
  return v_conversation;
end;
$$;
revoke all on function private.require_conversation(uuid, uuid) from public, anon, authenticated;

-- Öffentliche IDs aller Personen, die eine Unterhaltung sehen (für Echtzeit-Hinweise an user:<public_id>).
create function private.conversation_public_ids(p_conversation_id uuid)
returns setof uuid
language sql
stable
set search_path = ''
as $$
  select p.public_id
    from public.conversations c
    join public.profiles p on p.id in (c.user_a, c.user_b)
   where c.id = p_conversation_id and c.kind = 'direct'
  union
  select p.public_id
    from public.conversations c
    join public.group_members m on m.group_id = c.group_id
    join public.profiles p on p.id = m.user_id
   where c.id = p_conversation_id and c.kind = 'group';
$$;
revoke all on function private.conversation_public_ids(uuid) from public, anon, authenticated;

-- Echtzeit-Hinweis ohne Inhalt. Fehler beim Senden (z. B. Realtime nicht eingerichtet) verhindern die Nachricht
-- nicht: realtime.send fängt sie selbst ab; fehlt die Funktion ganz, wird nichts gesendet.
create function private.notify_conversation(p_conversation_id uuid, p_event text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_public_id uuid;
  v_payload jsonb := jsonb_build_object('conversation_id', p_conversation_id, 'event', p_event);
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is null then
    return;
  end if;
  perform realtime.send(v_payload, p_event, 'chat:' || p_conversation_id::text, true);
  for v_public_id in select * from private.conversation_public_ids(p_conversation_id) loop
    perform realtime.send(v_payload, 'conversation', 'user:' || v_public_id::text, true);
  end loop;
end;
$$;
revoke all on function private.notify_conversation(uuid, text) from public, anon, authenticated;

-- Nach neuer Nachricht: Zeitpunkt der letzten Aktivität und Echtzeit-Hinweis.
create function private.handle_chat_message_inserted()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.conversations c
     set last_message_at = greatest(coalesce(c.last_message_at, new.created_at), new.created_at)
   where c.id = new.conversation_id;
  perform private.notify_conversation(new.conversation_id, 'message');
  return null;
end;
$$;
revoke all on function private.handle_chat_message_inserted() from public, anon, authenticated;

create trigger chat_messages_after_insert
  after insert on public.chat_messages
  for each row execute function private.handle_chat_message_inserted();

-- Nach dem Löschen einer Nachricht: Echtzeit-Hinweis, damit sie bei allen verschwindet.
create function private.handle_chat_message_deleted()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform private.notify_conversation(new.conversation_id, 'message');
  return null;
end;
$$;
revoke all on function private.handle_chat_message_deleted() from public, anon, authenticated;

create trigger chat_messages_after_soft_delete
  after update of deleted_at on public.chat_messages
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function private.handle_chat_message_deleted();

-- Nachricht aus Sicht von p_me (Form wie ChatMessage in PaceCore).
create function private.chat_message_json(p_message public.chat_messages, p_me uuid)
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
    'shared_profile', (
      select private.profile_json(sp)
        from public.profiles sp
       where sp.id = p_message.shared_profile_id
         and not private.is_blocked(p_me, sp.id)
    ),
    'created_at', p_message.created_at
  );
$$;
revoke all on function private.chat_message_json(public.chat_messages, uuid) from public, anon, authenticated;

-- Unterhaltung aus Sicht von p_me (Form wie ConversationSummary in PaceCore).
create function private.conversation_json(p_conversation public.conversations, p_me uuid)
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
      'is_own', coalesce(v_last.sender_id = p_me, false),
      'sent_at', v_last.created_at
    ) end,
    'unread_count', v_unread,
    'can_send', private.can_send_conversation(p_conversation.id, p_me),
    'updated_at', coalesce(p_conversation.last_message_at, p_conversation.created_at)
  );
end;
$$;
revoke all on function private.conversation_json(public.conversations, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------------------------------------------

create function public.chat_conversations()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  -- Privatchats mit mindestens einer Nachricht und alle Gruppenchats eigener Gruppen, neueste zuerst.
  return (
    select coalesce(
             jsonb_agg(private.conversation_json(c.conversation, v_me) order by c.updated_at desc, c.id),
             '[]'::jsonb
           )
      from (
        select x as conversation, x.id, coalesce(x.last_message_at, x.created_at) as updated_at
          from public.conversations x
         where (x.kind = 'direct'
                and v_me in (x.user_a, x.user_b)
                and x.last_message_at is not null
                and not private.is_blocked(x.user_a, x.user_b))
            or (x.kind = 'group' and private.group_role(x.group_id, v_me) is not null)
         order by coalesce(x.last_message_at, x.created_at) desc
         limit 200
      ) c
  );
end;
$$;

revoke all on function public.chat_conversations() from public, anon;
grant execute on function public.chat_conversations() to authenticated;
comment on function public.chat_conversations() is
  'Pace: eigene Unterhaltungen (Privatchats mit Nachrichten, alle Gruppenchats) mit letzter Nachricht, Ungelesen-Zähler und can_send, neueste zuerst (max. 200).';

create function public.chat_open_direct(p_public_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_peer_id uuid;
  v_conversation public.conversations%rowtype;
begin
  select p.id into v_peer_id from public.profiles p where p.public_id = p_public_id;
  if v_peer_id is null then
    raise exception 'not_found';
  end if;
  if v_peer_id = v_me then
    raise exception 'self_request';
  end if;
  -- Selbst blockiert: verständlicher Fehler. Von der anderen Person blockiert: wie nicht vorhanden.
  if private.has_blocked(v_me, v_peer_id) then
    raise exception 'blocked';
  end if;
  if private.has_blocked(v_peer_id, v_me) then
    raise exception 'not_found';
  end if;

  select * into v_conversation
    from public.conversations c
   where c.kind = 'direct' and c.user_a = least(v_me, v_peer_id) and c.user_b = greatest(v_me, v_peer_id);
  if not found then
    -- Neu anlegen nur unter Freunden. Ein bestehender Verlauf bleibt auch nach dem Ende der Freundschaft lesbar.
    if not private.are_friends(v_me, v_peer_id) then
      raise exception 'not_found';
    end if;
    insert into public.conversations (kind, user_a, user_b)
    values ('direct', least(v_me, v_peer_id), greatest(v_me, v_peer_id))
    on conflict (user_a, user_b) where kind = 'direct' do nothing;
    select * into v_conversation
      from public.conversations c
     where c.kind = 'direct' and c.user_a = least(v_me, v_peer_id) and c.user_b = greatest(v_me, v_peer_id);
  end if;

  return private.conversation_json(v_conversation, v_me);
end;
$$;

revoke all on function public.chat_open_direct(uuid) from public, anon;
grant execute on function public.chat_open_direct(uuid) to authenticated;
comment on function public.chat_open_direct(uuid) is
  'Pace: Privatchat mit einer Person öffnen bzw. (nur unter Freunden) anlegen. blocked, wenn ich die Person blockiert habe.';

create function public.chat_group_conversation(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_conversation public.conversations%rowtype;
begin
  perform private.require_group_member(p_group_id, v_me);
  -- Für den Fall, dass eine Unterhaltung fehlt (z. B. Gruppe vor dem Trigger angelegt): jetzt anlegen.
  insert into public.conversations (kind, group_id) values ('group', p_group_id)
  on conflict (group_id) where kind = 'group' do nothing;
  select * into v_conversation from public.conversations c where c.kind = 'group' and c.group_id = p_group_id;
  return private.conversation_json(v_conversation, v_me);
end;
$$;

revoke all on function public.chat_group_conversation(uuid) from public, anon;
grant execute on function public.chat_group_conversation(uuid) to authenticated;
comment on function public.chat_group_conversation(uuid) is 'Pace: Gruppenchat einer Gruppe (nur für Mitglieder).';

create function public.chat_messages(p_conversation_id uuid, p_before timestamptz default null, p_limit integer default 40)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_limit integer := least(greatest(coalesce(p_limit, 40), 1), 100);
begin
  perform private.require_conversation(p_conversation_id, v_me);

  -- Die neuesten v_limit Nachrichten vor p_before, aufsteigend sortiert.
  return (
    select coalesce(jsonb_agg(private.chat_message_json(m, v_me) order by m.created_at, m.id), '[]'::jsonb)
      from (
        select x.*
          from public.chat_messages x
         where x.conversation_id = p_conversation_id
           and x.deleted_at is null
           and (p_before is null or x.created_at < p_before)
           and (x.sender_id is null or not private.has_blocked(v_me, x.sender_id))
         order by x.created_at desc, x.id desc
         limit v_limit
      ) m
  );
end;
$$;

revoke all on function public.chat_messages(uuid, timestamptz, integer) from public, anon;
grant execute on function public.chat_messages(uuid, timestamptz, integer) to authenticated;
comment on function public.chat_messages(uuid, timestamptz, integer) is
  'Pace: Nachrichten vor p_before (ohne: die neuesten), aufsteigend, 1–100 (Standard 40). Ohne gelöschte und ohne Nachrichten von Personen, die ich blockiert habe.';

create function public.chat_send(
  p_conversation_id uuid,
  p_client_id uuid,
  p_kind text,
  p_body text default null,
  p_media_path text default null,
  p_shared_profile_id uuid default null
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

  case p_kind
    when 'text' then
      v_body := btrim(coalesce(p_body, ''), E' \t\n\r');
      if char_length(v_body) not between 1 and 2000 or translate(v_body, E'\n\t', '') ~ '[[:cntrl:]]' then
        raise exception 'invalid_message';
      end if;
      if p_media_path is not null or p_shared_profile_id is not null then
        raise exception 'invalid_input';
      end if;
    when 'image', 'gif' then
      if p_body is not null or p_shared_profile_id is not null or p_media_path is null then
        raise exception 'invalid_input';
      end if;
      -- Nur eigene, bereits hochgeladene Dateien im Ordner dieser Unterhaltung; GIFs müssen image/gif sein.
      select o.metadata ->> 'mimetype' into v_mime
        from storage.objects o
       where o.bucket_id = 'chat-media'
         and o.name = p_media_path
         and o.owner_id = v_me::text
         and split_part(o.name, '/', 1) = p_conversation_id::text;
      if v_mime is null or (p_kind = 'gif' and v_mime <> 'image/gif') then
        raise exception 'invalid_input';
      end if;
      v_media_path := p_media_path;
    when 'profile' then
      if p_body is not null or p_media_path is not null or p_shared_profile_id is null then
        raise exception 'invalid_input';
      end if;
      select p.id into v_shared_id from public.profiles p where p.public_id = p_shared_profile_id;
      if v_shared_id is null or private.is_blocked(v_me, v_shared_id) then
        raise exception 'not_found';
      end if;
    else
      raise exception 'invalid_input';
  end case;

  perform private.consume_rate_limit(v_me, 'chat_send', 30, interval '1 minute');
  perform private.consume_rate_limit(v_me, 'chat_send_daily', 2000, interval '24 hours');

  begin
    insert into public.chat_messages (conversation_id, sender_id, client_id, kind, body, media_path, shared_profile_id)
    values (p_conversation_id, v_me, p_client_id, p_kind, v_body, v_media_path, v_shared_id)
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

revoke all on function public.chat_send(uuid, uuid, text, text, text, uuid) from public, anon;
grant execute on function public.chat_send(uuid, uuid, text, text, text, uuid) to authenticated;
comment on function public.chat_send(uuid, uuid, text, text, text, uuid) is
  'Pace: Nachricht senden (idempotent per client_id). read_only, wenn nicht mehr geschrieben werden kann. Max. 30 je Minute.';

create function public.chat_mark_read(p_conversation_id uuid, p_through timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  -- clock_timestamp(): Nachrichten tragen ihre tatsächliche Einfügezeit, nicht den Transaktionsbeginn.
  v_through timestamptz := least(coalesce(p_through, clock_timestamp()), clock_timestamp());
begin
  perform private.require_conversation(p_conversation_id, v_me);
  insert into public.conversation_reads (conversation_id, user_id, last_read_at)
  values (p_conversation_id, v_me, v_through)
  on conflict (conversation_id, user_id)
  do update set last_read_at = greatest(public.conversation_reads.last_read_at, excluded.last_read_at);
end;
$$;

revoke all on function public.chat_mark_read(uuid, timestamptz) from public, anon;
grant execute on function public.chat_mark_read(uuid, timestamptz) to authenticated;
comment on function public.chat_mark_read(uuid, timestamptz) is
  'Pace: alles bis einschließlich p_through (höchstens jetzt) als gelesen markieren. Der Lesestand geht nie zurück.';

create function public.chat_delete_message(p_message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_media_path text;
begin
  -- Eigene Nachrichten lassen sich immer löschen, auch nach Austritt oder Ende der Freundschaft.
  select m.media_path into v_media_path
    from public.chat_messages m
   where m.id = p_message_id and m.sender_id = v_me and m.deleted_at is null
     for update;
  if not found then
    raise exception 'not_found';
  end if;

  update public.chat_messages m
     set deleted_at = now(), body = null, media_path = null, shared_profile_id = null
   where m.id = p_message_id;

  -- Die App löscht die Datei danach über die Storage-API (nur die hochladende Person darf das).
  return jsonb_build_object('media_path', v_media_path);
end;
$$;

revoke all on function public.chat_delete_message(uuid) from public, anon;
grant execute on function public.chat_delete_message(uuid) to authenticated;
comment on function public.chat_delete_message(uuid) is
  'Pace: eigene Nachricht löschen (Inhalt wird entfernt). Liefert {media_path} der zugehörigen Datei zum Löschen im Storage.';
