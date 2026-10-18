-- =============================================================================================================
-- Pace – Social: Freundschaften, Gruppen, Einladungen und Gruppen-Streak.
--
-- * Kein direkter Tabellenzugriff für Clients: RLS ist auf allen Social-Tabellen aktiv, es gibt keine Policies und
--   keine Rechte für anon/authenticated. Alles läuft über security-definer-RPCs in public, die auth.uid() und ein
--   vorhandenes Profil voraussetzen.
-- * Ausgaben enthalten nur öffentliche Felder: public_id, username, display_name und Schritte. Nie Auth-IDs, nie
--   Gemeinden.
-- * Fehler sind stabile Tokens als Meldung (errcode P0001), nur not_authenticated hat 42501. not_found steht auch
--   für „nicht sichtbar“ und verrät nie, ob etwas existiert.
-- * Zustimmung: Wer eine Freundschaft eingeht, teilt seine Wettbewerbsschritte mit diesem Freund; wer einer Gruppe
--   beitritt, mit allen Mitgliedern – jeweils unabhängig von regional_leaderboard_enabled.
-- * Nebenläufigkeit: Gruppenzeilen werden mit „for update“ gesperrt, Nutzer und Rate-Limits mit Transaktions-
--   Advisory-Locks. Reihenfolge immer Gruppe → Nutzer → Rate-Limit, damit sich parallele Aufrufe nicht verklemmen.
-- * Bewusst nicht umgesetzt: Gruppenchat und Blockieren. Details: docs/SOCIAL.md.
-- =============================================================================================================

-- Zufallsbytes für Einladungscodes (in Supabase bereits vorhanden).
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------------------------------------------
-- Freundschaften
-- ---------------------------------------------------------------------------------------------------------------

create table public.friend_requests (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending',
  created_at   timestamptz not null default now(),
  responded_at timestamptz,

  constraint friend_requests_status_valid check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  constraint friend_requests_not_self check (requester_id <> addressee_id),
  -- Offene Anfragen haben noch keine Antwortzeit, beantwortete bzw. zurückgezogene immer.
  constraint friend_requests_responded_at check ((status = 'pending') = (responded_at is null))
);

comment on table public.friend_requests is
  'Pace: Freundschaftsanfragen mit Verlauf. Kein Clientzugriff – nur über die social_*-RPCs.';

-- Höchstens eine offene Anfrage je Paar, unabhängig von der Richtung.
create unique index friend_requests_open_pair_key on public.friend_requests
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id))
  where status = 'pending';
-- Ausgehende Anfragen (Limit, Cooldown) und Löschen von Profilen.
create index friend_requests_requester_idx on public.friend_requests (requester_id, addressee_id);
-- Eingehende Anfragen und Löschen von Profilen.
create index friend_requests_addressee_idx on public.friend_requests (addressee_id);

create table public.friendships (
  user_a     uuid not null references public.profiles (id) on delete cascade,
  user_b     uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),

  primary key (user_a, user_b),
  -- Jedes Paar genau einmal: kleinere ID zuerst.
  constraint friendships_ordered check (user_a < user_b)
);

comment on table public.friendships is
  'Pace: bestätigte Freundschaften (ein Eintrag je Paar). Kein Clientzugriff – nur über die social_*-RPCs.';

create index friendships_user_b_idx on public.friendships (user_b);

-- ---------------------------------------------------------------------------------------------------------------
-- Gruppen
-- ---------------------------------------------------------------------------------------------------------------

create table public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text not null default '',
  kind        text not null,
  -- Bestimmt den Gruppentag (Kalendertag in dieser Zeitzone) für alle Mitglieder.
  time_zone   text not null default 'Europe/Berlin',
  invite_code text not null,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- Dieselben Regeln wie profiles.display_name (Steuer- und unsichtbare Formatzeichen verboten), 3–40 Zeichen.
  constraint groups_name_valid check (
    char_length(name) between 3 and 40
    and name = btrim(name)
    and name !~ '[[:cntrl:]]'
    and name !~ '[\u0080-\u009F\u00AD\u0600-\u0605\u061C\u06DD\u070F\u180E\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u206F\uFEFF\uFFF9-\uFFFB\U000E0001\U000E0020-\U000E007F]'
  ),
  -- 0–200 Zeichen, Zeilenumbrüche erlaubt, sonst keine Steuer- und unsichtbaren Formatzeichen.
  constraint groups_description_valid check (
    char_length(description) <= 200
    and description = btrim(description, E' \n')
    and translate(description, E'\n', '') !~ '[[:cntrl:]]'
    and description !~ '[\u0080-\u009F\u00AD\u0600-\u0605\u061C\u06DD\u070F\u180E\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u206F\uFEFF\uFFF9-\uFFFB\U000E0001\U000E0020-\U000E007F]'
  ),
  constraint groups_kind_valid check (kind in ('friends', 'class', 'work', 'club', 'other')),
  -- 8 Zeichen ohne verwechselbare Zeichen (kein I, O, 0, 1).
  constraint groups_invite_code_format check (invite_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$'),
  constraint groups_invite_code_key unique (invite_code)
);

comment on table public.groups is 'Pace: Gruppen. Kein Clientzugriff – nur über die social_*-RPCs.';
comment on column public.groups.time_zone is
  'Zeitzone des Gruppentags (Name aus pg_timezone_names). Heute = (now() at time zone time_zone)::date.';

create index groups_created_by_idx on public.groups (created_by);

create trigger groups_set_updated_at
  before update on public.groups
  for each row execute function private.set_updated_at();

