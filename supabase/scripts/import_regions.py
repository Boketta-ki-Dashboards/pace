#!/usr/bin/env python3
"""Erzeugt die Regions-Migration für Pace aus dem amtlichen Gemeindeverzeichnis GV100AD (Destatis).

Eingabe ist die Quartalsausgabe des GV100AD (ZIP von Destatis oder die darin enthaltene Datei
``GV100AD_TTMMJJJJ.txt``), Ausgabe ist eine idempotente SQL-Migration (``insert ... on conflict (id) do
update``) für ``public.regions``. Das Skript braucht nur die Python-Standardbibliothek und kein Netzwerk.

Die Eingabedatei gilt als nicht vertrauenswürdig: Sie wird ausschließlich gelesen und geparst, nie entpackt
oder ausgeführt. Skript deshalb immer mit ``python3 -I`` starten.

Beispiel (aus dem Repository-Wurzelverzeichnis)::

    supabase migration new region_data_gv100ad_20260930
    python3 -I supabase/scripts/import_regions.py ~/Downloads/GV100AD3Q.zip \\
        --output supabase/migrations/<timestamp>_region_data_gv100ad_20260930.sql

Satzaufbau laut „Datensatzbeschreibung GV100AD“ (Satzstellen 1-basiert, zeichenbasiert; jeder Satz hat genau
220 Zeichen): Satzart 1–2, Gebietsstand 3–10, Land 11–12, Regierungsbezirk 13, Kreis 14–15, Gemeinde 16–18,
Gemeindeverband 19–22, Bezeichnung 23–72, Textkennzeichen 123–124, Bevölkerung insgesamt 140–150 (Satzart 60).

Aktualisierung (neue Quartalsausgabe): neue Migration mit diesem Skript erzeugen. Regionen, die im neuen
Stand fehlen, werden nicht gelöscht, sondern auf ``is_active = false`` gesetzt, weil Profile auf sie verweisen
können. Details: docs/BACKEND.md.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
import zipfile
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath

RECORD_LENGTH = 220
COUNTRY_ID = "DE"
COUNTRY_NAME = "Deutschland"
BATCH_SIZE = 500
# Schutz vor manipulierten ZIP-Dateien (die echte Datensatzdatei hat ca. 3,5 MB).
MAX_MEMBER_BYTES = 64 * 1024 * 1024

SOURCE_PAGE_TEMPLATE = (
    "https://www.destatis.de/DE/Themen/Laender-Regionen/Regionales/Gemeindeverzeichnis/Administrativ/"
    "Archiv/GV100ADQ/GV100AD{quarter}QAktuell.html"
)
ATTRIBUTION_TEMPLATE = (
    "© Statistisches Bundesamt (Destatis), {year} – im Auftrag der Herausgebergemeinschaft Statistische Ämter "
    "des Bundes und der Länder; Vervielfältigung und Verbreitung, auch auszugsweise, mit Quellenangabe gestattet"
)

KNOWN_RECORD_TYPES = frozenset({"10", "20", "30", "40", "50", "60"})

# Textkennzeichen Satzart 40 (Kreise) → regions.kind
DISTRICT_KINDS = {
    "41": "kreisfreie_stadt",
    "42": "stadtkreis",
    "43": "kreis",
    "44": "landkreis",
    "45": "regionalverband",
}

# Textkennzeichen Satzart 60 (Gemeinden) → regions.kind
MUNICIPALITY_KINDS = {
    "60": "markt",
    "61": "kreisfreie_stadt",
    "62": "stadtkreis",
    "63": "stadt",
    "64": "gemeinde",
    "65": "gemeindefreies_gebiet",  # bewohnt
    "67": "grosse_kreisstadt",
}

# Nicht importiert: unbewohnte gemeindefreie Gebiete (Forste, Seen, …) – dort kann niemand wohnen.
EXCLUDED_MUNICIPALITY_TEXT_CODES = {"66": "gemeindefreies Gebiet, unbewohnt"}


@dataclass(frozen=True)
class NameCorrection:
    """Dokumentierte Korrektur eines amtlichen Namens, der im GV100AD abgeschnitten ist (Feld: 50 Zeichen)."""

    ags: str
    truncated: str
    official_name: str
    reference: str


# Korrekturen aus den „Hinweisen“ zur jeweiligen Ausgabe. Jede Korrektur greift nur, wenn das Feld exakt den
# erwarteten abgeschnittenen Wert enthält. Steht dort schon der korrekte Name, wird nichts geändert. Bei jedem
# anderen Wert (oder wenn die Gemeinde fehlt) bricht der Import ab, damit die Tabelle geprüft wird.
NAME_CORRECTIONS: tuple[NameCorrection, ...] = (
    NameCorrection(
        ags="14625020",  # Bautzen (Sachsen)
        truncated="Bautzen / Budyšin, Stadt, Hochschulstadt / Wysokoš",
        official_name="Bautzen / Budyšin, Stadt, Hochschulstadt / Wysokošulske město",
        reference="Hinweise.txt zum GV100AD: Namensänderung zum 01.07.2025, Gemeindebezeichnung verkürzt",
    ),
)


@dataclass(frozen=True)
class Expectations:
    """Plausibilitätsgrenzen. Abweichungen deuten auf ein falsches oder beschädigtes Eingabeformat hin."""

    states: range = range(16, 17)
    districts: range = range(350, 451)
    municipalities: range = range(10_000, 12_001)


class RegionImportError(Exception):
    """Fehler in den Eingabedaten. Der Import bricht ab; es wird keine Migration geschrieben."""


@dataclass(frozen=True)
class Record:
    line_number: int
    record_type: str
    gebietsstand: str
    land: str
    regierungsbezirk: str
    kreis: str
    gemeinde: str
    name: str
    text_code: str
    population_raw: str

    @property
    def district_key(self) -> str:
        return self.land + self.regierungsbezirk + self.kreis

    @property
    def ags(self) -> str:
        return self.district_key + self.gemeinde


@dataclass
class Region:
    id: str
    level: str
    code: str
    name: str
    official_name: str
    kind: str
    parent_id: str | None
    district_id: str | None
    state_id: str | None
    country_id: str
    population: int | None
    municipality_count: int


@dataclass
class RegionSet:
    gebietsstand: str
    country: Region
    states: list[Region]
    districts: list[Region]
    municipalities: list[Region]
    excluded_municipalities: int
    applied_corrections: list[NameCorrection] = field(default_factory=list)

    def all_regions(self) -> list[Region]:
        """Alle Regionen in Einfügereihenfolge (Eltern vor Kindern)."""
        return [self.country, *self.states, *self.districts, *self.municipalities]

    @property
    def stand(self) -> str:
        """Gebietsstand als TT.MM.JJJJ."""
        return f"{self.gebietsstand[6:8]}.{self.gebietsstand[4:6]}.{self.gebietsstand[0:4]}"

    @property
    def source_label(self) -> str:
        return f"GV100AD Stand {self.stand}"


# --- Parsing ------------------------------------------------------------------------------------------------


def parse_records(text: str) -> list[Record]:
    """Zerlegt den Dateiinhalt in Sätze. Prüft Zeilenlänge (220 Zeichen) und bekannte Satzarten."""
    if text.startswith("﻿"):
        text = text[1:]
    normalized = text.replace("\r\n", "\n")
    if "\r" in normalized:
        raise RegionImportError("Unerwartetes Zeilenende (einzelnes CR) in der Datensatzdatei")
    lines = normalized.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if not lines:
        raise RegionImportError("Datensatzdatei ist leer")

    records: list[Record] = []
    for index, line in enumerate(lines, start=1):
        if len(line) != RECORD_LENGTH:
            raise RegionImportError(f"Zeile {index}: {len(line)} statt {RECORD_LENGTH} Zeichen")
        record_type = line[0:2]
        if record_type not in KNOWN_RECORD_TYPES:
            raise RegionImportError(f"Zeile {index}: unbekannte Satzart {record_type!r}")
        records.append(
            Record(
                line_number=index,
                record_type=record_type,
                gebietsstand=line[2:10],
                land=line[10:12],
                regierungsbezirk=line[12:13],
                kreis=line[13:15],
                gemeinde=line[15:18],
                name=line[22:72].rstrip(),
                text_code=line[122:124],
                population_raw=line[139:150],
            )
        )
    return records


def display_name(official_name: str) -> str:
    """Anzeigename ohne amtlichen Zusatz: Text vor dem ersten Komma.

    ``Pfungstadt, Stadt`` → ``Pfungstadt``; ``Hamburg, Freie und Hansestadt`` → ``Hamburg``;
    ``Regionalverband Saarbrücken`` bleibt unverändert. Getrennt wird am ersten Komma (üblich ist ``", "``;
    einzelne Einträge wie ``Ebstorf,Klosterflecken`` haben kein Leerzeichen nach dem Komma).
    """
    name = official_name.split(",", 1)[0].strip()
    if not name:
        raise RegionImportError(f"Leerer Anzeigename für {official_name!r}")
    return name


def _require_digits(value: str, length: int, what: str, record: Record) -> None:
    if len(value) != length or not value.isdigit():
        raise RegionImportError(f"Zeile {record.line_number}: ungültiger {what} {value!r}")


def _require_blank(value: str, what: str, record: Record) -> None:
    if value.strip():
        raise RegionImportError(f"Zeile {record.line_number}: {what} muss leer sein, ist {value!r}")


def _apply_corrections(
    municipalities: dict[str, Region], corrections: tuple[NameCorrection, ...]
) -> list[NameCorrection]:
    applied: list[NameCorrection] = []
    for correction in corrections:
        region = municipalities.get(f"{COUNTRY_ID}:{correction.ags}")
        if region is None:
            raise RegionImportError(
                f"Korrektur für AGS {correction.ags} passt nicht: Gemeinde fehlt im Stand. "
                "Korrekturtabelle prüfen."
            )
        if region.official_name == correction.official_name:
            continue  # Im Quelldatensatz bereits korrigiert.
        if region.official_name != correction.truncated:
            raise RegionImportError(
                f"Korrektur für AGS {correction.ags} passt nicht: erwartet {correction.truncated!r}, "
                f"gefunden {region.official_name!r}. Korrekturtabelle prüfen."
            )
        region.official_name = correction.official_name
        region.name = display_name(correction.official_name)
        applied.append(correction)
    return applied


def build_regions(
    records: list[Record],
    *,
    expectations: Expectations = Expectations(),
    corrections: tuple[NameCorrection, ...] = NAME_CORRECTIONS,
) -> RegionSet:
    """Baut Land, Bundesländer, Kreise und Gemeinden mit vollständiger Hierarchie und prüft die Konsistenz."""
    stands = {record.gebietsstand for record in records}
    if len(stands) != 1:
        raise RegionImportError(f"Uneinheitlicher Gebietsstand: {sorted(stands)}")
    gebietsstand = stands.pop()
    if not re.fullmatch(r"\d{8}", gebietsstand):
        raise RegionImportError(f"Ungültiger Gebietsstand {gebietsstand!r}")

    states: dict[str, Region] = {}
    districts: dict[str, Region] = {}
    municipalities: dict[str, Region] = {}
    excluded = 0

    def add(target: dict[str, Region], region: Region, record: Record) -> None:
        if any(region.id in existing for existing in (states, districts, municipalities)):
            raise RegionImportError(f"Zeile {record.line_number}: doppelte Region {region.id}")
        target[region.id] = region

    for record in records:
        if record.record_type == "10":
            _require_digits(record.land, 2, "Landesschlüssel", record)
            _require_blank(record.regierungsbezirk + record.kreis + record.gemeinde, "Kreis/Gemeinde", record)
            add(
                states,
                Region(
                    id=f"{COUNTRY_ID}:{record.land}",
                    level="state",
                    code=record.land,
                    name=display_name(record.name),
                    official_name=record.name,
                    kind="state",
                    parent_id=COUNTRY_ID,
                    district_id=None,
                    state_id=None,
                    country_id=COUNTRY_ID,
                    population=None,
                    municipality_count=0,
                ),
                record,
            )
        elif record.record_type == "40":
            _require_digits(record.district_key, 5, "Kreisschlüssel", record)
            _require_blank(record.gemeinde, "Gemeindeschlüssel", record)
            kind = DISTRICT_KINDS.get(record.text_code)
            if kind is None:
                raise RegionImportError(f"Zeile {record.line_number}: unbekanntes Textkennzeichen {record.text_code!r}")
            add(
                districts,
                Region(
                    id=f"{COUNTRY_ID}:{record.district_key}",
                    level="district",
                    code=record.district_key,
                    name=display_name(record.name),
                    official_name=record.name,
                    kind=kind,
                    parent_id=f"{COUNTRY_ID}:{record.land}",
                    district_id=None,
                    state_id=f"{COUNTRY_ID}:{record.land}",
                    country_id=COUNTRY_ID,
                    population=None,
                    municipality_count=0,
                ),
                record,
            )
        elif record.record_type == "60":
            _require_digits(record.ags, 8, "Gemeindeschlüssel", record)
            if record.text_code in EXCLUDED_MUNICIPALITY_TEXT_CODES:
                excluded += 1
                continue
            kind = MUNICIPALITY_KINDS.get(record.text_code)
            if kind is None:
                raise RegionImportError(f"Zeile {record.line_number}: unbekanntes Textkennzeichen {record.text_code!r}")
            _require_digits(record.population_raw, 11, "Bevölkerungswert", record)
            add(
                municipalities,
                Region(
                    id=f"{COUNTRY_ID}:{record.ags}",
                    level="municipality",
                    code=record.ags,
                    name=display_name(record.name),
                    official_name=record.name,
                    kind=kind,
                    parent_id=f"{COUNTRY_ID}:{record.district_key}",
                    district_id=f"{COUNTRY_ID}:{record.district_key}",
                    state_id=f"{COUNTRY_ID}:{record.land}",
                    country_id=COUNTRY_ID,
                    population=int(record.population_raw),
                    municipality_count=1,
                ),
                record,
            )
        # Satzarten 20 (Regierungsbezirk), 30 (Region, nur BW) und 50 (Gemeindeverband) werden nicht benötigt.

    for district in districts.values():
        if district.state_id not in states:
            raise RegionImportError(f"Kreis {district.id}: unbekanntes Land {district.state_id}")
    for municipality in municipalities.values():
        if municipality.district_id not in districts:
            raise RegionImportError(f"Gemeinde {municipality.id}: unbekannter Kreis {municipality.district_id}")
        if municipality.state_id not in states:
            raise RegionImportError(f"Gemeinde {municipality.id}: unbekanntes Land {municipality.state_id}")

    applied = _apply_corrections(municipalities, corrections)

    for municipality in municipalities.values():
        districts[municipality.district_id].municipality_count += 1  # type: ignore[index]
        states[municipality.state_id].municipality_count += 1  # type: ignore[index]
    for district in districts.values():
        if district.municipality_count == 0:
            raise RegionImportError(f"Kreis {district.id} enthält keine Gemeinde")
    for state in states.values():
        if state.municipality_count == 0:
            raise RegionImportError(f"Land {state.id} enthält keine Gemeinde")

    for label, count, allowed in (
        ("Länder", len(states), expectations.states),
        ("Kreise", len(districts), expectations.districts),
        ("Gemeinden", len(municipalities), expectations.municipalities),
    ):
        if count not in allowed:
            raise RegionImportError(f"Unerwartete Anzahl {label}: {count} (erwartet {allowed.start}–{allowed.stop - 1})")

    country = Region(
        id=COUNTRY_ID,
        level="country",
        code=COUNTRY_ID,
        name=COUNTRY_NAME,
        official_name=COUNTRY_NAME,
        kind="country",
        parent_id=None,
        district_id=None,
        state_id=None,
        country_id=COUNTRY_ID,
        population=None,
        municipality_count=len(municipalities),
    )
    return RegionSet(
        gebietsstand=gebietsstand,
        country=country,
        states=sorted(states.values(), key=lambda region: region.code),
        districts=sorted(districts.values(), key=lambda region: region.code),
        municipalities=sorted(municipalities.values(), key=lambda region: region.code),
        excluded_municipalities=excluded,
        applied_corrections=applied,
    )


# --- Eingabe ------------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class LoadedInput:
    input_name: str
    input_sha256: str
    record_file_name: str
    record_sha256: str
    record_text: str
    hinweise_text: str | None


_RECORD_FILE_PATTERN = re.compile(r"GV100AD_(\d{8})\.txt", re.IGNORECASE)


def _read_member(archive: zipfile.ZipFile, name: str) -> bytes:
    info = archive.getinfo(name)
    if info.file_size > MAX_MEMBER_BYTES:
        raise RegionImportError(f"ZIP-Eintrag {name} ist unerwartet groß ({info.file_size} Bytes)")
    data = archive.read(name)
    if len(data) > MAX_MEMBER_BYTES:
        raise RegionImportError(f"ZIP-Eintrag {name} ist unerwartet groß")
    return data


def _decode(data: bytes, what: str) -> str:
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise RegionImportError(f"{what} ist nicht UTF-8-kodiert: {error}") from error


def load_input(path: Path, hinweise_path: Path | None) -> LoadedInput:
    """Liest die Datensatzdatei (direkt oder aus dem ZIP, ohne zu entpacken) und optional die Hinweise."""
    raw = path.read_bytes()
    hinweise_text: str | None = None
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            record_names = [n for n in names if _RECORD_FILE_PATTERN.fullmatch(PurePosixPath(n).name)]
            if len(record_names) != 1:
                raise RegionImportError(f"ZIP muss genau eine Datei GV100AD_TTMMJJJJ.txt enthalten, gefunden: {record_names}")
            record_name = record_names[0]
            record_bytes = _read_member(archive, record_name)
            hinweise_names = [n for n in names if PurePosixPath(n).name.lower() == "hinweise.txt"]
            if len(hinweise_names) == 1 and hinweise_path is None:
                hinweise_text = _decode(_read_member(archive, hinweise_names[0]), "Hinweise.txt")
        record_file_name = PurePosixPath(record_name).name
    else:
        record_bytes = raw
        record_file_name = path.name
        sibling = path.with_name("Hinweise.txt")
        if hinweise_path is None and sibling.is_file():
            hinweise_path = sibling
    if hinweise_path is not None:
        hinweise_text = _decode(hinweise_path.read_bytes(), "Hinweise.txt")
    return LoadedInput(
        input_name=path.name,
        input_sha256=hashlib.sha256(raw).hexdigest(),
        record_file_name=record_file_name,
        record_sha256=hashlib.sha256(record_bytes).hexdigest(),
        record_text=_decode(record_bytes, record_file_name),
        hinweise_text=hinweise_text,
    )


def parse_erscheinungsmonat(hinweise_text: str) -> str | None:
    match = re.search(r"Erscheinungsmonat:\s*([^\W\d_]+ \d{4})", hinweise_text)
    return match.group(1) if match else None


def default_source_url(gebietsstand: str) -> str:
    month = gebietsstand[4:6]
    quarters = {"03": 1, "06": 2, "09": 3}
    if month not in quarters:
        raise RegionImportError(
            f"Für den Gebietsstand {gebietsstand} ist keine Quell-URL bekannt (keine Quartalsausgabe). "
            "Bitte --source-url angeben."
        )
    return SOURCE_PAGE_TEMPLATE.format(quarter=quarters[month])


# --- SQL ----------------------------------------------------------------------------------------------------


def sql_literal(value: str | int | bool | None) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if "\x00" in value:
        raise RegionImportError("NUL-Zeichen in Textwert")
    return "'" + value.replace("'", "''") + "'"


COLUMNS = (
    "id",
    "level",
    "code",
    "name",
    "official_name",
    "kind",
    "parent_id",
    "district_id",
    "state_id",
    "country_id",
    "population",
    "municipality_count",
    "is_active",
    "source",
)


def _row(region: Region, source_label: str) -> str:
    values = (
        region.id,
        region.level,
        region.code,
        region.name,
        region.official_name,
        region.kind,
        region.parent_id,
        region.district_id,
        region.state_id,
        region.country_id,
        region.population,
        region.municipality_count,
        True,
        source_label,
    )
    return "(" + ", ".join(sql_literal(value) for value in values) + ")"


@dataclass(frozen=True)
class Metadata:
    source_url: str
    erscheinungsmonat: str
    attribution: str
    command: str
    input_name: str
    input_sha256: str
    record_file_name: str
    record_sha256: str


def render_sql(regions: RegionSet, metadata: Metadata, batch_size: int = BATCH_SIZE) -> str:
    source = regions.source_label
    rows = regions.all_regions()
    counts = {
        "states": len(regions.states),
        "districts": len(regions.districts),
        "municipalities": len(regions.municipalities),
    }
    lines: list[str] = []
    out = lines.append
    out("-- " + "=" * 110)
    out("-- Pace – Regionsdaten aus dem amtlichen Gemeindeverzeichnis (GV100AD)")
    out("-- GENERIERT mit supabase/scripts/import_regions.py – nicht von Hand bearbeiten.")
    out("--")
    out("-- Quelle:             Statistisches Bundesamt (Destatis), Gemeindeverzeichnis GV100AD (Quartalsausgabe)")
    out(f"--                     {metadata.source_url}")
    out(f"-- Gebietsstand:       {regions.stand}")
    out(f"-- Erscheinungsmonat:  {metadata.erscheinungsmonat}")
    out(f"-- Eingabedatei:       {metadata.input_name}")
    out(f"--   SHA-256:          {metadata.input_sha256}")
    if metadata.record_file_name != metadata.input_name:
        out(f"-- Datensatzdatei:     {metadata.record_file_name}")
        out(f"--   SHA-256:          {metadata.record_sha256}")
    out(f"-- Erzeugt mit:        {metadata.command}")
    out("--")
    out(f"-- Quellenvermerk:     {metadata.attribution}")
    out("--")
    out(
        f"-- Inhalt: 1 Staat, {counts['states']} Länder, {counts['districts']} Kreise, "
        f"{counts['municipalities']} Gemeinden."
    )
    out(
        f"-- Nicht importiert: {regions.excluded_municipalities} gemeindefreie Gebiete, unbewohnt (Textkennzeichen 66)."
    )
    if regions.applied_corrections:
        out("-- Korrekturen (siehe NAME_CORRECTIONS im Skript):")
        for correction in regions.applied_corrections:
            out(f"--   AGS {correction.ags}: {correction.official_name!s} ({correction.reference})")
    out("--")
    out("-- Idempotent: Upsert über die feste ID. Regionen, die in diesem Stand fehlen, werden deaktiviert")
    out("-- (is_active = false), nicht gelöscht – Profile können auf sie verweisen.")
    out("-- " + "=" * 110)
    out("")

    column_list = ", ".join(COLUMNS)
    update_list = ",\n  ".join(f"{column} = excluded.{column}" for column in COLUMNS if column != "id")
    for start in range(0, len(rows), batch_size):
        batch = rows[start : start + batch_size]
        out(f"insert into public.regions ({column_list})")
        out("values")
        out(",\n".join("  " + _row(region, source) for region in batch))
        out("on conflict (id) do update set")
        out("  " + update_list + ";")
        out("")

    out("-- Regionen früherer Stände, die in diesem Stand nicht mehr vorkommen.")
    out("update public.regions")
    out("   set is_active = false")
    out(f" where country_id = {sql_literal(COUNTRY_ID)}")
    out("   and is_active")
    out(f"   and source <> {sql_literal(source)};")
    out("")
    out("-- Gemeindezahlen aus den aktiven Gemeinden neu berechnen (berücksichtigt auch deaktivierte Regionen).")
    out(f"select private.refresh_region_municipality_counts({sql_literal(COUNTRY_ID)});")
    out("")
    out("-- Plausibilitätsprüfung: bricht die Migration ab, wenn der Datenbestand nicht zum Import passt.")
    out("do $$")
    out("declare")
    out("  v_states integer;")
    out("  v_districts integer;")
    out("  v_municipalities integer;")
    out("  v_country_count integer;")
    out("begin")
    out("  select count(*) filter (where level = 'state'),")
    out("         count(*) filter (where level = 'district'),")
    out("         count(*) filter (where level = 'municipality')")
    out("    into v_states, v_districts, v_municipalities")
    out("    from public.regions")
    out(f"   where country_id = {sql_literal(COUNTRY_ID)} and is_active;")
    out(f"  select municipality_count into v_country_count from public.regions where id = {sql_literal(COUNTRY_ID)};")
    out(
        f"  if v_states <> {counts['states']} or v_districts <> {counts['districts']}"
        f" or v_municipalities <> {counts['municipalities']}"
        f" or v_country_count <> {counts['municipalities']} then"
    )
    out("    raise exception 'GV100AD-Import inkonsistent: % Länder, % Kreise, % Gemeinden, Gemeindezahl DE %',")
    out("      v_states, v_districts, v_municipalities, v_country_count;")
    out("  end if;")
    out("end")
    out("$$;")
    out("")
    return "\n".join(lines)


# --- CLI ----------------------------------------------------------------------------------------------------


def _portable_output_path(output: Path) -> str:
    parts = output.resolve().parts
    if len(parts) >= 3 and parts[-3] == "supabase" and parts[-2] == "migrations":
        return f"supabase/migrations/{parts[-1]}"
    return output.name


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Erzeugt die Regions-Migration (public.regions) aus dem GV100AD von Destatis."
    )
    parser.add_argument("input", type=Path, help="GV100AD-ZIP oder GV100AD_TTMMJJJJ.txt")
    parser.add_argument("--output", type=Path, help="Ziel-SQL-Datei (Standard: stdout)")
    parser.add_argument("--hinweise", type=Path, help="Hinweise.txt (Standard: aus dem ZIP bzw. daneben)")
    parser.add_argument("--erscheinungsmonat", help="z. B. 'August 2026' (Standard: aus Hinweise.txt)")
    parser.add_argument("--source-url", help="Quellseite bei Destatis (Standard: aus dem Gebietsstand abgeleitet)")
    args = parser.parse_args(argv)

    try:
        loaded = load_input(args.input, args.hinweise)
        records = parse_records(loaded.record_text)
        regions = build_regions(records)

        file_match = _RECORD_FILE_PATTERN.fullmatch(loaded.record_file_name)
        if file_match:
            day_month_year = file_match.group(1)
            file_stand = day_month_year[4:8] + day_month_year[2:4] + day_month_year[0:2]
            if file_stand != regions.gebietsstand:
                raise RegionImportError(
                    f"Dateiname {loaded.record_file_name} passt nicht zum Gebietsstand {regions.gebietsstand}"
                )

        erscheinungsmonat = args.erscheinungsmonat or (
            parse_erscheinungsmonat(loaded.hinweise_text) if loaded.hinweise_text else None
        )
        if not erscheinungsmonat:
            raise RegionImportError("Erscheinungsmonat nicht gefunden – bitte Hinweise.txt oder --erscheinungsmonat angeben")
        source_url = args.source_url or default_source_url(regions.gebietsstand)

        command = ["python3 -I supabase/scripts/import_regions.py", args.input.name]
        if args.hinweise:
            command += ["--hinweise", args.hinweise.name]
        if args.erscheinungsmonat:
            command += ["--erscheinungsmonat", f"'{args.erscheinungsmonat}'"]
        if args.source_url:
            command += ["--source-url", args.source_url]
        if args.output:
            command += ["--output", _portable_output_path(args.output)]

        metadata = Metadata(
            source_url=source_url,
            erscheinungsmonat=erscheinungsmonat,
            attribution=ATTRIBUTION_TEMPLATE.format(year=erscheinungsmonat.split()[-1]),
            command=" ".join(command),
            input_name=loaded.input_name,
            input_sha256=loaded.input_sha256,
            record_file_name=loaded.record_file_name,
            record_sha256=loaded.record_sha256,
        )
        sql = render_sql(regions, metadata)
    except (RegionImportError, OSError, zipfile.BadZipFile) as error:
        print(f"Fehler: {error}", file=sys.stderr)
        return 1

    if args.output:
        args.output.write_text(sql, encoding="utf-8", newline="\n")
    else:
        sys.stdout.write(sql)

    print(
        f"{regions.source_label}: 1 Staat, {len(regions.states)} Länder, {len(regions.districts)} Kreise, "
        f"{len(regions.municipalities)} Gemeinden (ausgeschlossen: {regions.excluded_municipalities} unbewohnte "
        f"gemeindefreie Gebiete), Korrekturen: {len(regions.applied_corrections)}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
