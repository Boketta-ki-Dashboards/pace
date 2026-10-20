-- =============================================================================================================
-- Pace – Profilbild, Auffindbarkeit, Präfixsuche, öffentliches Profil und Blockieren.
--
-- Baut auf 20261018100000_social.sql auf. Nur additive Änderungen: neue Spalten mit Standardwerten, neue Tabellen,
-- neue bzw. ersetzte Funktionen (gleiche Signaturen). Bestehende Daten bleiben unverändert.
--
-- * profiles.avatar_path: Pfad im privaten Bucket „avatars“, immer im Ordner der eigenen public_id. Ein Trigger
--   prüft Ordner und Format und dass die Datei bereits hochgeladen ist.
-- * profiles.is_discoverable: erscheint in der Präfixsuche (Standard: ja). Bei exakter Eingabe des Benutzernamens
--   und für Freunde ist ein Profil immer auffindbar – so wie es PaceCore (UserProfile.isDiscoverable) beschreibt.
-- * Blockieren (user_blocks): beendet Freundschaft, offene Anfragen und Einladungen zwischen beiden. Danach keine
--   neuen Anfragen, Einladungen oder Direktnachrichten in beide Richtungen; beide finden sich nicht mehr.
--   Gemeinsame Gruppen bleiben bestehen (Regel in docs/BACKEND.md, „Blockieren“).
-- * Öffentliches Profil (social_public_profile, max. 120 je 10 Minuten): Nicht auffindbare Profile ohne Beziehung
--   zeigt der Server nur mit Kontext (gemeinsame Gruppe, Gruppeneinladung, eigene Blockierung, kurz zuvor exakt per
--   Benutzernamen gefunden; Privatchat und im Chat geteilte Profile ergänzt 20261019100200_chat.sql) – sonst wie
--   „nicht gefunden“. So lassen sich public_ids (z. B. Ordnernamen im Bucket avatars) nicht zu Profilen auflösen.
-- * Ausgaben mit Personen enthalten zusätzlich avatar_path (öffentliches Feld wie Anzeigename).
-- * is_username_available bekommt ein Rate Limit, das auch ohne Profil (Onboarding) greift.
-- =============================================================================================================

-- ---------------------------------------------------------------------------------------------------------------
-- Profile: Profilbild und Auffindbarkeit
-- ---------------------------------------------------------------------------------------------------------------

alter table public.profiles
  add column avatar_path text,
  add column is_discoverable boolean not null default true;

comment on column public.profiles.avatar_path is
  'Profilbild im privaten Bucket avatars: <public_id>/<Name>.<jpg|jpeg|png|gif|heic|webp>. null = Initialen.';
comment on column public.profiles.is_discoverable is
  'Erscheint in der Präfixsuche anderer. Bei exakter Eingabe des Benutzernamens und für Freunde immer auffindbar.';

-- Format: Ordner = UUID (die eigene public_id prüft der Trigger), zufälliger Dateiname, erlaubte Bildendung.
alter table public.profiles add constraint profiles_avatar_path_format check (
  avatar_path is null
  or avatar_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|gif|heic|webp)$'
);

-- Präfixsuche über lower(username): text_pattern_ops vergleicht byteweise und unterstützt Bereichsabfragen
-- (der vorhandene eindeutige Index nutzt die Standard-Kollation und kann das nicht).
create index profiles_username_prefix_idx on public.profiles (lower(username) text_pattern_ops);

-- Die App ändert Profilbild und Auffindbarkeit direkt in der eigenen Zeile (RLS: nur eigene Zeile).
grant update (avatar_path, is_discoverable) on table public.profiles to authenticated;

-- Profilbild: nur im Ordner der eigenen public_id und nur, wenn die Datei im Bucket avatars existiert. So kann
-- niemand auf fremde oder nicht vorhandene Dateien verweisen. security definer: liest storage.objects unabhängig
-- von den Storage-Policies des aufrufenden Nutzers.
create function private.validate_profile_avatar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.avatar_path is not null
     and (tg_op = 'INSERT' or new.avatar_path is distinct from old.avatar_path) then
    if split_part(new.avatar_path, '/', 1) <> new.public_id::text
       or not exists (
         select 1 from storage.objects o where o.bucket_id = 'avatars' and o.name = new.avatar_path
       ) then
      raise exception 'invalid_avatar_path' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.validate_profile_avatar() from public, anon, authenticated;

