#!/usr/bin/env python3
"""Erzeugt die Marken-Assets von Pace aus der Wortmarke (Branding/source/pace-wordmark.jpg).

Ausgabe (wird überschrieben):
- DesignSystem: einfärbbare Wortmarke (Template-Bild, nur Alpha) für die App-Oberfläche
- DesignSystem: Vorschaubilder der App-Icons für die Icon-Auswahl im Profil
- App-Target: App-Icons aus der Original-Wortmarke (automatisch/hell/dunkel/getönt), Startbildschirm-Logo

Benötigt Pillow. Aufruf aus dem Repository-Wurzelverzeichnis:
    python3 -I Branding/generate_assets.py
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Branding/source/pace-wordmark.jpg"
DESIGN_ASSETS = ROOT / "Packages/PaceKit/Sources/DesignSystem/Resources/DesignSystem.xcassets"
APP_ASSETS = ROOT / "Pace/Resources/Assets.xcassets"

BRAND_LIGHT = (7, 45, 32)        # Farbe der Wortmarke (#072D20)
BRAND_DARK = (201, 247, 218)     # Mint für den Dark Mode (#C9F7DA)
LIGHT_BACKGROUND = (253, 253, 249)  # Hintergrund des Original-Logos (#FDFDF9)
DARK_BACKGROUND = (14, 22, 24)      # Dark-Mode-Hintergrund der App (#0E1618)
# Lage der Wortmarke im App-Icon, abgeleitet aus dem Original-Logo (Breite ≈ 81 %, Mitte bei ≈ 51 % der Höhe),
# mit etwas mehr Rand, damit die abgerundete Icon-Maske nichts anschneidet.
WORDMARK_ICON_WIDTH = 0.78
WORDMARK_ICON_CENTER_Y = 0.51


def glyph_mask() -> Image.Image:
    """Alphamaske der Wortmarke aus der Helligkeit (Kanten bleiben weich), auf die Glyphen zugeschnitten."""
    gray = Image.open(SOURCE).convert("L")
    background, glyph = 252, 37
    mask = gray.point(lambda v: max(0, min(255, round((background - v) * 255 / (background - glyph)))))
    mask = mask.point(lambda a: 0 if a < 12 else a)
    box = mask.point(lambda a: 255 if a > 128 else 0).getbbox()
    pad = 6
    return mask.crop((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad))


def colored(mask: Image.Image, color: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGBA", mask.size, color + (0,))
    image.putalpha(mask)
    return image


def scaled(image: Image.Image, width: int) -> Image.Image:
    height = round(image.height * width / image.width)
    return image.resize((width, height), Image.LANCZOS)


def write_json(path: Path, content: dict) -> None:
    path.write_text(json.dumps(content, indent=2) + "\n")


def write_imageset(directory: Path, base_width: int, variants: dict[str, Image.Image], template: bool) -> None:
    """`variants`: "any" und optional "dark" → Bild in voller Auflösung. Erzeugt @1x, @2x, @3x."""
    directory.mkdir(parents=True, exist_ok=True)
    for old in directory.glob("*.png"):
        old.unlink()
    images = []
    for appearance, image in variants.items():
        for scale in (1, 2, 3):
            name = f"{directory.stem}{'-dark' if appearance == 'dark' else ''}@{scale}x.png"
            scaled(image, base_width * scale).save(directory / name)
            entry = {"filename": name, "idiom": "universal", "scale": f"{scale}x"}
            if appearance == "dark":
                entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
            images.append(entry)
    content: dict = {"images": images, "info": {"author": "xcode", "version": 1}}
    if template:
        content["properties"] = {"template-rendering-intent": "template"}
    write_json(directory / "Contents.json", content)


def wordmark_icon(mask: Image.Image, background: tuple[int, int, int] | None, color: tuple[int, int, int]) -> Image.Image:
    """App-Icon: die komplette Original-Wortmarke, unverändert in Form und Proportionen, wie im Original-Logo
    horizontal zentriert und leicht unterhalb der Mitte. Nur Hintergrund- und Schriftfarbe variieren."""
    size = 1024
    glyph = scaled(mask, round(size * WORDMARK_ICON_WIDTH))
    canvas = Image.new("RGBA", (size, size), (background + (255,)) if background else (0, 0, 0, 0))
    x = (size - glyph.width) // 2
    y = round(size * WORDMARK_ICON_CENTER_Y - glyph.height / 2)
    canvas.alpha_composite(colored(glyph, color), (x, y))
    return canvas


def write_app_icon(directory: Path, variants: dict[str, Image.Image]) -> None:
    """`variants`: "any" sowie optional "dark" und "tinted" → 1024×1024-Bild (Single Size, ab Xcode 14)."""
    directory.mkdir(parents=True, exist_ok=True)
    for old in directory.glob("*.png"):
        old.unlink()
    images = []
    for appearance, image in variants.items():
        suffix = "" if appearance == "any" else f"-{appearance.capitalize()}"
        name = f"{directory.stem}{suffix}.png"
        if appearance == "tinted":
            image.convert("L").save(directory / name)
        else:
            image.convert("RGB").save(directory / name)
        entry: dict = {"filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance != "any":
            entry = {"appearances": [{"appearance": "luminosity", "value": appearance}], **entry}
        images.append(entry)
    write_json(directory / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})


def main() -> None:
    mask = glyph_mask()

    # Wortmarke für die App (Template: Farbe kommt aus dem Design-System).
    write_imageset(DESIGN_ASSETS / "PaceWordmark.imageset", 120, {"any": colored(mask, (255, 255, 255))}, template=True)
    write_json(DESIGN_ASSETS / "Contents.json", {"info": {"author": "xcode", "version": 1}})

    # Startbildschirm.
    write_imageset(
        APP_ASSETS / "LaunchLogo.imageset",
        150,
        {"any": colored(mask, BRAND_LIGHT), "dark": colored(mask, BRAND_DARK)},
        template=False,
    )

    # App-Icons aus der Original-Wortmarke: hell (Original), dunkel (gleiche Wortmarke in Mint auf dunklem Grund),
    # getönt (Graustufen für iOS 18). „AppIcon“ folgt dem Erscheinungsbild des Systems (Einstellung „Automatisch“),
    # „AppIconLight“ und „AppIconDark“ sind die alternativen Icons für „Hell“ und „Dunkel“.
    light = wordmark_icon(mask, LIGHT_BACKGROUND, BRAND_LIGHT)
    dark = wordmark_icon(mask, DARK_BACKGROUND, BRAND_DARK)
    tinted = wordmark_icon(mask, (0, 0, 0), (255, 255, 255))
    write_app_icon(APP_ASSETS / "AppIcon.appiconset", {"any": light, "dark": dark, "tinted": tinted})
    write_app_icon(APP_ASSETS / "AppIconLight.appiconset", {"any": light})
    write_app_icon(APP_ASSETS / "AppIconDark.appiconset", {"any": dark})

    # Vorschauen für die Icon-Auswahl im Profil (App-Icons selbst sind zur Laufzeit nicht als Bild ladbar).
    write_imageset(DESIGN_ASSETS / "AppIconPreviewLight.imageset", 64, {"any": light}, template=False)
    write_imageset(DESIGN_ASSETS / "AppIconPreviewDark.imageset", 64, {"any": dark}, template=False)

    print("Assets erzeugt.")


if __name__ == "__main__":
    main()
