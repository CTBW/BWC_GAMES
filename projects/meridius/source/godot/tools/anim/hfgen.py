"""Run squad sheets through the Higgsfield CLI (nano_banana_pro, 2K, 2 credits each).

  hfgen.py run <unit> <fac>:<frame> [<fac>:<frame> ...] [--again] [--no-cut] [--prompt-extra TEXT]
      Submit each sheet (in parallel), record its job id in art/raw/<unit>/jobs.json
      before waiting, download it to art/raw/<unit>/<fac>_<frame>.png (an earlier
      try is kept as <fac>_<frame>_tryN.png) and cut it (squadgen.py cut).
      A sheet that already has a job is not submitted again without --again.
  hfgen.py fetch <unit> <fac>:<frame>   Wait for / download the recorded job and cut it.
  hfgen.py auto <unit> [...]           Every sheet of each unit, stage by stage (each
                                        stage's sheets in parallel), skipping sheets
                                        already made; then squadgen.py build.
  hfgen.py spent                        Jobs and credits recorded so far.

Receipts: art/raw/<unit>/jobs.json (job ids, never committed).
Inputs come from squadgen.py prompt; a raw sheet of this unit with a finished
job is passed as that job id (the generator sees the original, not a re-upload),
other files as paths the CLI uploads itself. The Higgsfield CLI must be signed
in (knowledge/higgsfield-setup.md).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import threading
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import squadgen  # noqa: E402

_lock = threading.Lock()
# Cuts of one unit read and rewrite its facing's index.json: one at a time.
_cut_lock = threading.Lock()


def _receipts(unit):
    """One receipt file per unit (art/raw/<unit>/jobs.json): one process per unit
    writes it, so parallel units cannot overwrite each other's entries."""
    return squadgen.udir(unit, "jobs.json")


def _load(unit):
    d = squadgen.load_json(_receipts(unit), None) or {"jobs": []}
    d.setdefault("jobs", [])
    return d


def _record(entry):
    with _lock:
        d = _load(entry["unit"])
        for j in d["jobs"]:
            if j["job"] == entry["job"]:
                j.update(entry)
                break
        else:
            d["jobs"].append(entry)
        squadgen.save_json(_receipts(entry["unit"]), d)


def _latest(unit, fac, frame):
    jobs = [j for j in _load(unit)["jobs"] if j["fac"] == fac and j["frame"] == frame]
    return jobs[-1] if jobs else None


def _exe():
    """The CLI's own binary. The npm shim (higgsfield.cmd) runs through cmd.exe,
    which cuts an argument at its first line break: a prompt would arrive as its
    first paragraph only."""
    vendor = os.path.join(os.environ.get("APPDATA", ""), "npm", "node_modules", "@higgsfield", "cli", "vendor", "hf.exe")
    return vendor if os.path.exists(vendor) else (shutil.which("hf") or shutil.which("higgsfield") or "higgsfield")


def _cli(*args):
    r = subprocess.run([_exe(), *args], capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout).strip()[:500])
    return json.loads(r.stdout) if r.stdout.strip().startswith(("{", "[")) else r.stdout


def _inputs(unit, spec):
    out = []
    for path in spec["inputs"]:
        name = os.path.basename(path)
        stem = name[:-4]
        job = None
        if os.path.dirname(os.path.abspath(path)) == os.path.abspath(squadgen.udir(unit)) and "_" in stem:
            fac, frame = stem.split("_", 1)
            j = _latest(unit, fac, frame)
            if j and j.get("status") == "completed" and not j.get("mirrored") and not j.get("local"):
                job = j["job"]
        if job is None and not os.path.exists(path):
            raise SystemExit(f"missing input {path}")
        out.append(job or path)
    return out


def _spec(unit, fac, frame):
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        squadgen.cmd_prompt(unit, fac, frame)
    return json.loads(buf.getvalue())


def _download(unit, fac, frame, url):
    dest = squadgen.udir(unit, f"{fac}_{frame}.png")
    if os.path.exists(dest):
        n = 1
        while os.path.exists(squadgen.udir(unit, f"{fac}_{frame}_try{n}.png")):
            n += 1
        os.replace(dest, squadgen.udir(unit, f"{fac}_{frame}_try{n}.png"))
    urllib.request.urlretrieve(url, dest)
    return dest