create trigger profiles_validate_avatar
  before insert or update of avatar_path on public.profiles
  for each row execute function private.validate_profile_avatar();

-- Benutzername ändern: höchstens 5 Änderungen je 24 Stunden (rate_limited). Verhindert, dass sich jemand durch
-- ständiges Umbenennen Meldungen entzieht oder Namen anderer reserviert. security definer für das Rate Limit im
-- Schema private.
create function private.limit_username_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.username is distinct from old.username then
    perform private.consume_rate_limit(new.id, 'username_change', 5, interval '24 hours');
  end if;
  return new;
end;
$$;
revoke all on function private.limit_username_changes() from public, anon, authenticated;

create trigger profiles_limit_username_changes
  before update of username on public.profiles
  for each row execute function private.limit_username_changes();

-- ---------------------------------------------------------------------------------------------------------------
-- Rate Limit für angemeldete Nutzer ohne Profil (Onboarding)
-- ---------------------------------------------------------------------------------------------------------------

-- Wie private.rate_limit_events, aber an auth.users gebunden: is_username_available wird schon vor dem Anlegen des
-- Profils aufgerufen.
create table private.auth_rate_limit_events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  action     text not null,
  created_at timestamptz not null default now()
);

comment on table private.auth_rate_limit_events is
  'Pace: gezählte Aktionen je Auth-Nutzer (auch ohne Profil) für Rate Limits. Veraltete Einträge werden beim Prüfen gelöscht.';

create index auth_rate_limit_events_user_action_idx on private.auth_rate_limit_events (user_id, action, created_at);
revoke all on table private.auth_rate_limit_events from public, anon, authenticated;

-- Gleiche Logik wie private.consume_rate_limit (Advisory-Lock je Nutzer und Aktion, Fenster gleitend).
create function private.consume_auth_rate_limit(p_user_id uuid, p_action text, p_limit integer, p_window interval)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('pace.auth_rate_limit:' || p_user_id::text || ':' || p_action, 0));

  delete from private.auth_rate_limit_events e
   where e.user_id = p_user_id
     and e.action = p_action
     and e.created_at <= now() - p_window;

  if (select count(*) from private.auth_rate_limit_events e where e.user_id = p_user_id and e.action = p_action)
     >= p_limit then
    raise exception 'rate_limited';
  end if;

  insert into private.auth_rate_limit_events (user_id, action) values (p_user_id, p_action);
end;
$$;
revoke all on function private.consume_auth_rate_limit(uuid, text, integer, interval) from public, anon, authenticated;

-- Ersetzt die Fassung aus 20261016100200_profiles.sql: jetzt mit Rate Limit (60 Prüfungen je 10 Minuten), daher
-- plpgsql und volatile. Ergebnis unverändert: true, wenn kein Profil den Namen (ohne Groß-/Kleinschreibung) nutzt.
create or replace function public.is_username_available(p_username text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  perform private.consume_auth_rate_limit(v_user_id, 'username_check', 60, interval '10 minutes');

  return not exists (
    select 1 from public.profiles p
     where lower(p.username) = lower(btrim(coalesce(p_username, '')))
  );
end;
$$;

comment on function public.is_username_available(text) is
  'Pace: true, wenn kein Profil diesen Benutzernamen (ohne Groß-/Kleinschreibung) verwendet. Max. 60 Prüfungen je 10 Minuten.';

-- ---------------------------------------------------------------------------------------------------------------
-- Blockieren
-- ---------------------------------------------------------------------------------------------------------------

create table public.user_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),

  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

comment on table public.user_blocks is
  'Pace: Blockierungen (blocker hat blocked blockiert). Kein Clientzugriff – nur über die social_*-RPCs.';

-- Prüfung in Gegenrichtung und Löschen von Profilen.
create index user_blocks_blocked_idx on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;
revoke all on table public.user_blocks from anon, authenticated;

