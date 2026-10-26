#!/usr/bin/env python3
"""App icon: a low-poly "W" in PV module blue with sun rays falling onto it.

Writes the variants as SVG (1024 x 1024, full bleed, the platforms round the corners themselves)
and design/app-icon-varianten.html to compare them, large and at home-screen sizes.
With --render it also exports the chosen variant ([CHOSEN]) as every icon the platforms need
(web favicon, apple-touch-icon, manifest icons incl. maskable, iOS app icon set, Android mipmaps).
Rendering needs chromium and ffmpeg on the PATH.
Usage: python3 tools/app_icon.py [--render]
"""
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "design" / "icon"

# PV module blues, dark to light (monocrystalline cells under glass).
BLUE = ["#0a1a33", "#102852", "#163a72", "#1e4f95", "#2966b7", "#3d80d1", "#64a0e6"]
SUN = ["#e69500", "#f5ab00", "#ffc23d", "#ffd977"]  # app solar colours, warmer to lighter
# Softer sun: closer shades, so the disc reads as one shape and does not compete with the W.
SUN_SOFT = ["#f2ac2e", "#f5b944", "#f8c65e", "#fad37a"]


def pts(*p):
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in p)


def poly(p, fill, extra=""):
    return f'<polygon points="{pts(*p)}" fill="{fill}"{extra}/>'


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def w_shape(cx=500, top=360, bottom=820, mid=500, half=350, w=142):
    """Four slanted bars with horizontal ends, each split into low-poly facets.

    Returns (facets, outline) where facets are (points, shade index) and outline the bar polygons.
    """
    xl, xr = cx - half, cx + half  # outer top corners (left edge of bar 1, right edge of bar 4)
    v1, v2 = cx - half * 0.46, cx + half * 0.46  # valley centres
    bars = [
        # (top-left, top-right, bottom-right, bottom-left), shade base: light falls from the top right
        ((xl, top), (xl + w, top), (v1 + w / 2, bottom), (v1 - w / 2, bottom)),
        ((cx - w / 2, mid), (cx + w / 2, mid), (v1 + w / 2, bottom), (v1 - w / 2, bottom)),
        ((cx - w / 2, mid), (cx + w / 2, mid), (v2 + w / 2, bottom), (v2 - w / 2, bottom)),
        ((xr - w, top), (xr, top), (v2 + w / 2, bottom), (v2 - w / 2, bottom)),
    ]
    # Down strokes (1, 3) face the light less than up strokes (2, 4).
    base = [1, 4, 2, 5]
    facets = []
    for (a, b, c, d), s in zip(bars, base):
        # Split along a long diagonal and once more across the middle: four triangles per bar.
        m1, m2 = lerp(a, d, 0.55), lerp(b, c, 0.45)
        facets += [
            ((a, b, m2), s + 1),
            ((a, m2, m1), s),
            ((m1, m2, c), s + 1),
            ((m1, c, d), s - 1),
        ]
    return facets, bars


def sun(cx, cy, r, n=9, colors=SUN):
    """Low-poly sun disc: a fan of triangles, lit from the top right."""
    out = []
    for i in range(n):
        a0 = 2 * math.pi * i / n - math.pi / 2
        a1 = 2 * math.pi * (i + 1) / n - math.pi / 2
        p0 = (cx + r * math.cos(a0), cy + r * math.sin(a0))
        p1 = (cx + r * math.cos(a1), cy + r * math.sin(a1))
        am = (a0 + a1) / 2
        # Facets pointing up/right are lighter.
        light = (math.cos(am - (-math.pi / 4)) + 1) / 2
        out.append(poly([(cx, cy), p0, p1], colors[min(3, int(light * 3.99))]))
    return out


def rays(cx, cy, targets, r0, width, fill, opacity):
    """Light beams from the sun that widen towards the W and end behind it, so they seem to hit it."""
    out = []
    for tx, ty in targets:
        a = math.atan2(ty - cy, tx - cx)
        n = (-math.sin(a), math.cos(a))
        start = (cx + r0 * math.cos(a), cy + r0 * math.sin(a))
        end = (tx + 60 * math.cos(a), ty + 60 * math.sin(a))
        out.append(
            poly(
                [
                    (start[0] + n[0] * 6, start[1] + n[1] * 6),
                    (end[0] + n[0] * width, end[1] + n[1] * width),
                    (end[0] - n[0] * width, end[1] - n[1] * width),
                    (start[0] - n[0] * 6, start[1] - n[1] * 6),
                ],
                fill,
                f' fill-opacity="{opacity}"',
            )
        )
    return out


