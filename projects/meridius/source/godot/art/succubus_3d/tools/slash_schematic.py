"""Draws the whip-slash schematic (an SVG) from slash_schematic_blend.py's renders and data.

  python art/succubus_3d/tools/slash_schematic.py <render dir> <out.svg>

Rasterize the SVG with a browser at its own size (1800 x 3190). Three parts: how the lash
extends (the whip straight at attack frames 16-22, and the coil's and lash's scale keys),
the two strikes from the game camera for facing SE (the lash on every frame round the
strike beside the strike's effects drawn at their peak), and the effect layers with their
timing. The effects follow the rules and numbers of the Godot prototype
(prototypes/footman_anim/scripts/whip_fx.gd), on the clip's own lash path. Needs numpy.
"""
import base64, json, math, sys
from pathlib import Path
import numpy as np

# whip_fx.gd
PATH_HZ, INNER_U, LEAD_MAX, TAIL_MAX = 240.0, 0.5, 0.12, 0.06
SMEAR_LIFE, MIN_W = 0.22, 0.3
STAR_R, STAR_LIFE, RING_R, RING_LIFE, STREAK_LIFE = 0.4, 0.16, (0.12, 0.65), 0.24, 0.16
GROUND_H, DUST_LIFE, TRAIL_S, TRAIL_SPEED = 0.25, 0.42, 0.05, 15.0
INK, RIM, HOT, DEEP = "#3b1232", "#fff2f8", "#f25eaf", "#9a3dc4"
DUST, DUST_INK = "#e9d7b2", "#5c4027"
TILE = 2.72                      # the sandbox's tile (m)
# the moments the peak drawing shows (s after each burst is born)
STAR_AGE, RING_AGE, STREAK_AGE, SLAP_AGE = 0.032, 0.08, 0.06, 0.15
STREAK_RAYS = ((-0.95, 1.1), (-0.55, 0.8), (-0.18, 1.25), (0.2, 0.9), (0.6, 1.15), (1.0, 0.75))
PUFF_RAYS = ((0.3, 1.0), (1.57 - 0.5, 0.8), (3.14 + 0.7, 1.2), (4.71 - 0.2, 0.9))

TXT, MUTED, LINE, PAPER, CARD, VIEW = "#2a2230", "#6d6375", "#d9d2c8", "#f6f3ee", "#ffffff", "#fbfaf7"
PINK, STEEL, AHEAD, BEHIND = "#d9468f", "#5d5566", "#efe4d2", "#ece6f2"
FONT = "Segoe UI, Arial, sans-serif"
W, H = 1800, 3190

src = Path(sys.argv[1])
data = json.loads((src / "data.json").read_text())
view = json.loads((src / "view.json").read_text())
FPS = data["fps"]
fr = np.array([s["f"] for s in data["sub"]])
L = np.array([s["lash"] for s in data["sub"]])             # (n, 17, 3), Blender: she faces -Y, Z up
tip = L[:, -1]
vel = np.gradient(tip, axis=0) * PATH_HZ
spd = np.linalg.norm(vel, axis=1)
scales = np.array(data["scales"])                           # per frame: coil, Lash_1
RIGHT, UP = np.array(view["se"]["right"]), np.array(view["se"]["up"])


def t_of(f):
    return (f - 1) / FPS


def along(u):
    k = u * 16
    i = int(k)
    return L[:, i] * (1 - (k - i)) + L[:, min(i + 1, 16)] * (k - i)


INNER = along(INNER_U)


def strikes():
    """whip_fx.gd _sample: each strike's sweep (a..b), crack (i) and ground slap (g)."""
    out = []
    for c in data["events"]["strikes"]:
        c = round(c * FPS) / FPS
        i = int(np.argmin(abs(fr - (c * FPS + 1))))
        vc = vel[i] / spd[i]
        a = i
        while a > 1 and (i - a + 1) / PATH_HZ <= LEAD_MAX and vel[a - 1] @ vc > 0:
            a -= 1
        b = i
        while b < len(fr) - 2 and (b + 1 - i) / PATH_HZ <= TAIL_MAX and vel[b + 1] @ vc > 0:
            b += 1
        g = next((j for j in range(i, min(len(fr), i + int(0.12 * PATH_HZ))) if tip[j, 2] < GROUND_H), -1)
        out.append({"at": c, "i": i, "a": a, "b": b, "g": g})
    return out


STRIKES = strikes()


def where(p):
    fb = f"{-p[1]:.1f} m ahead" if p[1] < 0 else f"{p[1]:.1f} m behind her"
    side = f", {abs(p[0]):.1f} m to her {'left' if p[0] > 0 else 'right'}" if abs(p[0]) >= 0.3 else ""
    return fb + side


