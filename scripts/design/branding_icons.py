#!/usr/bin/env python3
"""Derive the launcher-icon SOURCE layers from the one master artwork.

Round 16 #1: the Android home-screen icon shipped as a plain white tile. The
cause was `icon-foreground.png` — an adaptive icon's foreground must be a
TRANSPARENT layer holding only the mark, and that file was a fully opaque white
square (alpha 255 in every pixel) with a whisper-faint check on it. It covered
the `#4F63EF` background layer completely, so every Android 8+ launcher drew
white.  The legacy `mipmap/ic_launcher.png` was fine, which is why the icon
still looked right in the Play listing and nowhere else.

Rather than hand-fix a PNG, derive every layer from the single master
(`icon.png`) so they can never drift apart again:

  icon-foreground.png   the mark alone, white on transparent, scaled into the
                        adaptive-icon safe zone (Google: key content inside the
                        centre 66 of 108 dp -> ~60 % of the canvas)
  icon-background.png   the brand gradient, full bleed, so Android's icon is
                        the same artwork as iOS's instead of a flat colour
  icon-monochrome.png   the same mark for Android 13+ themed icons, which tint
                        the alpha channel and ignore RGB

Then `dart run flutter_launcher_icons` turns these into the platform assets.

Usage:  python3 scripts/design/branding_icons.py [--check]
        --check verifies the committed layers instead of rewriting them.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
BRANDING = ROOT / "apps" / "app" / "assets" / "branding"
MASTER = BRANDING / "icon.png"

CANVAS = 1024

# --- adaptive-icon geometry, in the 108 dp units Android uses --------------
# The layer is 108 dp. flutter_launcher_icons wraps our drawable in
# <inset android:inset="16%">, so it is painted into the centre 73.44 dp. The
# launcher masks to the centre 72 dp, and Google's safe zone for key content is
# the centre 66 dp. Net effect: the fraction of the SOURCE canvas our mark
# occupies is very nearly the fraction of the VISIBLE icon it ends up as.
LAYER_DP = 108.0
TOOL_INSET = 0.16  # must match the <inset> flutter_launcher_icons emits
DRAWN_DP = LAYER_DP * (1 - 2 * TOOL_INSET)  # 73.44
VISIBLE_DP = 72.0
SAFE_DP = 66.0

# Match iOS exactly: in the master artwork the mark spans 64.7 % of the tile, so
# it should span the same share of the visible Android icon.
TARGET_VISIBLE_FRACTION = 0.647
SAFE_FRACTION = TARGET_VISIBLE_FRACTION * VISIBLE_DP / DRAWN_DP
# min(r, g, b) at or above this is "white" — the mark and the page around the
# artwork. The blue tile never gets past ~150 (measured on the master).
WHITE_FLOOR = 200
# Soft ramp so the mark keeps its anti-aliased edge instead of a jagged cutout.
ALPHA_LO, ALPHA_HI = 170, 245


def _min_channel(img: Image.Image) -> Image.Image:
    """min(r, g, b) per pixel — the cheapest "how white is this?" signal, and
    the one that separates the near-white mark from the blue tile cleanly."""
    r, g, b = img.split()[:3]
    return ImageChops.darker(ImageChops.darker(r, g), b)


def _mark_alpha(master: Image.Image) -> Image.Image:
    """Alpha for the white mark INSIDE the tile (the page around it excluded)."""
    minc = _min_channel(master)
    # Everything white-ish: the mark plus the page surrounding the tile.
    whiteish = minc.point(lambda v: 255 if v >= WHITE_FLOOR else 0)
    # Flood the page from a corner so only the mark is left at 255.
    flooded = whiteish.convert("L")
    ImageDraw.floodfill(flooded, (0, 0), 128)
    ImageDraw.floodfill(flooded, (master.width - 1, master.height - 1), 128)
    inside = flooded.point(lambda v: 255 if v == 255 else 0)
    # Soft alpha from the original luminance, gated to the mark.
    ramp = minc.point(
        lambda v: 0
        if v <= ALPHA_LO
        else (255 if v >= ALPHA_HI else int(255 * (v - ALPHA_LO) / (ALPHA_HI - ALPHA_LO)))
    )
    # Grow the gate a little so the ramp's anti-aliased fringe survives.
    gate = inside.filter(ImageFilter.MaxFilter(5))
    return ImageChops.multiply(ramp, gate)


def _tile_bbox(master: Image.Image) -> tuple[int, int, int, int]:
    """Bounding box of the coloured tile inside the master artwork."""
    minc = _min_channel(master)
    tile = minc.point(lambda v: 255 if v < WHITE_FLOOR else 0)
    box = tile.getbbox()
    if box is None:
        raise SystemExit("no coloured tile found in the master artwork")
    return box


def _sample_tile(master: Image.Image, cx: int, cy: int, radius: int) -> tuple[int, int, int]:
    """Mean tile colour around (cx, cy), ignoring the mark and the page.

    Sampling a single pixel is not safe: the tile is a ROUNDED square, so the
    corner of its bounding box is still page-white.
    """
    px = master.convert("RGB").load()
    acc, n = [0, 0, 0], 0
    for y in range(max(0, cy - radius), min(master.height, cy + radius)):
        for x in range(max(0, cx - radius), min(master.width, cx + radius)):
            c = px[x, y]
            if min(c) < WHITE_FLOOR:  # tile, not page and not mark
                acc = [acc[i] + c[i] for i in range(3)]
                n += 1
    if n == 0:
        raise SystemExit(f"no tile pixels near ({cx}, {cy}) — is the master artwork right?")
    return tuple(v // n for v in acc)  # type: ignore[return-value]


def _gradient_ends(master: Image.Image) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    """Sample the tile's gradient at its two diagonal ends, skipping the mark."""
    x0, y0, x1, y1 = _tile_bbox(master)
    inset = round((x1 - x0) * 0.16)
    radius = max(8, round((x1 - x0) * 0.05))
    return (
        _sample_tile(master, x0 + inset, y0 + inset, radius),
        _sample_tile(master, x1 - inset, y1 - inset, radius),
    )


