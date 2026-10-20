-- =============================================================================================================
-- Pace – Meldungen, Rückmeldungen und Datenschutz (Auskunft, eigene Dateien, Konto löschen).
--
-- * reports: Meldungen zu Personen, Nachrichten und Gruppen. Nur Ziele, die die meldende Person sehen darf; je
--   Ziel höchstens eine offene Meldung pro Person; max. 10 je 24 h. Clients haben keinen Lesezugriff – bearbeitet
--   wird außerhalb der App (Moderationsprozess in docs/BACKEND.md). target_snapshot hält fest, was gemeldet wurde,
--   damit eine spätere Löschung durch die gemeldete Person die Prüfung nicht verhindert. Das gilt auch für Bilder:
--   Solange eine Meldung offen ist (open/reviewing), lässt sich die gemeldete Datei (Profilbild, Chat-Bild bzw.
--   Gruppenbild aus dem Schnappschuss) über die Storage-API nicht löschen; chat_delete_message gibt sie dann nicht
--   zur Löschung frei, account_own_media lässt sie aus. Nach der Moderation räumt das Team sie auf (BACKEND.md).
-- * feedback: Rückmeldungen aus „Hilfe“ (Problem/Idee), ohne E-Mail-Adresse, max. 10 je 24 h.
-- * account_export(): alle personenbezogenen Serverdaten des Aufrufers als jsonb (DSGVO Art. 15/20).
-- * account_own_media(): eigene Dateien in Storage, damit die App sie vor dem Löschen des Kontos entfernt (ohne
--   Dateien unter offener Meldung – die bleiben bis zur Moderation erhalten).
-- * account_delete(): löscht eigene Nachrichten, entfernt Verweise auf Gruppenbilder, die es nicht mehr gibt bzw.
--   die von mir stammen, und löscht dann auth.users des Aufrufers. Die Fremdschlüssel löschen
--   Profil, Tageswerte, Freundschaften, Anfragen, Blockierungen, Mitgliedschaften (Eigentümerwechsel bzw. Löschen
--   leerer Gruppen über den vorhandenen Trigger), Einladungen, Lesestände, eigene Meldungen und Rückmeldungen.
--   Dateien in Storage löscht die App vorher über die Storage-API (direktes Löschen in storage.objects ist in
--   Supabase nicht erlaubt).
-- =============================================================================================================

-- ---------------------------------------------------------------------------------------------------------------
-- Meldungen
-- ---------------------------------------------------------------------------------------------------------------