# --- svg helpers ------------------------------------------------------------------
svg = []
HALO = 'paint-order="stroke" stroke="#fbfaf7" stroke-width="5" stroke-linejoin="round"'


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, size=17, fill=TXT, weight=400, anchor="start", extra=""):
    svg.append(f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" font-weight="{weight}" '
               f'text-anchor="{anchor}" {extra}>{esc(s)}</text>')


def para(x, y, s, width, size=17, fill=TXT, lh=1.42, weight=400):
    """Wrapped at about `width` px; returns the y of the next line."""
    per = max(10, int(width / (size * 0.52)))
    lines, cur = [], ""
    for w in s.split():
        if len(cur) + len(w) + 1 > per and cur:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    lines.append(cur)
    for k, ln in enumerate(lines):
        text(x, y + k * size * lh, ln, size, fill, weight)
    return y + len(lines) * size * lh


def pts_str(pts):
    return " ".join(f"{p[0]:.1f},{p[1]:.1f}" for p in pts)


def poly(pts, fill="none", stroke="none", sw=1.0, op=1.0):
    svg.append(f'<polygon points="{pts_str(pts)}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{op}" '
               f'stroke-linejoin="round"/>')


def pline(pts, stroke=TXT, sw=1.5, op=1.0, dash=""):
    da = f'stroke-dasharray="{dash}"' if dash else ""
    svg.append(f'<polyline points="{pts_str(pts)}" fill="none" stroke="{stroke}" stroke-width="{sw}" opacity="{op}" '
               f'stroke-linecap="round" stroke-linejoin="round" {da}/>')


def line(a, b, stroke=TXT, sw=1.5, dash="", op=1.0):
    pline([a, b], stroke, sw, op, dash)


def circle(c, r, fill="none", stroke="none", sw=1.0, op=1.0):
    svg.append(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r:.1f}" fill="{fill}" stroke="{stroke}" '
               f'stroke-width="{sw}" opacity="{op}"/>')


def rect(x, y, w, h, fill=CARD, stroke=LINE, r=10, sw=1.0):
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')


def band(outer, inner, fill):
    """The area between two closed outlines."""
    d = "M" + " L".join(f"{p[0]:.1f},{p[1]:.1f}" for p in outer) + " Z M" + " L".join(f"{p[0]:.1f},{p[1]:.1f}" for p in inner) + " Z"
    svg.append(f'<path d="{d}" fill="{fill}" fill-rule="evenodd"/>')


def image(path, x, y, w, h):
    b = base64.b64encode(Path(path).read_bytes()).decode()
    svg.append(f'<image x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" href="data:image/png;base64,{b}"/>')


def arrow_head(p, d, size=11, fill=TXT):
    d = np.array(d, float)
    d /= np.linalg.norm(d) + 1e-9
    n = np.array([-d[1], d[0]])
    p = np.array(p, float)
    poly([p + d * size * 0.4, p - d * size * 0.6 + n * size * 0.5, p - d * size * 0.6 - n * size * 0.5], fill)


def badge(c, n, r=13):
    circle(c, r + 2, "#fff")
    circle(c, r, TXT)
    text(c[0], c[1] + 5.5, str(n), 15, "#fff", 700, "middle")


def callout(anchor, at, lines, size=15, side="start"):
    x, y = at
    line(anchor, (x - 5 if side == "start" else x + 5 if side == "end" else x, y - size * 0.4 if side != "middle" else y + 6), MUTED, 1.2)
    circle(anchor, 3, TXT)
    for k, (s, wgt) in enumerate(lines):
        text(x, y + k * size * 1.3, s, size, TXT if k == 0 else MUTED, wgt, side)


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


# --- the effects at their peak, on screen ------------------------------------------
def crescent(P, s):
    """The slash, every sample laid and none closing yet (whip_fx.gd _smear)."""
    js = list(range(s["a"], s["b"] + 1))
    u = (np.array(js) - s["a"]) / max(s["b"] - s["a"], 1)
    w = np.sin(np.pi * u) ** 0.7
    O = np.array([P(p) for p in tip[js]])
    I = np.array([P(p) for p in tip[js] + (INNER[js] - tip[js]) * w[:, None]])
    alo = np.gradient(O, axis=0)
    side = np.stack([-alo[:, 1], alo[:, 0]], 1)
    side /= np.linalg.norm(side, axis=1)[:, None] + 1e-9
    sgn = 1 if np.sum((I - O) * side) >= 0 else -1
    for j in range(len(js)):                       # at least MIN_W across the path
        d = (I[j] - O[j]) @ side[j] * sgn
        if d < MIN_W * P.k * w[j]:
            I[j] += side[j] * sgn * (MIN_W * P.k * w[j] - d)
    f = np.linspace(0, 1, len(js))
    rim_from = np.array([lerp(0.8, 0.62, smoothstep(0.7, 1.0, x)) for x in f])
    one = np.ones_like(f)
    for v0, v1, col, op in ((0.12 * one, 0.25 * one, DEEP, 0.45), (0.25 * one, 0.45 * one, DEEP, 1),
                            (0.45 * one, rim_from, HOT, 1), (rim_from, 0.94 * one, RIM, 1), (0.94 * one, one, INK, 1)):
        poly(list(I + (O - I) * v1[:, None]) + list((I + (O - I) * v0[:, None])[::-1]), col, col, 0.6, op)
    return O, I


