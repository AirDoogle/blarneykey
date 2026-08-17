#!/usr/bin/env python3
"""Build the app icon from the mark.

macOS icons are not full-bleed squares. They sit as a rounded "squircle" inside a
transparent canvas with a margin, and an icon that ignores that reads as a sticker
pasted on the Dock. This composites the mark onto a correctly proportioned plate and
writes the iconset that `iconutil` turns into BlarneyKey.icns.

    python3 assets/make-icon.py

Light and dark plates are both written. macOS uses the light one for the app icon; the
dark plate is for README screenshots and anywhere the icon sits on a dark surface.
"""
from pathlib import Path
from PIL import Image, ImageDraw

ASSETS = Path(__file__).parent
MARK = ASSETS / "blarneykey-mark.png"

# Apple's proportions for a macOS app icon: the plate is 824 of a 1024 canvas, with a
# corner radius of 185. Everything else scales from that.
CANVAS = 1024
PLATE = 824
RADIUS = 185
# The mark sits inside the plate with its own breathing room.
MARK_FRACTION = 0.66

PLATES = {
    "icon-light.png": ((255, 255, 255, 255), None),
    # On a dark plate Action Blue is too close to the background, so the mark switches to
    # Sky Link Blue, exactly as the design system requires for accents on dark tiles.
    "icon-dark.png": ((28, 28, 30, 255), (41, 151, 255)),
}


def rounded_plate(fill: tuple) -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    inset = (CANVAS - PLATE) // 2
    draw.rounded_rectangle(
        [inset, inset, inset + PLATE, inset + PLATE], radius=RADIUS, fill=fill
    )
    return canvas


def recolour(mark: Image.Image, rgb: tuple) -> Image.Image:
    tinted = Image.new("RGBA", mark.size, rgb + (0,))
    tinted.putalpha(mark.getchannel("A"))
    return tinted


def build(name: str, fill: tuple, tint: tuple | None) -> Image.Image:
    plate = rounded_plate(fill)
    mark = Image.open(MARK).convert("RGBA")
    if tint:
        mark = recolour(mark, tint)

    side = int(PLATE * MARK_FRACTION)
    mark = mark.resize((side, side), Image.LANCZOS)
    offset = ((CANVAS - side) // 2, (CANVAS - side) // 2)
    plate.paste(mark, offset, mark)
    plate.save(ASSETS / name)
    print(f"wrote {name}")
    return plate


def write_iconset(icon: Image.Image) -> None:
    """The ten sizes iconutil expects, at both scales."""
    iconset = ASSETS / "BlarneyKey.iconset"
    iconset.mkdir(exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(iconset / f"icon_{size}x{size}.png")
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(
            iconset / f"icon_{size}x{size}@2x.png"
        )
    print(f"wrote {iconset.name} (10 files)")


if __name__ == "__main__":
    light = None
    for name, (fill, tint) in PLATES.items():
        image = build(name, fill, tint)
        if name == "icon-light.png":
            light = image
    write_iconset(light)