create table public.reports (
  id              uuid primary key default gen_random_uuid(),
  reporter_id     uuid not null references public.profiles (id) on delete cascade,
  target_type     text not null,
  -- user: public_id der Person, message: ID der Nachricht, group: ID der Gruppe.
  target_id       uuid not null,
  reason          text not null,
  details         text,
  target_snapshot jsonb not null default '{}'::jsonb,
  status          text not null default 'open',
  created_at      timestamptz not null default now(),
  reviewed_at     timestamptz,
  -- Gemeldete Datei aus dem Schnappschuss (Profilbild der Person, Bild der Nachricht, Gruppenbild). Solange die
  -- Meldung offen ist, sperren die Storage-Delete-Policies sie (pace_access.is_report_evidence).
  evidence_bucket text generated always as (
    case target_type when 'user' then 'avatars' when 'message' then 'chat-media' when 'group' then 'group-images' end
  ) stored,
  evidence_path   text generated always as (
    case target_type
      when 'user' then target_snapshot ->> 'avatar_path'
      when 'message' then target_snapshot ->> 'media_path'
      when 'group' then target_snapshot ->> 'image_path'
    end
  ) stored,

  constraint reports_target_type_valid check (target_type in ('user', 'message', 'group')),
  constraint reports_reason_valid check (reason in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other')),
  constraint reports_details_valid check (
    details is null
    or (char_length(details) between 1 and 1000 and details = btrim(details, E' \t\n\r'))
  ),
  constraint reports_status_valid check (status in ('open', 'reviewing', 'resolved', 'dismissed'))
);

comment on table public.reports is
  'Pace: Meldungen an das Pace-Team. Kein Clientzugriff (nur social_report schreibt). Bearbeitung über das Dashboard.';

-- Höchstens eine offene Meldung je Person und Ziel; Zugriffspfad für die Bearbeitung.
create unique index reports_open_key on public.reports (reporter_id, target_type, target_id) where status = 'open';
create index reports_status_idx on public.reports (status, created_at);
-- Prüfung der Storage-Delete-Policies: Ist eine Datei Beweis einer offenen Meldung?
create index reports_evidence_idx on public.reports (evidence_bucket, evidence_path)
  where status in ('open', 'reviewing') and evidence_path is not null;

alter table public.reports enable row level security;
revoke all on table public.reports from anon, authenticated;

create function public.social_report(p_target_type text, p_target_id uuid, p_reason text, p_details text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_details text := nullif(btrim(coalesce(p_details, ''), E' \t\n\r'), '');
  v_snapshot jsonb;
  v_target_user uuid;
  v_message public.chat_messages%rowtype;
begin
  if p_target_id is null then
    raise exception 'not_found';
  end if;

  case p_target_type
    when 'user' then
      -- Jede bekannte Person außer mir selbst (auch nach einer Blockierung, z. B. wegen Belästigung davor).
      select p.id, private.profile_json(p) into v_target_user, v_snapshot
        from public.profiles p
       where p.public_id = p_target_id;
      if v_target_user is null or v_target_user = v_me then
        raise exception 'not_found';
      end if;
    when 'message' then
      -- Nur Nachrichten anderer in Unterhaltungen, die ich lesen darf.
      select * into v_message from public.chat_messages m where m.id = p_target_id and m.deleted_at is null;
      if not found
         or v_message.sender_id is not distinct from v_me
         or not private.can_read_conversation(v_message.conversation_id, v_me) then
        raise exception 'not_found';
      end if;
      v_snapshot := jsonb_build_object(
        'conversation_id', v_message.conversation_id,
        'kind', v_message.kind,
        'body', v_message.body,
        'media_path', v_message.media_path,
        'sender', (select private.profile_json(s) from public.profiles s where s.id = v_message.sender_id),
        'created_at', v_message.created_at
      );
    when 'group' then
      -- Gruppen, in denen ich Mitglied bin oder in die ich eingeladen wurde.
      if private.group_role(p_target_id, v_me) is null
         and not exists (
           select 1 from public.group_invitations i
            where i.group_id = p_target_id and i.invitee_id = v_me and i.status = 'pending'
         ) then
        raise exception 'not_found';
      end if;
      select jsonb_build_object('name', g.name, 'description', g.description, 'image_path', g.image_path)
        into v_snapshot
        from public.groups g
       where g.id = p_target_id;
    else
      raise exception 'invalid_input';
  end case;

  if p_reason is null
     or p_reason not in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other')
     or (v_details is not null and char_length(v_details) > 1000) then
    raise exception 'invalid_input';
  end if;

  -- Erneutes Melden desselben Ziels, solange die Meldung offen ist, ist unschädlich und zählt nicht.
  if exists (
    select 1 from public.reports r
     where r.reporter_id = v_me and r.target_type = p_target_type and r.target_id = p_target_id and r.status = 'open'
  ) then
    return;
  end if;
  perform private.consume_rate_limit(v_me, 'report', 10, interval '24 hours');

  insert into public.reports (reporter_id, target_type, target_id, reason, details, target_snapshot)
  values (v_me, p_target_type, p_target_id, p_reason, v_details, coalesce(v_snapshot, '{}'::jsonb))
  on conflict (reporter_id, target_type, target_id) where status = 'open' do nothing;
end;
$$;

revoke all on function public.social_report(text, uuid, text, text) from public, anon;
grant execute on function public.social_report(text, uuid, text, text) to authenticated;
comment on function public.social_report(text, uuid, text, text) is
  'Pace: Person (public_id), Nachricht oder Gruppe melden. Nur sichtbare Ziele; eine offene Meldung je Ziel; max. 10 je 24 h.';

-- ---------------------------------------------------------------------------------------------------------------
-- Gemeldete Dateien bleiben bis zur Moderation erhalten
-- ---------------------------------------------------------------------------------------------------------------

-- Ist die Datei Beweis einer offenen Meldung (Status open oder reviewing)? security definer: Clients lesen
-- public.reports nicht.
create function pace_access.is_report_evidence(p_bucket text, p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.reports r
     where r.status in ('open', 'reviewing')
       and r.evidence_bucket = p_bucket
       and r.evidence_path = p_name
  );
$$;
revoke all on function pace_access.is_report_evidence(text, text) from public, anon;
grant execute on function pace_access.is_report_evidence(text, text) to authenticated;

-- Die Delete-Policies aus 20261019100300_storage_realtime_access.sql: zusätzlich nichts löschen, was gemeldet ist.
-- Die Storage-API meldet dann keinen Fehler, löscht aber nichts (die Datei fehlt in der Antwort).
alter policy pace_avatars_delete on storage.objects
  using (
    bucket_id = 'avatars'
    and pace_access.can_write_avatar(name)
    and not pace_access.is_report_evidence(bucket_id, name)
  );

alter policy pace_group_images_delete on storage.objects
  using (
    bucket_id = 'group-images'
    and (owner_id = (select auth.uid())::text or pace_access.can_write_group_image(name))
    and not pace_access.is_report_evidence(bucket_id, name)
  );

alter policy pace_chat_media_delete on storage.objects
  using (
    bucket_id = 'chat-media'
    and owner_id = (select auth.uid())::text
    and not pace_access.is_report_evidence(bucket_id, name)
  );

-- Ersetzt die Fassung aus 20261019100200_chat.sql: Ist das Bild der Nachricht gemeldet (offene Meldung), liefert
-- die Funktion media_path = null – die App versucht dann nicht, die Datei zu löschen. Der Inhalt der Nachricht
-- verschwindet trotzdem (die Meldung hat ihren Schnappschuss).
create or replace function public.chat_delete_message(p_message_id uuid)
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

  -- Die App löscht die Datei danach über die Storage-API (nur die hochladende Person darf das) – außer sie ist
  -- Beweis einer offenen Meldung.
  if v_media_path is not null and pace_access.is_report_evidence('chat-media', v_media_path) then
    v_media_path := null;
  end if;
  return jsonb_build_object('media_path', v_media_path);
end;
$$;

comment on function public.chat_delete_message(uuid) is
  'Pace: eigene Nachricht löschen (Inhalt wird entfernt). Liefert {media_path} der zugehörigen Datei zum Löschen im Storage (null, wenn keine oder gemeldet).';

-- ---------------------------------------------------------------------------------------------------------------
-- Rückmeldungen
-- ---------------------------------------------------------------------------------------------------------------

create table public.feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kind        text not null,
  message     text not null,
  app_version text not null default '',
  created_at  timestamptz not null default now(),

  constraint feedback_kind_valid check (kind in ('problem', 'idea')),
  constraint feedback_message_valid check (
    char_length(message) between 1 and 2000 and message = btrim(message, E' \t\n\r')
  ),
  constraint feedback_app_version_valid check (app_version ~ '^[0-9A-Za-z .()_-]{0,40}$')
);

comment on table public.feedback is
  'Pace: Rückmeldungen aus der App (ohne E-Mail-Adresse). Kein Clientzugriff (nur submit_feedback schreibt).';

create index feedback_user_idx on public.feedback (user_id);
create index feedback_created_idx on public.feedback (created_at);

alter table public.feedback enable row level security;
revoke all on table public.feedback from anon, authenticated;

create function public.submit_feedback(p_kind text, p_message text, p_app_version text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.consume_rate_limit(v_me, 'feedback', 10, interval '24 hours');
  begin
    insert into public.feedback (user_id, kind, message, app_version)
    values (
      v_me,
      coalesce(p_kind, ''),
      btrim(coalesce(p_message, ''), E' \t\n\r'),
      coalesce(btrim(p_app_version), '')
    );
  exception
    when check_violation then
      raise exception 'invalid_input';
  end;
end;
$$;

revoke all on function public.submit_feedback(text, text, text) from public, anon;
grant execute on function public.submit_feedback(text, text, text) to authenticated;
comment on function public.submit_feedback(text, text, text) is
  'Pace: Rückmeldung (problem/idea, 1–2000 Zeichen) speichern. Max. 10 je 24 h.';

-- ---------------------------------------------------------------------------------------------------------------
-- Datenschutz
-- ---------------------------------------------------------------------------------------------------------------

create function public.account_export()
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
               'shared_profile', (select private.profile_json(s) from public.profiles s where s.id = m.shared_profile_id),
               'created_at', m.created_at,
               'deleted_at', m.deleted_at
             ) order by m.created_at), '[]'::jsonb)
        from public.chat_messages m where m.sender_id = v_me
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