def star(c, d, r):
    a0 = math.atan2(d[1], d[0])
    for scale, col in ((1.0, INK), (0.78, HOT), (0.5, RIM)):
        pts = []
        for k in range(240):
            a = k / 240 * math.tau
            m = abs(math.cos(a)) ** 14
            sd = 0.62 * abs(math.sin(a)) ** 14
            dg = 0.4 * max(abs(math.cos(a - 0.785)) ** 18, abs(math.cos(a + 0.785)) ** 18)
            rr = (0.26 + 0.74 * max(m, sd, dg)) * r * scale
            pts.append((c[0] + rr * math.cos(a + a0), c[1] + rr * math.sin(a + a0)))
        poly(pts, col)


def ring(c, r, th):
    """Camera-facing ring: hot band from r(1-th) to r, rim in its middle half."""
    circle(c, r * (1 - th / 2), "none", HOT, r * th)
    circle(c, r * (1 - th / 2), "none", RIM, r * th / 2)


def flat_ring(P, at, r, th):
    """A ring lying on the ground, seen from the camera."""
    def loop(rad):
        return [P(at + rad * np.array([math.cos(q), math.sin(q), 0])) for q in np.linspace(0, math.tau, 64, endpoint=False)]
    band(loop(r), loop(r * (1 - th)), HOT)
    band(loop(r * (1 - th * 0.25)), loop(r * (1 - th * 0.75)), RIM)


def streaks(c, d, k_px, age):
    a0 = math.atan2(d[1], d[0])
    ks = age / STREAK_LIFE
    for off, sp in STREAK_RAYS:
        e = np.array([math.cos(a0 + off), math.sin(a0 + off)])
        p0 = np.array(c) + e * (0.12 + 4.5 * sp * age) * k_px
        p1 = p0 + e * 0.3 * sp * (1 - ks) * k_px
        pline([p0, p1], HOT, 0.036 * k_px, 1)
        pline([p0, p1], RIM, 0.016 * k_px, 1)


def puff(c, r):
    circle(c, r * 0.87, DUST, DUST_INK, r * 0.26)


def effects(P, s):
    i, g = s["i"], s["g"]
    K = P.k
    O, I = crescent(P, s)
    cp = P(tip[i])
    d_scr = P(tip[i] + vel[i] * 0.01) - cp
    kr = RING_AGE / RING_LIFE
    ring(cp, lerp(RING_R[0], RING_R[1], 1 - (1 - kr) ** 2) * K, lerp(0.35, 0.08, kr))
    streaks(cp, d_scr, K, STREAK_AGE)
    k = STAR_AGE / STAR_LIFE
    star(cp, d_scr, STAR_R * (lerp(0.8, 1.2, k / 0.2) if k < 0.2 else lerp(1.2, 0.0, (k - 0.2) / 0.8)) * K)
    gp = None
    if g >= 0:
        gp = np.array([tip[g, 0], tip[g, 1], 0.02])
        k = SLAP_AGE / DUST_LIFE
        ease = 1 - (1 - k) ** 2
        flat_ring(P, gp, lerp(0.1, 0.7, ease), lerp(0.5, 0.1, k))
        for ang, sp in PUFF_RAYS:
            pp = gp + np.array([math.cos(ang), math.sin(ang), 0]) * (0.15 + 0.9 * ease * sp) + np.array([0, 0, 0.08 + 0.25 * k])
            puff(P(pp), 0.11 * (1 + 0.6 * k) * K)
    return O, I, cp, d_scr, gp


class Proj:
    """The SE game camera into a view: render shot `shot` drawn at (x, y), k px per metre."""
    def __init__(self, shot, x, y, k):
        self.s, self.x, self.y, self.k = view["se"]["shots"][shot], x, y, k
        self.w, self.h = self.s["w"] * k, self.s["h"] * k

    def __call__(self, p):
        p = np.asarray(p, float)
        return np.array([self.x + (p @ RIGHT - (self.s["cx"] - self.s["w"] / 2)) * self.k,
                         self.y + ((self.s["cy"] + self.s["h"] / 2) - p @ UP) * self.k])

    def inside(self, q, m=60):
        return self.x + m < q[0] < self.x + self.w - m and self.y + m < q[1] < self.y + self.h - m


