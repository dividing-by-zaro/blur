"""Renders the app icon: tan field, stippled, with the Blur mark on it.

    uv run --no-project --with pillow python Tools/make_icon.py

Writes `blur-icon.png` (the RGBA master, which the README shows) and the
flattened `icon-1024.png` the asset catalogue ships — iOS icons must carry no
alpha channel, so the second is the first composited onto opaque tan.

The mark itself is `Tools/icon-glyph.png`, an 8-bit coverage mask and the only
hand-drawn asset here. Everything else — the field, its gradient, the stipple —
is generated, which is the point: the stipple is the same construction the app
draws on its cards, so the icon is made of the app's material rather than being
a picture that happens to sit next to it.
"""

import random

from PIL import Image, ImageDraw

SIZE = 1024
# Dots are drawn at 4x and downsampled. A 2px dot rasterised directly has one
# hard pixel of anti-aliasing and reads as grit; supersampled it stays round.
SS = 4

TAN_LIGHT = (217, 203, 174)   # the field's top-left
TAN_DARK = (192, 171, 134)    # its bottom-right
INK = (27, 26, 23)            # Blur.ink — the mark, and the dots on the field

# Matches `BlurCard`: ink dots on the light surface, cream dots inside the dark
# shape, the second slightly stronger because it has less to work against.
FIELD_DOTS = 0.14
MARK_DOTS = 0.11

# Pitch in icon pixels. Far coarser than the app's 6pt card stipple: this is
# read at 60pt on a home screen, and dots scaled to the app's density would
# dissolve into an even wash long before then.
SPACING = 20
DOT_SCALE = 2.7


def field() -> Image.Image:
    """The tan ground, warming from top-left to bottom-right.

    Built tiny and scaled up — a 64px diagonal ramp resampled to 1024 is
    smoother than one computed per pixel, and about a thousand times faster.
    """
    small = Image.new("RGB", (64, 64))
    pixels = small.load()
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            pixels[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(TAN_LIGHT, TAN_DARK)
            )
    return small.resize((SIZE, SIZE), Image.BICUBIC)


def stipple(color: tuple[int, int, int], opacity: float, seed: int) -> Image.Image:
    """Dots on a jittered grid, as an RGBA layer.

    A jittered grid rather than scattered points: uniform random placement
    clumps and leaves bald patches, which reads as dirt on the artwork. Dots
    grow toward the bottom so the field has some weight to it, the same grading
    the app's cards use.
    """
    layer = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    alpha = round(255 * opacity)
    step = SPACING * SS

    y = step / 2
    while y < SIZE * SS:
        x = step / 2
        while x < SIZE * SS:
            jx = rng.uniform(-0.42, 0.42) * step
            jy = rng.uniform(-0.42, 0.42) * step
            weight = 0.55 + 0.45 * (y / (SIZE * SS))
            r = rng.uniform(0.34, 1.05) * weight * DOT_SCALE * SS
            draw.ellipse((x + jx - r, y + jy - r, x + jx + r, y + jy + r),
                         fill=color + (alpha,))
            x += step
        y += step

    return layer.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    mark = Image.open("Tools/icon-glyph.png").convert("L")
    if mark.size != (SIZE, SIZE):
        mark = mark.resize((SIZE, SIZE), Image.LANCZOS)

    icon = field().convert("RGBA")
    icon.alpha_composite(stipple(INK, FIELD_DOTS, seed=0xBACCD009))

    # The mark goes on solid, over the field's dots, so the stipple never lands
    # behind a stroke and thins it.
    icon.paste(Image.new("RGBA", (SIZE, SIZE), INK + (255,)), mask=mark)

    # Then a lighter stipple clipped to the mark, so both surfaces carry the
    # same texture — exactly what `BlurCard` does for light and dark cards.
    inside = stipple(TAN_LIGHT, MARK_DOTS, seed=0xC0FFEE01)
    inside.putalpha(Image.composite(inside.getchannel("A"),
                                    Image.new("L", (SIZE, SIZE), 0), mark))
    icon.alpha_composite(inside)

    icon.save("blur-icon.png")

    flat = Image.new("RGB", (SIZE, SIZE), TAN_LIGHT)
    flat.paste(icon, mask=icon.getchannel("A"))
    flat.save("Blur/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

    print("wrote blur-icon.png and icon-1024.png")


if __name__ == "__main__":
    main()