revoke all on function public.account_export() from public, anon;
grant execute on function public.account_export() to authenticated;
comment on function public.account_export() is
  'Pace: alle personenbezogenen Serverdaten des eigenen Kontos als JSON (Auskunft/Datenübertragbarkeit). Max. 5 je Stunde.';

create function public.account_own_media()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  -- Selbst hochgeladene Dateien, dazu Bilder von Gruppen, deren owner ich bin (auch von anderen hochgeladen).
  -- Ohne Dateien unter offener Meldung: Die Storage-Policies lassen sie ohnehin nicht löschen, sie bleiben bis zur
  -- Moderation erhalten (Aufbewahrung siehe docs/BACKEND.md, „Konto und Datenschutz“).
  return (
    select coalesce(jsonb_agg(jsonb_build_object('bucket', x.bucket_id, 'path', x.name) order by x.bucket_id, x.name),
                    '[]'::jsonb)
      from (
        select o.bucket_id, o.name
          from storage.objects o
         where o.owner_id = v_me::text and o.bucket_id in ('avatars', 'group-images', 'chat-media')
        union
        select o.bucket_id, o.name
          from storage.objects o
          join public.group_members m
            on m.user_id = v_me and m.role = 'owner'
           and pace_access.object_folder(o.name) = m.group_id
         where o.bucket_id = 'group-images'
      ) x
     where not pace_access.is_report_evidence(x.bucket_id, x.name)
  );
