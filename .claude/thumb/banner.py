import math, sys
from PIL import Image, ImageDraw, ImageFont, ImageChops
REPO = sys.argv[1]; OUT = sys.argv[2]
SW, SH = 3840, 2160           # supersampled; final 1920x1080
RED = (200, 30, 30); DARK = (176, 24, 24); WHITE = (255, 255, 255)
img = Image.new("RGB", (SW, SH), RED)
d = ImageDraw.Draw(img)
def gear(cx, cy, r_out, r_in, r_hole, teeth):
    pts = []
    for i in range(teeth * 4):
        a = 2 * math.pi * i / (teeth * 4)
        r = r_out if i % 4 in (1, 2) else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts, fill=DARK)
    d.ellipse((cx - r_hole, cy - r_hole, cx + r_hole, cy + r_hole), fill=RED)
gear(3380, 1900, 900, 770, 350, 20)
gear(420, 2080, 520, 440, 190, 14)
gear(3650, 260, 380, 320, 130, 12)
src = Image.open(f"{REPO}/ace_logo_canary.png").convert("RGB").crop((70, 245, 570, 372))
mask = ImageChops.subtract(src.split()[2], Image.new("L", src.size, 30)).point(lambda v: min(255, v * 255 // 225))
W = 1700; H = round(mask.height * W / mask.width)
mask = mask.resize((W, H), Image.LANCZOS)
y0 = 430
img.paste(WHITE, ((SW - W) // 2, y0, (SW - W) // 2 + W, y0 + H), mask)
EXO = r"C:/Users/dyer0/AppData/Local/Microsoft/Windows/Fonts/Exo2-VariableFont_wght.ttf"
def centred(text, y, size, wght=700, track=0):
    f = ImageFont.truetype(EXO, size); f.set_variation_by_axes([wght])
    widths = [d.textlength(c, font=f) for c in text]
    total = sum(widths) + track * (len(text) - 1); x = (SW - total) / 2
    for c, w in zip(text, widths):
        d.text((x, y), c, font=f, fill=WHITE); x += w + track
centred("Customs", y0 + H + 40, 460, wght=800)
ly = y0 + H + 660
d.rectangle((SW / 2 - 640, ly, SW / 2 + 640, ly + 12), fill=WHITE)
centred("MOBILITY  ·  DRIVETRAIN  ·  THERMAL", ly + 50, 96, wght=600, track=10)
img.resize((1920, 1080), Image.LANCZOS).save(OUT, quality=92)
