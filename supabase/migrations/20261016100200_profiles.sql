-- =============================================================================================================
-- Pace – Profile.
--
-- Jeder Nutzer verwaltet nur sein eigenes Profil. Andere Nutzer sehen Profile ausschließlich über die
-- Leaderboard-Funktionen (nur Anzeigename, Benutzername, Schritte, Rang – und nur bei Zustimmung).
-- =============================================================================================================

create table public.profiles (
  id                           uuid primary key references auth.users (id) on delete cascade,
  public_id                    uuid not null unique default gen_random_uuid(),
  username                     text not null,
  display_name                 text not null,
  municipality_id              text references public.regions (id),
  regional_leaderboard_enabled boolean not null default false,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now(),

  -- Spiegelt PaceCore.UsernameRules.
  constraint profiles_username_format check (username ~ '^[A-Za-z0-9_]{3,20}$'),
  constraint profiles_username_not_reserved check (lower(username) <> all (array[
    'admin', 'administrator', 'pace', 'paceapp', 'support', 'help', 'hilfe', 'moderator', 'mod',
    'system', 'root', 'official', 'offiziell', 'team', 'staff', 'null', 'undefined', 'me', 'du'
  ])),
  -- Spiegelt PaceCore.DisplayNameRules (die App normalisiert Leerzeichen vor dem Senden).
  constraint profiles_display_name_valid check (
    char_length(display_name) between 1 and 30
    and display_name = btrim(display_name)
    and display_name !~ '[[:cntrl:]]'
  )
);

comment on table public.profiles is 'Pace: eigenes Profil. Nur für den Nutzer selbst lesbar und änderbar.';
comment on column public.profiles.public_id is 'Öffentliche ID für Rankings – unabhängig von der Auth-ID.';
comment on column public.profiles.regional_leaderboard_enabled is
  'Ausdrückliche Zustimmung zu öffentlichen Regionalrankings. Standard: aus.';

-- Benutzernamen sind ohne Beachtung der Groß-/Kleinschreibung eindeutig.
create unique index profiles_username_lower_key on public.profiles (lower(username));
-- Teilnehmer eines Regionalrankings.
create index profiles_ranked_municipality_idx on public.profiles (municipality_id)
  where regional_leaderboard_enabled;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

-- Die Gemeinde muss eine aktive Region der Ebene „municipality“ sein (ein Fremdschlüssel prüft keine Ebene).
create function private.validate_profile_municipality()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.municipality_id is not null
     and (tg_op = 'INSERT' or new.municipality_id is distinct from old.municipality_id)
     and not exists (
       select 1 from public.regions r
        where r.id = new.municipality_id and r.level = 'municipality' and r.is_active
     ) then
    raise exception 'invalid_municipality: % ist keine aktive Gemeinde', new.municipality_id
      using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_profile_municipality() from public, anon, authenticated;

create trigger profiles_validate_municipality
  before insert or update of municipality_id on public.profiles
  for each row execute function private.validate_profile_municipality();

-- Zugriff: nur die eigene Zeile.
alter table public.profiles enable row level security;

create policy profiles_select_own on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy profiles_update_own on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- Spaltengenaue Rechte: id, public_id und Zeitstempel können Clients nicht ändern.
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant insert (id, username, display_name, municipality_id, regional_leaderboard_enabled)
  on table public.profiles to authenticated;
grant update (username, display_name, municipality_id, regional_leaderboard_enabled)
  on table public.profiles to authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- RPC: Ist ein Benutzername noch frei? Prüft nur die Belegung, nicht das Format.
-- security definer, weil Nutzer fremde Profile nicht lesen dürfen.
-- ---------------------------------------------------------------------------------------------------------------
create function public.is_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.profiles p
     where lower(p.username) = lower(btrim(coalesce(p_username, '')))
  );
$$;

revoke all on function public.is_username_available(text) from public, anon;
grant execute on function public.is_username_available(text) to authenticated;
comment on function public.is_username_available(text) is
  'Pace: true, wenn kein Profil diesen Benutzernamen (ohne Groß-/Kleinschreibung) verwendet.';
