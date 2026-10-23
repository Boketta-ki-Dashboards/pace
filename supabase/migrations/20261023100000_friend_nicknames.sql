-- =============================================================================================================
-- Pace – Spitznamen für Freunde (privat je Nutzer).
--
-- Nur additive Änderungen: neue Tabelle, neue Funktionen, ersetzte Funktionen mit gleicher Signatur. Ältere
-- App-Versionen kennen das Feld nickname nicht und ignorieren es.
--
-- * friend_nicknames: Spitzname, den owner für target vergeben hat. Nur für aktuelle Freunde; endet die
--   Freundschaft (Entfernen, Blockieren, Löschen eines Kontos), wird der Spitzname gelöscht (Trigger). Kein
--   Clientzugriff (RLS ohne Policies) – Schreiben nur über social_set_friend_nickname.
-- * Ausgabe: private.profile_json liefert zusätzlich nickname – den Spitznamen, den der Aufrufer (auth.uid())
--   vergeben hat, sonst null. Damit tragen alle Profile anderer Personen in Freundesliste, Anfragen, Suche,
--   Profilansicht, Gruppen-Einladungen, Chat (Absender, Gegenüber, geteilte Profile) den eigenen Spitznamen. Die
--   Rankings (Freunde, Gruppe, Region) und die Einladungsliste bauen ihre Einträge selbst und ergänzen nickname
--   ausdrücklich. Fremde Spitznamen gibt der Server nie aus: Gelesen wird ausschließlich owner_id = auth.uid().
-- * account_export enthält die eigenen Spitznamen (friend_nicknames).
-- * Fehler-Tokens: not_found (keine aktuelle Freundschaft), invalid_nickname, rate_limited.
-- =============================================================================================================

-- ---------------------------------------------------------------------------------------------------------------
-- Tabelle
-- ---------------------------------------------------------------------------------------------------------------

create table public.friend_nicknames (
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  target_id  uuid not null references public.profiles (id) on delete cascade,
  nickname   text not null,
  updated_at timestamptz not null default now(),

  primary key (owner_id, target_id),
  constraint friend_nicknames_not_self check (owner_id <> target_id),
  -- Gleiche Regeln wie profiles.display_name (PaceCore.NicknameRules): 1–30 Zeichen ohne Rand-Leerraum, keine
  -- Steuer- und unsichtbaren Formatzeichen.
  constraint friend_nicknames_nickname_valid check (
    char_length(nickname) between 1 and 30
    and nickname = btrim(nickname)
    and nickname !~ '[[:cntrl:]]'
    and nickname !~ '[\u0080-\u009F\u00AD\u0600-\u0605\u061C\u06DD\u070F\u180E\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u206F\uFEFF\uFFF9-\uFFFB\U000E0001\U000E0020-\U000E007F]'
  )
);

comment on table public.friend_nicknames is
  'Pace: private Spitznamen für Freunde (owner vergibt für target). Kein Clientzugriff – nur über social_set_friend_nickname; Ausgabe nur an owner.';

-- Löschen von Profilen (Fremdschlüssel) und Aufräumen beim Ende einer Freundschaft.
create index friend_nicknames_target_idx on public.friend_nicknames (target_id);

alter table public.friend_nicknames enable row level security;
revoke all on table public.friend_nicknames from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Hilfsfunktionen und Trigger (intern)
-- ---------------------------------------------------------------------------------------------------------------

