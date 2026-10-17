"""Tests für import_regions.py mit synthetischen GV100AD-Sätzen.

Ausführen (aus dem Repository-Wurzelverzeichnis)::

    python3 -I -m unittest discover -s supabase/scripts -p 'test_*.py'
"""

from __future__ import annotations

import io
import sys
import tempfile
import unittest
import zipfile
from contextlib import redirect_stderr
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import import_regions as importer  # noqa: E402

STAND = "20260930"
RELAXED = importer.Expectations(states=range(1, 20), districts=range(1, 500), municipalities=range(1, 20_000))


def record(
    satzart: str,
    key: str,
    name: str,
    text_code: str = "  ",
    population: int | None = None,
    stand: str = STAND,
) -> str:
    """Baut einen 220 Zeichen langen Satz. `key` ist der Regionalschlüssel ohne Leerstellen (2, 5 oder 8 Stellen)."""
    chars = [" "] * importer.RECORD_LENGTH

    def put(start: int, value: str) -> None:  # start ist 1-basiert wie in der Datensatzbeschreibung
        chars[start - 1 : start - 1 + len(value)] = list(value)

    put(1, satzart)
    put(3, stand)
    put(11, key)
    if satzart == "60":
        put(19, "0000")
    put(23, name[:50])
    put(123, text_code)
    if population is not None:
        put(140, f"{population:011d}")
    line = "".join(chars)
    assert len(line) == importer.RECORD_LENGTH
    return line


def sample_lines() -> list[str]:
    return [
        record("10", "06", "Hessen"),
        record("20", "064", "Darmstadt"),
        record("40", "06411", "Darmstadt, Wissenschaftsstadt", "41"),
        record("60", "06411000", "Darmstadt, Wissenschaftsstadt", "61", 168253),
        record("40", "06432", "Darmstadt-Dieburg", "44"),
        record("50", "06432", "Verband", "50"),
        record("60", "06432008", "Griesheim, Stadt", "63", 29385),
        record("60", "06432018", "Pfungstadt, Stadt", "63", 25475),
        record("60", "06432099", "Gemeindefreies Waldgebiet, gemfr. Gebiet", "66", 0),
        record("10", "11", "Berlin"),
        record("40", "11000", "Berlin, Stadt", "41"),
        record("60", "11000000", "Berlin, Stadt", "61", 3700577),
    ]


def build(lines: list[str], corrections: tuple[importer.NameCorrection, ...] = ()) -> importer.RegionSet:
    text = "﻿" + "\r\n".join(lines) + "\r\n"
    return importer.build_regions(importer.parse_records(text), expectations=RELAXED, corrections=corrections)


class DisplayNameTests(unittest.TestCase):
    def test_strips_official_suffix(self) -> None:
        self.assertEqual(importer.display_name("Pfungstadt, Stadt"), "Pfungstadt")
        self.assertEqual(importer.display_name("Frankfurt am Main, Stadt"), "Frankfurt am Main")
        self.assertEqual(importer.display_name("Hamburg, Freie und Hansestadt"), "Hamburg")
        self.assertEqual(
            importer.display_name("Bautzen / Budyšin, Stadt, Hochschulstadt / Wysokošulske město"),
            "Bautzen / Budyšin",
        )

    def test_keeps_names_without_suffix(self) -> None:
        self.assertEqual(importer.display_name("Regionalverband Saarbrücken"), "Regionalverband Saarbrücken")
        self.assertEqual(importer.display_name("Münster (Hessen)"), "Münster (Hessen)")

    def test_comma_without_space(self) -> None:
        self.assertEqual(importer.display_name("Ebstorf,Klosterflecken"), "Ebstorf")


