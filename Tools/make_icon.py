"""Renders the app icon: a white clock mark on the pink→orange→yellow sweep.

Pure stdlib (zlib + struct write the PNG), so there's no image-library
dependency. Edges are anti-aliased analytically via signed-distance smoothing
rather than by supersampling, which keeps it fast at 1024².
"""

import math
import os
import struct
import zlib

SIZE = 1024
OUT = os.path.join(os.path.dirname(__file__), "build", "icon-1024.png")

PINK = (255, 28, 130)
ORANGE = (255, 112, 28)
YELLOW = (255, 201, 13)


def lerp(a, b, t):
    return a + (b - a) * t


def gradient(t):
    """Three-stop diagonal sweep."""
    t = max(0.0, min(1.0, t))
    if t < 0.5:
        u = t / 0.5
        return tuple(lerp(PINK[i], ORANGE[i], u) for i in range(3))
    u = (t - 0.5) / 0.5
    return tuple(lerp(ORANGE[i], YELLOW[i], u) for i in range(3))


def smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def capsule_distance(px, py, ax, ay, bx, by):
    """Distance from a point to the segment AB — used for the clock hands."""
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    denom = vx * vx + vy * vy
    t = 0.0 if denom == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / denom))
    cx, cy = ax + t * vx, ay + t * vy
    return math.hypot(px - cx, py - cy)


def render():
    cx = cy = SIZE / 2
    ring_radius = SIZE * 0.315
    ring_half = SIZE * 0.033          # half the ring's stroke width
    hand_half = SIZE * 0.030          # half the hand thickness
    aa = 1.2                          # anti-alias width, in pixels

    # 12 o'clock is -90°. Hour hand straight up, minute hand out to 3 — equal
    # length hands at 10:10 just read as a "V", this reads unmistakably as a clock.
    minute_len = ring_radius - SIZE * 0.075
    hour_len = (ring_radius - SIZE * 0.075) * 0.60
    minute_angle = math.radians(0)      # 3 o'clock
    hour_angle = math.radians(-90)      # 12 o'clock

    mx = cx + minute_len * math.cos(minute_angle)
    my = cy + minute_len * math.sin(minute_angle)
    hx = cx + hour_len * math.cos(hour_angle)
    hy = cy + hour_len * math.sin(hour_angle)

    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            # Background sweep, corner to corner.
            base = gradient((x + y) / (2 * SIZE - 2))

            dist_center = math.hypot(x - cx, y - cy)

            # Ring: an annulus around `ring_radius`.
            ring_sd = abs(dist_center - ring_radius) - ring_half
            coverage = 1.0 - smoothstep(-aa, aa, ring_sd)

            # Hands, drawn as rounded capsules from the centre outward.
            for (ex, ey) in ((mx, my), (hx, hy)):
                hand_sd = capsule_distance(x, y, cx, cy, ex, ey) - hand_half
                coverage = max(coverage, 1.0 - smoothstep(-aa, aa, hand_sd))

            # Centre pin, punched back out of the hands for a crisp hub.
            hub_sd = dist_center - SIZE * 0.026
            coverage = max(coverage, 1.0 - smoothstep(-aa, aa, hub_sd))

            r = int(lerp(base[0], 255, coverage))
            g = int(lerp(base[1], 255, coverage))
            b = int(lerp(base[2], 255, coverage))
            row += bytes((r, g, b))
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)

    def chunk(tag, data):
        payload = tag + data
        return (struct.pack(">I", len(data)) + payload
                + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit RGB
    raw = b"".join(b"\x00" + r for r in rows)                    # filter type 0

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", header))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))
    print(f"Wrote {path} ({os.path.getsize(path) / 1024:.0f} KB)")


if __name__ == "__main__":
    write_png(OUT, render())