def ground(P, cid):
    """Tiles round her, the tile ahead and the one behind tinted and named."""
    svg.append(f'<clipPath id="{cid}"><rect x="{P.x:.1f}" y="{P.y:.1f}" width="{P.w:.1f}" height="{P.h:.1f}" rx="8"/></clipPath>')
    svg.append(f'<rect x="{P.x:.1f}" y="{P.y:.1f}" width="{P.w:.1f}" height="{P.h:.1f}" rx="8" fill="{VIEW}" stroke="{LINE}"/>')
    svg.append(f'<g clip-path="url(#{cid})">')
    T = TILE
    for sgn, col in ((-1, AHEAD), (1, BEHIND)):
        poly([P((x, sgn * y, 0)) for x, y in ((-T / 2, T / 2), (T / 2, T / 2), (T / 2, 1.5 * T), (-T / 2, 1.5 * T))], col)
    for k in range(-4, 5):
        line(P(((k + 0.5) * T, -4 * T, 0)), P(((k + 0.5) * T, 4 * T, 0)), "#d6cdc0", 1.2)
        line(P((-4 * T, (k + 0.5) * T, 0)), P((4 * T, (k + 0.5) * T, 0)), "#d6cdc0", 1.2)
    for sgn, name, col in ((-1, "the tile ahead", "#9a8263"), (1, "the tile behind her", "#8a7a9c")):
        best = None
        for x in np.linspace(-0.35, 0.35, 8) * T:
            for y in np.linspace(0.62, 1.38, 9) * T:
                q = P((x, sgn * y, 0))
                dist = abs(x) + abs(y - T)
                if P.inside(q, 70) and (best is None or dist < best[0]):
                    best = (dist, q)
        if best:
            text(best[1][0], best[1][1], name, 15, col, 600, "middle", HALO)
    feet = P((0, 0, 0))
    svg.append(f'<ellipse cx="{feet[0]:.1f}" cy="{feet[1]:.1f}" rx="{0.42 * P.k:.1f}" ry="{0.21 * P.k:.1f}" fill="#3b2a30" opacity="0.16"/>')


# --- page ----------------------------------------------------------------------------
svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{FONT}">')
svg.append(f'<rect width="{W}" height="{H}" fill="{PAPER}"/>')
text(40, 58, "Succubus whip · the extending slash", 36, TXT, 700)
text(40, 92, "A code-drawn schematic from the attack clip (succubus_anim.blend, 30 fps). The effects follow the Godot "
     "prototype's rules (whip_fx.gd) on the same lash path.", 18, MUTED)

# 1 · extending -------------------------------------------------------------------------
y0 = 120
rect(20, y0, 1760, 560)
text(44, y0 + 40, "1 · How the lash extends", 24, TXT, 700)
text(44, y0 + 66, "The whip straightened, keyed as at attack frames 16-22 (in the clip it curls through the air "
     "while it grows).", 16, MUTED)
wv = view["whip"]
SC = 0.92
wppm = wv["ppm"] * SC
ww, wh = (wv["x1"] - wv["x0"]) * wppm, (wv["y1"] - wv["y0"]) * wppm
wx = 250
row0 = y0 + 100
RS = 100
for r, f in enumerate((16, 18, 20, 22)):
    ry = row0 + r * RS
    c, g = wv["frames"][str(f)]["coil"], wv["frames"][str(f)]["lash"]
    text(44, ry + 48, f"frame {f}", 19, TXT, 700)
    text(44, ry + 72, f"{t_of(f):.2f} s", 16, MUTED)
    text(140, ry + 48, f"coil {c * 100:.0f} %", 16, STEEL, 600)
    text(140, ry + 72, f"lash {g * 100:.0f} %", 16, PINK, 600)
    image(src / f"whip_{f}.png", wx, ry, ww, wh)


def wx_at(s):
    return wx + (s - wv["x0"]) * wppm


ax_y = row0 + 3 * RS + wv["y1"] * wppm              # the lash's axis on the last row
line((wx_at(0), row0 + 4), (wx_at(0), ax_y + 30), MUTED, 1.2, "4 4")
ty = ax_y + 38
for k, s in enumerate(wv["ticks"]):
    line((wx_at(s), ty - 8), (wx_at(s), ty), MUTED, 1.2)
    if k in (4, 8, 12, 16):
        text(wx_at(s), ty + 18, f"{s:.1f} m", 14, MUTED, 400, "middle")
