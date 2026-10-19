-- =============================================================================================================
-- Pace – Gruppen: Privatsphäre, Gruppenbild, Erstellen mit Einladungen.
--
-- Nur additive Änderungen: neue Spalten mit Standardwerten, neue Funktionen, ersetzte Funktionen mit gleicher
-- Signatur. Bestehende Gruppen behalten ihr Verhalten (privacy = 'code': Beitritt per Code und Einladung).
--
-- * groups.privacy: 'invite_only' (nur auf Einladung, der Code ist abgeschaltet) oder 'code'.
-- * groups.image_path: Gruppenbild im privaten Bucket „group-images“, immer im Ordner der Gruppen-ID. Ein Trigger
--   prüft Ordner, Format und dass die Datei bereits hochgeladen ist.
-- * social_create_group mit p_privacy und p_invitee_public_ids legt Gruppe, Eigentümer und Einladungen in einer
--   Transaktion an (nur Freunde, Limits wie bei social_invite_to_group). Die alte Fassung (5 Parameter) bleibt für
--   ältere App-Versionen erhalten und erstellt weiterhin Gruppen mit Code.
-- * social_update_group_details und social_set_group_image (nur owner).
-- * Ausgaben enthalten image_path, privacy und Profilbilder (avatar_path) der Personen.
-- =============================================================================================================

alter table public.groups
  add column privacy text not null default 'code',
  add column image_path text;

alter table public.groups add constraint groups_privacy_valid check (privacy in ('invite_only', 'code'));
alter table public.groups add constraint groups_image_path_format check (
  image_path is null
  or image_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|gif|heic|webp)$'
);

comment on column public.groups.privacy is
  'Beitritt: invite_only = nur auf Einladung (Code abgeschaltet), code = Einladung oder Einladungscode.';
comment on column public.groups.image_path is
  'Gruppenbild im privaten Bucket group-images: <group_id>/<Name>.<jpg|jpeg|png|gif|heic|webp>. null = Symbol der Art.';

-- Gruppenbild: nur im Ordner der eigenen Gruppe und nur, wenn die Datei im Bucket existiert. security definer:
-- liest storage.objects unabhängig von den Storage-Policies.
create function private.validate_group_image()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.image_path is not null
     and (tg_op = 'INSERT' or new.image_path is distinct from old.image_path) then
    if split_part(new.image_path, '/', 1) <> new.id::text
       or not exists (
         select 1 from storage.objects o where o.bucket_id = 'group-images' and o.name = new.image_path
       ) then
      raise exception 'invalid_image_path' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.validate_group_image() from public, anon, authenticated;

create trigger groups_validate_image
  before insert or update of image_path on public.groups
  for each row execute function private.validate_group_image();

