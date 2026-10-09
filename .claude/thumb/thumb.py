import math, sys
from PIL import Image, ImageDraw, ImageFont, ImageChops
REPO = sys.argv[1]; OUT = sys.argv[2]
S = 2048                      # supersampled; final 1024
RED = (200, 30, 30); DARK = (176, 24, 24); WHITE = (255, 255, 255)
img = Image.new("RGB", (S, S), RED)
d = ImageDraw.Draw(img)

# Faint gear, bottom right, cropped by the frame (mobility motif).
def gear(cx, cy, r_out, r_in, r_hole, teeth, col):
    pts = []
    for i in range(teeth * 4):
        a = 2 * math.pi * i / (teeth * 4)
        r = r_out if i % 4 in (1, 2) else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts, fill=col)
    d.ellipse((cx - r_hole, cy - r_hole, cx + r_hole, cy + r_hole), fill=RED)
gear(1720, 1760, 760, 650, 300, 18, DARK)
gear(330, 1960, 420, 350, 150, 12, DARK)

# ACE wordmark from the canary logo (white on red -> alpha mask).
src = Image.open(f"{REPO}/ace_logo_canary.png").convert("RGB").crop((70, 245, 570, 372))
mask = ImageChops.subtract(src.split()[2], Image.new("L", src.size, 30)).point(lambda v: min(255, v * 255 // 225))
W = 1500; H = round(mask.height * W / mask.width)
mask = mask.resize((W, H), Image.LANCZOS)
img.paste(WHITE, ((S - W) // 2, 470, (S - W) // 2 + W, 470 + H), mask)

EXO = r"C:/Users/dyer0/AppData/Local/Microsoft/Windows/Fonts/Exo2-VariableFont_wght.ttf"
def centred(text, y, size, wght=700, fill=WHITE, track=0):
    f = ImageFont.truetype(EXO, size); f.set_variation_by_axes([wght])
    if track:
        widths = [d.textlength(c, font=f) for c in text]
        total = sum(widths) + track * (len(text) - 1); x = (S - total) / 2
        for c, w in zip(text, widths):
            d.text((x, y), c, font=f, fill=fill); x += w + track
    else:
        d.text(((S - d.textlength(text, font=f)) / 2, y), text, font=f, fill=fill)
centred("Customs", 800, 400, wght=800)
d.rectangle((S / 2 - 520, 1355, S / 2 + 520, 1365), fill=WHITE)
centred("MOBILITY  ·  DRIVETRAIN  ·  THERMAL", 1400, 80, wght=600, track=8)

img.resize((1024, 1024), Image.LANCZOS).save(OUT, optimize=True)