# Where the rays land: tops of the up strokes and the middle peak.
TARGETS = [(790, 420), (600, 540), (330, 430)]


def icon(bg, w_blues, ray_fill, ray_opacity, sun_pos=(842, 182), sun_r=104, sun_colors=SUN):
    facets, bars = w_shape()
    body = []
    for p, s in facets:
        body.append(poly(p, w_blues[max(0, min(len(w_blues) - 1, s))]))
    # Thin cell lines across the W: the module look, subtle.
    clip = "".join(poly(b, "#000") for b in bars)
    lines = []
    for y in range(360 + 66, 820, 66):
        lines.append(f'<line x1="0" y1="{y}" x2="1024" y2="{y}"/>')
    for x in range(110, 1000, 66):
        lines.append(f'<line x1="{x}" y1="0" x2="{x}" y2="1024"/>')
    sx, sy = sun_pos
    ray_list = rays(sx, sy, TARGETS, sun_r + 24, 34, ray_fill, ray_opacity)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs><clipPath id="w">{clip}</clipPath></defs>
  {bg}
  {''.join(ray_list)}
  {''.join(body)}
  <g clip-path="url(#w)" stroke="#ffffff" stroke-opacity="0.10" stroke-width="3">{''.join(lines)}</g>
  {''.join(sun(sx, sy, sun_r, colors=sun_colors))}
</svg>
"""


LIGHT_BG = '<rect width="1024" height="1024" fill="#f2f2f7"/>'

VARIANTS = {
    "tag-dezent": (
        "Tag, Sonne dezent (gewählt)",
        "Kleinere Sonne in weicheren Tönen, Strahlen etwas zurückgenommen.",
        icon(LIGHT_BG, BLUE[1:], "#f5ab00", 0.45, sun_pos=(856, 168), sun_r=82, sun_colors=SUN_SOFT),
    ),
    "tag-leise": (
        "Tag, Sonne leise",
        "Noch kleiner und blasser; das W trägt das Icon allein, die Sonne ist nur noch Absender des Lichts.",
        icon(LIGHT_BG, BLUE[1:], "#f5b944", 0.38, sun_pos=(866, 158), sun_r=68, sun_colors=SUN_SOFT[1:] + ["#fce0a0"]),
    ),
    "tag": (
        "Tag (erste Fassung)",
        "Heller Grund wie die App im Hellmodus, goldene Strahlen.",
        icon(LIGHT_BG, BLUE[1:], "#f5ab00", 0.55),
    ),
    "nacht": (
        "Nacht",
        "Tiefes Blau, das W hebt sich mit helleren Facetten ab; Strahlen als warmes Licht.",
        icon(
            '<rect width="1024" height="1024" fill="#08111f"/>',
            BLUE[2:] + ["#7fb0ea"],
            "#ffc23d",
            0.6,
        ),
    ),
    "himmel": (
        "Sonnenkarte",
        "Grund im Verlauf der Solar-Karte der App, Strahlen hell.",
        icon(
            '<defs><linearGradient id="g" x1="1" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#f5ab00"/><stop offset="1" stop-color="#d98200"/></linearGradient></defs>'
            '<rect width="1024" height="1024" fill="url(#g)"/>',
            BLUE,
            "#fff3c4",
            0.5,
        ),
    ),
}


def page():
    cards = []
    for key, (name, desc, _) in VARIANTS.items():
        src = f"icon/{key}.svg"
        cards.append(f"""
    <section class="card">
      <h2>{name}</h2>
      <p>{desc}</p>
      <div class="row">
        <img class="big" src="{src}" alt="{name}">
        <div class="small">
          <img src="{src}" width="120" alt=""><img src="{src}" width="60" alt=""><img src="{src}" width="40" alt="">
          <div class="home light"><img src="{src}" width="60" alt=""><span>Wattbury</span></div>
          <div class="home dark"><img src="{src}" width="60" alt=""><span>Wattbury</span></div>
        </div>
      </div>
    </section>""")
    return f"""<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>App-Icon Varianten</title>