class ParserTests(unittest.TestCase):
    def test_builds_hierarchy_and_ids(self) -> None:
        regions = build(sample_lines())
        self.assertEqual(regions.gebietsstand, STAND)
        self.assertEqual(regions.source_label, "GV100AD Stand 30.09.2026")
        self.assertEqual([state.id for state in regions.states], ["DE:06", "DE:11"])
        self.assertEqual([district.id for district in regions.districts], ["DE:06411", "DE:06432", "DE:11000"])

        by_id = {region.id: region for region in regions.all_regions()}
        pfungstadt = by_id["DE:06432018"]
        self.assertEqual(pfungstadt.level, "municipality")
        self.assertEqual(pfungstadt.code, "06432018")
        self.assertEqual(pfungstadt.name, "Pfungstadt")
        self.assertEqual(pfungstadt.official_name, "Pfungstadt, Stadt")
        self.assertEqual(pfungstadt.kind, "stadt")
        self.assertEqual(pfungstadt.parent_id, "DE:06432")
        self.assertEqual(pfungstadt.district_id, "DE:06432")
        self.assertEqual(pfungstadt.state_id, "DE:06")
        self.assertEqual(pfungstadt.country_id, "DE")
        self.assertEqual(pfungstadt.population, 25475)
        self.assertEqual(pfungstadt.municipality_count, 1)

        district = by_id["DE:06432"]
        self.assertEqual((district.level, district.kind, district.parent_id), ("district", "landkreis", "DE:06"))
        self.assertEqual((district.state_id, district.district_id, district.population), ("DE:06", None, None))
        self.assertEqual(district.municipality_count, 2)  # ohne unbewohntes gemeindefreies Gebiet

        darmstadt = by_id["DE:06411"]
        self.assertEqual((darmstadt.name, darmstadt.kind, darmstadt.municipality_count), ("Darmstadt", "kreisfreie_stadt", 1))

        hessen = by_id["DE:06"]
        self.assertEqual((hessen.level, hessen.kind, hessen.parent_id, hessen.state_id), ("state", "state", "DE", None))
        self.assertEqual(hessen.municipality_count, 3)

        country = by_id["DE"]
        self.assertEqual((country.level, country.parent_id, country.country_id), ("country", None, "DE"))
        self.assertEqual(country.municipality_count, 4)

    def test_excludes_uninhabited_unincorporated_areas(self) -> None:
        regions = build(sample_lines())
        ids = {region.id for region in regions.municipalities}
        self.assertNotIn("DE:06432099", ids)
        self.assertEqual(regions.excluded_municipalities, 1)

    def test_inhabited_unincorporated_area_is_imported(self) -> None:
        lines = sample_lines() + [record("60", "06432098", "Testbezirk, gemfr. Bezirk", "65", 812)]
        regions = build(lines)
        area = next(region for region in regions.municipalities if region.id == "DE:06432098")
        self.assertEqual((area.kind, area.name, area.population), ("gemeindefreies_gebiet", "Testbezirk", 812))

    def test_kind_mapping(self) -> None:
        lines = sample_lines() + [
            record("60", "06432001", "Markt A, M", "60", 1),
            record("60", "06432002", "Gemeinde B", "64", 2),
            record("60", "06432003", "Stadt C, GKSt", "67", 3),
        ]
        kinds = {region.code: region.kind for region in build(lines).municipalities}
        self.assertEqual(kinds["06432001"], "markt")
        self.assertEqual(kinds["06432002"], "gemeinde")
        self.assertEqual(kinds["06432003"], "grosse_kreisstadt")

    def test_accepts_lf_line_endings_without_bom(self) -> None:
        records = importer.parse_records("\n".join(sample_lines()) + "\n")
        self.assertEqual(len(records), len(sample_lines()))

    def test_rejects_wrong_record_width(self) -> None:
        lines = sample_lines()
        lines[3] = lines[3][:-1]
        with self.assertRaisesRegex(importer.RegionImportError, "Zeile 4: 219 statt 220"):
            build(lines)

    def test_rejects_unknown_record_type(self) -> None:
        lines = sample_lines() + ["99" + " " * 218]
        with self.assertRaisesRegex(importer.RegionImportError, "unbekannte Satzart"):
            build(lines)

    def test_rejects_municipality_with_unknown_district(self) -> None:
        lines = sample_lines() + [record("60", "06433001", "Irgendwo", "64", 100)]
        with self.assertRaisesRegex(importer.RegionImportError, "unbekannter Kreis DE:06433"):
            build(lines)

    def test_rejects_district_with_unknown_state(self) -> None:
        lines = sample_lines() + [record("40", "07111", "Koblenz", "41"), record("60", "07111000", "Koblenz", "61", 1)]
        with self.assertRaisesRegex(importer.RegionImportError, "unbekanntes Land DE:07"):
            build(lines)

    def test_rejects_duplicate_ids(self) -> None:
        lines = sample_lines() + [record("60", "06432018", "Pfungstadt, Stadt", "63", 1)]
        with self.assertRaisesRegex(importer.RegionImportError, "doppelte Region DE:06432018"):
            build(lines)

    def test_rejects_mixed_gebietsstand(self) -> None:
        lines = sample_lines() + [record("60", "06432001", "Alt", "64", 1, stand="20260630")]
        with self.assertRaisesRegex(importer.RegionImportError, "Uneinheitlicher Gebietsstand"):
            build(lines)

    def test_rejects_unknown_text_code(self) -> None:
        lines = sample_lines() + [record("60", "06432001", "Neu", "69", 1)]
        with self.assertRaisesRegex(importer.RegionImportError, "unbekanntes Textkennzeichen"):
            build(lines)

    def test_rejects_non_numeric_population(self) -> None:
        lines = sample_lines()
        lines[7] = lines[7][:139] + "0000000abcd" + lines[7][150:]
        with self.assertRaisesRegex(importer.RegionImportError, "Bevölkerungswert"):
            build(lines)

    def test_rejects_unexpected_counts(self) -> None:
        text = "\r\n".join(sample_lines())
        with self.assertRaisesRegex(importer.RegionImportError, "Unerwartete Anzahl Länder: 2"):
            importer.build_regions(importer.parse_records(text), corrections=())