def _finish(unit, fac, frame, job, cut=True):
    res = _cli("generate", "wait", job, "--json")
    if isinstance(res, list):
        res = res[0]
    status = res.get("status")
    _record({"unit": unit, "fac": fac, "frame": frame, "job": job, "status": status})
    if status != "completed":
        print(f"{unit} {fac}:{frame} job {job}: {status}")
        return False
    dest = _download(unit, fac, frame, res["result_url"])
    print(f"{unit} {fac}:{frame} job {job}: done -> {dest}")
    if frame == "base_l" or frame == "base_t":
        # Drawn facing the upper left: mirrored, it is the upper-right back view.
        # Each grid cell mirrored in place, so every man keeps his slot (his face in the front view).
        from PIL import Image
        im = Image.open(dest).convert("RGB")
        cols, rows = squadgen.UNITS[unit]["grid"]
        out = im.copy()
        for c in range(cols):
            x0, x1 = round(c * im.width / cols), round((c + 1) * im.width / cols)
            out.paste(im.crop((x0, 0, x1, im.height)).transpose(Image.FLIP_LEFT_RIGHT), (x0, 0))
        out.save(squadgen.udir(unit, "b_base.png"))
        _record({"unit": unit, "fac": "b", "frame": "base", "job": job, "status": "completed", "mirrored": True})
        frame = "base"
        dest = squadgen.udir(unit, "b_base.png")
    if cut and frame not in ("swap",):
        try:
            with _cut_lock:
                squadgen.cmd_cut(unit, fac, frame, dest)
        except SystemExit as e:
            print(f"{unit} {fac}:{frame}: cut failed: {e}")
            return False
    return True


def run_one(unit, fac, frame, again=False, cut=True, extra=""):
    prev = _latest(unit, fac, frame)
    if prev and not again and prev.get("status") in (None, "completed", "pending", "in_progress"):
        print(f"{unit} {fac}:{frame}: already job {prev['job']} ({prev.get('status')}); use --again or fetch")
        return False
    spec = _spec(unit, fac, frame)
    refs = _inputs(unit, spec)
    prompt = spec["prompt"].replace("—", "-") + (("\n\n" + extra) if extra else "")
    args = ["generate", "create", "nano_banana_pro", "--prompt", prompt, "--aspect_ratio", spec["aspect"], "--resolution", "2k", "--json"]
    for r in refs:
        args += ["--image-references", r]
    res = _cli(*args)
    # The CLI answers with a list of job ids (or of job objects).
    first = res[0] if isinstance(res, list) and res else res
    job = first if isinstance(first, str) else (first.get("id") if isinstance(first, dict) else None)
    if not job:
        raise RuntimeError(f"no job id in {str(res)[:300]}")
    _record({"unit": unit, "fac": fac, "frame": frame, "job": job, "status": "pending", "credits": 2,
             "inputs": refs, "extra": extra or None})
    sent = (_cli("generate", "get", job, "--json").get("params") or {}).get("prompt", "")
    if len(sent) < len(prompt) - 5:
        print(f"{unit} {fac}:{frame}: WARNING job {job} received {len(sent)} of {len(prompt)} prompt characters")
    print(f"{unit} {fac}:{frame}: submitted {job}")
    return _finish(unit, fac, frame, job, cut)


EDIT_TAIL = ("Keep everything else exactly as in image 1: every face, body, pose, clothes and equipment not named above, the position "
             "and size of every figure, the pixel-art style and pixel size, the outlines and palette, and the perfectly flat plain "
             "light grey background. Genuine crisp pixel art, no anti-aliasing, no shadows, no ground, no text.")


def edit_one(unit, fac, frame, change, refs_extra=()):
    """An edit of the sheet as it is (its job as image 1) that changes only `change`;
    the result becomes the sheet (the old one is kept as _tryN) and is cut."""
    prev = _latest(unit, fac, frame)
    if not (prev and prev.get("status") == "completed"):
        raise SystemExit(f"{unit} {fac}:{frame}: no finished sheet to edit")
    spec = _spec(unit, fac, frame)
    prompt = (f"Edit image 1, a pixel-art sprite sheet of separate {squadgen.UNITS[unit]['plural']} on a flat grey background.\n\n"
              f"{change}\n\n{EDIT_TAIL}")
    args = ["generate", "create", "nano_banana_pro", "--prompt", prompt, "--aspect_ratio", spec["aspect"], "--resolution", "2k",
            "--json", "--image-references", prev["job"]]
    for r in refs_extra:
        args += ["--image-references", r]
    res = _cli(*args)
    first = res[0] if isinstance(res, list) and res else res
    job = first if isinstance(first, str) else (first.get("id") if isinstance(first, dict) else None)
    if not job:
        raise RuntimeError(f"no job id in {str(res)[:300]}")
    _record({"unit": unit, "fac": fac, "frame": frame, "job": job, "status": "pending", "credits": 2,
             "inputs": [prev["job"], *refs_extra], "edit": change})
    print(f"{unit} {fac}:{frame}: edit submitted {job}")
    return _finish(unit, fac, frame, job, True)