create table public.group_members (
  group_id  uuid not null references public.groups (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  role      text not null default 'member',
  joined_at timestamptz not null default now(),

  primary key (group_id, user_id),
  constraint group_members_role_valid check (role in ('owner', 'member'))
);

comment on table public.group_members is
  'Pace: aktuelle Gruppenmitglieder. Genau ein owner je Gruppe. Kein Clientzugriff – nur über die social_*-RPCs.';

-- Höchstens ein Eigentümer; dass es immer einen gibt, stellt der Lösch-Trigger sicher.
create unique index group_members_one_owner_key on public.group_members (group_id) where role = 'owner';
create index group_members_user_idx on public.group_members (user_id);

-- Historie der Mitgliedschaften für die Gruppen-Streak. Wird ausschließlich per Trigger auf group_members gepflegt.
create table public.group_membership_periods (
  id        uuid primary key default gen_random_uuid(),
  group_id  uuid not null references public.groups (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null,
  left_at   timestamptz,

  constraint group_membership_periods_order check (left_at is null or left_at >= joined_at)
);

comment on table public.group_membership_periods is
  'Pace: Mitgliedschaftsperioden (Beitritt bis Austritt) für die Gruppen-Streak. Gepflegt per Trigger.';

-- Höchstens eine offene Periode je Mitglied; zugleich Zugriffspfad des Austritts-Triggers.
create unique index group_membership_periods_open_key on public.group_membership_periods (group_id, user_id)
  where left_at is null;
-- Perioden einer Gruppe für die Tagesberechnung.
create index group_membership_periods_group_idx on public.group_membership_periods (group_id, joined_at);
create index group_membership_periods_user_idx on public.group_membership_periods (user_id);

create table public.group_goal_history (
  group_id       uuid not null references public.groups (id) on delete cascade,
  -- Erster Gruppentag, an dem das Ziel gilt (bis zum nächsten Eintrag).
  effective_from date not null,
  daily_goal     integer not null,

  primary key (group_id, effective_from),
  constraint group_goal_history_daily_goal_valid check (daily_goal between 1000 and 100000)
);

comment on table public.group_goal_history is
  'Pace: Tagesziele einer Gruppe mit Gültigkeitsbeginn. Änderungen gelten ab dem nächsten Gruppentag.';

create table public.group_invitations (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id) on delete cascade,
  inviter_id   uuid not null references public.profiles (id) on delete cascade,
  invitee_id   uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending',
  created_at   timestamptz not null default now(),
  responded_at timestamptz,

  constraint group_invitations_status_valid check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  constraint group_invitations_not_self check (inviter_id <> invitee_id),
  constraint group_invitations_responded_at check ((status = 'pending') = (responded_at is null))
);

comment on table public.group_invitations is
  'Pace: Gruppeneinladungen an Freunde mit Verlauf. Kein Clientzugriff – nur über die social_*-RPCs.';

-- Höchstens eine offene Einladung je Gruppe und eingeladener Person.
create unique index group_invitations_open_key on public.group_invitations (group_id, invitee_id)
  where status = 'pending';
create index group_invitations_group_idx on public.group_invitations (group_id);
create index group_invitations_inviter_idx on public.group_invitations (inviter_id);
create index group_invitations_invitee_idx on public.group_invitations (invitee_id);

-- Zugriff: keiner. RLS ohne Policies und ohne Rechte – Clients nutzen ausschließlich die RPCs unten.
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_membership_periods enable row level security;
alter table public.group_goal_history enable row level security;
alter table public.group_invitations enable row level security;

revoke all on table public.friend_requests from anon, authenticated;
revoke all on table public.friendships from anon, authenticated;
revoke all on table public.groups from anon, authenticated;
revoke all on table public.group_members from anon, authenticated;
revoke all on table public.group_membership_periods from anon, authenticated;
revoke all on table public.group_goal_history from anon, authenticated;
revoke all on table public.group_invitations from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Rate Limits (intern)
-- ---------------------------------------------------------------------------------------------------------------

create table private.rate_limit_events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  action     text not null,
  created_at timestamptz not null default now()
);

comment on table private.rate_limit_events is
  'Pace: gezählte Aktionen je Nutzer für Rate Limits. Veraltete Einträge werden beim Prüfen gelöscht.';

create index rate_limit_events_user_action_idx on private.rate_limit_events (user_id, action, created_at);
revoke all on table private.rate_limit_events from public, anon, authenticated;

-- Zählt eine Aktion und wirft rate_limited, wenn im Zeitfenster schon p_limit Aktionen gezählt sind.
-- Gezählt wird nur, was committet wird: Bricht die aufrufende RPC später mit einem Fehler ab, verfällt der Eintrag.
create function private.consume_rate_limit(p_user_id uuid, p_action text, p_limit integer, p_window interval)
returns void
language plpgsql
set search_path = ''
as $$
begin
  -- Parallele Aufrufe desselben Nutzers für dieselbe Aktion nacheinander prüfen, sonst zählten beide denselben Stand.
  perform pg_advisory_xact_lock(hashtextextended('pace.rate_limit:' || p_user_id::text || ':' || p_action, 0));

  delete from private.rate_limit_events e
   where e.user_id = p_user_id
     and e.action = p_action
     and e.created_at <= now() - p_window;

  if (select count(*) from private.rate_limit_events e where e.user_id = p_user_id and e.action = p_action)
     >= p_limit then
    raise exception 'rate_limited';
  end if;

  insert into private.rate_limit_events (user_id, action) values (p_user_id, p_action);
end;
$$;
revoke all on function private.consume_rate_limit(uuid, text, integer, interval) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Gemeinsame Hilfsfunktionen (intern)
-- ---------------------------------------------------------------------------------------------------------------

-- Angemeldeter Nutzer mit Profil: liefert die Auth-ID oder wirft not_authenticated (42501) bzw. profile_required.
create function private.require_profile()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_user_id) then
    raise exception 'profile_required';
  end if;
  return v_user_id;
end;
$$;
revoke all on function private.require_profile() from public, anon, authenticated;

-- Sperrt Nutzer bis zum Ende der Transaktion (Advisory-Lock je Nutzer). Serialisiert Freundschaftsänderungen und
-- Limitprüfungen je Nutzer. Mehrere Nutzer werden immer in derselben Reihenfolge gesperrt (kein Deadlock).
create function private.lock_users(p_user_ids uuid[])
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_key bigint;
begin
  for v_key in
    select distinct hashtextextended('pace.social.user:' || u.user_id::text, 0)
      from unnest(p_user_ids) as u(user_id)
     order by 1
  loop
    perform pg_advisory_xact_lock(v_key);
  end loop;
end;
$$;
revoke all on function private.lock_users(uuid[]) from public, anon, authenticated;

-- Stichtage für Freundesansichten wie bei den Leaderboards: heute (UTC) − 14 bis + 1, sonst invalid_date.
create function private.assert_social_date(p_date date)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
begin
  if p_date is null or p_date not between v_today - 14 and v_today + 1 then
    raise exception 'invalid_date';
  end if;
end;
$$;
revoke all on function private.assert_social_date(date) from public, anon, authenticated;

-- Zeitraum zu einem Stichtag: 'daily' = der Tag, 'weekly' = ISO-Woche (Montag–Sonntag), sonst invalid_period.
create function private.period_bounds(p_period text, p_date date, out first_day date, out last_day date)
language plpgsql
immutable
set search_path = ''
as $$
begin
  case p_period
    when 'daily' then
      first_day := p_date;
      last_day := p_date;
    when 'weekly' then
      first_day := date_trunc('week', p_date::timestamp)::date;
      last_day := first_day + 6;
    else
      raise exception 'invalid_period';
  end case;
end;
$$;
revoke all on function private.period_bounds(text, date) from public, anon, authenticated;