-- Spitzname, den p_owner für p_target vergeben hat (null ohne Eintrag oder ohne p_owner).
create function private.friend_nickname(p_owner uuid, p_target uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select n.nickname from public.friend_nicknames n where n.owner_id = p_owner and n.target_id = p_target;
$$;
revoke all on function private.friend_nickname(uuid, uuid) from public, anon, authenticated;

-- Endet eine Freundschaft (Entfernen, Blockieren, Cascade beim Löschen eines Kontos), verlieren beide Seiten ihre
-- Spitznamen füreinander.
create function private.delete_friendship_nicknames()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  delete from public.friend_nicknames n
   where (n.owner_id = old.user_a and n.target_id = old.user_b)
      or (n.owner_id = old.user_b and n.target_id = old.user_a);
  return null;
end;
$$;
revoke all on function private.delete_friendship_nicknames() from public, anon, authenticated;

create trigger friendships_delete_nicknames
  after delete on public.friendships
  for each row execute function private.delete_friendship_nicknames();

-- Blockieren beendet die Freundschaft ohnehin; zusätzlich hier, damit auch ohne Freundschaft nie ein Spitzname
-- zwischen blockierten Personen übrig bleibt.
create function private.delete_blocked_nicknames()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  delete from public.friend_nicknames n
   where (n.owner_id = new.blocker_id and n.target_id = new.blocked_id)
      or (n.owner_id = new.blocked_id and n.target_id = new.blocker_id);
  return null;
end;
$$;
revoke all on function private.delete_blocked_nicknames() from public, anon, authenticated;

create trigger user_blocks_delete_nicknames
  after insert on public.user_blocks
  for each row execute function private.delete_blocked_nicknames();

-- Ersetzt die Fassung aus 20261019100000_profiles_blocks_search.sql: zusätzlich nickname – der Spitzname, den der
-- Aufrufer (auth.uid()) für diese Person vergeben hat. Ohne Anmeldung (z. B. Trigger) und ohne Eintrag null.
create or replace function private.profile_json(p_profile public.profiles)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'public_id', p_profile.public_id,
    'username', p_profile.username,
    'display_name', p_profile.display_name,
    'avatar_path', p_profile.avatar_path,
    'nickname', private.friend_nickname(auth.uid(), p_profile.id)
  );
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- RPC: Spitzname setzen
-- ---------------------------------------------------------------------------------------------------------------

create function public.social_set_friend_nickname(p_public_id uuid, p_nickname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_target public.profiles%rowtype;
  v_nickname text;
begin
  select * into v_target from public.profiles p where p.public_id = p_public_id;
  if not found or v_target.id = v_me then
    raise exception 'not_found';
  end if;

  -- Wie social_remove_friend/social_block_user: beide Nutzer sperren, damit kein Spitzname nach dem parallelen Ende
  -- der Freundschaft übrig bleibt.
  perform private.lock_users(array[v_me, v_target.id]);
  if not private.are_friends(v_me, v_target.id) then
    raise exception 'not_found';
  end if;

  -- Leerraum zusammenfassen und am Rand entfernen (wie NicknameRules.normalized in der App); leer entfernt.
  v_nickname := nullif(btrim(regexp_replace(coalesce(p_nickname, ''), '[[:space:]]+', ' ', 'g')), '');
  perform private.consume_rate_limit(v_me, 'friend_nickname', 30, interval '10 minutes');

  if v_nickname is null then
    delete from public.friend_nicknames n where n.owner_id = v_me and n.target_id = v_target.id;
  else
    begin
      insert into public.friend_nicknames (owner_id, target_id, nickname)
      values (v_me, v_target.id, v_nickname)
      on conflict (owner_id, target_id)
      do update set nickname = excluded.nickname, updated_at = now();
    exception
      when check_violation then
        raise exception 'invalid_nickname';
    end;
  end if;

  return private.profile_json(v_target);
end;
$$;

revoke all on function public.social_set_friend_nickname(uuid, text) from public, anon;
grant execute on function public.social_set_friend_nickname(uuid, text) to authenticated;
comment on function public.social_set_friend_nickname(uuid, text) is
  'Pace: eigenen Spitznamen für einen aktuellen Freund setzen (1–30 Zeichen) bzw. mit leer/null entfernen. Liefert das Profil mit nickname. not_found ohne Freundschaft; max. 30 je 10 Minuten.';

-- ---------------------------------------------------------------------------------------------------------------
-- Rankings und Einladungen: Einträge mit nickname
-- ---------------------------------------------------------------------------------------------------------------

-- Ersetzt die Fassung aus 20261019100000_profiles_blocks_search.sql: zusätzlich nickname.
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
             ) || jsonb_build_object(
               'avatar_path', private.avatar_path_of(r.user_id),
               'nickname', private.friend_nickname(v_me, r.user_id)
             )
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

