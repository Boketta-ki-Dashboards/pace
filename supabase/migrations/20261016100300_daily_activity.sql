-- =============================================================================================================
-- Pace – tägliche Wettbewerbsschritte.
--
-- Datensparsam: gespeichert wird ausschließlich die Zahl der Competition Steps pro lokalem Kalendertag.
-- Keine Health Steps, keine Distanz, keine Kalorien, keine Stockwerke, keine Trainingsminuten, keine Rohdaten.
-- =============================================================================================================

create table public.daily_activity (
  user_id           uuid not null references public.profiles (id) on delete cascade,
  -- Lokaler Kalendertag des Geräts (YYYY-MM-DD).
  activity_date     date not null,
  competition_steps integer not null,
  -- Vom Server gesetzt: letzter Sync.
  synced_at         timestamptz not null default now(),
  -- Vom Server gesetzt: letzte Änderung der Schrittzahl. Gleichstand im Ranking → wer den Wert zuerst hatte.
  steps_changed_at  timestamptz not null default now(),

  primary key (user_id, activity_date),
  constraint daily_activity_steps_range check (competition_steps between 0 and 200000)
);

comment on table public.daily_activity is
  'Pace: Competition Steps pro Nutzer und lokalem Kalendertag. Keine weiteren Gesundheitsdaten.';

create index daily_activity_date_steps_idx on public.daily_activity (activity_date, competition_steps desc);

-- Zeitstempel kommen immer vom Server; Werte des Clients werden überschrieben.
create function private.maintain_daily_activity_timestamps()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.synced_at := now();
  if tg_op = 'INSERT' or new.competition_steps is distinct from old.competition_steps then
    new.steps_changed_at := now();
  else
    new.steps_changed_at := old.steps_changed_at;
  end if;
  return new;
end;
$$;
revoke all on function private.maintain_daily_activity_timestamps() from public, anon, authenticated;

create trigger daily_activity_maintain_timestamps
  before insert or update on public.daily_activity
  for each row execute function private.maintain_daily_activity_timestamps();

-- Zugriff: nur eigene Zeilen. Geschrieben werden dürfen nur Tage im Sync-Fenster (letzte 8 Tage bis morgen, UTC –
-- deckt alle Zeitzonen ab). Ältere Tage lassen sich nachträglich nicht mehr ändern.
alter table public.daily_activity enable row level security;

create policy daily_activity_select_own on public.daily_activity
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy daily_activity_insert_own on public.daily_activity
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and activity_date between (now() at time zone 'utc')::date - 8 and (now() at time zone 'utc')::date + 1
  );

create policy daily_activity_update_own on public.daily_activity
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and activity_date between (now() at time zone 'utc')::date - 8 and (now() at time zone 'utc')::date + 1
  );

-- Upsert über PostgREST setzt alle gesendeten Spalten im DO UPDATE – deshalb update auch auf die Schlüsselspalten.
revoke all on table public.daily_activity from anon, authenticated;
grant select on table public.daily_activity to authenticated;
grant insert (user_id, activity_date, competition_steps) on table public.daily_activity to authenticated;
grant update (user_id, activity_date, competition_steps) on table public.daily_activity to authenticated;
