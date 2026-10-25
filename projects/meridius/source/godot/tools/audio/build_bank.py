"""Render the sound bank's recorded takes from the audio library.

tools/audio/recipe.json says which library takes (ids from the library's
candidates.json) become which bank event's takes, and how: cut, sliced from a
multi-take recording, layered, made into a seamless loop, levelled. This
script renders them with ffmpeg into assets/audio/bank/, writes the takes into
assets/audio/bank/bank.json (events and ambience presets; every other option
there is left as it is) and records every file's sources, licences and edits
in assets/audio/bank/provenance.json.

Files made only from CC0 sources or our own generations go to
assets/audio/bank/<dir>/ (in Git). Files with any Sonniss source go to
assets/audio/bank/local/<dir>/, which is gitignored: the Sonniss licence
forbids redistributing its sounds and this repository is public. The
Higgsfield voices go there too (the owner keeps them out of the public
repository, 25 Oct 2026). A clone without the library simply plays the synth
fallback for those takes.

  python -I tools/audio/build_bank.py                 # everything
  python -I tools/audio/build_bank.py hit_metal step  # some groups (by name)
  python -I tools/audio/build_bank.py --list          # the recipe's groups
  python -I tools/audio/build_bank.py --bank-only     # levels and aliases only, no rendering

Library: $MERIDIUS_AUDIO_LIBRARY, default local/audio-library at the
repository root (gitignored). Needs ffmpeg and ffprobe on PATH. Then run
tools/import.sh.

Music: the owner's Suno downloads (music/suno/<track>/<file>.wav in the
library) are named "suno/<track>/<file>.wav" in the recipe, no candidates.json
entry needed. A group of kind "music" makes stereo Vorbis loops like a bed;
a take spec with bpm and bars (and start at a downbeat) loops on exactly that
many bars. Its bank entry {"music": "<track>"} fills bank.json music.tracks.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))
BANK_DIR = os.path.join(PROJ, "assets", "audio", "bank")
BANK_JSON = os.path.join(BANK_DIR, "bank.json")
PROVENANCE = os.path.join(BANK_DIR, "provenance.json")
RECIPE = os.path.join(HERE, "recipe.json")
# The repository's gitignored local/ folder (local/README.md).
LIBRARY = os.environ.get("MERIDIUS_AUDIO_LIBRARY", os.path.normpath(os.path.join(PROJ, "..", "..", "..", "..", "local", "audio-library")))
RATE = 44100
# Licences that may be committed to the public repository (not Higgsfield
# output: the owner keeps the voices local).
FREE = ("CC0", "Kenney", "Suno", "own")
SUNO_LICENSE = "Suno (Pro plan: the owner's generation, commercial use)"
LOOPED = ("bed", "loop", "music")


def run(args):
    r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise RuntimeError("%s\n%s" % (" ".join(args[:6]), r.stderr[-1500:]))
    return r


def levels(path):
    """(RMS dBFS, peak dBFS) of a file, measured in float (volumedetect clips at 0 dBFS)."""
    err = run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "astats=measure_perchannel=none",
               "-f", "null", "-"]).stderr
    overall = err[err.rfind("Overall"):]
    mean = re.search(r"RMS level dB: (-?[\d.]+|-inf)", overall)
    peak = re.search(r"Peak level dB: (-?[\d.]+|-inf)", overall)
    f = lambda m: -120.0 if m is None or m.group(1) == "-inf" else float(m.group(1))
    return f(mean), f(peak)


def duration(path):
    out = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path]).stdout
    return float(out.strip() or 0)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class Library:
    def __init__(self, root):
        self.root = root
        c = json.load(open(os.path.join(root, "candidates.json"), encoding="utf-8"))
        self.takes = {}
        for ev, lst in c.get("events", c).items():
            for t in lst:
                self.takes[t["id"]] = t

    def get(self, take_id):
        if take_id.startswith("suno/") and take_id not in self.takes:
            path = os.path.join(self.root, "music", *take_id.split("/"))
            if not os.path.exists(path):
                raise KeyError("no Suno download %s" % path)
            self.takes[take_id] = {"id": take_id, "file": path, "kind": "master", "source": "Suno",
                                   "url": None, "author": "Generated for Meridius (Suno)",
                                   "license": SUNO_LICENSE, "tech": {"sha256": sha256(path)}}
        if take_id not in self.takes:
            raise KeyError("unknown library take %s" % take_id)
        t = self.takes[take_id]
        # candidates.json keeps the absolute paths of the machine that wrote it;
        # a library copied elsewhere finds its files under its own root.
        if not os.path.exists(t["file"]):
            parts = re.split(r"[\\/]", t["file"])
            if "audio-library" in parts:
                rel = parts[parts.index("audio-library") + 1:]
                moved = os.path.join(self.root, *rel)
                if os.path.exists(moved):
                    t = dict(t, file=moved)
        return t

    @staticmethod
    def free(t):
        lic = t.get("license") or ""
        return lic.startswith(FREE) and "Sonniss" not in lic


class Builder:
    def __init__(self, lib, tmp):
        self.lib = lib
        self.tmp = tmp
        self.n = 0

    def _tmp(self, ext="wav"):
        self.n += 1
        return os.path.join(self.tmp, "t%04d.%s" % (self.n, ext))

    def extract(self, t, start=0.0, length=None, mono=True):
        """A region of a library take as float WAV at RATE."""
        out = self._tmp()
        args = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
        if start:
            args += ["-ss", "%.3f" % start]
        if length:
            args += ["-t", "%.3f" % length]
        args += ["-i", t["file"], "-ac", "1" if mono else "2", "-ar", str(RATE), "-c:a", "pcm_f32le", out]
        run(args)
        return out

    def slices(self, t, count, lo, hi, floor_db, gap, start=0.0, length=None, mono=True):
        """Up to `count` separate events (lo..hi s) of a multi-take recording, spread over it."""
        src = self.extract(t, start, length, mono=True)
        _, peak = levels(src)
        thr = peak + floor_db
        err = run(["ffmpeg", "-hide_banner", "-nostats", "-i", src, "-af",
                   "highpass=f=60,silencedetect=noise=%.1fdB:d=%.3f" % (thr, gap), "-f", "null", "-"]).stderr
        total = duration(src)
        starts = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", err)]
        ends = [float(x) for x in re.findall(r"silence_end: (-?[\d.]+)", err)]
        # Sound runs from each silence end to the next silence start.
        bounds, cur = [], 0.0
        if starts and starts[0] <= 0.01:
            cur = ends[0] if ends else total
            starts, ends = starts[1:], ends[1:]
        for i, s in enumerate(starts):
            bounds.append((cur, s))
            cur = ends[i] if i < len(ends) else total
        if cur < total - 0.02:
            bounds.append((cur, total))
        segs = [(a, min(b, a + hi)) for a, b in bounds if b - a >= lo]
        if not segs:
            print("  warning: no slices of %.2f-%.2f s in %s; skipped" % (lo, hi, t["id"]))
            return [], []
        if len(segs) > count:
            step = len(segs) / float(count)
            segs = [segs[int(i * step + step / 2)] for i in range(count)]
        out = []
        for a, b in segs:
            pre = min(0.015, a)
            out.append((start + a - pre, (b - a) + pre + 0.12))
        return [self.extract(t, a, l, mono) for a, l in out], out

    def filter(self, path, af):
        """An ffmpeg filter chain on a part (e.g. rubberband=pitch=0.8,lowpass=f=900)."""
        if not af:
            return path
        out = self._tmp()
        run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", path, "-af", af, "-c:a", "pcm_f32le", out])
        return out

    def gain(self, path, db):
        out = self._tmp()
        run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", path, "-af", "volume=%.2fdB" % db,
             "-c:a", "pcm_f32le", out])
        return out

    def shape(self, path, trim_start, max_len, fade_ms, fade_in_ms=3):
        """Trim leading silence, cap the length, fade the tail."""
        _, peak = levels(path)
        out = self._tmp()
        af = []
        if trim_start:
            af.append("silenceremove=start_periods=1:start_threshold=%.1fdB:start_silence=0.004" % (peak - 36))
        if max_len:
            af.append("atrim=0:%.3f" % max_len)
        af.append("afade=t=in:d=%.3f" % (fade_in_ms / 1000.0))
        run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", path, "-af", ",".join(af),
             "-c:a", "pcm_f32le", out])
        d = duration(out)
        if fade_ms and d > fade_ms / 1000.0:
            out2 = self._tmp()
            run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", out, "-af",
                 "afade=t=out:st=%.3f:d=%.3f" % (d - fade_ms / 1000.0, fade_ms / 1000.0), "-c:a", "pcm_f32le", out2])
            out = out2
        return out

    def mix(self, parts):
        """Layer [(path, delay_s, gain_db)]; the first part sets the reference level."""
        out = self._tmp()
        args = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
        for p, _, _ in parts:
            args += ["-i", p]
        chains = []
        for i, (_, delay, g) in enumerate(parts):
            ms = int(round(delay * 1000))
            chains.append("[%d:a]volume=%.2fdB,adelay=%d:all=1[a%d]" % (i, g, ms, i))
        labels = "".join("[a%d]" % i for i in range(len(parts)))
        graph = ";".join(chains) + ";%samix=inputs=%d:duration=longest:normalize=0[o]" % (labels, len(parts))
        run(args + ["-filter_complex", graph, "-map", "[o]", "-c:a", "pcm_f32le", out])
        return out

    def level(self, path, target_mean, peak_cap=-1.0, limit=False):
        """To the target RMS, peaks capped; `limit` reaches the target by limiting the peaks
        instead (crackle and pops, whose few loud clicks would keep the rest inaudible)."""
        mean, peak = levels(path)
        g = target_mean - mean
        if peak + g <= peak_cap:
            return self.gain(path, g), g
        if not limit:
            g = peak_cap - peak
            return self.gain(path, g), g
        out = self._tmp()
        cap = 10 ** (peak_cap / 20.0)
        run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", path, "-af",
             "volume=%.2fdB,alimiter=limit=%.4f:attack=1:release=40:level=disabled" % (g, cap), "-c:a", "pcm_f32le", out])
        return out, g

    def loop(self, path, xfade):
        """A seamless loop: the tail crossfades into the head (the file is `xfade` shorter)."""
        d = duration(path)
        head, body = self._tmp(), self._tmp()
        run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", path, "-af", "atrim=0:%.3f" % xfade,
             "-c:a", "pcm_f32le", head])
        run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", path, "-af",
             "atrim=%.3f:%.3f,asetpts=PTS-STARTPTS" % (xfade, d), "-c:a", "pcm_f32le", body])
        out = self._tmp()
        run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", body, "-i", head, "-filter_complex",
             "[0:a][1:a]acrossfade=d=%.3f:c1=qsin:c2=qsin[o]" % xfade, "-map", "[o]", "-c:a", "pcm_f32le", out])
        return out


def render_take(b, spec, g):
    """One take spec -> list of (temp path, sources[], edits{})."""
    mono = g.get("mono", True)
    floor_db = g.get("slice_floor_db", -30.0)
    gap = g.get("slice_gap", 0.12)
    results = []
    if "mix" in spec:
        parts, sources = [], []
        for layer in spec["mix"]:
            t = b.lib.get(layer["id"])
            if "slice" in layer:
                # One event of a multi-take recording: {slice: k, of: n, min, max}.
                paths, cuts = b.slices(t, layer.get("of", 8), layer.get("min", 0.1), layer.get("max", 1.0),
                                       layer.get("floor_db", floor_db), layer.get("gap", gap),
                                       layer.get("start", 0.0), layer.get("len"), mono)
                if not paths:
                    continue
                k = layer["slice"] % len(paths)
                p, (a, l) = paths[k], cuts[k]
            else:
                a, l = layer.get("start", 0.0), layer.get("len")
                p = b.extract(t, a, l, mono)
            p = b.filter(p, layer.get("af"))
            p = b.shape(p, layer.get("trim", True), layer.get("max_len"), layer.get("fade_ms", 40))
            _, peak = levels(p)
            p = b.gain(p, -peak)  # each layer at 0 dBFS peak before its gain
            parts.append((p, layer.get("delay", 0.0), layer.get("gain", 0.0)))
            sources.append({"id": t["id"], "start": round(a, 3), "len": round(l, 3) if l else l,
                            "delay": layer.get("delay", 0.0), "gain_db": layer.get("gain", 0.0), "af": layer.get("af")})
        results.append((b.mix(parts), sources, {"layered": True}))
        return results
    t = b.lib.get(spec["id"])
    if "slices" in spec:
        paths, cuts = b.slices(t, spec["slices"], spec.get("min", 0.15), spec.get("max", g.get("max_len") or 3.0),
                               spec.get("floor_db", floor_db), spec.get("gap", gap), spec.get("start", 0.0),
                               spec.get("len"), mono)
        for p, (a, l) in zip(paths, cuts):
            results.append((b.filter(p, spec.get("af")), [{"id": t["id"], "start": round(a, 3), "len": round(l, 3),
                                                            "af": spec.get("af")}], {"sliced": True}))
        return results
    start, length = spec.get("start", 0.0), spec.get("len")
    if "bars" in spec:
        # A loop of exactly `bars` bars: the looped file is `xfade` shorter than its cut
        # and begins `xfade` into it, so cutting that much earlier starts it on the downbeat.
        xfade = g.get("xfade", 3.0)
        length = spec["bars"] * spec.get("beats", 4) * 60.0 / spec["bpm"] + xfade
        start = max(0.0, start - xfade)
    p = b.extract(t, start, length, mono)
    results.append((b.filter(p, spec.get("af")), [{"id": t["id"], "start": round(start, 3),
                                                   "len": round(length, 3) if length else length,
                                                   "af": spec.get("af")}],
                    {"bpm": spec["bpm"], "bars": spec["bars"]} if "bars" in spec else {}))
    return results


def build_group(b, g, prov, bank_refs):
    name = g["name"]
    kind = g.get("kind", "oneshot")
    rendered = []
    for spec in g["takes"]:
        # A take's `weight` (an event's takes only): how often it comes up next to weight 1.
        rendered += [r + (spec.get("weight"),) for r in render_take(b, spec, g)]
    files = []
    for i, (p, sources, edits, weight) in enumerate(rendered):
        src_meta = [b.lib.get(s["id"]) for s in sources]
        free = all(Library.free(t) for t in src_meta)
        sub = g["dir"] if free else "local/" + g["dir"]
        ext = "ogg" if kind in LOOPED else "wav"
        rel = "%s/%s_%02d.%s" % (sub, name, i + 1, ext)
        dst = os.path.join(BANK_DIR, *rel.split("/"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        looped = kind in LOOPED and g.get("loop", True)
        if looped:
            p = b.loop(p, g.get("xfade", 3.0))
        else:
            # A one-shot (a music sting with "loop": false keeps its own ending).
            p = b.shape(p, g.get("trim", True), g.get("max_len"), g.get("fade_ms", 60))
        p, gdb = b.level(p, g.get("target_db", -18.0), g.get("peak_cap", -1.0), g.get("limit", False))
        if ext == "ogg":
            run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", p, "-c:a", "libvorbis",
                 "-q:a", str(g.get("vorbis_q", 6)), dst])
        else:
            run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", p, "-c:a", "pcm_s16le", dst])
        res = "res://assets/audio/bank/" + rel
        files.append(res if weight is None else {"file": res, "weight": weight})
        prov[res] = {
            "group": name,
            "kind": kind,
            "sources": [dict(s, author=t.get("author"), license=(t.get("license") or "").split("(")[0].strip(),
                             source=t.get("source"), url=t.get("url"), master=t.get("kind") == "master",
                             sha256=(t.get("tech") or {}).get("sha256")) for s, t in zip(sources, src_meta)],
            "edits": dict(edits, mono=g.get("mono", True), level_gain_db=round(gdb, 2),
                          target_mean_db=g.get("target_db", -18.0), max_len=g.get("max_len"),
                          loop_xfade=g.get("xfade", 3.0) if looped else None),
            "in_git": free,
            "duration_s": round(duration(dst), 3),
            "sha256": sha256(dst),
        }
    for ref in g["bank"]:
        bank_refs.append((ref, files))
    return files


def apply_bank(bank, refs, recipe):
    for ref, files in refs:
        if "event" in ref:
            ev = bank["events"].setdefault(ref["event"], {"takes": []})
            ev["takes"] = files
            for k, v in (ref.get("options") or {}).items():
                ev[k] = v
        elif "music" in ref:
            tracks = bank.setdefault("music", {}).setdefault("tracks", {})
            tr = tracks.setdefault(ref["music"], {"takes": []})
            tr["takes"] = files
            for k, v in (ref.get("options") or {}).items():
                tr[k] = v
        else:
            preset, part, key = ref["ambience"]
            pr = bank["ambience"]["presets"].setdefault(preset, {"beds": [], "loops": [], "oneshots": []})
            lst = pr.setdefault(part, [])
            entry = next((e for e in lst if e.get("id") == key), None)
            if entry is None:
                entry = {"id": key}
                lst.append(entry)
            entry["takes"] = files
            for k, v in (ref.get("options") or {}).items():
                entry[k] = v
    for preset, part, key in recipe.get("remove_ambience", []):
        lst = bank["ambience"]["presets"].get(preset, {}).get(part, [])
        bank["ambience"]["presets"][preset][part] = [e for e in lst if e.get("id") != key]
    # The mix: each event's level.
    for name, db in recipe.get("levels", {}).items():
        if name in bank["events"]:
            bank["events"][name]["volume_db"] = float(db)
    # Events that play another event's takes (step_orc_brute -> step_large), with their own options.
    for name, spec in recipe.get("aliases", {}).items():
        ev = bank["events"].setdefault(name, {})
        ev["takes"] = []
        for k, v in spec.items():
            ev[k] = v
        if name in recipe.get("levels", {}):
            ev["volume_db"] = float(recipe["levels"][name])


def main(argv):
    recipe = json.load(open(RECIPE, encoding="utf-8"))
    groups = recipe["groups"]
    if "--list" in argv:
        for g in groups:
            print("%-22s %-8s %2d specs -> %s" % (g["name"], g.get("kind", "oneshot"), len(g["takes"]),
                                                   ", ".join(r.get("event") or ("music:" + r["music"] if "music" in r
                                                             else "/".join(r["ambience"])) for r in g["bank"])))
        return 0
    only = [a for a in argv if not a.startswith("-")]
    todo = [] if "--bank-only" in argv else [g for g in groups if not only or g["name"] in only]
    lib = Library(LIBRARY)
    prov = json.load(open(PROVENANCE, encoding="utf-8")) if os.path.exists(PROVENANCE) else {}
    bank = json.load(open(BANK_JSON, encoding="utf-8"))
    refs = []
    tmp = tempfile.mkdtemp(prefix="meridius_bank_")
    try:
        b = Builder(lib, tmp)
        if not only and "--bank-only" not in argv:
            # A full build drops the files of groups the recipe no longer has.
            names = {g["name"] for g in groups}
            for res in [r for r, v in prov.items() if v.get("group") not in names]:
                path = os.path.join(PROJ, *res.replace("res://", "").split("/"))
                if os.path.exists(path):
                    os.remove(path)
                if os.path.exists(path + ".import"):
                    os.remove(path + ".import")
                del prov[res]
        for g in todo:
            # A rebuilt group replaces its old files.
            for res in [r for r, v in prov.items() if v.get("group") == g["name"]]:
                path = os.path.join(PROJ, *res.replace("res://", "").split("/"))
                if os.path.exists(path):
                    os.remove(path)
                if os.path.exists(path + ".import"):
                    os.remove(path + ".import")
                del prov[res]
            files = build_group(b, g, prov, refs)
            print("%-22s %d takes" % (g["name"], len(files)))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    apply_bank(bank, refs, recipe if not only else {"levels": recipe.get("levels", {})})
    with open(BANK_JSON, "w", encoding="utf-8") as f:
        json.dump(bank, f, indent=1, ensure_ascii=False)
        f.write("\n")
    with open(PROVENANCE, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(prov.items())), f, indent=1, ensure_ascii=False)
        f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