class CorrectionTests(unittest.TestCase):
    correction = importer.NameCorrection(
        ags="06432018",
        truncated="Pfungstadt, Sta",
        official_name="Pfungstadt, Stadt der Tests",
        reference="Test",
    )

    def test_applies_documented_correction(self) -> None:
        lines = sample_lines()
        lines[7] = record("60", "06432018", "Pfungstadt, Sta", "63", 25475)
        regions = build(lines, corrections=(self.correction,))
        pfungstadt = next(region for region in regions.municipalities if region.code == "06432018")
        self.assertEqual(pfungstadt.official_name, "Pfungstadt, Stadt der Tests")
        self.assertEqual(pfungstadt.name, "Pfungstadt")
        self.assertEqual(regions.applied_corrections, [self.correction])

    def test_skips_correction_when_source_is_already_correct(self) -> None:
        lines = sample_lines()
        lines[7] = record("60", "06432018", "Pfungstadt, Stadt der Tests", "63", 25475)
        regions = build(lines, corrections=(self.correction,))
        self.assertEqual(regions.applied_corrections, [])

    def test_fails_when_correction_no_longer_matches(self) -> None:
        with self.assertRaisesRegex(importer.RegionImportError, "Korrektur für AGS 06432018 passt nicht"):
            build(sample_lines(), corrections=(self.correction,))

    def test_bautzen_correction_is_registered(self) -> None:
        bautzen = next(c for c in importer.NAME_CORRECTIONS if c.ags == "14625020")
        self.assertTrue(bautzen.official_name.startswith(bautzen.truncated))
        self.assertEqual(len(bautzen.truncated), 50)
        self.assertEqual(bautzen.official_name, "Bautzen / Budyšin, Stadt, Hochschulstadt / Wysokošulske město")


