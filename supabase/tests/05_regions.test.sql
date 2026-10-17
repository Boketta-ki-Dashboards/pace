-- Pace: Regionsdaten (echter GV100AD-Import) und Gemeindesuche.
begin;
select plan(20);

-- Bestand aus dem Gemeindeverzeichnis.
select is((select municipality_count from public.regions where id = 'DE'), 10749, 'Deutschland: 10749 Gemeinden');
select is((select count(*)::int from public.regions where level = 'state' and country_id = 'DE'), 16, '16 Bundesländer');
select is((select count(*)::int from public.regions where level = 'district' and country_id = 'DE'), 401, '401 Kreise');
select is((select municipality_count from public.regions where id = 'DE:06'), 421, 'Hessen: 421 Gemeinden');
select is(
  (select district_id || ' ' || state_id || ' ' || country_id from public.regions where id = 'DE:06432018'),
  'DE:06432 DE:06 DE', 'Pfungstadt → Darmstadt-Dieburg → Hessen → Deutschland'
);
select is(
  (select name || ' (' || kind || ')' from public.regions where id = 'DE:06432'),
  'Darmstadt-Dieburg (landkreis)', 'Kreis mit Art'
);
select is(
  (select count(*)::int from public.regions where level = 'municipality' and name is null), 0, 'keine Gemeinde ohne Namen'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":true}';

select is(
  (select municipality_id || ' | ' || district_name || ' | ' || district_kind || ' | ' || state_name
     from public.search_municipalities('Pfungstadt', 5) limit 1),
  'DE:06432018 | Darmstadt-Dieburg | landkreis | Hessen', 'Suche: Pfungstadt mit Hierarchie'
);
select is((select municipality_id from public.search_municipalities('pfung', 5) limit 1), 'DE:06432018', 'Präfix-Suche');
select is((select municipality_id from public.search_municipalities('München', 5) limit 1), 'DE:09162000', 'Suche mit Umlaut');
select is((select municipality_id from public.search_municipalities('munchen', 5) limit 1), 'DE:09162000', 'Suche ohne Umlaut');
select is((select municipality_id from public.search_municipalities('muenchen', 5) limit 1), 'DE:09162000', 'Suche mit ue');
select is(
  (select municipality_id || ' | ' || district_kind || ' | ' || district_municipality_count
     from public.search_municipalities('Frankfurt', 5) limit 1),
  'DE:06412000 | kreisfreie_stadt | 1', 'Frankfurt am Main vor Frankfurt (Oder), kreisfreie Stadt'
);
select ok(
  exists (select 1 from public.search_municipalities('Frankfurt', 5) where municipality_id = 'DE:12053000'),
  'Frankfurt (Oder) ebenfalls gefunden'
);
select is((select count(*)::int from public.search_municipalities('berg', 5)), 5, 'limit');
select ok((select count(*) from public.search_municipalities('berg', 1000)) <= 50, 'limit höchstens 50');
select is((select count(*)::int from public.search_municipalities('P', 20)), 0, 'zu kurze Suche');
select is((select count(*)::int from public.regions where kind = 'gemeindefreies_gebiet'), 2, 'nur bewohnte gemeindefreie Gebiete importiert');

select is(
  (select state_name || ' ' || state_municipality_count from public.get_region_hierarchy('DE:11000000')),
  'Berlin 1', 'Berlin: Stadtstaat mit einer Gemeinde'
);
select is((select count(*)::int from public.get_region_hierarchy('DE:06432')), 0, 'Hierarchie nur für Gemeinden');

reset role;
select * from finish();
rollback;