-- Ersetzt die Fassung aus 20261018100000_social.sql um die neue Prüfregel.
create or replace function private.group_check_token(p_constraint text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_constraint
    when 'groups_name_valid' then 'invalid_name'
    when 'groups_description_valid' then 'invalid_description'
    when 'groups_kind_valid' then 'invalid_kind'
    when 'groups_privacy_valid' then 'invalid_privacy'
    when 'group_goal_history_daily_goal_valid' then 'invalid_goal'
  end;
$$;

-- Ersetzt die Fassung aus 20261018100000_social.sql: zusätzlich image_path und privacy. Alle Angaben für die
-- Gruppenansicht (Bild 4) stehen darin: member_count, today_required_count (ceil(n/3)), today_reached_count,
-- today_complete („Flamme gesichert“), current_streak/best_streak und daily_goal (Tagesziel je Mitglied).
create or replace function private.group_summary(p_group_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_role text := private.require_group_member(p_group_id, p_user_id);
  v_group public.groups%rowtype;
  v_today date;
  v_goal integer;
  v_next_goal integer;
  v_member_count integer;
  v_current_streak integer;
  v_best_streak integer;
  v_today_required integer;
  v_today_reached integer;
  v_today_complete boolean;
begin
  select * into v_group from public.groups g where g.id = p_group_id;
  v_today := private.local_today(v_group.time_zone);
  v_goal := private.group_goal_on(p_group_id, v_today);
  v_next_goal := private.group_goal_on(p_group_id, v_today + 1);
  select count(*)::integer into v_member_count from public.group_members m where m.group_id = p_group_id;

  -- Inseln aufeinanderfolgender erreichter Tage: Tag minus laufende Nummer ist innerhalb einer Insel konstant.
  with stats as materialized (
    select s.day, s.required_count, s.reached_count, s.reached
      from private.group_day_stats(
             p_group_id,
             greatest((v_group.created_at at time zone v_group.time_zone)::date, v_today - 729),
             v_today
           ) s
  ),
  islands as (
    select max(r.day) as last_day, count(*)::integer as streak_length
      from (
        select st.day, st.day - (row_number() over (order by st.day))::integer as island
          from stats st
         where st.reached
      ) r
     group by r.island
  )
  select coalesce((select max(i.streak_length) from islands i where i.last_day >= v_today - 1), 0),
         coalesce((select max(i.streak_length) from islands i), 0),
         coalesce((select st.required_count from stats st where st.day = v_today), 0),
         coalesce((select st.reached_count from stats st where st.day = v_today), 0),
         coalesce((select st.reached from stats st where st.day = v_today), false)
    into v_current_streak, v_best_streak, v_today_required, v_today_reached, v_today_complete;

  return jsonb_build_object(
    'group_id', v_group.id,
    'name', v_group.name,
    'description', v_group.description,
    'kind', v_group.kind,
    'role', v_role,
    'member_count', v_member_count,
    'daily_goal', v_goal,
    'next_daily_goal', case when v_next_goal is distinct from v_goal then v_next_goal end,
    'time_zone', v_group.time_zone,
    'group_today', v_today,
    'invite_code', v_group.invite_code,
    'current_streak', v_current_streak,
    'best_streak', v_best_streak,
    'today_reached_count', v_today_reached,
    'today_required_count', v_today_required,
    'today_complete', v_today_complete,
    'created_at', v_group.created_at,
    'image_path', v_group.image_path,
    'privacy', v_group.privacy
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Gruppe erstellen (mit Privatsphäre und Einladungen)
-- ---------------------------------------------------------------------------------------------------------------

-- Legt eine Gruppe mit p_user_id als owner an und liefert ihre ID. Voraussetzung: Der Aufrufer hält
-- private.lock_users für p_user_id. Limits: 10 Gruppen als Eigentümer, 20 Mitgliedschaften, 5 neue je 24 h.
create function private.create_group(
  p_user_id uuid,
  p_name text,
  p_description text,
  p_kind text,
  p_daily_goal integer,
  p_time_zone text,
  p_privacy text
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_time_zone text := coalesce(p_time_zone, 'Europe/Berlin');
  v_group_id uuid;
  v_constraint text;
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names t where t.name = v_time_zone) then
    raise exception 'invalid_time_zone';
  end if;

  if (select count(*) from public.group_members m where m.user_id = p_user_id and m.role = 'owner') >= 10
     or (select count(*) from public.group_members m where m.user_id = p_user_id) >= 20 then
    raise exception 'limit_reached';
  end if;
  perform private.consume_rate_limit(p_user_id, 'group_create', 5, interval '24 hours');

  -- Name, Beschreibung, Art, Privatsphäre und Ziel prüfen die Constraints.
  begin
    loop
      insert into public.groups (name, description, kind, time_zone, invite_code, created_by, privacy)
      values (
        coalesce(btrim(p_name, E' \t\n\r'), ''),
        coalesce(btrim(p_description, E' \t\n\r'), ''),
        coalesce(p_kind, ''),
        v_time_zone,
        private.generate_invite_code(),
        p_user_id,
        coalesce(p_privacy, '')
      )
      on conflict (invite_code) do nothing
      returning id into v_group_id;
      -- Ein bereits vergebener Code (praktisch ausgeschlossen) führt zu einem neuen Versuch.
      exit when v_group_id is not null;
    end loop;

    -- Das Ziel gilt ab dem Erstellungstag.
    insert into public.group_goal_history (group_id, effective_from, daily_goal)
    values (v_group_id, private.local_today(v_time_zone), coalesce(p_daily_goal, 0));
  exception
    when check_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if private.group_check_token(v_constraint) is null then
        raise;
      end if;
      raise exception '%', private.group_check_token(v_constraint);
  end;

  insert into public.group_members (group_id, user_id, role) values (v_group_id, p_user_id, 'owner');
  return v_group_id;
end;
$$;
revoke all on function private.create_group(uuid, text, text, text, integer, text, text)
  from public, anon, authenticated;

-- Ersetzt die Fassung aus 20261018100000_social.sql (gleiches Verhalten, jetzt über private.create_group).
create or replace function public.social_create_group(
  p_name text,
  p_description text,
  p_kind text,
  p_daily_goal integer,
  p_time_zone text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_group_id uuid;
begin
  perform private.lock_users(array[v_me]);
  v_group_id := private.create_group(v_me, p_name, p_description, p_kind, p_daily_goal, p_time_zone, 'code');
  return private.group_summary(v_group_id, v_me);
end;
$$;

create function public.social_create_group(
  p_name text,
  p_description text,
  p_kind text,
  p_daily_goal integer,
  p_time_zone text,
  p_privacy text,
  p_invitee_public_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_requested uuid[];
  v_invitee_ids uuid[];
  v_invitee_id uuid;
  v_group_id uuid;
begin
  -- Eingeladene auflösen: ohne Doppelte und ohne mich selbst. Unbekannte IDs → not_found (wie
  -- social_invite_to_group).
  select coalesce(array_agg(distinct i.public_id), '{}')
    into v_requested
    from unnest(coalesce(p_invitee_public_ids, '{}')) as i(public_id)
   where i.public_id is not null
     and i.public_id <> (select p.public_id from public.profiles p where p.id = v_me);
  select coalesce(array_agg(p.id), '{}')
    into v_invitee_ids
    from public.profiles p
   where p.public_id = any (v_requested);
  if cardinality(v_invitee_ids) <> cardinality(v_requested) then
    raise exception 'not_found';
  end if;
  -- Höchstens 49 Einladungen: zusammen mit dem Eigentümer passt dann jede eingeladene Person in die Gruppe.
  if cardinality(v_invitee_ids) > 49 then
    raise exception 'limit_reached';
  end if;

  -- Alle Beteiligten in einem Aufruf sperren (feste Reihenfolge, kein Deadlock mit parallelen Freundschafts-RPCs).
  perform private.lock_users(array[v_me] || v_invitee_ids);
  v_group_id := private.create_group(
    v_me, p_name, p_description, p_kind, p_daily_goal, p_time_zone, coalesce(p_privacy, 'invite_only')
  );

  foreach v_invitee_id in array v_invitee_ids loop
    -- Einladen kann man nur eigene Freunde (Blockierungen beenden Freundschaften).
    if not private.are_friends(v_me, v_invitee_id) then
      raise exception 'not_found';
    end if;
    perform private.consume_rate_limit(v_me, 'group_invite', 30, interval '24 hours');
    insert into public.group_invitations (group_id, inviter_id, invitee_id) values (v_group_id, v_me, v_invitee_id);
  end loop;

  return private.group_summary(v_group_id, v_me);
end;
$$;

revoke all on function public.social_create_group(text, text, text, integer, text, text, uuid[]) from public, anon;
grant execute on function public.social_create_group(text, text, text, integer, text, text, uuid[]) to authenticated;
comment on function public.social_create_group(text, text, text, integer, text, text, uuid[]) is
  'Pace: Gruppe mit Privatsphäre erstellen und Freunde einladen (eine Transaktion, max. 49 Einladungen) und summary liefern.';

-- ---------------------------------------------------------------------------------------------------------------
-- Gruppe bearbeiten und Gruppenbild
-- ---------------------------------------------------------------------------------------------------------------

create function public.social_update_group_details(
  p_group_id uuid,
  p_name text,
  p_description text,
  p_kind text,
  p_privacy text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_constraint text;
begin
  perform private.lock_group_member(p_group_id, v_me, true);

  -- null lässt den jeweiligen Wert unverändert.
  begin
    update public.groups g
       set name = coalesce(btrim(p_name, E' \t\n\r'), g.name),
           description = coalesce(btrim(p_description, E' \t\n\r'), g.description),
           kind = coalesce(p_kind, g.kind),
           privacy = coalesce(p_privacy, g.privacy)
     where g.id = p_group_id;
  exception
    when check_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if private.group_check_token(v_constraint) is null then
        raise;
      end if;
      raise exception '%', private.group_check_token(v_constraint);
  end;

  return private.group_summary(p_group_id, v_me);
end;
$$;

revoke all on function public.social_update_group_details(uuid, text, text, text, text) from public, anon;
grant execute on function public.social_update_group_details(uuid, text, text, text, text) to authenticated;
comment on function public.social_update_group_details(uuid, text, text, text, text) is
  'Pace: Name, Beschreibung, Art und Privatsphäre ändern (nur owner; null = unverändert) und summary liefern.';

create function public.social_set_group_image(p_group_id uuid, p_path text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.lock_group_member(p_group_id, v_me, true);
  begin
    update public.groups g set image_path = nullif(btrim(p_path), '') where g.id = p_group_id;
  exception
    when check_violation then
      raise exception 'invalid_image_path';
  end;
  return private.group_summary(p_group_id, v_me);
end;
$$;

revoke all on function public.social_set_group_image(uuid, text) from public, anon;
grant execute on function public.social_set_group_image(uuid, text) to authenticated;
comment on function public.social_set_group_image(uuid, text) is
  'Pace: Gruppenbild setzen (Pfad im Bucket group-images, Ordner = Gruppen-ID, Datei muss existieren) oder mit null entfernen (nur owner).';

-- ---------------------------------------------------------------------------------------------------------------
-- Ersetzte Gruppen-RPCs: Privatsphäre und Profilbilder
-- ---------------------------------------------------------------------------------------------------------------

-- Ersetzt die Fassung aus 20261018100000_social.sql: Gruppen mit privacy = 'invite_only' lassen sich nicht per
-- Code betreten. Die Antwort ist dann dieselbe wie bei einem falschen Code (verrät nicht, dass es den Code gibt).
create or replace function public.social_join_group(p_invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_group_id uuid;
begin
  -- Normalisieren: Großbuchstaben, ohne Leerzeichen und Bindestriche.
  select g.id into v_group_id
    from public.groups g
   where g.invite_code = upper(regexp_replace(coalesce(p_invite_code, ''), '[[:space:]-]', '', 'g'))
     and g.privacy = 'code'
     for update;
  if v_group_id is not null then
    perform private.lock_users(array[v_me]);
  end if;

  -- Jeder Versuch zählt, auch mit falschem Code – sonst ließen sich Codes durchprobieren.
  perform private.consume_rate_limit(v_me, 'group_join', 20, interval '1 hour');
  if v_group_id is null then
    -- Bewusst kein raise (siehe 20261018100000_social.sql): HTTP 400 mit demselben JSON wie bei raise exception,
    -- der gezählte Versuch bleibt erhalten.
    perform set_config('response.status', '400', true);
    return jsonb_build_object('code', 'P0001', 'message', 'invalid_invite_code', 'details', null, 'hint', null);
  end if;

  perform private.add_group_member(v_group_id, v_me);
  return private.group_summary(v_group_id, v_me);
end;
$$;

comment on function public.social_join_group(text) is
  'Pace: Gruppe per Einladungscode beitreten (idempotent, nur privacy = code) und summary liefern. Max. 20 Versuche je Stunde; falscher Code → HTTP 400 invalid_invite_code.';

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
               'avatar_path', private.avatar_path_of(r.user_id)
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

create or replace function public.social_group_outgoing_invitations(p_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_role text;
begin
  v_role := private.require_group_member(p_group_id, v_me);
  -- Der Eigentümer sieht alle offenen Einladungen der Gruppe, Mitglieder nur ihre eigenen.
  return (
    select coalesce(
             jsonb_agg(
               private.profile_json(p) || jsonb_build_object(
                 'invitation_id', i.id,
                 'created_at', i.created_at
               ) order by i.created_at desc, i.id
             ),
             '[]'::jsonb
           )
      from public.group_invitations i
      join public.profiles p on p.id = i.invitee_id
     where i.group_id = p_group_id
       and i.status = 'pending'
       and (v_role = 'owner' or i.inviter_id = v_me)
  );
end;
$$;
