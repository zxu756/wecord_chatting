#!/usr/bin/env python3
"""Draws the WeCord web icons into web/ (needs Pillow).

The mark is a white speech bubble with a "W" on the app's seed blue
(WeCordTheme._seedColor, #2F7CF6), drawn on a 1024 px canvas and scaled
down, so every size comes from one drawing:

* web/icons/Icon-192.png, Icon-512.png, Icon-1024.png: rounded square,
  transparent corners (manifest purpose "any").
* web/icons/Icon-maskable-192.png, -512.png, -1024.png: full-bleed blue,
  the mark inside the 80% safe zone (manifest purpose "maskable").
* web/icons/apple-touch-icon.png (180): full-bleed, iOS rounds it.
* web/favicon.png (32) and web/icons/favicon-16.png.

Run from the repository root: python3 tool/generate_web_icons.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

CANVAS = 1024
BLUE_TOP = (79, 150, 255)  # lighter seed blue
BLUE_BOTTOM = (31, 95, 208)  # deeper seed blue
SEED_BLUE = (47, 124, 246)  # #2F7CF6
WHITE = (255, 255, 255)

WEB = Path(__file__).resolve().parent.parent / "web"


def gradient() -> Image.Image:
    """A top-to-bottom blue gradient filling the canvas."""
    image = Image.new("RGBA", (CANVAS, CANVAS))
    draw = ImageDraw.Draw(image)
    for y in range(CANVAS):
        t = y / (CANVAS - 1)
        color = tuple(
            round(top + (bottom - top) * t)
            for top, bottom in zip(BLUE_TOP, BLUE_BOTTOM)
        )
        draw.line([(0, y), (CANVAS, y)], fill=color + (255,))
    return image


def mark(scale: float) -> Image.Image:
    """The white bubble with a blue W, centred, [scale] of the canvas wide."""
    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    size = CANVAS * scale
    left = (CANVAS - size) / 2
    top = (CANVAS - size) / 2 - size * 0.04

    # Bubble body and its tail at the bottom left.
    body = (left, top, left + size, top + size * 0.78)
    draw.rounded_rectangle(body, radius=size * 0.26, fill=WHITE)
    draw.polygon(
        [
            (left + size * 0.20, top + size * 0.62),
            (left + size * 0.44, top + size * 0.74),
            (left + size * 0.14, top + size * 0.98),
        ],
        fill=WHITE,
    )

    # The W, as one thick stroke with rounded ends.
    stroke = size * 0.105
    w_top = top + size * 0.22
    w_bottom = top + size * 0.56
    points = [
        (left + size * 0.21, w_top),
        (left + size * 0.355, w_bottom),
        (left + size * 0.50, w_top + size * 0.07),
        (left + size * 0.645, w_bottom),
        (left + size * 0.79, w_top),
    ]
    draw.line(points, fill=SEED_BLUE, width=round(stroke), joint="curve")
    radius = stroke / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=SEED_BLUE)
    return layer


def rounded_icon() -> Image.Image:
    """The mark on a rounded blue square with transparent corners."""
    background = gradient()
    clip = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(clip).rounded_rectangle(
        (0, 0, CANVAS - 1, CANVAS - 1), radius=CANVAS * 0.22, fill=255
    )
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    icon.paste(background, (0, 0), clip)
    return Image.alpha_composite(icon, mark(0.62))


def full_bleed_icon(scale: float) -> Image.Image:
    """The mark on a square of blue to the edges (maskable, Apple)."""
    return Image.alpha_composite(gradient(), mark(scale))


def save(image: Image.Image, path: Path, size: int, opaque: bool = False) -> None:
    resized = image.resize((size, size), Image.Resampling.LANCZOS)
    if opaque:
        resized = resized.convert("RGB")
    path.parent.mkdir(parents=True, exist_ok=True)
    resized.save(path, optimize=True)
    print(f"wrote {path.relative_to(WEB.parent)} ({size}x{size})")


def main() -> None:
    rounded = rounded_icon()
    # The maskable safe zone is a circle of 80% of the width.
    maskable = full_bleed_icon(0.50)
    apple = full_bleed_icon(0.60)

    save(rounded, WEB / "icons" / "Icon-192.png", 192)
    save(rounded, WEB / "icons" / "Icon-512.png", 512)
    save(rounded, WEB / "icons" / "Icon-1024.png", 1024)
    save(maskable, WEB / "icons" / "Icon-maskable-192.png", 192, opaque=True)
    save(maskable, WEB / "icons" / "Icon-maskable-512.png", 512, opaque=True)
    save(maskable, WEB / "icons" / "Icon-maskable-1024.png", 1024, opaque=True)
    save(apple, WEB / "icons" / "apple-touch-icon.png", 180, opaque=True)
    save(rounded, WEB / "favicon.png", 32)
    save(rounded, WEB / "icons" / "favicon-16.png", 16)


if __name__ == "__main__":
    main()