def build() -> dict[str, Image.Image]:
    master = Image.open(MASTER).convert("RGBA")
    alpha = _mark_alpha(master)

    box = alpha.getbbox()
    if box is None:
        raise SystemExit("no mark found in the master artwork")
    mark = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 0))
    cropped = alpha.crop(box)
    scale = (CANVAS * SAFE_FRACTION) / max(cropped.size)
    size = (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale)))
    cropped = cropped.resize(size, Image.LANCZOS)
    white = Image.new("RGBA", size, (255, 255, 255, 255))
    white.putalpha(cropped)
    mark.alpha_composite(
        white, ((CANVAS - size[0]) // 2, (CANVAS - size[1]) // 2)
    )

    top, bottom = _gradient_ends(master)
    background = Image.new("RGB", (CANVAS, CANVAS))
    draw = ImageDraw.Draw(background)
    # Diagonal gradient, drawn as a top-left -> bottom-right sweep over 2N bands.
    steps = CANVAS * 2
    for i in range(steps):
        t = i / (steps - 1)
        colour = tuple(round(top[c] + (bottom[c] - top[c]) * t) for c in range(3))
        draw.line([(i, 0), (0, i)], fill=colour)

    return {
        "icon-foreground.png": mark,
        "icon-monochrome.png": mark.copy(),
        "icon-background.png": background.convert("RGBA"),
    }


def verify(layers: dict[str, Image.Image]) -> list[str]:
    """The invariants that, had they been checked once, would have caught this."""
    problems: list[str] = []
    for name in ("icon-foreground.png", "icon-monochrome.png"):
        img = layers[name]
        a = img.getchannel("A")
        corners = [
            a.getpixel(p)
            for p in [(0, 0), (img.width - 1, 0), (0, img.height - 1),
                      (img.width - 1, img.height - 1)]
        ]
        if any(c != 0 for c in corners):
            problems.append(
                f"{name}: corners are not transparent ({corners}) — an adaptive "
                "foreground must not cover the background layer"
            )
        box = a.getbbox()
        if box is None:
            problems.append(f"{name}: empty layer")
            continue
        span = max(box[2] - box[0], box[3] - box[1]) / img.width
        safe_dp = span * DRAWN_DP
        if safe_dp > SAFE_DP:
            problems.append(
                f"{name}: mark lands at {safe_dp:.1f} dp of the 108 dp layer — "
                f"past Google's {SAFE_DP:.0f} dp safe zone, so round and squircle "
                "masks would clip it"
            )
        cx = (box[0] + box[2]) / 2 / img.width
        cy = (box[1] + box[3]) / 2 / img.height
        if abs(cx - 0.5) > 0.02 or abs(cy - 0.5) > 0.02:
            problems.append(
                f"{name}: mark is off centre ({cx:.0%}, {cy:.0%})"
            )
    bg = layers["icon-background.png"]
    if bg.getchannel("A").getextrema()[0] != 255:
        problems.append("icon-background.png: must be fully opaque")
    return problems


def main() -> int:
    check_only = "--check" in sys.argv
    layers = build()

    problems = verify(layers)
    for line in problems:
        print(f"FAIL {line}")

    if check_only:
        for name, img in layers.items():
            path = BRANDING / name
            if not path.exists():
                problems.append(f"{name}: missing")
                print(f"FAIL {name}: missing")
                continue
            if Image.open(path).convert("RGBA").tobytes() != img.tobytes():
                problems.append(f"{name}: out of date, re-run this script")
                print(f"FAIL {name}: out of date, re-run this script")
    else:
        for name, img in layers.items():
            img.save(BRANDING / name)
            a = img.getchannel("A")
            box = a.getbbox()
            span = (max(box[2] - box[0], box[3] - box[1]) / img.width) if box else 0
            visible = span * DRAWN_DP / VISIBLE_DP
            print(
                f"wrote {name}  source span {span:.0%}  -> {visible:.0%} of the "
                f"visible icon  corner alpha {a.getpixel((0, 0))}"
            )

    print(f"FAILURES: {len(problems)}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