text(wx_at(0), ty + 18, "collar", 14, TXT, 600, "middle")
line((wx_at(0), ty - 4), (wx_at(2.0), ty - 4), MUTED, 1.2)
text(wx_at(1.0), ty + 42, "16 lash bones (Lash_1 … Lash_16), 12.5 cm each: 2 m out of the collar", 15, TXT, 600, "middle")
callout((wx_at(0.2), row0 + 30), (wx_at(0.42), row0 + 22), [("the coil, on its own bone (WhipCoil)", 600), ("rolls up into the collar a frame ahead of the lash", 400)], 14)
callout((wx_at(-0.17), row0 + 3 * RS + 34), (wx_at(-0.17), row0 + 3 * RS - 2), [("the handle stays in her fist", 600)], 14, "middle")
callout((wx_at(0.53), ax_y - 20), (wx_at(0.62), ax_y - 54), [("blades in pairs, three a bone, spiralling", 600)], 14)
callout((wx_at(1.72), ax_y - 8), (wx_at(1.72), ax_y - 56), [("gold ferrule, 86 %", 600)], 14, "middle")
callout((wx_at(1.985), ax_y - 2), (wx_at(1.985) + 8, ax_y - 34), [("hooked tip", 600)], 14, "start")

cx0, cy0, cw, ch = 1340, y0 + 118, 185, 150
for n, (fa, fb, title, marks) in enumerate(((14, 24, "out · frames 14-24", (16, 18, 20, 22)), (60, 72, "in · frames 60-72", ()))):
    gx = cx0 + n * (cw + 30)
    text(gx, cy0 - 14, title, 15, TXT, 600)
    svg.append(f'<rect x="{gx}" y="{cy0}" width="{cw}" height="{ch}" fill="#faf8f5" stroke="{LINE}"/>')
    X = lambda f: gx + (f - fa) / (fb - fa) * cw
    Y = lambda v: cy0 + ch * (1 - v)
    line((gx, Y(0.5)), (gx + cw, Y(0.5)), LINE, 1)
    for f in marks:
        line((X(f), cy0), (X(f), cy0 + ch), "#c9bfb2", 1, "3 3")
    for col, idx in ((STEEL, 0), (PINK, 1)):
        pline([(X(f), Y(scales[f - 1, idx] if scales[f - 1, idx] > 0.002 else 0)) for f in range(fa, fb + 1)], col, 3)
    for f in range(fa, fb + 1, 2):
        text(X(f), cy0 + ch + 18, str(f), 12, MUTED, 400, "middle")
ly = cy0 + ch + 46
text(cx0, ly, "scale", 14, MUTED)
line((cx0 + 44, ly - 5), (cx0 + 70, ly - 5), STEEL, 3)
text(cx0 + 76, ly, "coil", 14, STEEL, 600)
line((cx0 + 118, ly - 5), (cx0 + 144, ly - 5), PINK, 3)
text(cx0 + 150, ly, "lash (Lash_1)", 14, PINK, 600)
para(cx0, ly + 34, "Lash_1 grows out of the collar and the other fifteen bones inherit its scale, so the whole "
     "lash slides out at full shape, then moves as a whip driven by her hand. Coil and lash are two meshes on one "
     "handle: nothing is spawned. The collar is 9.5 cm from the pommel.", 410, 15, TXT)

# 2 · the strikes -----------------------------------------------------------------------
K = 150
INFO = [
    {"title": "Strike 1 · overhand, forward and down", "shot": "27",
     "intro": "Her hand throws forward and down from above her left shoulder. The lash, laid back over her shoulder, "
              "rolls over in a loop that runs out to the tip and snaps straight towards the tile ahead. Then it "
              "recoils in an S-wave, droops and lies on the ground by her hand."},
    {"title": "Strike 2 · underhand, rising forward", "shot": "52",
     "intro": "From her hip her hand sweeps forward and up. The lash, lying on the ground behind her, is dragged up "
              "into a loop that snaps straight towards the tile ahead. Her arm stops there and sinks, and the lash "
              "recoils, droops and hangs from her hand in front of her."},
]


def on_tile_ahead(p):
    return TILE / 2 <= -p[1] <= 1.5 * TILE and abs(p[0]) <= TILE / 2
