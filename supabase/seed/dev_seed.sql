-- ##############################################################################################################
-- ##  DEVELOPMENT ONLY – NIEMALS IN PRODUKTION AUSFÜHREN                                                      ##
-- ##                                                                                                          ##
-- ##  Erfundene Testnutzer für lokale Rankings. Wird nur lokal über supabase/config.toml ([db.seed]) bei      ##
-- ##  `supabase start` bzw. `supabase db reset` eingespielt. `supabase db push` wendet Seeds ohne              ##
-- ##  --include-seed nicht an – diese Option darf für das Produktionsprojekt nie verwendet werden.            ##
-- ##  Alle Nutzer heißen dev_… und tragen „(Dev)“ im Anzeigenamen.                                            ##
-- ##############################################################################################################

do $$
begin
  if exists (select 1 from public.profiles where username like 'dev\_%' escape '\') then
    raise notice 'Dev-Seed bereits vorhanden – übersprungen.';
    return;
  end if;

  -- Testnutzer: (laufende Nummer, Benutzername, Anzeigename, Gemeinde, Zustimmung zum Regionalranking)
  create temporary table dev_users (n integer, username text, display_name text, municipality_id text, opt_in boolean)
    on commit drop;
  insert into dev_users values
    (1,  'dev_leon',    'Leon (Dev)',    'DE:06432018', true),   -- Pfungstadt
    (2,  'dev_flavio',  'Flavio (Dev)',  'DE:06432018', true),
    (3,  'dev_tim',     'Tim (Dev)',     'DE:06432018', true),
    (4,  'dev_max',     'Max (Dev)',     'DE:06432018', true),
    (5,  'dev_jonas',   'Jonas (Dev)',   'DE:06432018', true),
    (6,  'dev_lena',    'Lena (Dev)',    'DE:06432018', false),  -- ohne Zustimmung: erscheint nirgends
    (7,  'dev_mia',     'Mia (Dev)',     'DE:06432010', true),   -- Griesheim
    (8,  'dev_noah',    'Noah (Dev)',    'DE:06432010', true),
    (9,  'dev_emma',    'Emma (Dev)',    'DE:06411000', true),   -- Darmstadt (kreisfreie Stadt)
    (10, 'dev_paul',    'Paul (Dev)',    'DE:06411000', true),
    (11, 'dev_hannah',  'Hannah (Dev)',  'DE:06412000', true),   -- Frankfurt am Main
    (12, 'dev_elias',   'Elias (Dev)',   'DE:06412000', true),
    (13, 'dev_sofia',   'Sofia (Dev)',   'DE:11000000', true),   -- Berlin
    (14, 'dev_ben',     'Ben (Dev)',     'DE:11000000', false),
    (15, 'dev_lukas',   'Lukas (Dev)',   'DE:09162000', true),   -- München
    (16, 'dev_anna',    'Anna (Dev)',    'DE:09162000', true);

  insert into auth.users (id, aud, role, is_anonymous, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
         'authenticated', 'authenticated', true,
         '{"provider":"anonymous","providers":["anonymous"]}'::jsonb, '{}'::jsonb, now(), now()
    from dev_users;

  insert into public.profiles (id, username, display_name, municipality_id, regional_leaderboard_enabled)
  select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, username, display_name, municipality_id, opt_in
    from dev_users;

  -- Deterministische Schrittzahlen für heute und die sechs Tage davor.
  insert into public.daily_activity (user_id, activity_date, competition_steps)
  select ('00000000-0000-4000-8000-' || lpad(u.n::text, 12, '0'))::uuid,
         current_date - d,
         2000 + abs(hashtext(u.username || d::text)) % 16000
    from dev_users u
   cross join generate_series(0, 6) as d;
end
$$;
