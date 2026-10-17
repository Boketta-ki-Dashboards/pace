-- =============================================================================================================
-- Pace – Regionen: Gemeinde → Kreis bzw. kreisfreie Stadt → Bundesland → Staat.
--
-- Regionen werden ausschließlich über feste IDs referenziert, nie über Namen:
--   Staat 'DE', Land 'DE:<Landesschlüssel>', Kreis 'DE:<Kreisschlüssel>', Gemeinde 'DE:<AGS>'.
-- Die Daten stammen aus dem amtlichen Gemeindeverzeichnis (GV100AD) und werden mit
-- supabase/scripts/import_regions.py als eigene Migration erzeugt. Clients lesen nur.
-- =============================================================================================================

create table public.regions (
  id                 text primary key,
  level              public.region_level not null,
  code               text not null,
  name               text not null,
  official_name      text not null,
  kind               text not null,
  parent_id          text references public.regions (id),
  district_id        text references public.regions (id),
  state_id           text references public.regions (id),
  country_id         text not null references public.regions (id),
  population         integer,
  municipality_count integer not null default 0,
  is_active          boolean not null default true,
  source             text not null,
  -- Normalisierter Name für die Suche (Umlaute, Diakritika, ae/oe/ue, Satzzeichen).
  search_name        text generated always as (private.normalize_search_text(name)) stored,

  constraint regions_kind_valid check (kind in (
    'country', 'state',
    'kreisfreie_stadt', 'stadtkreis', 'kreis', 'landkreis', 'regionalverband',
    'markt', 'stadt', 'gemeinde', 'grosse_kreisstadt', 'gemeindefreies_gebiet'
  )),
  constraint regions_code_unique unique (country_id, level, code),
  constraint regions_municipality_count_valid check (municipality_count >= 0),
  constraint regions_population_valid check (population is null or population >= 0),
  -- Gemeinden kennen ihre komplette Hierarchie; Kreise ihr Land.
  constraint regions_hierarchy_complete check (
    case level
      when 'municipality' then parent_id is not null and district_id = parent_id and state_id is not null
      when 'district' then parent_id is not null and state_id = parent_id and district_id is null
      when 'state' then parent_id = country_id and district_id is null and state_id is null
      else parent_id is null and district_id is null and state_id is null and country_id = id
    end
  )
);

comment on table public.regions is
  'Pace: amtliche Gebietseinheiten (GV100AD). Öffentliche Referenzdaten, nur lesbar.';
comment on column public.regions.municipality_count is
  'Anzahl aktiver Gemeinden in der Region (Gemeinde: 1). Der Client blendet Ranking-Ebenen mit gleicher Anzahl aus.';
comment on column public.regions.is_active is
  'false, wenn die Region in einem neueren Gemeindeverzeichnis fehlt. Wird nie gelöscht, weil Profile darauf verweisen.';

-- Suche (Teilstring) und Zuordnung von Gemeinden zu Kreis/Land/Staat für Rankings.
create index regions_search_name_trgm on public.regions
  using gin (search_name extensions.gin_trgm_ops)
  where level = 'municipality' and is_active;
create index regions_municipality_district_idx on public.regions (district_id) where level = 'municipality';
create index regions_municipality_state_idx on public.regions (state_id) where level = 'municipality';
create index regions_municipality_country_idx on public.regions (country_id) where level = 'municipality';
create index regions_parent_idx on public.regions (parent_id);

-- Zugriff: nur lesen, nur für angemeldete Nutzer.
alter table public.regions enable row level security;

create policy regions_select_authenticated on public.regions
  for select to authenticated
  using (true);

revoke all on table public.regions from anon, authenticated;
grant select on table public.regions to authenticated;