yS = y0 + 580
for n, s in enumerate(STRIKES):
    info = INFO[n]
    py = yS + n * 820
    rect(20, py, 1760, 800)
    i, a, b, g = s["i"], s["a"], s["b"], s["g"]
    fc = round(s["at"] * FPS + 1)
    text(44, py + 40, f"2.{n + 1} · {info['title']}", 24, TXT, 700)
    text(44, py + 66, f"Crack at frame {fc} ({s['at']:.2f} s) · the slash is laid over frames {fr[a]:.1f}-{fr[b]:.1f} · "
         f"seen from the game camera for facing SE", 16, MUTED)
    f_lo, f_hi = int(math.floor(fr[a])) - 1, int(math.ceil(fr[b])) + 1
    for v, cap in enumerate((f"The motion · the lash at frames {f_lo}-{f_hi}", "The effects · each at its peak")):
        P = Proj(info["shot"], 44 + v * 680, py + 92, K)
        ground(P, f"c{n}{v}")
        image(src / f"her_{info['shot']}.png", P.x, P.y, P.w, P.h)
        jj = [j for j in range(len(fr)) if f_lo <= fr[j] <= f_hi]
        path = [P(tip[j]) for j in jj]
        if v == 0:
            hand = [P(L[j, 0]) for j in jj]
            pline(hand, STEEL, 2, 0.8, "2 5")
            arrow_head(hand[-1], hand[-1] - hand[-5], 12, STEEL)
            frames = list(range(f_lo, f_hi + 1))
            for q, f in enumerate(frames):
                j = int(np.argmin(abs(fr - f)))
                tc = q / max(len(frames) - 1, 1)
                col = "#%02x%02x%02x" % tuple(int(lerp(c0, c1, tc)) for c0, c1 in ((0xc6, 0x4a), (0xb9, 0x3a), (0xd2, 0x58)))
                if f != fc:
                    pline([P(p) for p in L[j]], col, 2.2, 0.95)
            pline(path, PINK, 2.6, 1, "8 6")
            for q in (len(path) // 4, len(path) * 3 // 4):
                arrow_head(path[q], path[q + 1] - path[q - 1], 16, PINK)
            for f in frames:
                e = P(tip[int(np.argmin(abs(fr - f)))])
                circle(e, 4.5 if f == fc else 3.5, PINK if f == fc else TXT)
                text(e[0] + 8, e[1] - 7, str(f), 15 if f == fc else 14, PINK if f == fc else TXT, 700, "start", HALO)
            hp = P(L[i, 0])
            text(hp[0] + 10, hp[1] - 12, "her hand", 14, STEEL, 600, "start", HALO)
        else:
            pline(path, TXT, 1.6, 0.35, "6 6")
            O, I, cp, d_scr, gp = effects(P, s)
            mid = len(O) // 3
            badge(O[mid] + (I[mid] - O[mid]) * 0.5, 1)
            nrm = np.array([-d_scr[1], d_scr[0]]) / (np.linalg.norm(d_scr) + 1e-9)
            badge(cp + nrm * 0.62 * K * (1 if nrm[1] < 0 else -1), 2)
            if gp is not None:
                badge(P(gp) + np.array([0, 0.62 * K * 0.5 + 28]), 3)
        svg.append("</g>")
        text(P.x + 12, P.y + 26, cap, 15, TXT, 700, "start", HALO)
    nx, ny = 1424, py + 104
    ny = para(nx, ny, info["intro"], 330, 15.5, TXT) + 14
    notes = [
        ("Slash crescent", f"Laid over frames {fr[a]:.1f}-{fr[b]:.1f} ({(fr[b] - fr[a]) / FPS:.2f} s): the outer half of "
                           f"the lash, swept, widest at the crack. Each piece closes onto the tip's path 0.22 s after it "
                           f"was laid; gone by {t_of(fr[b]) + SMEAR_LIFE:.2f} s."),
        (f"Crack · frame {fc}", f"At the tip, {where(tip[i])}, {tip[i, 2]:.1f} m up, moving at {spd[i]:.0f} m/s. Star "
                                f"0.16 s, shock ring 0.24 s, six streaks along its travel."),
    ]
    if g >= 0:
        notes.append((f"Ground slap · frame {fr[g]:.1f}", f"The tip reaches the ground {where(tip[g])}, "
                                                          f"{(fr[g] - fr[i]) / FPS:.2f} s after the crack: a dust ring and four puffs, 0.42 s."))
    for k, (ttl, body) in enumerate(notes):
        badge((nx + 13, ny - 5), k + 1)
        text(nx + 36, ny, ttl, 16.5, TXT, 700)
        ny = para(nx + 36, ny + 24, body, 294, 14.5, TXT) + 14
    ny += 6
    hit = on_tile_ahead(tip[i])
    vcol = "#2f7a4d" if hit else "#b0412f"
    verdict = (("A hit on the tile ahead." if hit else "Not on the tile ahead."),
               f"The crack is in the air over {'the tile ahead' if hit else 'another tile'}, {tip[i, 2]:.1f} m up "
               f"(the tile's centre is {TILE:.1f} m ahead). Both cracks aim at it.")
    svg.append(f'<rect x="{nx}" y="{ny - 4}" width="332" height="4" rx="2" fill="{vcol}"/>')
    text(nx, ny + 24, verdict[0], 16.5, vcol, 700)
    para(nx, ny + 48, verdict[1], 330, 14.5, TXT)

# 3 · layers and timing -------------------------------------------------------------------
y2 = yS + 2 * 820
rect(20, y2, 1760, 800)
text(44, y2 + 40, "3 · The effect layers and their timing", 24, TXT, 700)
text(44, y2 + 66, "All on the clip's clock, so they slow with the playback speed. The slash, crack and slap stay where "
     "they were laid if she moves on.", 16, MUTED)
cards = [
    ("Slash crescent", "Laid in world space while the clip passes a strike's sweep: from where the tip turns towards the "
     "strike (at most 0.12 s before) to where it turns away (0.06 s after). From the tip's path in to half the lash, "
     "widest at the strike. Each piece closes onto the tip's path 0.22 s after it was laid, oldest first."),
    ("Crack", "At the tip at the strike time (the sidecar's events.strikes, snapped to the frame). A star pops to 1.2 "
     "and shrinks away in 0.16 s, a shock ring opens from 0.12 to 0.65 m in 0.24 s, and six streaks fly out along "
     "the tip's travel."),
    ("Ground slap", "Where the tip next comes within 25 cm of the ground, at most 0.12 s after a strike: a flat dust "
     "ring opens to 0.7 m and four puffs drift out and up, 0.42 s. Neither crack of this attack does: both are in "
     "the air."),
    ("Tip trail", "While the lash is out and its tip moves faster than 15 m/s: a 3.5 cm streak along the tip's last "
     "0.05 s, tapering to its old end. It shows the loop running out to each crack."),
]
for k, (ttl, body) in enumerate(cards):
    cx = 44 + k * 432
    cy = y2 + 90
    svg.append(f'<rect x="{cx}" y="{cy}" width="412" height="270" rx="8" fill="#faf8f5" stroke="{LINE}"/>')
    ic = np.array([cx + 76, cy + 62])
    if k == 0:
        th = np.linspace(0.12, 0.88, 40) * math.pi
        O_ = np.array([ic + np.array([-math.cos(t) * 64, -math.sin(t) * 46 + 34]) for t in th])
        prof = np.sin(np.linspace(0, math.pi, 40)) ** 0.7
        I_ = np.array([o + (ic + np.array([0, 34]) - o) * 0.5 * p for o, p in zip(O_, prof)])
        for v0, v1, col, op in ((0.12, 0.25, DEEP, 0.45), (0.25, 0.45, DEEP, 1), (0.45, 0.78, HOT, 1), (0.78, 0.94, RIM, 1), (0.94, 1.0, INK, 1)):
            poly(list(I_ + (O_ - I_) * v1) + list((I_ + (O_ - I_) * v0)[::-1]), col, col, 0.6, op)
    elif k == 1:
        ring(ic, 40, 0.22)
        streaks(ic, (1, -0.25), 110, 0.05)
        star(ic, (1, -0.25), 30)
    elif k == 2:
        ell = lambda r: [ic + np.array([math.cos(q) * r, math.sin(q) * r * 0.5 + 10]) for q in np.linspace(0, math.tau, 48, endpoint=False)]
        band(ell(46), ell(30), HOT)
        band(ell(42), ell(34), RIM)
        for q in range(4):
            puff(ic + np.array([math.cos(q * 1.57 + 0.4) * 52, math.sin(q * 1.57 + 0.4) * 26 - 2]), 12)
    else:
        pts = [ic + np.array([-56 + x, 22 - 34 * math.sin(x / 112 * math.pi)]) for x in np.linspace(0, 112, 28)]
        for j in range(len(pts) - 1):
            wdt = 1 + 8 * j / len(pts)
            pline([pts[j], pts[j + 1]], HOT, wdt + 2.5)
            pline([pts[j], pts[j + 1]], RIM, wdt * 0.5)
    text(cx + 160, cy + 50, ttl, 20, TXT, 700)
    para(cx + 20, cy + 140, body, 376, 14.5, TXT, 1.42)

gx0, gx1 = 220, 1740
t0, t1 = 0.4, 2.5
gy = y2 + 440
X = lambda t: gx0 + (t - t0) / (t1 - t0) * (gx1 - gx0)
rows_y = {"lash": gy, "speed": gy + 50, "slash": gy + 128, "crack": gy + 162, "slap": gy + 200, "trail": gy + 234}
labels = {"lash": "coil · lash", "speed": "tip speed", "slash": "slash crescent", "crack": "crack: star · ring",
          "slap": "ground slap", "trail": "tip trail"}
for kname, yy in rows_y.items():
    text(gx0 - 16, yy + (30 if kname == "speed" else 14), labels[kname], 15, TXT, 600, "end")
fx = [(f, X(t_of(f))) for f in range(1, len(scales) + 1) if t0 <= t_of(f) <= t1]
base = rows_y["lash"] + 24
poly([(fx[0][1], base)] + [(x, base - 22 * scales[f - 1, 1]) for f, x in fx] + [(fx[-1][1], base)], PINK, "none", 1, 0.85)
pline([(x, base - 22 * scales[f - 1, 0]) for f, x in fx], STEEL, 2.2)
text(X(0.45), base - 28, "coil", 12.5, STEEL, 600)
text(X(1.4), base - 6, "lash out", 12.5, "#fff", 700, "middle")
sp_y = rows_y["speed"] + 56
shown = np.interp(fr, np.arange(1, len(scales) + 1), scales[:, 1])
sp = np.where(shown > 0.05, spd, 0)
SPK = 52 / 110
sel = [(f, v) for f, v in zip(fr, sp) if t0 <= t_of(f) <= t1]
poly([(X(t_of(sel[0][0])), sp_y)] + [(X(t_of(f)), sp_y - min(v, 110) * SPK) for f, v in sel] + [(X(t_of(sel[-1][0])), sp_y)], "#efcfe0", "#b0517f", 1.2)
line((gx0, sp_y - TRAIL_SPEED * SPK), (gx1, sp_y - TRAIL_SPEED * SPK), MUTED, 1, "4 4")
text(gx1 + 6, sp_y - TRAIL_SPEED * SPK + 4, "15 m/s", 11.5, MUTED)
for v in (50, 100):
    line((gx0 - 4, sp_y - v * SPK), (gx0, sp_y - v * SPK), MUTED, 1)
    text(gx0 + 4, sp_y - v * SPK + 4, f"{v}", 11.5, MUTED)


def span(ta, tb, yy, col, h=18, op=1.0, label=""):
    svg.append(f'<rect x="{X(ta):.1f}" y="{yy:.1f}" width="{max(X(tb) - X(ta), 2):.1f}" height="{h}" rx="3" fill="{col}" opacity="{op}"/>')
    if label:
        text(X(tb) + 8, yy + h / 2 + 4.5, label, 13, MUTED)


for n, s in enumerate(STRIKES):
    ta, tb = t_of(fr[s["a"]]), t_of(fr[s["b"]])
    span(ta, tb, rows_y["slash"], HOT)
    span(tb, tb + SMEAR_LIFE, rows_y["slash"], HOT, op=0.4, label=f"laid {fr[s['a']]:.1f}-{fr[s['b']]:.1f}, closing")
    span(s["at"], s["at"] + STAR_LIFE, rows_y["crack"], INK, 9)
    span(s["at"], s["at"] + RING_LIFE, rows_y["crack"] + 11, HOT, 9, label=f"frame {s['at'] * FPS + 1:.0f}")
    if s["g"] >= 0:
        tg = t_of(fr[s["g"]])
        span(tg, tg + DUST_LIFE, rows_y["slap"], "#c9a978", label=f"frame {fr[s['g']]:.1f}")
if all(s["g"] < 0 for s in STRIKES):
    text(X(STRIKES[0]["at"]), rows_y["slap"] + 14, "none: both cracks are in the air", 13, MUTED)
on = sp > TRAIL_SPEED
k = 0
while k < len(on):
    if on[k]:
        e = k
        while e + 1 < len(on) and on[e + 1]:
            e += 1
        span(t_of(fr[k]), t_of(fr[e]) + TRAIL_S, rows_y["trail"], "#f4a9cf", 14)
        k = e + 1
    else:
        k += 1
ax = gy + 268
line((gx0, ax), (gx1, ax), TXT, 1.2)
for f in range(15, 77, 5):
    line((X(t_of(f)), ax), (X(t_of(f)), ax + 6), TXT, 1)
    text(X(t_of(f)), ax + 22, f"f{f}", 12, MUTED, 400, "middle")
for t in np.arange(0.5, 2.51, 0.25):
    text(X(t), ax + 42, f"{t:.2f} s", 13, TXT, 600, "middle")
ev = data["events"]
for t, lab, row in ((ev["lash_out"], "lash out", 0), (STRIKES[0]["at"], "strike 1", 1), (STRIKES[1]["at"], "strike 2", 1),
                    (ev["lash_in"], "lash in", 0)):
    col = PINK if row else MUTED
    line((X(t), gy - 28 - 18 * row + 6), (X(t), ax), col, 1.2, "3 4")
    text(X(t), gy - 30 - 18 * row, f"{lab} · {t:.2f} s", 13, col, 700, "middle")
text(44, y2 + 776, "The clip runs 0-3.5 s; the lash is only out between the marks shown. Sidecar events (succubus.json, "
     f"clips.attack.events): lash_out {ev['lash_out']:.2f}, strikes {ev['strikes'][0]:.4g} and {ev['strikes'][1]:.4g}, "
     f"lash_in {ev['lash_in']:.2f} s. The game doesn't use them yet.", 14, MUTED)

text(40, H - 18, "Generated by art/succubus_3d/tools/slash_schematic.py from slash_schematic_blend.py's renders. "
     "Native Godot captures of the same effects: tests/visual/out/whip_slash/.", 14, MUTED)
svg.append("</svg>")
Path(sys.argv[2]).write_text("\n".join(svg), encoding="utf-8")
print("SCHEMATIC", sys.argv[2], [(float(fr[s['a']]), float(fr[s['b']]), float(fr[s['g']]) if s['g'] >= 0 else None) for s in STRIKES])
