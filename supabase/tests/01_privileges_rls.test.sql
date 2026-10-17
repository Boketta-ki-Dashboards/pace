-- Pace: Rechte und Row Level Security (Struktur).
begin;
select plan(27);

-- RLS ist auf allen Tabellen aktiv.
select ok((select relrowsecurity from pg_class where oid = 'public.regions'::regclass), 'RLS: regions');
select ok((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass), 'RLS: profiles');
select ok((select relrowsecurity from pg_class where oid = 'public.daily_activity'::regclass), 'RLS: daily_activity');

-- anon (nur Publishable Key, ohne Anmeldung) hat keinen Tabellenzugriff.
select ok(not has_table_privilege('anon', 'public.regions', 'select'), 'anon: regions nicht lesbar');
select ok(not has_table_privilege('anon', 'public.profiles', 'select'), 'anon: profiles nicht lesbar');
select ok(not has_table_privilege('anon', 'public.profiles', 'insert'), 'anon: profiles nicht schreibbar');
select ok(not has_table_privilege('anon', 'public.daily_activity', 'select'), 'anon: daily_activity nicht lesbar');
select ok(not has_table_privilege('anon', 'public.daily_activity', 'insert'), 'anon: daily_activity nicht schreibbar');

-- anon darf keine RPCs ausführen, authenticated schon.
select ok(not has_function_privilege('anon', 'public.search_municipalities(text, integer)', 'execute'), 'anon: search');
select ok(not has_function_privilege('anon', 'public.get_region_hierarchy(text)', 'execute'), 'anon: hierarchy');
select ok(not has_function_privilege('anon', 'public.is_username_available(text)', 'execute'), 'anon: username');
select ok(not has_function_privilege('anon', 'public.leaderboard_page(text, text, date, integer, integer)', 'execute'), 'anon: page');
select ok(not has_function_privilege('anon', 'public.leaderboard_neighborhood(text, text, date, integer)', 'execute'), 'anon: neighborhood');
select ok(has_function_privilege('authenticated', 'public.leaderboard_page(text, text, date, integer, integer)', 'execute'), 'authenticated: page');
select ok(has_function_privilege('authenticated', 'public.search_municipalities(text, integer)', 'execute'), 'authenticated: search');

-- Das interne Schema ist für Clients gesperrt.
select ok(not has_schema_privilege('authenticated', 'private', 'usage'), 'private: kein usage für authenticated');
select ok(not has_schema_privilege('anon', 'private', 'usage'), 'private: kein usage für anon');
select ok(not has_function_privilege('authenticated', 'private.leaderboard_ranking(text, text, date)', 'execute'), 'private: Ranking intern');

-- Geschützte Spalten.
select ok(not has_column_privilege('authenticated', 'public.profiles', 'id', 'update'), 'profiles.id nicht änderbar');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'public_id', 'update'), 'profiles.public_id nicht änderbar');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'public_id', 'insert'), 'profiles.public_id nicht setzbar');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'created_at', 'update'), 'profiles.created_at nicht änderbar');
select ok(not has_column_privilege('authenticated', 'public.daily_activity', 'synced_at', 'insert'), 'synced_at nur vom Server');
select ok(not has_column_privilege('authenticated', 'public.daily_activity', 'steps_changed_at', 'update'), 'steps_changed_at nur vom Server');
select ok(not has_table_privilege('authenticated', 'public.profiles', 'delete'), 'profiles: kein delete');
select ok(not has_table_privilege('authenticated', 'public.regions', 'insert'), 'regions: kein insert');

-- Datensparsamkeit: daily_activity enthält keine weiteren Gesundheitswerte.
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute
    where attrelid = 'public.daily_activity'::regclass and attnum > 0 and not attisdropped),
  array['user_id', 'activity_date', 'competition_steps', 'synced_at', 'steps_changed_at'],
  'daily_activity speichert nur Competition Steps'
);

select * from finish();
rollback;