-- Ersetzt die Fassung aus 20261019100100_groups_privacy_images.sql: zusätzlich nickname.
create or replace function public.social_group_ranking(p_group_id uuid, p_period text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_today date;
  v_goal integer;
  v_first_day date;
  v_last_day date;
  v_total integer;
  v_entries jsonb;
begin
  perform private.require_group_member(p_group_id, v_me);
  select private.local_today(g.time_zone) into v_today from public.groups g where g.id = p_group_id;
  select b.first_day, b.last_day into v_first_day, v_last_day from private.period_bounds(p_period, v_today) b;
  v_goal := private.group_goal_on(p_group_id, v_today);

  select count(*)::integer,
         coalesce(
           jsonb_agg(
             private.leaderboard_entry_json(
               r.rank, r.public_user_id, r.username, r.display_name, r.competition_steps, r.user_id = v_me
             ) || jsonb_build_object(
               'role', m.role,
               'reached_goal_today', coalesce(t.competition_steps >= v_goal, false),
               'avatar_path', private.avatar_path_of(r.user_id),
               'nickname', private.friend_nickname(v_me, r.user_id)
             ) order by r.rank
           ),
           '[]'::jsonb
         )
    into v_total, v_entries
    from private.social_step_ranking(
           array(select gm.user_id from public.group_members gm where gm.group_id = p_group_id),
           v_first_day,
           v_last_day
         ) r
    join public.group_members m on m.group_id = p_group_id and m.user_id = r.user_id
    left join public.daily_activity t on t.user_id = r.user_id and t.activity_date = v_today;

  return jsonb_build_object(
    'total_participants', v_total,
    'group_today', v_today,
    'daily_goal', v_goal,
    'entries', v_entries
  );
end;
$$;

-- Ersetzt die Fassung aus 20261019100000_profiles_blocks_search.sql: zusätzlich nickname (Freunde können auch im
-- Regionalranking stehen).
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
             ) || jsonb_build_object(
               'avatar_path', private.avatar_path_of(r.user_id),
               'nickname', private.friend_nickname(v_user_id, r.user_id)
             )
             order by r.rank
           ) filter (where r.rank > v_offset and r.rank <= v_offset + v_limit),
           '[]'::jsonb
         )
    into v_total, v_entries
    from ranking r;

  return jsonb_build_object('total_participants', v_total, 'entries', v_entries);
end;
$$;

-- Ersetzt die Fassung aus 20261019100000_profiles_blocks_search.sql: zusätzlich nickname.
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
                     ) || jsonb_build_object(
                       'avatar_path', private.avatar_path_of(r.user_id),
                       'nickname', private.friend_nickname(v_user_id, r.user_id)
                     )
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

-- Ersetzt die Fassung aus 20261019100100_groups_privacy_images.sql: zusätzlich inviter_nickname (Einladungen kommen
-- nur von Freunden).
create or replace function public.social_group_invitations()
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
               jsonb_build_object(
                 'invitation_id', i.id,
                 'group_id', g.id,
                 'group_name', g.name,
                 'group_kind', g.kind,
                 'group_image_path', g.image_path,
                 'group_privacy', g.privacy,
                 'member_count', (select count(*) from public.group_members m where m.group_id = g.id),
                 'inviter_public_id', p.public_id,
                 'inviter_username', p.username,
                 'inviter_display_name', p.display_name,
                 'inviter_avatar_path', p.avatar_path,
                 'inviter_nickname', private.friend_nickname(v_me, p.id),
                 'created_at', i.created_at
               ) order by i.created_at desc, i.id
             ),
             '[]'::jsonb
           )
      from public.group_invitations i
      join public.groups g on g.id = i.group_id
      join public.profiles p on p.id = i.inviter_id
     where i.invitee_id = v_me
       and i.status = 'pending'
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Datenschutz: Auskunft mit eigenen Spitznamen
-- ---------------------------------------------------------------------------------------------------------------

-- Ersetzt die Fassung aus 20261019100400_moderation_account.sql: zusätzlich friend_nicknames (eigene Spitznamen).
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

comment on function public.account_export() is
  'Pace: alle personenbezogenen Serverdaten des eigenen Kontos als JSON (Auskunft/Datenübertragbarkeit), inkl. eigener Spitznamen. Max. 5 je Stunde.';
