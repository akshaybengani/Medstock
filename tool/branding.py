"""Renders the Medstock mark (bottle with a fill level) at every size Android
and iOS need, plus the splash logo. Single source of truth: draw_mark()."""
from PIL import Image, ImageDraw
import os

TEAL       = (0, 105, 109, 255)
TEAL_DARK  = (0, 47, 50, 255)
MINT       = (156, 240, 242, 255)
WHITE      = (255, 255, 255, 255)
SS = 4  # supersample

def draw_mark(size, bg=None, glyph_scale=1.0, fg=WHITE, fill=MINT):
    """The bottle mark. bg=None gives a transparent canvas (for adaptive
    foregrounds and splash logos)."""
    W = size * SS
    img = Image.new('RGBA', (W, W), bg if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Geometry as fractions of the canvas, then scaled for safe zones.
    s = glyph_scale
    bw, bh = W * 0.42 * s, W * 0.46 * s
    x0 = (W - bw) / 2
    y0 = W * 0.34 - (W * 0.46 * (s - 1)) / 2

    cw, ch = bw * 0.52, W * 0.085 * s
    cx0 = (W - cw) / 2
    cy0 = y0 - ch - W * 0.028 * s

    rad = W * 0.055 * s
    d.rounded_rectangle([cx0, cy0, cx0 + cw, cy0 + ch],
                        radius=ch * 0.34, fill=fg)
    d.rounded_rectangle([x0, y0, x0 + bw, y0 + bh], radius=rad, fill=fg)

    # Liquid: the lower ~55% of the bottle interior.
    inset = W * 0.030 * s
    level = y0 + bh * 0.45
    liquid = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(liquid).rounded_rectangle(
        [x0 + inset, y0 + inset, x0 + bw - inset, y0 + bh - inset],
        radius=rad * 0.7, fill=fill)
    clip = Image.new('L', (W, W), 0)
    ImageDraw.Draw(clip).rectangle([0, level, W, W], fill=255)
    img.paste(liquid, (0, 0),
              Image.composite(liquid.split()[3], Image.new('L', (W, W), 0), clip))

    return img.resize((size, size), Image.LANCZOS)

def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return path

written = []

# ---- master assets -------------------------------------------------------
written.append(save(draw_mark(1024, bg=TEAL), 'assets/branding/icon.png'))
# Adaptive foreground: glyph pulled in to survive the circular/squircle mask.
written.append(save(draw_mark(1024, bg=None, glyph_scale=0.68),
                    'assets/branding/icon_foreground.png'))
# Splash logo, drawn for a light and a dark background.
written.append(save(draw_mark(1024, bg=None, glyph_scale=0.52, fg=TEAL, fill=MINT),
                    'assets/branding/splash_light.png'))
written.append(save(draw_mark(1024, bg=None, glyph_scale=0.52, fg=WHITE, fill=MINT),
                    'assets/branding/splash_dark.png'))

# ---- Android legacy mipmaps ---------------------------------------------
for folder, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                   ('xxhdpi', 144), ('xxxhdpi', 192)]:
    written.append(save(draw_mark(px, bg=TEAL),
                        f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png'))
    # Round variant for launchers that ask for it.
    written.append(save(draw_mark(px, bg=TEAL),
                        f'android/app/src/main/res/mipmap-{folder}/ic_launcher_round.png'))
    # Adaptive foreground layer.
    written.append(save(draw_mark(int(px * 108 / 48), bg=None, glyph_scale=0.68),
                        f'android/app/src/main/res/mipmap-{folder}/ic_launcher_foreground.png'))

# ---- iOS AppIcon set ----------------------------------------------------
ios_sizes = [
    (20, 2), (20, 3), (29, 1), (29, 2), (29, 3), (40, 1), (40, 2), (40, 3),
    (60, 2), (60, 3), (76, 1), (76, 2), (83.5, 2), (1024, 1),
]
ios_dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
seen = set()
for pt, scale in ios_sizes:
    px = int(round(pt * scale))
    name = f'Icon-App-{pt:g}x{pt:g}@{scale}x.png'
    if px in seen and pt != 1024:
        pass
    seen.add(px)
    # iOS icons must be fully opaque with no alpha.
    img = draw_mark(px, bg=TEAL).convert('RGB')
    written.append(save(img, f'{ios_dir}/{name}'))

print(f'{len(written)} files written')
for w in written[:6]:
    print(' ', w)
