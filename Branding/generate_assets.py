#!/usr/bin/env python3
"""Erzeugt die Marken-Assets von Pace aus der Wortmarke (Branding/source/pace-wordmark.jpg).

Ausgabe (wird überschrieben):
- DesignSystem: einfärbbare Wortmarke (Template-Bild, nur Alpha) für die App-Oberfläche
- App-Target: App-Icon (hell, dunkel, getönt), Startbildschirm-Logo (hell/dunkel)

Benötigt Pillow. Aufruf aus dem Repository-Wurzelverzeichnis:
    python3 -I Branding/generate_assets.py
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Branding/source/pace-wordmark.jpg"
DESIGN_ASSETS = ROOT / "Packages/PaceKit/Sources/DesignSystem/Resources/DesignSystem.xcassets"
APP_ASSETS = ROOT / "Pace/Resources/Assets.xcassets"

BRAND_LIGHT = (7, 45, 32)        # Farbe der Wortmarke (#072D20)
BRAND_DARK = (201, 247, 218)     # Mint für den Dark Mode (#C9F7DA)
ICON_GREEN_TOP = (16, 84, 56)    # #105438
ICON_GREEN_BOTTOM = (6, 46, 31)  # #062E1F
ICON_MINT = (196, 247, 214)      # #C4F7D6
DARK_BACKGROUND = (14, 22, 24)   # #0E1618


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


def letter_p(mask: Image.Image) -> Image.Image:
    """Der erste Buchstabe („p“) der Wortmarke – Spalten bis zur ersten Lücke."""
    columns = [mask.crop((x, 0, x + 1, mask.height)).getextrema()[1] for x in range(mask.width)]
    start = next(x for x, value in enumerate(columns) if value > 128)
    end = next(x for x in range(start, mask.width) if columns[x] < 20)
    letter = mask.crop((start, 0, end, mask.height))
    return letter.crop(letter.point(lambda a: 255 if a > 20 else 0).getbbox())


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    gradient = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        gradient.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return gradient.resize((size, size))


def icon(letter: Image.Image, background: Image.Image | None, color: tuple[int, int, int]) -> Image.Image:
    size = 1024
    glyph_height = 560
    glyph = letter.resize((round(letter.width * glyph_height / letter.height), glyph_height), Image.LANCZOS)
    canvas = background.convert("RGBA") if background else Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # Optisch zentriert: der Bauch des „p“ sitzt in der Mitte, die Unterlänge ragt nach unten.
    x = (size - glyph.width) // 2 + 14
    y = (size - glyph_height) // 2 + 62
    canvas.alpha_composite(colored(glyph, color), (x, y))
    return canvas


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

    # App-Icon: das „p“ der Wortmarke in Mint auf tiefem Grün.
    letter = letter_p(mask)
    icon_dir = APP_ASSETS / "AppIcon.appiconset"
    for old in icon_dir.glob("*.png"):
        old.unlink()
    icon(letter, vertical_gradient(1024, ICON_GREEN_TOP, ICON_GREEN_BOTTOM), ICON_MINT).convert("RGB").save(icon_dir / "AppIcon.png")
    icon(letter, None, ICON_MINT).save(icon_dir / "AppIcon-Dark.png")
    tinted = Image.new("RGB", (1024, 1024), (0, 0, 0))
    tinted.paste(icon(letter, None, (255, 255, 255)), (0, 0), icon(letter, None, (255, 255, 255)))
    tinted.convert("L").save(icon_dir / "AppIcon-Tinted.png")
    write_json(icon_dir / "Contents.json", {
        "images": [
            {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "AppIcon-Dark.png",
             "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "AppIcon-Tinted.png",
             "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    })
    print("Assets erzeugt.")


if __name__ == "__main__":
    main()