-- Berechnet municipality_count aller Regionen eines Staats neu (nach jedem Import).
create function private.refresh_region_municipality_counts(p_country_id text)
returns void
language sql
set search_path = ''
as $$
  update public.regions r
     set municipality_count = case r.level
       when 'municipality' then case when r.is_active then 1 else 0 end
       when 'district' then (
         select count(*) from public.regions m
          where m.level = 'municipality' and m.is_active and m.district_id = r.id)
       when 'state' then (
         select count(*) from public.regions m
          where m.level = 'municipality' and m.is_active and m.state_id = r.id)
       else (
         select count(*) from public.regions m
          where m.level = 'municipality' and m.is_active and m.country_id = r.id)
     end
   where r.country_id = p_country_id;
$$;
revoke all on function private.refresh_region_municipality_counts(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- RPC: Gemeindesuche. Liefert je Treffer die komplette Hierarchie („hierarchy row“).
-- security definer, weil die Normalisierung im nicht erreichbaren Schema private liegt; gelesen werden nur
-- öffentliche Referenzdaten.
-- ---------------------------------------------------------------------------------------------------------------
create function public.search_municipalities(p_query text, p_limit integer default 20)
returns table (
  municipality_id text, municipality_code text, municipality_name text, municipality_kind text,
  district_id text, district_code text, district_name text, district_kind text, district_municipality_count integer,
  state_id text, state_code text, state_name text, state_municipality_count integer,
  country_id text, country_code text, country_name text, country_municipality_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with params as (
    select private.normalize_search_text(coalesce(p_query, '')) as term,
           least(greatest(coalesce(p_limit, 20), 1), 50) as max_rows
  )
  select m.id, m.code, m.name, m.kind,
         d.id, d.code, d.name, d.kind, d.municipality_count,
         s.id, s.code, s.name, s.municipality_count,
         c.id, c.code, c.name, c.municipality_count
    from params
    join public.regions m
      on m.level = 'municipality'
     and m.is_active
     and m.search_name like '%' || params.term || '%'
    join public.regions d on d.id = m.district_id
    join public.regions s on s.id = m.state_id
    join public.regions c on c.id = m.country_id
   where char_length(params.term) >= 2
   order by
     case
       when m.search_name = params.term then 0
       when m.search_name like params.term || '%' then 1
       when m.search_name like '% ' || params.term || '%' then 2
       else 3
     end,
     m.population desc nulls last,
     m.name,
     m.id
   limit (select max_rows from params);
$$;

revoke all on function public.search_municipalities(text, integer) from public, anon;
grant execute on function public.search_municipalities(text, integer) to authenticated;
comment on function public.search_municipalities(text, integer) is
  'Pace: Gemeindesuche (umlaut- und groß/klein-tolerant), sortiert nach Relevanz und Einwohnerzahl.';

-- ---------------------------------------------------------------------------------------------------------------
-- RPC: Hierarchie einer Gemeinde (0 oder 1 Zeile, auch für deaktivierte Gemeinden).
-- ---------------------------------------------------------------------------------------------------------------
create function public.get_region_hierarchy(p_municipality_id text)
returns table (
  municipality_id text, municipality_code text, municipality_name text, municipality_kind text,
  district_id text, district_code text, district_name text, district_kind text, district_municipality_count integer,
  state_id text, state_code text, state_name text, state_municipality_count integer,
  country_id text, country_code text, country_name text, country_municipality_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, m.code, m.name, m.kind,
         d.id, d.code, d.name, d.kind, d.municipality_count,
         s.id, s.code, s.name, s.municipality_count,
         c.id, c.code, c.name, c.municipality_count
    from public.regions m
    join public.regions d on d.id = m.district_id
    join public.regions s on s.id = m.state_id
    join public.regions c on c.id = m.country_id
   where m.id = p_municipality_id
     and m.level = 'municipality';
$$;

revoke all on function public.get_region_hierarchy(text) from public, anon;
grant execute on function public.get_region_hierarchy(text) to authenticated;
comment on function public.get_region_hierarchy(text) is
  'Pace: Gemeinde mit Kreis bzw. kreisfreier Stadt, Bundesland und Staat.';