class SqlTests(unittest.TestCase):
    def metadata(self) -> importer.Metadata:
        return importer.Metadata(
            source_url="https://example.invalid/quelle",
            erscheinungsmonat="August 2026",
            attribution=importer.ATTRIBUTION_TEMPLATE.format(year="2026"),
            command="python3 -I supabase/scripts/import_regions.py test.txt",
            input_name="test.zip",
            input_sha256="a" * 64,
            record_file_name="GV100AD_30092026.txt",
            record_sha256="b" * 64,
        )

    def test_renders_idempotent_upsert_in_batches(self) -> None:
        lines = sample_lines() + [record("60", "06432030", "O'Testdorf", "64", 7)]
        sql = importer.render_sql(build(lines), self.metadata(), batch_size=3)
        self.assertEqual(sql.count("insert into public.regions"), 4)  # 11 Regionen in Blöcken zu 3
        self.assertEqual(sql.count("on conflict (id) do update set"), 4)
        self.assertIn("'O''Testdorf'", sql)
        self.assertIn("('DE', 'country', 'DE', 'Deutschland', 'Deutschland', 'country', null, null, null, 'DE', null, 5, true, 'GV100AD Stand 30.09.2026')", sql)
        self.assertIn("'DE:06432018', 'municipality', '06432018', 'Pfungstadt', 'Pfungstadt, Stadt', 'stadt', 'DE:06432', 'DE:06432', 'DE:06', 'DE', 25475, 1, true", sql)
        self.assertIn("source <> 'GV100AD Stand 30.09.2026'", sql)
        self.assertIn("select private.refresh_region_municipality_counts('DE');", sql)
        self.assertIn("Gebietsstand:       30.09.2026", sql)
        self.assertIn("Erscheinungsmonat:  August 2026", sql)
        self.assertIn("SHA-256:          " + "a" * 64, sql)
        self.assertIn("© Statistisches Bundesamt (Destatis), 2026 – im Auftrag der Herausgebergemeinschaft", sql)
        self.assertNotIn("begin;", sql.lower())

    def test_parents_are_inserted_before_children(self) -> None:
        sql = importer.render_sql(build(sample_lines()), self.metadata())
        self.assertLess(sql.index("('DE', "), sql.index("('DE:06', "))
        self.assertLess(sql.index("('DE:06', "), sql.index("('DE:06432', "))
        self.assertLess(sql.index("('DE:06432', "), sql.index("('DE:06432018', "))

    def test_sql_literal(self) -> None:
        self.assertEqual(importer.sql_literal(None), "null")
        self.assertEqual(importer.sql_literal(True), "true")
        self.assertEqual(importer.sql_literal(42), "42")
        self.assertEqual(importer.sql_literal("a'b"), "'a''b'")
        with self.assertRaises(importer.RegionImportError):
            importer.sql_literal("a\x00b")


class CommandLineTests(unittest.TestCase):
    def test_reads_zip_with_hinweise(self) -> None:
        hinweise = "﻿Erscheinungsmonat: August 2026\r\n"
        content = ("﻿" + "\r\n".join(sample_lines()) + "\r\n").encode("utf-8")
        with tempfile.TemporaryDirectory() as directory:
            archive_path = Path(directory) / "GV100AD3Q.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("GV100AD_30092026.txt", content)
                archive.writestr("Hinweise.txt", hinweise.encode("utf-8"))
            loaded = importer.load_input(archive_path, None)
            self.assertEqual(loaded.record_file_name, "GV100AD_30092026.txt")
            self.assertEqual(importer.parse_erscheinungsmonat(loaded.hinweise_text or ""), "August 2026")
            self.assertEqual(len(importer.parse_records(loaded.record_text)), len(sample_lines()))

    def test_main_fails_loudly_on_bad_input(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "GV100AD_30092026.txt"
            path.write_text("kaputt\r\n", encoding="utf-8")
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = importer.main([str(path), "--erscheinungsmonat", "August 2026"])
            self.assertEqual(code, 1)
            self.assertIn("Fehler: Zeile 1", stderr.getvalue())
            self.assertFalse((Path(directory) / "out.sql").exists())

    def test_default_source_url(self) -> None:
        self.assertEqual(
            importer.default_source_url("20260930"),
            "https://www.destatis.de/DE/Themen/Laender-Regionen/Regionales/Gemeindeverzeichnis/Administrativ/"
            "Archiv/GV100ADQ/GV100AD3QAktuell.html",
        )
        with self.assertRaises(importer.RegionImportError):
            importer.default_source_url("20261231")


if __name__ == "__main__":
    unittest.main()