-- Schritt-Ranking einer festen Teilnehmermenge im Zeitraum. Teilnehmer ohne Tageswert zählen mit 0.
-- Reihenfolge: Schritte absteigend, dann wer den Wert zuerst hatte (ohne Tageswert zuletzt), dann public_id.
create function private.social_step_ranking(p_user_ids uuid[], p_first_day date, p_last_day date)
returns table (
  rank bigint,
  user_id uuid,
  public_user_id uuid,
  username text,
  display_name text,
  competition_steps bigint
)
language sql
stable
set search_path = ''
as $$
  select row_number() over (order by t.steps desc, t.changed_at asc nulls last, t.public_id asc),
         t.id,
         t.public_id,
         t.username,
         t.display_name,
         t.steps
    from (
      select p.id,
             p.public_id,
             p.username,
             p.display_name,
             coalesce(sum(a.competition_steps), 0)::bigint as steps,
             max(a.steps_changed_at) as changed_at
        from public.profiles p
        left join public.daily_activity a
          on a.user_id = p.id
         and a.activity_date between p_first_day and p_last_day
       where p.id = any (p_user_ids)
       group by p.id
    ) t;
$$;
revoke all on function private.social_step_ranking(uuid[], date, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Hilfsfunktionen Freundschaften (intern)
-- ---------------------------------------------------------------------------------------------------------------

-- Freunde eines Nutzers mit Beginn der Freundschaft.
create function private.friends_of(p_user_id uuid)
returns table (friend_id uuid, friends_since timestamptz)
language sql
stable
set search_path = ''
as $$
  select f.user_b, f.created_at from public.friendships f where f.user_a = p_user_id
  union all
  select f.user_a, f.created_at from public.friendships f where f.user_b = p_user_id;
$$;
revoke all on function private.friends_of(uuid) from public, anon, authenticated;

create function private.are_friends(p_user_id uuid, p_other_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships f
     where f.user_a = least(p_user_id, p_other_id)
       and f.user_b = greatest(p_user_id, p_other_id)
  );
$$;
revoke all on function private.are_friends(uuid, uuid) from public, anon, authenticated;

-- Offene Anfrage zwischen zwei Nutzern, gleich in welcher Richtung (höchstens eine).
create function private.open_friend_request(p_user_id uuid, p_other_id uuid)
returns setof public.friend_requests
language sql
stable
set search_path = ''
as $$
  select r.*
    from public.friend_requests r
   where r.status = 'pending'
     and least(r.requester_id, r.addressee_id) = least(p_user_id, p_other_id)
     and greatest(r.requester_id, r.addressee_id) = greatest(p_user_id, p_other_id);
$$;
revoke all on function private.open_friend_request(uuid, uuid) from public, anon, authenticated;

-- Nimmt eine offene Anfrage an und legt die Freundschaft an. Max. 200 Freunde je Seite (limit_reached).
-- Voraussetzung: Der Aufrufer hält private.lock_users für beide Nutzer.
create function private.accept_friend_request(p_request_id uuid, p_requester_id uuid, p_addressee_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from private.friends_of(p_requester_id)) >= 200
     or (select count(*) from private.friends_of(p_addressee_id)) >= 200 then
    raise exception 'limit_reached';
  end if;

  insert into public.friendships (user_a, user_b)
  values (least(p_requester_id, p_addressee_id), greatest(p_requester_id, p_addressee_id))
  on conflict do nothing;

  update public.friend_requests r
     set status = 'accepted', responded_at = now()
   where r.id = p_request_id;
end;
$$;
revoke all on function private.accept_friend_request(uuid, uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Hilfsfunktionen Gruppen (intern)
-- ---------------------------------------------------------------------------------------------------------------

-- Kalendertag „heute“ in einer Zeitzone (Gruppentag).
create function private.local_today(p_time_zone text)
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone p_time_zone)::date;
$$;
revoke all on function private.local_today(text) from public, anon, authenticated;

-- Einladungscode: 8 kryptographisch zufällige Zeichen aus 32 Zeichen (256 / 32 → gleichverteilt).
create function private.generate_invite_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', get_byte(r.bytes, i.n) % 32 + 1, 1), '' order by i.n)
    from (select extensions.gen_random_bytes(8) as bytes) r
   cross join generate_series(0, 7) as i(n);
$$;
revoke all on function private.generate_invite_code() from public, anon, authenticated;

-- Übersetzt eine verletzte Prüfregel in das Fehler-Token für die App. Die Regeln selbst stehen nur in den
-- Constraints der Tabellen; null = keine Validierungsregel der App.
create function private.group_check_token(p_constraint text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_constraint
    when 'groups_name_valid' then 'invalid_name'
    when 'groups_description_valid' then 'invalid_description'
    when 'groups_kind_valid' then 'invalid_kind'
    when 'group_goal_history_daily_goal_valid' then 'invalid_goal'
  end;
$$;
revoke all on function private.group_check_token(text) from public, anon, authenticated;

-- Rolle eines Nutzers in einer Gruppe; null, wenn er kein Mitglied ist.
create function private.group_role(p_group_id uuid, p_user_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select m.role from public.group_members m where m.group_id = p_group_id and m.user_id = p_user_id;
$$;
revoke all on function private.group_role(uuid, uuid) from public, anon, authenticated;

-- Rolle des Nutzers; wirft not_found, wenn die Gruppe fehlt oder er kein Mitglied ist (Existenz bleibt verborgen).
create function private.require_group_member(p_group_id uuid, p_user_id uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_role text := private.group_role(p_group_id, p_user_id);
begin
  if v_role is null then
    raise exception 'not_found';
  end if;
  return v_role;
end;
$$;
revoke all on function private.require_group_member(uuid, uuid) from public, anon, authenticated;

-- Sperrt die Gruppenzeile für eine Änderung und prüft die Mitgliedschaft (not_found) bzw. bei p_owner_only die
-- Eigentümerrolle (not_allowed).
create function private.lock_group_member(p_group_id uuid, p_user_id uuid, p_owner_only boolean)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_role text;
begin
  perform 1 from public.groups g where g.id = p_group_id for update;
  v_role := private.require_group_member(p_group_id, p_user_id);
  if p_owner_only and v_role <> 'owner' then
    raise exception 'not_allowed';
  end if;
end;
$$;
revoke all on function private.lock_group_member(uuid, uuid, boolean) from public, anon, authenticated;

-- Tagesziel einer Gruppe an einem Gruppentag: Eintrag mit dem größten effective_from <= Tag.
create function private.group_goal_on(p_group_id uuid, p_day date)
returns integer
language sql
stable
set search_path = ''
as $$
  select gh.daily_goal
    from public.group_goal_history gh
   where gh.group_id = p_group_id
     and gh.effective_from <= p_day
   order by gh.effective_from desc
   limit 1;
$$;
revoke all on function private.group_goal_on(uuid, date) from public, anon, authenticated;

-- Nimmt einen Nutzer in eine Gruppe auf (idempotent) und markiert offene Einladungen dieser Gruppe an ihn als
-- angenommen. Limits: 50 Mitglieder je Gruppe, 20 Mitgliedschaften je Nutzer (limit_reached).
-- Voraussetzung: Der Aufrufer hat zuerst die Gruppenzeile (for update) und dann den Nutzer (lock_users) gesperrt –
-- so können parallele Beitritte keines der Limits überschreiten.
create function private.add_group_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if private.group_role(p_group_id, p_user_id) is null then
    if (select count(*) from public.group_members m where m.group_id = p_group_id) >= 50
       or (select count(*) from public.group_members m where m.user_id = p_user_id) >= 20 then
      raise exception 'limit_reached';
    end if;
    insert into public.group_members (group_id, user_id, role) values (p_group_id, p_user_id, 'member');
  end if;

  update public.group_invitations i
     set status = 'accepted', responded_at = now()
   where i.group_id = p_group_id
     and i.invitee_id = p_user_id
     and i.status = 'pending';
end;
$$;
revoke all on function private.add_group_member(uuid, uuid) from public, anon, authenticated;

-- Kennzahlen je Gruppentag von p_first_day bis p_last_day (eine Zeile je Tag, aufsteigend).
--   * Tagesende d = Beginn von d + 1 in der Zeitzone der Gruppe (berücksichtigt Sommer-/Winterzeit).
--   * Mitglieder des Tages: Perioden, die das Tagesende abdecken (joined_at < Tagesende und left_at fehlt oder
--     >= Tagesende). Für den laufenden Tag sind das genau die aktuellen Mitglieder. Jede Person zählt einmal.
--   * Ziel: Eintrag der Zielhistorie mit dem größten effective_from <= d.
--   * Erreicht hat, wer am Tag d (daily_activity.activity_date) mindestens das Ziel an Competition Steps hat.
--   * required = ceil(n / 3); reached = n > 0 und mindestens required Mitglieder haben das Ziel erreicht.
create function private.group_day_stats(p_group_id uuid, p_first_day date, p_last_day date)
returns table (
  day date,
  member_count integer,
  required_count integer,
  reached_count integer,
  daily_goal integer,
  reached boolean
)
language sql
stable
set search_path = ''
as $$
  with days as (
    select p_first_day + s.n as day,
           (p_first_day + s.n + 1)::timestamp at time zone g.time_zone as day_end
      from public.groups g
     cross join generate_series(0, p_last_day - p_first_day) as s(n)
     where g.id = p_group_id
  ),
  -- Perioden, die mindestens ein Tagesende im Zeitraum abdecken.
  periods as (
    select mp.user_id, mp.joined_at, mp.left_at
      from public.group_membership_periods mp
     where mp.group_id = p_group_id
       and mp.joined_at < (select max(d.day_end) from days d)
       and (mp.left_at is null or mp.left_at >= (select min(d.day_end) from days d))
  ),
  -- Tageswerte dieser Mitglieder im Zeitraum: je Person ein Bereichszugriff über den Primärschlüssel, damit der
  -- Aufwand von der Gruppe abhängt und nicht von der Größe der gesamten Tabelle.
  activity as materialized (
    select a.user_id, a.activity_date, a.competition_steps
      from (select distinct p.user_id from periods p) u
     cross join lateral (
       select x.user_id, x.activity_date, x.competition_steps
         from public.daily_activity x
        where x.user_id = u.user_id
          and x.activity_date between p_first_day and p_last_day
     ) a
  ),
  goals as (
    select gh.effective_from,
           lead(gh.effective_from) over (order by gh.effective_from) as superseded_from,
           gh.daily_goal
      from public.group_goal_history gh
     where gh.group_id = p_group_id
  ),
  -- count(distinct …): Jede Person zählt pro Tag einmal, auch wenn sich Perioden überschneiden sollten.
  totals as (
    select d.day,
           go.daily_goal,
           count(distinct p.user_id)::integer as member_count,
           (count(distinct p.user_id) filter (where ac.competition_steps >= go.daily_goal))::integer as reached_count
      from days d
      left join goals go
        on go.effective_from <= d.day
       and (go.superseded_from is null or d.day < go.superseded_from)
      left join periods p
        on p.joined_at < d.day_end
       and (p.left_at is null or p.left_at >= d.day_end)
      left join activity ac on ac.user_id = p.user_id and ac.activity_date = d.day
     group by d.day, go.daily_goal
  )
  select t.day,
         t.member_count,
         (t.member_count + 2) / 3,
         t.reached_count,
         t.daily_goal,
         t.member_count > 0 and t.reached_count >= (t.member_count + 2) / 3
    from totals t
   order by t.day;
$$;
revoke all on function private.group_day_stats(uuid, date, date) from public, anon, authenticated;

-- Gruppen-JSON „summary“ aus Sicht eines Mitglieds (not_found für Nichtmitglieder).
--   * Berücksichtigt werden die Gruppentage vom Erstellungstag bis heute, höchstens die letzten 730 (inkl. heute).
--   * current_streak: lückenlos erreichte Tage bis heute bzw. – solange heute noch nicht erreicht ist – bis gestern.
--     Der laufende Tag bricht die Streak also nie vorzeitig.
--   * best_streak: längste Folge erreichter Tage im berücksichtigten Zeitraum.
create function private.group_summary(p_group_id uuid, p_user_id uuid)
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
    'created_at', v_group.created_at
  );
end;
$$;
revoke all on function private.group_summary(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Trigger: Mitgliedschaftshistorie, Eigentümerwechsel, leere Gruppen
-- ---------------------------------------------------------------------------------------------------------------

-- Beitritt öffnet eine Mitgliedschaftsperiode.
create function private.open_group_membership_period()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.group_membership_periods (group_id, user_id, joined_at)
  values (new.group_id, new.user_id, new.joined_at);
  return null;
end;
$$;
revoke all on function private.open_group_membership_period() from public, anon, authenticated;

create trigger group_members_open_period
  after insert on public.group_members
  for each row execute function private.open_group_membership_period();

-- Austritt, Entfernen oder Löschen des Profils: Periode schließen und offene Einladungen dieser Person in die Gruppe
-- zurückziehen. Fehlt danach der Eigentümer, wird das am längsten beigetretene verbleibende Mitglied Eigentümer; ist
-- niemand mehr übrig, wird die Gruppe gelöscht. Wird die Gruppe selbst gelöscht (Cascade), ist ihre Zeile schon weg
-- und es bleibt nichts zu tun.
create function private.handle_group_member_removed()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.group_membership_periods mp
     set left_at = now()
   where mp.group_id = old.group_id
     and mp.user_id = old.user_id
     and mp.left_at is null;

  -- Gruppe sperren, damit parallele Austritte nicht gleichzeitig verschiedene Eigentümer bestimmen.
  perform 1 from public.groups g where g.id = old.group_id for update;
  if not found then
    return null;
  end if;

  -- Einladungen gelten nur, solange die einladende Person Mitglied ist – sonst bliebe z. B. die Einladung eines
  -- entfernten Mitglieds annehmbar.
  update public.group_invitations i
     set status = 'cancelled', responded_at = now()
   where i.group_id = old.group_id
     and i.inviter_id = old.user_id
     and i.status = 'pending';

  if not exists (select 1 from public.group_members m where m.group_id = old.group_id) then
    delete from public.groups g where g.id = old.group_id;
  elsif not exists (select 1 from public.group_members m where m.group_id = old.group_id and m.role = 'owner') then
    update public.group_members m
       set role = 'owner'
     where m.group_id = old.group_id
       and m.user_id = (
         select n.user_id
           from public.group_members n
          where n.group_id = old.group_id
          order by n.joined_at, n.user_id
          limit 1
       );
  end if;
  return null;
end;
$$;
revoke all on function private.handle_group_member_removed() from public, anon, authenticated;

create trigger group_members_after_delete
  after delete on public.group_members
  for each row execute function private.handle_group_member_removed();

-- Vor dem Löschen eines Profils alle seine Gruppen sperren (nach ID sortiert). So gilt auch beim Cascade die
-- Reihenfolge Gruppe → Mitgliedszeile wie in den RPCs, und parallele Gruppenänderungen verklemmen sich nicht.
create function private.lock_groups_of_deleted_profile()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform 1
     from public.groups g
    where g.id in (select m.group_id from public.group_members m where m.user_id = old.id)
    order by g.id
      for update of g;
  return old;
end;
$$;
revoke all on function private.lock_groups_of_deleted_profile() from public, anon, authenticated;

create trigger profiles_lock_groups_before_delete
  before delete on public.profiles
  for each row execute function private.lock_groups_of_deleted_profile();

-- ---------------------------------------------------------------------------------------------------------------
-- RPCs: Freundschaften
-- ---------------------------------------------------------------------------------------------------------------

create function public.social_find_profile(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_username text := btrim(p_username);
  v_target public.profiles%rowtype;
  v_request public.friend_requests%rowtype;
  v_relationship text;
begin
  -- Jede Suche zählt, auch ungültige und erfolglose – sonst ließen sich Benutzernamen beliebig durchprobieren.
  perform private.consume_rate_limit(v_me, 'profile_search', 30, interval '10 minutes');

  if v_username is null or v_username !~ '^[A-Za-z0-9_]{3,20}$' then
    return null;
  end if;
  select * into v_target from public.profiles p where lower(p.username) = lower(v_username);
  if not found then
    return null;
  end if;

  if v_target.id = v_me then
    v_relationship := 'self';
  elsif private.are_friends(v_me, v_target.id) then
    v_relationship := 'friend';
  else
    select * into v_request from private.open_friend_request(v_me, v_target.id);
    v_relationship := case
      when v_request.id is null then 'none'
      when v_request.requester_id = v_me then 'outgoing_request'
      else 'incoming_request'
    end;
  end if;

  return jsonb_build_object(
    'public_id', v_target.public_id,
    'username', v_target.username,
    'display_name', v_target.display_name,
    'relationship', v_relationship,
    'request_id', v_request.id
  );
end;
$$;

revoke all on function public.social_find_profile(text) from public, anon;
grant execute on function public.social_find_profile(text) to authenticated;
comment on function public.social_find_profile(text) is
  'Pace: Profil per exaktem Benutzernamen (ohne Groß-/Kleinschreibung) mit Beziehung; null ohne Treffer. Max. 30 Suchen je 10 Minuten.';

create function public.social_send_friend_request(p_public_id uuid)
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

revoke all on function public.social_send_friend_request(uuid) from public, anon;
grant execute on function public.social_send_friend_request(uuid) to authenticated;
comment on function public.social_send_friend_request(uuid) is
  'Pace: Freundschaftsanfrage senden ({status, request_id}); nimmt eine offene Gegenanfrage automatisch an.';

create function public.social_respond_friend_request(p_request_id uuid, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_request public.friend_requests%rowtype;
begin
  select * into v_request from public.friend_requests r where r.id = p_request_id and r.addressee_id = v_me;
  -- Ohne eindeutige Antwort (p_accept null) bleibt die Anfrage unverändert.
  if not found or p_accept is null then
    raise exception 'not_found';
  end if;

  perform private.lock_users(array[v_request.requester_id, v_me]);
  -- Nach dem Sperren neu lesen: Eine parallele Antwort oder Rücknahme kann den Status geändert haben.
  select * into v_request from public.friend_requests r where r.id = p_request_id;

  if v_request.status = 'pending' then
    if p_accept then
      perform private.accept_friend_request(v_request.id, v_request.requester_id, v_me);
      return jsonb_build_object('status', 'accepted');
    end if;
    update public.friend_requests r set status = 'declined', responded_at = now() where r.id = p_request_id;
    return jsonb_build_object('status', 'declined');
  end if;

  -- Wiederholtes Annehmen (z. B. nach Verbindungsabbruch) ist idempotent, solange die Freundschaft besteht.
  if p_accept and v_request.status = 'accepted' and private.are_friends(v_me, v_request.requester_id) then
    return jsonb_build_object('status', 'accepted');
  end if;
  raise exception 'not_found';
end;
$$;

revoke all on function public.social_respond_friend_request(uuid, boolean) from public, anon;
grant execute on function public.social_respond_friend_request(uuid, boolean) to authenticated;
comment on function public.social_respond_friend_request(uuid, boolean) is
  'Pace: eingehende offene Freundschaftsanfrage annehmen oder ablehnen ({status}). Annehmen ist idempotent.';

create function public.social_cancel_friend_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  update public.friend_requests r
     set status = 'cancelled', responded_at = now()
   where r.id = p_request_id
     and r.requester_id = v_me
     and r.status = 'pending';
  if not found then
    raise exception 'not_found';
  end if;
end;
$$;

revoke all on function public.social_cancel_friend_request(uuid) from public, anon;
grant execute on function public.social_cancel_friend_request(uuid) to authenticated;
comment on function public.social_cancel_friend_request(uuid) is
  'Pace: eigene offene Freundschaftsanfrage zurückziehen.';

create function public.social_remove_friend(p_public_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_friend_id uuid;
begin
  select p.id into v_friend_id from public.profiles p where p.public_id = p_public_id;
  if v_friend_id is null then
    raise exception 'not_found';
  end if;

  perform private.lock_users(array[v_me, v_friend_id]);
  delete from public.friendships f
   where f.user_a = least(v_me, v_friend_id)
     and f.user_b = greatest(v_me, v_friend_id);
  if not found then
    raise exception 'not_found';
  end if;

  -- Einladungen setzen eine Freundschaft voraus: Offene Einladungen zwischen beiden werden zurückgezogen.
  update public.group_invitations i
     set status = 'cancelled', responded_at = now()
   where i.status = 'pending'
     and ((i.inviter_id = v_me and i.invitee_id = v_friend_id)
       or (i.inviter_id = v_friend_id and i.invitee_id = v_me));
end;
$$;

revoke all on function public.social_remove_friend(uuid) from public, anon;
grant execute on function public.social_remove_friend(uuid) to authenticated;
comment on function public.social_remove_friend(uuid) is
  'Pace: Freundschaft beenden; offene Gruppeneinladungen zwischen beiden werden zurückgezogen.';

create function public.social_friend_requests()
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
                 'request_id', r.id,
                 'direction', case when r.addressee_id = v_me then 'incoming' else 'outgoing' end,
                 'public_id', p.public_id,
                 'username', p.username,
                 'display_name', p.display_name,
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

revoke all on function public.social_friend_requests() from public, anon;
grant execute on function public.social_friend_requests() to authenticated;
comment on function public.social_friend_requests() is
  'Pace: offene eingehende und ausgehende Freundschaftsanfragen, neueste zuerst.';

create function public.social_friends()
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
                 'public_id', p.public_id,
                 'username', p.username,
                 'display_name', p.display_name,
                 'friends_since', f.friends_since
               ) order by lower(p.display_name), lower(p.username)
             ),
             '[]'::jsonb
           )
      from private.friends_of(v_me) f
      join public.profiles p on p.id = f.friend_id
  );
end;
$$;

revoke all on function public.social_friends() from public, anon;
grant execute on function public.social_friends() to authenticated;
comment on function public.social_friends() is
  'Pace: eigene Freunde, sortiert nach Anzeigename (ohne Groß-/Kleinschreibung), dann Benutzername.';

create function public.social_friend_ranking(p_period text, p_date date)
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
             ) order by r.rank
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

revoke all on function public.social_friend_ranking(text, date) from public, anon;
grant execute on function public.social_friend_ranking(text, date) to authenticated;
comment on function public.social_friend_ranking(text, date) is
  'Pace: Ranking aus mir und meinen Freunden ({total_participants, entries}), daily oder weekly. Nur öffentliche Felder.';

create function public.social_friend_profile(p_public_id uuid, p_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_friend_id uuid;
  v_public_id uuid;
  v_username text;
  v_display_name text;
  v_friends_since timestamptz;
  v_week_start date;
  v_week_end date;
begin
  perform private.assert_social_date(p_date);
  select p.id, p.public_id, p.username, p.display_name, f.created_at
    into v_friend_id, v_public_id, v_username, v_display_name, v_friends_since
    from public.profiles p
    join public.friendships f
      on f.user_a = least(v_me, p.id)
     and f.user_b = greatest(v_me, p.id)
   where p.public_id = p_public_id;
  if v_friend_id is null then
    raise exception 'not_found';
  end if;
  select b.first_day, b.last_day into v_week_start, v_week_end from private.period_bounds('weekly', p_date) b;

  return jsonb_build_object(
    'public_id', v_public_id,
    'username', v_username,
    'display_name', v_display_name,
    'friends_since', v_friends_since,
    'steps_today', coalesce((
      select a.competition_steps from public.daily_activity a
       where a.user_id = v_friend_id and a.activity_date = p_date
    ), 0),
    'steps_week', coalesce((
      select sum(a.competition_steps)::bigint from public.daily_activity a
       where a.user_id = v_friend_id and a.activity_date between v_week_start and v_week_end
    ), 0)
  );
end;
$$;

revoke all on function public.social_friend_profile(uuid, date) from public, anon;
grant execute on function public.social_friend_profile(uuid, date) to authenticated;
comment on function public.social_friend_profile(uuid, date) is
  'Pace: Profil eines Freundes mit Schritten am Stichtag und in dessen ISO-Woche. Nur für Freunde.';

-- ---------------------------------------------------------------------------------------------------------------
-- RPCs: Gruppen
-- ---------------------------------------------------------------------------------------------------------------

create function public.social_create_group(
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
  v_time_zone text := coalesce(p_time_zone, 'Europe/Berlin');
  v_group_id uuid;
  v_constraint text;
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names t where t.name = v_time_zone) then
    raise exception 'invalid_time_zone';
  end if;

  perform private.lock_users(array[v_me]);
  -- Max. 10 Gruppen als Eigentümer und 20 Mitgliedschaften.
  if (select count(*) from public.group_members m where m.user_id = v_me and m.role = 'owner') >= 10
     or (select count(*) from public.group_members m where m.user_id = v_me) >= 20 then
    raise exception 'limit_reached';
  end if;
  perform private.consume_rate_limit(v_me, 'group_create', 5, interval '24 hours');

  -- Name, Beschreibung, Art und Ziel prüfen die Constraints; fehlende Pflichtwerte werden zu ungültigen Werten.
  begin
    loop
      insert into public.groups (name, description, kind, time_zone, invite_code, created_by)
      values (
        coalesce(btrim(p_name, E' \t\n\r'), ''),
        coalesce(btrim(p_description, E' \t\n\r'), ''),
        coalesce(p_kind, ''),
        v_time_zone,
        private.generate_invite_code(),
        v_me
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

  insert into public.group_members (group_id, user_id, role) values (v_group_id, v_me, 'owner');
  return private.group_summary(v_group_id, v_me);
end;
$$;

revoke all on function public.social_create_group(text, text, text, integer, text) from public, anon;
grant execute on function public.social_create_group(text, text, text, integer, text) to authenticated;
comment on function public.social_create_group(text, text, text, integer, text) is
  'Pace: Gruppe erstellen (Ersteller wird owner) und summary liefern. Max. 5 je 24 h, 10 als Eigentümer.';

create function public.social_update_group(p_group_id uuid, p_name text, p_description text, p_kind text)
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
           kind = coalesce(p_kind, g.kind)
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

revoke all on function public.social_update_group(uuid, text, text, text) from public, anon;
grant execute on function public.social_update_group(uuid, text, text, text) to authenticated;
comment on function public.social_update_group(uuid, text, text, text) is
  'Pace: Name, Beschreibung und Art einer Gruppe ändern (nur owner; null = unverändert) und summary liefern.';

create function public.social_set_group_goal(p_group_id uuid, p_daily_goal integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_tomorrow date;
  v_constraint text;
begin
  perform private.lock_group_member(p_group_id, v_me, true);
  select private.local_today(g.time_zone) + 1 into v_tomorrow from public.groups g where g.id = p_group_id;

  -- Gilt ab dem nächsten Gruppentag; Vergangenheit und der laufende Tag bleiben unverändert.
  begin
    insert into public.group_goal_history (group_id, effective_from, daily_goal)
    values (p_group_id, v_tomorrow, coalesce(p_daily_goal, 0))
    on conflict (group_id, effective_from) do update set daily_goal = excluded.daily_goal;
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

revoke all on function public.social_set_group_goal(uuid, integer) from public, anon;
grant execute on function public.social_set_group_goal(uuid, integer) to authenticated;
comment on function public.social_set_group_goal(uuid, integer) is
  'Pace: Tagesziel ab dem nächsten Gruppentag setzen (nur owner, 1000–100000) und summary liefern.';

create function public.social_my_groups()
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
             jsonb_agg(private.group_summary(g.id, v_me) order by lower(g.name), g.created_at, g.id),
             '[]'::jsonb
           )
      from public.group_members m
      join public.groups g on g.id = m.group_id
     where m.user_id = v_me
  );
end;
$$;

revoke all on function public.social_my_groups() from public, anon;
grant execute on function public.social_my_groups() to authenticated;
comment on function public.social_my_groups() is 'Pace: summary aller eigenen Gruppen, sortiert nach Name.';

create function public.social_group(p_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  return private.group_summary(p_group_id, v_me);
end;
$$;

revoke all on function public.social_group(uuid) from public, anon;
grant execute on function public.social_group(uuid) to authenticated;
comment on function public.social_group(uuid) is 'Pace: summary einer Gruppe (nur für Mitglieder).';

create function public.social_group_ranking(p_group_id uuid, p_period text)
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
               'reached_goal_today', coalesce(t.competition_steps >= v_goal, false)
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

revoke all on function public.social_group_ranking(uuid, text) from public, anon;
grant execute on function public.social_group_ranking(uuid, text) to authenticated;
comment on function public.social_group_ranking(uuid, text) is
  'Pace: Ranking der aktuellen Mitglieder für den Gruppentag (daily) bzw. dessen ISO-Woche (weekly).';

create function public.social_group_days(p_group_id uuid, p_days integer default 14)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_today date;
  v_first_day date;
begin
  perform private.require_group_member(p_group_id, v_me);
  -- 1–60 Tage, nie vor dem Erstellungstag.
  select private.local_today(g.time_zone),
         greatest(
           (g.created_at at time zone g.time_zone)::date,
           private.local_today(g.time_zone) - (least(greatest(coalesce(p_days, 14), 1), 60) - 1)
         )
    into v_today, v_first_day
    from public.groups g
   where g.id = p_group_id;

  return (
    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'day', s.day,
                 'member_count', s.member_count,
                 'required_count', s.required_count,
                 'reached_count', s.reached_count,
                 'daily_goal', s.daily_goal,
                 'reached', s.reached,
                 'is_today', s.day = v_today
               ) order by s.day desc
             ),
             '[]'::jsonb
           )
      from private.group_day_stats(p_group_id, v_first_day, v_today) s
  );
end;
$$;

revoke all on function public.social_group_days(uuid, integer) from public, anon;
grant execute on function public.social_group_days(uuid, integer) to authenticated;
comment on function public.social_group_days(uuid, integer) is
  'Pace: Gruppentage mit Mitgliederzahl, benötigten und erreichten Mitgliedern, neueste zuerst (1–60 Tage).';

create function public.social_regenerate_invite_code(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.lock_group_member(p_group_id, v_me, true);

  loop
    begin
      update public.groups g set invite_code = private.generate_invite_code() where g.id = p_group_id;
      exit;
    exception
      when unique_violation then
        -- Bereits vergebener Code (praktisch ausgeschlossen): mit einem neuen Code wiederholen.
        null;
    end;
  end loop;

  return private.group_summary(p_group_id, v_me);
end;
$$;

revoke all on function public.social_regenerate_invite_code(uuid) from public, anon;
grant execute on function public.social_regenerate_invite_code(uuid) to authenticated;
comment on function public.social_regenerate_invite_code(uuid) is
  'Pace: neuen Einladungscode erzeugen (nur owner; der alte wird ungültig) und summary liefern.';

create function public.social_join_group(p_invite_code text)
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
     for update;
  if v_group_id is not null then
    perform private.lock_users(array[v_me]);
  end if;

  -- Jeder Versuch zählt, auch mit falschem Code – sonst ließen sich Codes durchprobieren.
  perform private.consume_rate_limit(v_me, 'group_join', 20, interval '1 hour');
  if v_group_id is null then
    -- Bewusst kein raise: Eine Exception rollte die Transaktion samt gezähltem Versuch zurück. Stattdessen antwortet
    -- PostgREST über response.status mit HTTP 400 und demselben JSON wie bei raise exception (code P0001, message
    -- invalid_invite_code) – und committet den gezählten Versuch.
    perform set_config('response.status', '400', true);
    return jsonb_build_object('code', 'P0001', 'message', 'invalid_invite_code', 'details', null, 'hint', null);
  end if;

  perform private.add_group_member(v_group_id, v_me);
  return private.group_summary(v_group_id, v_me);
end;
$$;

revoke all on function public.social_join_group(text) from public, anon;
grant execute on function public.social_join_group(text) to authenticated;
comment on function public.social_join_group(text) is
  'Pace: Gruppe per Einladungscode beitreten (idempotent) und summary liefern. Max. 20 Versuche je Stunde; falscher Code → HTTP 400 invalid_invite_code.';

create function public.social_leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.lock_group_member(p_group_id, v_me, false);
  -- Eigentümerwechsel bzw. Löschen der leeren Gruppe übernimmt der Trigger group_members_after_delete.
  delete from public.group_members m where m.group_id = p_group_id and m.user_id = v_me;
end;
$$;

revoke all on function public.social_leave_group(uuid) from public, anon;
grant execute on function public.social_leave_group(uuid) to authenticated;
comment on function public.social_leave_group(uuid) is
  'Pace: Gruppe verlassen. Der Eigentümer wird ersetzt; verlässt die letzte Person die Gruppe, wird sie gelöscht.';

create function public.social_remove_group_member(p_group_id uuid, p_public_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_member_id uuid;
begin
  perform private.lock_group_member(p_group_id, v_me, true);
  select p.id into v_member_id from public.profiles p where p.public_id = p_public_id;
  if v_member_id = v_me then
    raise exception 'not_allowed';
  end if;

  delete from public.group_members m where m.group_id = p_group_id and m.user_id = v_member_id;
  if not found then
    raise exception 'not_found';
  end if;
end;
$$;

revoke all on function public.social_remove_group_member(uuid, uuid) from public, anon;
grant execute on function public.social_remove_group_member(uuid, uuid) to authenticated;
comment on function public.social_remove_group_member(uuid, uuid) is
  'Pace: Mitglied aus der Gruppe entfernen (nur owner, nicht sich selbst).';

create function public.social_delete_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.lock_group_member(p_group_id, v_me, true);
  delete from public.groups g where g.id = p_group_id;
end;
$$;

revoke all on function public.social_delete_group(uuid) from public, anon;
grant execute on function public.social_delete_group(uuid) to authenticated;
comment on function public.social_delete_group(uuid) is
  'Pace: Gruppe mit Mitgliedschaften, Historie und Einladungen löschen (nur owner).';

create function public.social_invite_to_group(p_group_id uuid, p_public_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_invitee_id uuid;
  v_invitation_id uuid;
begin
  perform private.lock_group_member(p_group_id, v_me, false);

  select p.id into v_invitee_id from public.profiles p where p.public_id = p_public_id;
  if v_invitee_id = v_me then
    return jsonb_build_object('status', 'already_member', 'invitation_id', null);
  end if;
  if v_invitee_id is null then
    raise exception 'not_found';
  end if;
  -- Beide Nutzer sperren wie social_remove_friend: Eine parallel beendete Freundschaft hinterlässt so keine Einladung.
  perform private.lock_users(array[v_me, v_invitee_id]);
  -- Einladen kann man nur eigene Freunde.
  if not private.are_friends(v_me, v_invitee_id) then
    raise exception 'not_found';
  end if;
  if private.group_role(p_group_id, v_invitee_id) is not null then
    return jsonb_build_object('status', 'already_member', 'invitation_id', null);
  end if;

  select i.id into v_invitation_id
    from public.group_invitations i
   where i.group_id = p_group_id
     and i.invitee_id = v_invitee_id
     and i.status = 'pending';
  if v_invitation_id is not null then
    return jsonb_build_object('status', 'already_invited', 'invitation_id', v_invitation_id);
  end if;

  if (select count(*) from public.group_members m where m.group_id = p_group_id) >= 50 then
    raise exception 'limit_reached';
  end if;
  perform private.consume_rate_limit(v_me, 'group_invite', 30, interval '24 hours');

  insert into public.group_invitations (group_id, inviter_id, invitee_id)
  values (p_group_id, v_me, v_invitee_id)
  returning id into v_invitation_id;
  return jsonb_build_object('status', 'invited', 'invitation_id', v_invitation_id);
end;
$$;

revoke all on function public.social_invite_to_group(uuid, uuid) from public, anon;
grant execute on function public.social_invite_to_group(uuid, uuid) to authenticated;
comment on function public.social_invite_to_group(uuid, uuid) is
  'Pace: Freund in die Gruppe einladen ({status, invitation_id}). Nur Mitglieder; max. 30 Einladungen je 24 h.';

create function public.social_group_invitations()
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
                 'member_count', (select count(*) from public.group_members m where m.group_id = g.id),
                 'inviter_username', p.username,
                 'inviter_display_name', p.display_name,
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

revoke all on function public.social_group_invitations() from public, anon;
grant execute on function public.social_group_invitations() to authenticated;
comment on function public.social_group_invitations() is 'Pace: offene eingehende Gruppeneinladungen, neueste zuerst.';

create function public.social_group_outgoing_invitations(p_group_id uuid)
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
               jsonb_build_object(
                 'invitation_id', i.id,
                 'public_id', p.public_id,
                 'username', p.username,
                 'display_name', p.display_name,
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

revoke all on function public.social_group_outgoing_invitations(uuid) from public, anon;
grant execute on function public.social_group_outgoing_invitations(uuid) to authenticated;
comment on function public.social_group_outgoing_invitations(uuid) is
  'Pace: offene Einladungen einer Gruppe (owner: alle, Mitglieder: eigene), neueste zuerst.';

create function public.social_respond_group_invitation(p_invitation_id uuid, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_group_id uuid;
begin
  -- Ohne eindeutige Antwort (p_accept null) bleibt die Einladung unverändert.
  if p_accept is null then
    raise exception 'not_found';
  end if;

  if not p_accept then
    update public.group_invitations i
       set status = 'declined', responded_at = now()
     where i.id = p_invitation_id
       and i.invitee_id = v_me
       and i.status = 'pending';
    if not found then
      raise exception 'not_found';
    end if;
    return jsonb_build_object('status', 'declined', 'group', null);
  end if;

  select i.group_id into v_group_id
    from public.group_invitations i
   where i.id = p_invitation_id
     and i.invitee_id = v_me
     and i.status = 'pending';
  if v_group_id is null then
    raise exception 'not_found';
  end if;

  perform 1 from public.groups g where g.id = v_group_id for update;
  perform private.lock_users(array[v_me]);
  -- Nach dem Sperren erneut prüfen: Die Einladung kann inzwischen zurückgezogen oder beantwortet worden sein.
  perform 1 from public.group_invitations i where i.id = p_invitation_id and i.status = 'pending';
  if not found then
    raise exception 'not_found';
  end if;

  perform private.add_group_member(v_group_id, v_me);
  return jsonb_build_object('status', 'accepted', 'group', private.group_summary(v_group_id, v_me));
end;
$$;

revoke all on function public.social_respond_group_invitation(uuid, boolean) from public, anon;
grant execute on function public.social_respond_group_invitation(uuid, boolean) to authenticated;
comment on function public.social_respond_group_invitation(uuid, boolean) is
  'Pace: eingehende offene Gruppeneinladung annehmen (Limits wie beim Beitritt) oder ablehnen ({status, group}).';

create function public.social_cancel_group_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
begin
  update public.group_invitations i
     set status = 'cancelled', responded_at = now()
   where i.id = p_invitation_id
     and i.status = 'pending'
     and (i.inviter_id = v_me or private.group_role(i.group_id, v_me) = 'owner');
  if not found then
    raise exception 'not_found';
  end if;
end;
$$;

revoke all on function public.social_cancel_group_invitation(uuid) from public, anon;
grant execute on function public.social_cancel_group_invitation(uuid) to authenticated;
comment on function public.social_cancel_group_invitation(uuid) is
  'Pace: offene Gruppeneinladung zurückziehen (einladende Person oder owner).';
