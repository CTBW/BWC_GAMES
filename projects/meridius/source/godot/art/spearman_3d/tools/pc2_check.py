"""Check baked cape caches (.pc2) without Blender (needs numpy).

  python pc2_check.py low <cache dir> <clip> [<clip> ...]
      Per clip: vertices on the 1 cm ground clamp, the last frame's lowest point and the
      largest single-frame vertex jump (pops during a fall show here).
  python pc2_check.py diff <a.pc2> <b.pc2>
      Largest and mean vertex distance between two bakes (the sim is deterministic, so a
      re-bake of an unchanged clip gives 0).
"""
import struct, sys
from pathlib import Path
import numpy as np


def load(p):
    raw = open(p, "rb").read(); _, _, n, _, _, ns = struct.unpack("<12siiffi", raw[:32])
    return np.frombuffer(raw[32:], dtype="<f4").reshape(ns, n, 3)


if sys.argv[1] == "low":
    for c in sys.argv[3:]:
        a = load(Path(sys.argv[2]) / f"{c}.pc2")
        z = a[..., 2]
        on = (z <= 0.0101).sum(axis=1)
        near = (z <= 0.03).sum(axis=1)
        fr = np.nonzero(on)[0]
        step = np.linalg.norm(np.diff(a, axis=0), axis=2).max(axis=1)
        print(f"{c}: frames {len(a)}, lowest {z.min():.3f} m, on clamp (z<=1cm) max {on.max()} verts" + (f" in frames {fr[0]+1}-{fr[-1]+1}" if len(fr) else "") +
              f", <=3cm last frame {near[-1]}, last-frame min z {z[-1].min():.3f}, max vert step {step.max():.3f} m at f{step.argmax()+2}")
elif sys.argv[1] == "diff":
    a, b = load(sys.argv[2]), load(sys.argv[3])
    print("shapes", a.shape, b.shape)
    if a.shape == b.shape:
        d = np.linalg.norm(a - b, axis=2); print("max diff %.4f m, mean %.5f m" % (d.max(), d.mean()))
else:
    sys.exit(__doc__)
