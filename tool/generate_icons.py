"""One-off icon packaging script for Dot Commander: Pirates.

Takes the source artwork (assets/icon/app_icon_source.png) and packages
it into the standard Android launcher icon resources, WITHOUT altering a
single pixel of the artwork itself -- only uniform resizing (never
stretched/cropped/distorted, aspect ratio locked since the source is
already square) and, for the adaptive icon foreground only, padding the
unmodified artwork on a larger transparent canvas so it sits inside
Android's guaranteed-safe zone.

Not part of the Flutter app's build. Run by hand (`python
tool/generate_icons.py`) whenever the source artwork is replaced; kept
here, tracked, as the reproducible record of how the committed icon
files under android/app/src/main/res/ and assets/icon/ were produced.
"""
from PIL import Image
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "icon", "app_icon_source.png")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

src = Image.open(SRC).convert("RGBA")
assert src.width == src.height, f"expected a square source image, got {src.size}"
print("source size:", src.size)

# --- 1. Legacy launcher icon (ic_launcher.png), one per density -----------
# Direct uniform resize of the full, unmodified artwork -- no crop, no
# stretch (source is already 1:1, matching every target's 1:1 aspect).
LEGACY_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
for folder, size in LEGACY_SIZES.items():
    out_dir = os.path.join(RES, folder)
    os.makedirs(out_dir, exist_ok=True)
    resized = src.resize((size, size), Image.LANCZOS)
    resized.save(os.path.join(out_dir, "ic_launcher.png"))
    print(f"legacy {folder}: {size}x{size}")

# --- 2. Adaptive icon foreground, one per density --------------------------
# The full, unmodified artwork is scaled down to 60% of each foreground
# canvas and centered on a transparent background. Android's guaranteed-
# safe zone for adaptive-icon content is the inner 66/108 (~61%) circle,
# so 60% keeps every pixel of the source -- including the ship's flag
# tip and bowsprit, which reach close to the source's own edges -- safely
# inside that zone regardless of which mask shape a given launcher applies.
ADAPTIVE_SIZES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}
SAFE_SCALE = 0.60
for folder, canvas_size in ADAPTIVE_SIZES.items():
    out_dir = os.path.join(RES, folder)
    os.makedirs(out_dir, exist_ok=True)
    inner = round(canvas_size * SAFE_SCALE)
    art = src.resize((inner, inner), Image.LANCZOS)
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    offset = ((canvas_size - inner) // 2, (canvas_size - inner) // 2)
    canvas.paste(art, offset, art)
    canvas.save(os.path.join(out_dir, "ic_launcher_foreground.png"))
    print(f"adaptive fg {folder}: canvas {canvas_size}x{canvas_size}, art {inner}x{inner} @ {offset}")

# --- 3. Play Store listing icon: clean 512x512, no padding -----------------
play_dir = os.path.join(ROOT, "assets", "icon")
play = src.resize((512, 512), Image.LANCZOS)
play.save(os.path.join(play_dir, "play_store_icon_512.png"))
print("play store icon: 512x512 ->", os.path.join(play_dir, "play_store_icon_512.png"))

print("done")