-- p_blocker hat p_blocked blockiert.
create function private.has_blocked(p_blocker uuid, p_blocked uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.user_blocks b where b.blocker_id = p_blocker and b.blocked_id = p_blocked
  );
$$;
revoke all on function private.has_blocked(uuid, uuid) from public, anon, authenticated;

-- Eine der beiden Personen hat die andere blockiert.
create function private.is_blocked(p_user_id uuid, p_other_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.has_blocked(p_user_id, p_other_id) or private.has_blocked(p_other_id, p_user_id);
$$;
revoke all on function private.is_blocked(uuid, uuid) from public, anon, authenticated;

-- Öffentliche Felder einer Person (gleiche Form in allen Ausgaben).
create function private.profile_json(p_profile public.profiles)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'public_id', p_profile.public_id,
    'username', p_profile.username,
    'display_name', p_profile.display_name,
    'avatar_path', p_profile.avatar_path
  );
$$;
revoke all on function private.profile_json(public.profiles) from public, anon, authenticated;

-- Profilbild eines Nutzers (für Ranking-Einträge).
create function private.avatar_path_of(p_user_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select p.avatar_path from public.profiles p where p.id = p_user_id;
$$;
revoke all on function private.avatar_path_of(uuid) from public, anon, authenticated;

-- Beziehung zwischen mir und einer anderen Person: self, friend, outgoing_request, incoming_request oder none,
-- dazu die ID einer offenen Anfrage.
create function private.relationship(p_me uuid, p_other_id uuid, out relationship text, out request_id uuid)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_request public.friend_requests%rowtype;
begin
  if p_other_id = p_me then
    relationship := 'self';
  elsif private.are_friends(p_me, p_other_id) then
    relationship := 'friend';
  else
    select * into v_request from private.open_friend_request(p_me, p_other_id);
    relationship := case
      when v_request.id is null then 'none'
      when v_request.requester_id = p_me then 'outgoing_request'
      else 'incoming_request'
    end;
    request_id := v_request.id;
  end if;
end;
$$;
revoke all on function private.relationship(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Sichtbarkeit von Profilen
-- ---------------------------------------------------------------------------------------------------------------

-- Wer ein nicht auffindbares Profil exakt per Benutzernamen gefunden hat (social_find_profile, exakter Treffer der
-- Präfixsuche), darf es danach 24 Stunden lang öffnen – z. B. über einen geteilten Link pace://u/<name>.
create table private.profile_lookups (
  viewer_id    uuid not null references public.profiles (id) on delete cascade,
  target_id    uuid not null references public.profiles (id) on delete cascade,
  looked_up_at timestamptz not null default now(),

  primary key (viewer_id, target_id)
);

comment on table private.profile_lookups is
  'Pace: exakte Benutzernamen-Treffer auf nicht auffindbare Profile (Kontext für social_public_profile, 24 h gültig).';

-- Löschen von Profilen (Fremdschlüssel).
create index profile_lookups_target_idx on private.profile_lookups (target_id);
revoke all on table private.profile_lookups from public, anon, authenticated;

create function private.remember_profile_lookup(p_viewer uuid, p_target uuid)
returns void
language sql
set search_path = ''
as $$
  delete from private.profile_lookups l
   where l.viewer_id = p_viewer and l.looked_up_at <= now() - interval '24 hours';
  insert into private.profile_lookups (viewer_id, target_id)
  values (p_viewer, p_target)
  on conflict (viewer_id, target_id) do update set looked_up_at = excluded.looked_up_at;
$$;
revoke all on function private.remember_profile_lookup(uuid, uuid) from public, anon, authenticated;

-- Darf p_viewer das Profil von p_target sehen (öffentliches Profil, im Chat geteiltes Profil)? Nie, wenn p_target
-- p_viewer blockiert hat. Sonst: sich selbst und auffindbare Profile immer; nicht auffindbare nur mit Kontext –
-- Freundschaft, offene Freundschaftsanfrage oder Gruppeneinladung (eine Richtung genügt), gemeinsame Gruppe (auch
-- frühere Mitglieder einer Gruppe, in der ich bin: ihre Nachrichten stehen im Gruppenchat), von mir blockiert (steht
-- in meiner Liste) oder in den letzten 24 Stunden exakt per Benutzernamen gefunden.
-- 20261019100200_chat.sql ersetzt die Funktion und ergänzt Privatchat und im Chat geteilte Profile.
create function private.can_view_profile(p_viewer uuid, p_target uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when p_viewer = p_target then true
    when private.has_blocked(p_target, p_viewer) then false
    else exists (select 1 from public.profiles t where t.id = p_target and t.is_discoverable)
      or private.has_blocked(p_viewer, p_target)
      or private.are_friends(p_viewer, p_target)
      or exists (select 1 from private.open_friend_request(p_viewer, p_target))
      or exists (
        select 1 from public.group_invitations i
         where i.status = 'pending'
           and ((i.inviter_id = p_viewer and i.invitee_id = p_target)
             or (i.inviter_id = p_target and i.invitee_id = p_viewer))
      )
      or exists (
        select 1
          from public.group_members m
          join public.group_membership_periods mp on mp.group_id = m.group_id and mp.user_id = p_target
         where m.user_id = p_viewer
      )
      or exists (
        select 1 from private.profile_lookups l
         where l.viewer_id = p_viewer
           and l.target_id = p_target
           and l.looked_up_at > now() - interval '24 hours'
      )
  end;
$$;
revoke all on function private.can_view_profile(uuid, uuid) from public, anon, authenticated;

create function public.social_block_user(p_public_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_target_id uuid;
begin
  select p.id into v_target_id from public.profiles p where p.public_id = p_public_id;
  if v_target_id is null then
    raise exception 'not_found';
  end if;
  if v_target_id = v_me then
    raise exception 'self_request';
  end if;

  perform private.lock_users(array[v_me, v_target_id]);
  -- Erneutes Blockieren ist unschädlich und zählt nicht.
  if private.has_blocked(v_me, v_target_id) then
    return;
  end if;
  if (select count(*) from public.user_blocks b where b.blocker_id = v_me) >= 1000 then
    raise exception 'limit_reached';
  end if;
  perform private.consume_rate_limit(v_me, 'block', 50, interval '24 hours');

  insert into public.user_blocks (blocker_id, blocked_id) values (v_me, v_target_id);

  -- Freundschaft endet.
  delete from public.friendships f
   where f.user_a = least(v_me, v_target_id)
     and f.user_b = greatest(v_me, v_target_id);

  -- Offene Anfragen: eigene gelten als zurückgezogen, eingehende als abgelehnt.
  update public.friend_requests r
     set status = case when r.requester_id = v_me then 'cancelled' else 'declined' end,
         responded_at = now()
   where r.status = 'pending'
     and ((r.requester_id = v_me and r.addressee_id = v_target_id)
       or (r.requester_id = v_target_id and r.addressee_id = v_me));

  -- Offene Gruppeneinladungen zwischen beiden enden.
  update public.group_invitations i
     set status = 'cancelled', responded_at = now()
   where i.status = 'pending'
     and ((i.inviter_id = v_me and i.invitee_id = v_target_id)
       or (i.inviter_id = v_target_id and i.invitee_id = v_me));
end;
$$;

revoke all on function public.social_block_user(uuid) from public, anon;
grant execute on function public.social_block_user(uuid) to authenticated;
comment on function public.social_block_user(uuid) is
  'Pace: Person blockieren (idempotent). Beendet Freundschaft, offene Anfragen und Einladungen. Max. 50 je 24 h.';

create function public.social_unblock_user(p_public_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  -- Idempotent: Wer nicht (mehr) blockiert ist, bleibt es nicht.
  delete from public.user_blocks b
   using public.profiles p
   where p.public_id = p_public_id
     and b.blocker_id = v_me
     and b.blocked_id = p.id;
end;
$$;

revoke all on function public.social_unblock_user(uuid) from public, anon;
grant execute on function public.social_unblock_user(uuid) to authenticated;
comment on function public.social_unblock_user(uuid) is
  'Pace: Blockierung aufheben (idempotent). Freundschaft und Anfragen werden nicht wiederhergestellt.';

create function public.social_blocked_users()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  return (
    select coalesce(
             jsonb_agg(
               private.profile_json(p) || jsonb_build_object('blocked_at', b.created_at)
               order by lower(p.display_name), lower(p.username)
             ),
             '[]'::jsonb
           )
      from public.user_blocks b
      join public.profiles p on p.id = b.blocked_id
     where b.blocker_id = v_me
  );
end;
$$;

revoke all on function public.social_blocked_users() from public, anon;
grant execute on function public.social_blocked_users() to authenticated;
comment on function public.social_blocked_users() is
  'Pace: von mir blockierte Personen (öffentliche Felder, blocked_at), sortiert nach Anzeigename.';

-- ---------------------------------------------------------------------------------------------------------------
-- Suche
-- ---------------------------------------------------------------------------------------------------------------

-- Ersetzt die Fassung aus 20261018100000_social.sql: Blockierungen in beiden Richtungen liefern null, die Ausgabe
-- enthält avatar_path. Exakte Suche findet auch nicht auffindbare Profile (siehe Kopf).
create or replace function public.social_find_profile(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_username text := btrim(p_username);
  v_target public.profiles%rowtype;
  v_relationship record;
begin
  -- Jede Suche zählt, auch ungültige und erfolglose – sonst ließen sich Benutzernamen beliebig durchprobieren.
  perform private.consume_rate_limit(v_me, 'profile_search', 30, interval '10 minutes');

  if v_username is null or v_username !~ '^[A-Za-z0-9_]{3,20}$' then
    return null;
  end if;
  select * into v_target from public.profiles p where lower(p.username) = lower(v_username);
  if not found or private.is_blocked(v_me, v_target.id) then
    return null;
  end if;
  -- Wer den genauen Namen kennt, darf ein nicht auffindbares Profil danach auch öffnen (social_public_profile).
  if not v_target.is_discoverable and v_target.id <> v_me then
    perform private.remember_profile_lookup(v_me, v_target.id);
  end if;

  select * into v_relationship from private.relationship(v_me, v_target.id);
  return private.profile_json(v_target) || jsonb_build_object(
    'relationship', v_relationship.relationship,
    'request_id', v_relationship.request_id
  );
end;
$$;

comment on function public.social_find_profile(text) is
  'Pace: Profil per exaktem Benutzernamen (ohne Groß-/Kleinschreibung) mit Beziehung; null ohne Treffer oder bei Blockierung. Ein Treffer gibt 24 h Zugriff auf das öffentliche Profil. Max. 30 Suchen je 10 Minuten.';

create function public.social_search_profiles(p_query text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_query text := lower(btrim(coalesce(p_query, '')));
begin
  -- Jede Anfrage zählt (auch zu kurze), damit sich die Suche nicht zum Durchprobieren eignet. Das Limit reicht für
  -- Suche während der Eingabe mit Verzögerung in der App.
  perform private.consume_rate_limit(v_me, 'profile_prefix_search', 120, interval '10 minutes');

  if left(v_query, 1) = '@' then
    v_query := substr(v_query, 2);
  end if;
  -- Mindestens 3 Zeichen; nur Zeichen, die in Benutzernamen erlaubt sind (damit auch keine LIKE-Platzhalter).
  if v_query !~ '^[a-z0-9_]{3,20}$' then
    return '[]'::jsonb;
  end if;

  -- Exakter Treffer auf ein nicht auffindbares Profil: wie bei social_find_profile darf es danach geöffnet werden.
  perform private.remember_profile_lookup(v_me, p.id)
     from public.profiles p
    where lower(p.username) = v_query
      and not p.is_discoverable
      and p.id <> v_me
      and not private.is_blocked(v_me, p.id);

  return (
    select coalesce(
             jsonb_agg(
               private.profile_json(c.profile)
                 || jsonb_build_object('relationship', c.relationship, 'request_id', c.request_id)
               order by c.is_exact desc, c.is_friend desc, char_length(c.username_lower), c.username_lower
             ),
             '[]'::jsonb
           )
      from (
        select p as profile,
               lower(p.username) as username_lower,
               lower(p.username) = v_query as is_exact,
               rel.relationship = 'friend' as is_friend,
               rel.relationship,
               rel.request_id
          from public.profiles p
         cross join lateral private.relationship(v_me, p.id) rel
         -- Präfix als Bereich über profiles_username_prefix_idx (byteweise; „~“ liegt hinter allen erlaubten
         -- Zeichen). starts_with hält die Bedingung lesbar und exakt.
         where lower(p.username) ~>=~ v_query
           and lower(p.username) ~<~ (v_query || '~')
           and starts_with(lower(p.username), v_query)
           and p.id <> v_me
           and not private.is_blocked(v_me, p.id)
           and (p.is_discoverable or lower(p.username) = v_query or rel.relationship = 'friend')
         order by lower(p.username) = v_query desc, rel.relationship = 'friend' desc,
                  char_length(p.username), lower(p.username)
         limit 20
      ) c
  );
end;
$$;

revoke all on function public.social_search_profiles(text) from public, anon;
grant execute on function public.social_search_profiles(text) to authenticated;
comment on function public.social_search_profiles(text) is
  'Pace: Präfixsuche über Benutzernamen (ab 3 Zeichen, max. 20 Treffer, exakte zuerst). Ohne mich, ohne Blockierte; nicht auffindbare Profile nur exakt oder als Freunde. Max. 120 Anfragen je 10 Minuten.';

-- ---------------------------------------------------------------------------------------------------------------
-- Öffentliches Profil
-- ---------------------------------------------------------------------------------------------------------------

-- volatile wegen des Rate Limits (zählt in private.rate_limit_events).
create function public.social_public_profile(p_public_id uuid, p_date date)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_target public.profiles%rowtype;
  v_relationship record;
  v_friends_since timestamptz;
  v_week_start date;
  v_week_end date;
  v_steps_today bigint;
  v_steps_week bigint;
begin
  -- Gegen massenhaftes Auflösen von public_ids. Es zählen die Abrufe, die ein Profil liefern; not_found verrät
  -- nichts (nicht vorhanden und nicht sichtbar sind gleich).
  perform private.consume_rate_limit(v_me, 'public_profile', 120, interval '10 minutes');
  perform private.assert_social_date(p_date);
  select * into v_target from public.profiles p where p.public_id = p_public_id;
  -- Wer mich blockiert hat, ist für mich nicht sichtbar; nicht auffindbare Profile ohne Beziehung nur mit Kontext
  -- (private.can_view_profile).
  if not found or not private.can_view_profile(v_me, v_target.id) then
    raise exception 'not_found';
  end if;

  select * into v_relationship from private.relationship(v_me, v_target.id);

  -- Wettbewerbsschritte nur unter Freunden (Zustimmung durch die Freundschaft, siehe 20261018100000_social.sql).
  if v_relationship.relationship = 'friend' then
    select f.created_at into v_friends_since
      from public.friendships f
     where f.user_a = least(v_me, v_target.id)
       and f.user_b = greatest(v_me, v_target.id);
    select b.first_day, b.last_day into v_week_start, v_week_end from private.period_bounds('weekly', p_date) b;
    v_steps_today := coalesce((
      select a.competition_steps from public.daily_activity a
       where a.user_id = v_target.id and a.activity_date = p_date
    ), 0);
    v_steps_week := coalesce((
      select sum(a.competition_steps)::bigint from public.daily_activity a
       where a.user_id = v_target.id and a.activity_date between v_week_start and v_week_end
    ), 0);
  end if;

  return private.profile_json(v_target) || jsonb_build_object(
    'relationship', v_relationship.relationship,
    'request_id', v_relationship.request_id,
    'friends_since', v_friends_since,
    'steps_today', v_steps_today,
    'steps_week', v_steps_week,
    'is_blocked_by_me', private.has_blocked(v_me, v_target.id)
  );
end;
$$;

revoke all on function public.social_public_profile(uuid, date) from public, anon;
grant execute on function public.social_public_profile(uuid, date) to authenticated;
comment on function public.social_public_profile(uuid, date) is
  'Pace: Profil einer Person mit Beziehung; Schritte (Stichtag, ISO-Woche) nur unter Freunden. not_found, wenn die Person mich blockiert hat oder nicht auffindbar ist und kein Kontext besteht. Max. 120 je 10 Minuten.';

-- ---------------------------------------------------------------------------------------------------------------
-- Ersetzte Freundschafts-RPCs: Blockierung und avatar_path
-- ---------------------------------------------------------------------------------------------------------------

create or replace function public.social_send_friend_request(p_public_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_target_id uuid;
  v_request public.friend_requests%rowtype;
  v_request_id uuid;
begin
  select p.id into v_target_id from public.profiles p where p.public_id = p_public_id;
  if v_target_id is null then
    raise exception 'not_found';
  end if;
  if v_target_id = v_me then
    raise exception 'self_request';
  end if;

  perform private.lock_users(array[v_me, v_target_id]);

  -- Selbst blockiert: verständlicher Fehler. Von der anderen Person blockiert: wie nicht vorhanden.
  if private.has_blocked(v_me, v_target_id) then
    raise exception 'blocked';
  end if;
  if private.has_blocked(v_target_id, v_me) then
    raise exception 'not_found';
  end if;

  if private.are_friends(v_me, v_target_id) then
    return jsonb_build_object('status', 'already_friends', 'request_id', null);
  end if;

  select * into v_request from private.open_friend_request(v_me, v_target_id);
  if found then
    if v_request.requester_id = v_me then
      return jsonb_build_object('status', 'already_requested', 'request_id', v_request.id);
    end if;
    -- Gegenanfrage: Die andere Person hat mich bereits angefragt – beide wollen die Freundschaft.
    perform private.accept_friend_request(v_request.id, v_target_id, v_me);
    return jsonb_build_object('status', 'accepted', 'request_id', v_request.id);
  end if;

  -- Nach einer Ablehnung 7 Tage Pause gegenüber derselben Person.
  if exists (
    select 1 from public.friend_requests r
     where r.requester_id = v_me
       and r.addressee_id = v_target_id
       and r.status = 'declined'
       and r.responded_at > now() - interval '7 days'
  ) then
    raise exception 'cooldown';
  end if;
  if (select count(*) from public.friend_requests r where r.requester_id = v_me and r.status = 'pending') >= 50 then
    raise exception 'limit_reached';
  end if;
  perform private.consume_rate_limit(v_me, 'friend_request', 20, interval '24 hours');

  insert into public.friend_requests (requester_id, addressee_id)
  values (v_me, v_target_id)
  returning id into v_request_id;
  return jsonb_build_object('status', 'requested', 'request_id', v_request_id);
end;
$$;

comment on function public.social_send_friend_request(uuid) is
  'Pace: Freundschaftsanfrage senden ({status, request_id}); nimmt eine offene Gegenanfrage automatisch an. blocked, wenn ich die Person blockiert habe.';

create or replace function public.social_friend_requests()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  return (
    select coalesce(
             jsonb_agg(
               private.profile_json(p) || jsonb_build_object(
                 'request_id', r.id,
                 'direction', case when r.addressee_id = v_me then 'incoming' else 'outgoing' end,
                 'created_at', r.created_at
               ) order by r.created_at desc, r.id
             ),
             '[]'::jsonb
           )
      from public.friend_requests r
      join public.profiles p
        on p.id = case when r.addressee_id = v_me then r.requester_id else r.addressee_id end
     where r.status = 'pending'
       and (r.requester_id = v_me or r.addressee_id = v_me)
  );
end;
$$;

create or replace function public.social_friends()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  return (
    select coalesce(
             jsonb_agg(
               private.profile_json(p) || jsonb_build_object('friends_since', f.friends_since)
               order by lower(p.display_name), lower(p.username)
             ),
             '[]'::jsonb
           )
      from private.friends_of(v_me) f
      join public.profiles p on p.id = f.friend_id
  );
end;
$$;

create or replace function public.social_friend_ranking(p_period text, p_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_first_day date;
  v_last_day date;
  v_total integer;
  v_entries jsonb;
begin
  perform private.assert_social_date(p_date);
  select b.first_day, b.last_day into v_first_day, v_last_day from private.period_bounds(p_period, p_date) b;

  -- Teilnehmer: ich und alle Freunde (max. 200), auch ohne Tageswert.
  select count(*)::integer,
         coalesce(
           jsonb_agg(
             private.leaderboard_entry_json(
               r.rank, r.public_user_id, r.username, r.display_name, r.competition_steps, r.user_id = v_me
             ) || jsonb_build_object('avatar_path', private.avatar_path_of(r.user_id))
             order by r.rank
           ) filter (where r.rank <= 201),
           '[]'::jsonb
         )
    into v_total, v_entries
    from private.social_step_ranking(
           array(select v_me union all select f.friend_id from private.friends_of(v_me) f),
           v_first_day,
           v_last_day
         ) r;

  return jsonb_build_object('total_participants', v_total, 'entries', v_entries);
end;
$$;

create or replace function public.social_friend_profile(p_public_id uuid, p_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_friend public.profiles%rowtype;
  v_friends_since timestamptz;
  v_week_start date;
  v_week_end date;
begin
  perform private.assert_social_date(p_date);
  select * into v_friend from public.profiles p where p.public_id = p_public_id;
  if found then
    select f.created_at into v_friends_since
      from public.friendships f
     where f.user_a = least(v_me, v_friend.id)
       and f.user_b = greatest(v_me, v_friend.id);
  end if;
  if v_friends_since is null then
    raise exception 'not_found';
  end if;
  select b.first_day, b.last_day into v_week_start, v_week_end from private.period_bounds('weekly', p_date) b;

  return private.profile_json(v_friend) || jsonb_build_object(
    'friends_since', v_friends_since,
    'steps_today', coalesce((
      select a.competition_steps from public.daily_activity a
       where a.user_id = v_friend.id and a.activity_date = p_date
    ), 0),
    'steps_week', coalesce((
      select sum(a.competition_steps)::bigint from public.daily_activity a
       where a.user_id = v_friend.id and a.activity_date between v_week_start and v_week_end
    ), 0)
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Regionalrankings: Einträge mit avatar_path (Profilbilder sind für alle Angemeldeten lesbar)
-- ---------------------------------------------------------------------------------------------------------------

create or replace function public.leaderboard_page(
  p_region_id text,
  p_period text,
  p_date date,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total bigint;
  v_entries jsonb;
begin
  perform private.assert_leaderboard_access(v_user_id, p_region_id, p_date);

  with ranking as (
    select * from private.leaderboard_ranking(p_region_id, p_period, p_date)
  )
  select coalesce(max(r.total_participants), 0),
         coalesce(
           jsonb_agg(
             private.leaderboard_entry_json(
               r.rank, r.public_user_id, r.username, r.display_name, r.competition_steps, r.user_id = v_user_id
             ) || jsonb_build_object('avatar_path', private.avatar_path_of(r.user_id))
             order by r.rank
           ) filter (where r.rank > v_offset and r.rank <= v_offset + v_limit),
           '[]'::jsonb
         )
    into v_total, v_entries
    from ranking r;

  return jsonb_build_object('total_participants', v_total, 'entries', v_entries);
end;
$$;

create or replace function public.leaderboard_neighborhood(
  p_region_id text,
  p_period text,
  p_date date,
  p_radius integer default 1
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_radius integer := least(greatest(coalesce(p_radius, 1), 0), 10);
  v_total bigint;
  v_entries jsonb;
begin
  perform private.assert_leaderboard_access(v_user_id, p_region_id, p_date);

  -- Das Ranking wird einmal berechnet (CTE mit mehreren Verweisen wird materialisiert).
  with ranking as materialized (
    select * from private.leaderboard_ranking(p_region_id, p_period, p_date)
  ),
  me as (
    select r.rank from ranking r where r.user_id = v_user_id
  )
  select coalesce((select max(r.total_participants) from ranking r), 0),
         coalesce(
           (select jsonb_agg(
                     private.leaderboard_entry_json(
                       r.rank, r.public_user_id, r.username, r.display_name, r.competition_steps, r.user_id = v_user_id
                     ) || jsonb_build_object('avatar_path', private.avatar_path_of(r.user_id))
                     order by r.rank
                   )
              from ranking r
              join me on r.rank between me.rank - v_radius and me.rank + v_radius),
           '[]'::jsonb
         )
    into v_total, v_entries;

  return jsonb_build_object('total_participants', v_total, 'entries', v_entries);
end;
$$;
