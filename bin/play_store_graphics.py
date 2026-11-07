#!/usr/bin/env python3
# Generate the Google Play listing graphics that are not screenshots:
#
#   app-icon-512.png          512x512, 24-bit RGB (no alpha): the Play
#                             Console high-res app icon
#   feature-graphic-1024x500.png
#                             1024x500, 24-bit RGB (no alpha): the listing
#                             feature graphic
#
# Both are composed from the brand mark (the largest raster available, inside
# backend/public/icon.svg) and the design tokens from DESIGN.md, so they stay
# consistent with the app without a designer round-trip. Outputs are written
# to assets/play-store/ and committed: CI does not need to regenerate them,
# edit the script and re-run it when the branding changes.
#
# Requires Pillow (python3 -m pip install --user Pillow). Run from anywhere:
#   bin/play_store_graphics.py
import base64
import glob
import io
import re
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MARK_SVG = ROOT / "backend/public/icon.svg"
OUTPUT_DIR = ROOT / "assets/play-store"

# DESIGN.md tokens
INK = (40, 34, 25)          # #282219 — the mark
VELLUM = (246, 241, 231)    # #f6f1e7 — feature graphic text / mark
BOOKPAGE = (253, 251, 246)  # #fdfbf6 — app icon background
SPRUCE = (19, 78, 74)       # #134e4a — feature graphic background
TAGLINE = "A fresh, literary operating system for book clubs."

# Liberation Serif is the closest installed match for the Playfair Display
# used on the site; every Linux distro ships a serif fallback.
SERIF_BOLD = "/usr/share/fonts/liberation/LiberationSerif-Bold.ttf"
SERIF_REG = "/usr/share/fonts/liberation/LiberationSerif-Regular.ttf"
FALLBACKS = ["NotoSerif-Bold.ttf", "NotoSerif-Regular.ttf", "DejaVuSerif.ttf"]


def find_font(preferred, fallback_name):
    """Return the first existing font path, or exit with a repair hint."""
    for path in [preferred] + [
        str(p) for p in glob.glob(f"/usr/share/fonts/**/{fallback_name}", recursive=True)
    ]:
        if Path(path).exists():
            return path
    sys.exit(
        f"error: no serif font available (looked for {preferred}, then {fallback_name}); "
        "install Liberation fonts"
    )


def load_mark():
    """The mark is embedded as base64 PNG inside the favicon svg."""
    svg = MARK_SVG.read_text()
    match = re.search(r"base64,([A-Za-z0-9+/=]+)", svg)
    if not match:
        sys.exit(f"error: no embedded raster found in {MARK_SVG}")
    return Image.open(io.BytesIO(base64.b64decode(match.group(1)))).convert("RGBA")


def recolor(image, rgb):
    out = Image.new("RGBA", image.size, rgb + (255,))
    out.putalpha(image.split()[3])
    return out


def save_flat_rgb(image, path):
    """Play requires 24-bit RGB PNG without alpha."""
    if image.mode != "RGB":
        image = image.convert("RGB")
    image.save(path, format="PNG")


def app_icon(mark, size=512):
    icon = Image.new("RGB", (size, size), BOOKPAGE)
    width = int(size * 0.82)
    scaled = mark.resize((width, round(mark.height * width / mark.width)), Image.LANCZOS)
    icon.paste(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2 - 16), scaled)
    return icon


def feature_graphic(mark, width=1024, height=500):
    fg = Image.new("RGB", (width, height), SPRUCE)
    mark_v = recolor(mark, VELLUM)

    mark_w = 290
    scaled = mark_v.resize((mark_w, round(mark_v.height * mark_w / mark_v.width)), Image.LANCZOS)
    fg.paste(scaled, ((width - scaled.width) // 2, 26), scaled)

    draw = ImageDraw.Draw(fg)
    wordmark = ImageFont.truetype(find_font(SERIF_BOLD, FALLBACKS[0]), 88)
    tagline = ImageFont.truetype(find_font(SERIF_REG, FALLBACKS[1]), 27)

    def center_text(y, text, font, fill):
        bb = draw.textbbox((0, 0), text, font=font)
        draw.text(((width - (bb[2] - bb[0])) / 2 - bb[0], y - bb[1]), text, font=font, fill=fill)

    center_text(300, "LitLoop", wordmark, VELLUM)
    center_text(408, TAGLINE, tagline, (222, 214, 200))
    return fg


def verify():
    expected = {
        "app-icon-512.png": (512, 512),
        "feature-graphic-1024x500.png": (1024, 500),
    }
    for name, (w, h) in expected.items():
        path = OUTPUT_DIR / name
        with open(path, "rb") as handle:
            header = handle.read(26)
        if header[:8] != b"\x89PNG\r\n\x1a\n":
            sys.exit(f"error: {path} is not a PNG")
        if struct.unpack(">II", header[16:24]) != (w, h):
            sys.exit(f"error: {path} is not {w}x{h}")
        color_type = struct.unpack(">B", header[25:26])[0]
        if color_type not in (2, 6):  # RGB, RGBA
            sys.exit(f"error: unexpected PNG color type {color_type} in {path}")
    print(f"generated {len(expected)} assets in {OUTPUT_DIR}")


def main():
    mark = load_mark()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    save_flat_rgb(app_icon(mark), OUTPUT_DIR / "app-icon-512.png")
    save_flat_rgb(feature_graphic(mark), OUTPUT_DIR / "feature-graphic-1024x500.png")
    verify()


if __name__ == "__main__":
    main()
