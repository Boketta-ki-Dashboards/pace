-- =============================================================================================================
-- Pace – Basis: internes Schema, Erweiterungen, gemeinsame Typen und Hilfsfunktionen.
--
-- Konventionen für alle Pace-Migrationen:
--   * Die App nutzt nur den Publishable Key + Nutzer-JWT (anonyme Anmeldung → Rolle authenticated).
--   * Tabellen in public: RLS aktiv; breite Standardrechte von anon/authenticated werden entzogen und nur die
--     benötigten Rechte (teilweise spaltengenau) vergeben.
--   * Funktionen: set search_path = '' und voll qualifizierte Namen; execute nicht für public/anon.
--   * Interne Hilfsfunktionen liegen im Schema private. Es ist nicht über die Data API erreichbar und anon/
--     authenticated haben dort keine Rechte (usage entzogen).
-- =============================================================================================================

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;
comment on schema private is 'Pace: interne Hilfsfunktionen. Nicht über die Data API erreichbar.';

-- Trigramm-Index für die Gemeindesuche (Teilstring-Suche).
create extension if not exists pg_trgm with schema extensions;

-- Ebenen der regionalen Hierarchie.
create type public.region_level as enum ('municipality', 'district', 'state', 'country');
comment on type public.region_level is 'Pace: Gemeinde, Kreis bzw. kreisfreie Stadt, Bundesland, Staat.';

-- Pflegt updated_at bei jeder Änderung.
create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.set_updated_at() from public, anon, authenticated;

-- Normalisiert Namen und Suchanfragen für die Gemeindesuche:
--   Kleinschreibung, ß → ss, Diakritika entfernen (ä → a, š → s, …), Umschreibungen ae/oe/ue → a/o/u,
--   alle übrigen Zeichen → Leerzeichen. Dadurch finden „münchen“, „munchen“ und „muenchen“ dieselbe Gemeinde.
-- Wird für die generierte Spalte regions.search_name und für die Suchanfrage verwendet (gleiche Regeln).
create function private.normalize_search_text(p_value text)
returns text
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select btrim(
    regexp_replace(
      replace(replace(replace(
        translate(
          replace(replace(replace(replace(replace(replace(lower(p_value),
            'ß', 'ss'), 'ẞ', 'ss'), 'æ', 'ae'), 'Æ', 'ae'), 'œ', 'oe'), 'Œ', 'oe'),
          'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝàáâãäåçèéêëìíîïðñòóôõöøùúûüýÿĀāĂăĄąĆćĈĉĊċČčĎďĐđĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħĨĩĪīĬĭĮįİıĴĵĶķĹĺĻļĽľĿŀŁłŃńŅņŇňŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŦŧŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽž',
          'aaaaaaceeeeiiiidnoooooouuuuyaaaaaaceeeeiiiidnoooooouuuuyyaaaaaaccccccccddddeeeeeeeeeegggggggghhhhiiiiiiiiiijjkklllllllllllnnnnnnoooooorrrrrrssssssssttttttuuuuuuuuuuuuwwyyyzzzzzz'
        ),
        'ae', 'a'), 'oe', 'o'), 'ue', 'u'),
      '[^a-z0-9]+', ' ', 'g'
    )
  );
$$;
-- Nur für die generierte Spalte regions.search_name und für public.search_municipalities (security definer).
revoke all on function private.normalize_search_text(text) from public, anon, authenticated;
comment on function private.normalize_search_text(text) is
  'Pace: normalisiert Namen/Suchanfragen (Kleinschreibung, Umlaute, Diakritika, ae/oe/ue, Satzzeichen).';