def _done(unit, fac, frame):
    """The sheet's job finished and its figures are cut."""
    if frame in ("base_t", "base_l"):
        frame = "base"
    j = _latest(unit, fac, frame)
    if not (j and j.get("status") == "completed" and os.path.exists(squadgen.udir(unit, f"{fac}_{frame}.png"))):
        return False
    return f"{frame}_0" in squadgen.load_json(squadgen.sdir(unit, fac, "index.json"), {})


def _stage(unit, sheets):
    todo = [(f, fr) for f, fr in sheets if not _done(unit, f, fr)]
    threads = [threading.Thread(target=lambda f=f, fr=fr: _safe(run_one, unit, f, fr, True, True, "")) for f, fr in todo]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return all(_done(unit, f, fr) for f, fr in sheets)


def auto(unit):
    from units import UNITS
    shield = UNITS[unit]["shield"]
    squadgen.cmd_refs(unit)
    if UNITS[unit].get("kind") == "engine":
        if _stage(unit, [("e", "base")]):
            squadgen.cmd_build(unit)
        return
    if not _stage(unit, [("f", "base")]):
        print(f"{unit}: no front sheet; stopping")
        return
    if shield:
        squadgen.cmd_mirror(unit, "fs")
    falls = UNITS[unit].get("deaths", True)
    b = [("b", "base_t"), ("f", "walk_a"), ("f", "wind"), ("f", "hit")] + ([("f", "kneel")] if falls else []) + ([("fs", "base")] if shield else [])
    _stage(unit, b)
    c = [("b", "walk_a"), ("b", "wind"), ("b", "hit")] + ([("b", "kneel")] if falls else [])
    if shield and _done(unit, "b", "base"):
        squadgen.cmd_mirror(unit, "bs")
        c.append(("bs", "base"))
    if shield and _done(unit, "fs", "base"):
        c += [("fs", "walk_a"), ("fs", "wind"), ("fs", "hit")]
    if _done(unit, "f", "kneel"):
        squadgen.cmd_relay(unit, "f")
        c.append(("f", "down"))
    _stage(unit, c)
    d = []
    if _done(unit, "b", "kneel"):
        squadgen.cmd_relay(unit, "b")
        d.append(("b", "slump"))
    if shield:
        d += [("bs", "walk_a"), ("bs", "wind"), ("bs", "hit")] if _done(unit, "bs", "base") else []
    _stage(unit, d)
    try:
        squadgen.cmd_build(unit)
    except SystemExit as e:
        print(f"{unit}: build failed: {e}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("run")
    p.add_argument("unit"); p.add_argument("sheets", nargs="+")
    p.add_argument("--again", action="store_true"); p.add_argument("--no-cut", action="store_true")
    p.add_argument("--prompt-extra", default="")
    p = sub.add_parser("fetch")
    p.add_argument("unit"); p.add_argument("sheet")
    sub.add_parser("spent")
    p = sub.add_parser("auto")
    p.add_argument("units", nargs="+")
    p = sub.add_parser("edit")
    p.add_argument("unit"); p.add_argument("sheet"); p.add_argument("change")
    p.add_argument("--ref", action="append", default=[], help="another image (path or job id) the change may use")
    a = ap.parse_args()
    if a.cmd == "edit":
        fac, frame = a.sheet.split(":")
        edit_one(a.unit, fac, frame, a.change, a.ref)
        return
    if a.cmd == "auto":
        for u in a.units:
            auto(u)
        return
    if a.cmd == "spent":
        jobs = [j for u in sorted(os.listdir(squadgen.RAW)) if os.path.isdir(squadgen.udir(u)) for j in _load(u)["jobs"]]
        done = [j for j in jobs if j.get("status") == "completed"]
        print(f"{len(jobs)} jobs, {len(done)} completed, about {2 * len(jobs)} credits")
        return
    if a.cmd == "fetch":
        fac, frame = a.sheet.split(":")
        j = _latest(a.unit, fac, frame)
        if not j:
            raise SystemExit("no recorded job")
        _finish(a.unit, fac, frame, j["job"])
        return
    threads = []
    for s in a.sheets:
        fac, frame = s.split(":")
        t = threading.Thread(target=lambda f=fac, fr=frame: _safe(run_one, a.unit, f, fr, a.again, not a.no_cut, a.prompt_extra))
        t.start()
        threads.append(t)
    for t in threads:
        t.join()


def _safe(fn, *args):
    try:
        fn(*args)
    except Exception as e:  # report and let the other sheets finish
        print(f"error {args[:3]}: {e}")


if __name__ == "__main__":
    main()
