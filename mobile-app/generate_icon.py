"""
App launcher icon — purple gradient + white map pin + green dot
Simple, reliable approach using numpy for gradient + PIL for drawing
"""
from PIL import Image, ImageDraw
import math

S = 1024
OUT = "assets/images/app_icon.png"

# ── 1. Start with solid purple base ─────────────────────────────────────────
img  = Image.new("RGB", (S, S), (0x4F, 0x46, 0xE5))
draw = ImageDraw.Draw(img)

# Manual diagonal gradient by drawing horizontal lines with interpolated colour
c1 = (0x4F, 0x46, 0xE5)  # #4F46E5
c2 = (0x7C, 0x3A, 0xED)  # #7C3AED
for i in range(S):
    t = i / (S - 1)
    r = int(c1[0] + (c2[0] - c1[0]) * t)
    g = int(c1[1] + (c2[1] - c1[1]) * t)
    b = int(c1[2] + (c2[2] - c1[2]) * t)
    draw.line([(0, i), (S, i)], fill=(r, g, b))

# ── 2. Apply rounded rect mask ───────────────────────────────────────────────
img_rgba = img.convert("RGBA")
mask     = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(
    [0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=255
)
img_rgba.putalpha(mask)

draw = ImageDraw.Draw(img_rgba)

# ── 3. MAP PIN — drawn large and centred ─────────────────────────────────────
# Pin head centre
cx   = S // 2
cy   = int(S * 0.40)
hr   = int(S * 0.21)   # head outer radius
ir   = int(S * 0.085)  # inner hole radius
tip_y = cy + int(S * 0.30)  # tail tip y

WHITE = (255, 255, 255, 255)

# Build teardrop polygon: upper arc + tail tip
def arc_pts(cx, cy, r, deg_start, deg_end, steps=120):
    pts = []
    for i in range(steps + 1):
        a = math.radians(deg_start + (deg_end - deg_start) * i / steps)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

# Arc from bottom-left to bottom-right going over the top
arc    = arc_pts(cx, cy, hr, 210, 330, 120)
tip    = (float(cx), float(tip_y))
teardrop = arc + [tip]

# Draw filled white teardrop
draw.polygon(teardrop, fill=WHITE)
# Fill the full circle head (covers any polygon gaps)
draw.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=WHITE)

# ── 4. Inner hole — exact gradient colour at pin centre ──────────────────────
t_c  = cy / (S - 1)   # use vertical position for colour
hc_r = int(c1[0] + (c2[0] - c1[0]) * t_c)
hc_g = int(c1[1] + (c2[1] - c1[1]) * t_c)
hc_b = int(c1[2] + (c2[2] - c1[2]) * t_c)
hole_colour = (hc_r, hc_g, hc_b, 255)
draw.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], fill=hole_colour)

# ── 5. Green dot — bottom-right of pin head, overlapping ─────────────────────
# Position at 45° from centre of head, at 75% of head radius
dot_angle = math.radians(40)
dot_dist  = int(hr * 0.72)
dot_cx    = cx + int(dot_dist * math.cos(dot_angle))
dot_cy    = cy + int(dot_dist * math.sin(dot_angle))
dot_r     = int(S * 0.055)
dot_border = int(S * 0.020)

# White ring
draw.ellipse(
    [dot_cx - dot_r - dot_border, dot_cy - dot_r - dot_border,
     dot_cx + dot_r + dot_border, dot_cy + dot_r + dot_border],
    fill=WHITE
)
# Green fill
draw.ellipse(
    [dot_cx - dot_r, dot_cy - dot_r,
     dot_cx + dot_r, dot_cy + dot_r],
    fill=(0x34, 0xD3, 0x99, 255)
)

# ── 6. Save ──────────────────────────────────────────────────────────────────
img_rgba.save(OUT, "PNG")
print(f"Saved {OUT}")

# Also open a quick preview
img_rgba.resize((256, 256), Image.LANCZOS).save("/tmp/icon_preview_256.png")
print("Preview saved to /tmp/icon_preview_256.png")