<style>
  :root {{ --bg: #f2f2f7; --card: #fff; --fg: #111; --muted: #6b6f76; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --bg: #000; --card: #1c1c1e; --fg: #f2f2f7; --muted: #9a9ea6; }} }}
  body {{ margin: 0; padding: 24px 16px; background: var(--bg); color: var(--fg); font: 15px/1.4 system-ui, sans-serif; }}
  h1 {{ font-size: 24px; margin: 0 0 4px; }}
  .lead {{ color: var(--muted); margin: 0 0 20px; max-width: 720px; }}
  .card {{ background: var(--card); border-radius: 18px; padding: 18px; margin-bottom: 16px; max-width: 760px; }}
  .card h2 {{ margin: 0; font-size: 18px; }}
  .card p {{ margin: 4px 0 14px; color: var(--muted); }}
  .row {{ display: flex; gap: 20px; flex-wrap: wrap; align-items: center; }}
  img {{ border-radius: 22.37%; display: block; }}
  .big {{ width: 256px; height: 256px; box-shadow: 0 6px 24px rgba(0,0,0,.18); }}
  .small {{ display: flex; gap: 14px; align-items: center; flex-wrap: wrap; }}
  .home {{ display: flex; flex-direction: column; align-items: center; gap: 6px; padding: 14px 16px; border-radius: 14px; font-size: 12px; }}
  .home.light {{ background: linear-gradient(160deg, #cfe3f7, #f7e7cf); color: #111; }}
  .home.dark {{ background: linear-gradient(160deg, #0d1626, #29213a); color: #eee; }}
</style>
</head>
<body>
<h1>App-Icon</h1>
<p class="lead">Low-Poly-W in PV-Modul-Blau, Sonnenstrahlen fallen von oben rechts darauf. Groß, in Home-Screen-Größen und auf hellem und dunklem Hintergrund. Erzeugt von tools/app_icon.py.</p>
{''.join(cards)}
</body>
</html>
"""


# Chosen on 26.10.2026.
CHOSEN = "tag-dezent"
ICON_BG = "#f2f2f7"


def render(svg: Path, size: int, out: Path, scale: float = 1.0):
    """PNG of [svg] at [size] px, motif scaled by [scale] on the icon background, without alpha
    (the App Store rejects icons with an alpha channel)."""
    with tempfile.TemporaryDirectory() as tmp:
        inner = round(size * scale)
        off = (size - inner) // 2
        html = Path(tmp) / "icon.html"
        html.write_text(
            f'<!doctype html><html><body style="margin:0;background:{ICON_BG}">'
            f'<div style="width:{size}px;height:{size}px;background:{ICON_BG};position:relative">'
            f'<img src="{svg.as_uri()}" style="position:absolute;left:{off}px;top:{off}px;width:{inner}px;height:{inner}px">'
            "</div></body></html>"
        )
        shot = Path(tmp) / "shot.png"
        # Headless windows are smaller than requested, so render big and crop.
        side = max(1200, size + 200)
        subprocess.run(
            ["chromium", "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
             f"--window-size={side},{side}", f"--screenshot={shot}", html.as_uri()],
            check=True, capture_output=True,
        )
        out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", str(shot), "-vf", f"crop={size}:{size}:0:0",
             "-pix_fmt", "rgb24", str(out)],
            check=True,
        )


def export():
    svg = OUT / f"{CHOSEN}.svg"
    web = ROOT / "web"
    shutil.copy(svg, web / "favicon.svg")
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "favicon.png"
        render(svg, 32, png)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(png), str(web / "favicon.ico")], check=True)
    render(svg, 180, web / "apple-touch-icon.png")
    # Not "icons/": Apache servers (All-Inkl among them) alias /icons/ to their own symbols.
    for n in (192, 512):
        render(svg, n, web / "app-icons" / f"Icon-{n}.png")
        # Maskable: launchers may cut a circle of 80 % diameter. The sun's far edge sits at 0.555 of
        # the size from the centre, so 0.7 keeps it inside (0.4 / 0.555 = 0.72).
        render(svg, n, web / "app-icons" / f"Icon-maskable-{n}.png", scale=0.7)

    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for img in json.loads((ios / "Contents.json").read_text())["images"]:
        px = round(float(img["size"].split("x")[0]) * int(img["scale"].rstrip("x")))
        render(svg, px, ios / img["filename"])

    for density, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        render(svg, px, ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")
    print(f"exported {CHOSEN} to web/, ios/ and android/")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for key, (_, _, svg) in VARIANTS.items():
        (OUT / f"{key}.svg").write_text(svg)
    (ROOT / "design" / "app-icon-varianten.html").write_text(page())
    print("wrote", ", ".join(f"design/icon/{k}.svg" for k in VARIANTS), "and design/app-icon-varianten.html")
    if "--render" in sys.argv:
        export()


if __name__ == "__main__":
    main()