end;
$$;

revoke all on function public.account_own_media() from public, anon;
grant execute on function public.account_own_media() to authenticated;
comment on function public.account_own_media() is
  'Pace: eigene Dateien in Storage ({bucket, path}) und Bilder eigener Gruppen – zum Löschen vor account_delete. Ohne Dateien unter offener Meldung.';

create function public.account_delete()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  -- Auch ohne Profil möglich (z. B. abgebrochenes Onboarding).
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- Eigene Nachrichten werden gelöscht, nicht nur vom Konto getrennt.
  delete from public.chat_messages m where m.sender_id = v_me;
  -- Gruppenbilder nicht weiter referenzieren – die Gruppe zeigt dann wieder das Symbol ihrer Art:
  --  * Bilder eigener Gruppen (die App hat sie über account_own_media gelöscht),
  --  * Verweise auf Dateien, die es nicht mehr gibt (eigene Uploads in fremden Gruppen hat die App vorher gelöscht;
  --    welche Gruppe betroffen war, lässt sich danach nur noch so erkennen),
  --  * eigene Uploads, die als Beweis einer offenen Meldung erhalten bleiben (nicht mehr in der Gruppe zeigen).
  update public.groups g
     set image_path = null
   where g.image_path is not null
     and (
       exists (
         select 1 from public.group_members m
          where m.group_id = g.id and m.user_id = v_me and m.role = 'owner'
       )
       or not exists (
         select 1 from storage.objects o
          where o.bucket_id = 'group-images' and o.name = g.image_path
       )
       or exists (
         select 1 from storage.objects o
          where o.bucket_id = 'group-images' and o.name = g.image_path and o.owner_id = v_me::text
       )
     );
  delete from auth.users u where u.id = v_me;
end;
$$;

revoke all on function public.account_delete() from public, anon;
grant execute on function public.account_delete() to authenticated;
comment on function public.account_delete() is
  'Pace: eigenes Konto endgültig löschen (Nachrichten, Profil und alle verknüpften Daten). Dateien vorher über Storage löschen.';
