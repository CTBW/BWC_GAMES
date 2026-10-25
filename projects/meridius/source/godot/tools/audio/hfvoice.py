"""Generate voice lines through the Higgsfield CLI.

tools/audio/voices.json lists rounds of lines (speaker, text, model, takes).
Each take is its own job; its file goes to the audio library's
voices/higgsfield/<round>/<line>_<n>.<ext>, every job is recorded in
voices/higgsfield/receipts.json as it is submitted, and finished takes are
registered in the library's candidates.json (state "candidate") under the
line's category, so audition.html lists them. Takes already done are skipped.

  python -I tools/audio/hfvoice.py round2 --cost            # estimate the missing takes, no jobs
  python -I tools/audio/hfvoice.py round2                   # submit the missing takes, wait, download
  python -I tools/audio/hfvoice.py round2 knox_square_form  # only these lines
  python -I tools/audio/hfvoice.py round2 --adopt <line> <job_id>   # a job submitted by hand

Calls the CLI's own binary (vendor/hf.exe), not the npm shim, which cuts
arguments at line breaks (knowledge/higgsfield-setup.md). A few jobs run at a
time: a batch of twelve once hit HTTP 429.
"""
import concurrent.futures
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))
VOICES = os.path.join(HERE, "voices.json")
# The repository's gitignored local/ folder (local/README.md).
LIBRARY = os.environ.get("MERIDIUS_AUDIO_LIBRARY", os.path.normpath(os.path.join(PROJ, "..", "..", "..", "..", "local", "audio-library")))
VDIR = os.path.join(LIBRARY, "voices", "higgsfield")
RECEIPTS = os.path.join(VDIR, "receipts.json")
CANDIDATES = os.path.join(LIBRARY, "candidates.json")
WORKERS = 3
LICENSE = "Higgsfield output (own generation)"

_lock = threading.Lock()


def _exe():
    vendor = os.path.join(os.environ.get("APPDATA", ""), "npm", "node_modules", "@higgsfield", "cli", "vendor", "hf.exe")
    return vendor if os.path.exists(vendor) else (shutil.which("hf") or shutil.which("higgsfield") or "higgsfield")


def _cli(*args):
    r = subprocess.run([_exe(), *args], capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout).strip()[:500])
    out = r.stdout.strip()
    return json.loads(out) if out.startswith(("{", "[")) else out


def _load_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _save_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def _text(line):
    return line.get("text") or line.get("prompt") or ""


def _args(line, spec):
    """The CLI arguments of one take of `line` (after `generate create|cost`)."""
    model = line.get("model", "elevenlabs_v4")
    if model.startswith("elevenlabs"):
        voice = spec["voices"][line["voice"]]
        dialogue = [{"text": line["text"], "voice_type": "preset", "voice_id": voice["voice_id"]}]
        args = [model, "--dialogue", json.dumps(dialogue, ensure_ascii=False)]
        if line.get("stability") is not None:
            args += ["--stability", str(line["stability"])]
        return args
    if model == "seed_audio":
        args = [model, "--prompt", line["prompt"]]
        if line.get("image"):
            args += ["--image-references", os.path.normpath(os.path.join(PROJ, line["image"]))]
        return args
    if model == "inworld_text_to_speech":
        return [model, "--prompt", line["text"], "--voice", line["inworld_voice"]]
    raise SystemExit("hfvoice: no argument rule for model %s" % model)


def _speaker(line, spec):
    if line.get("voice"):
        return spec["voices"][line["voice"]]["name"]
    return line.get("inworld_voice") or "described"


def _jobs(receipts, rnd):
    return receipts.setdefault(rnd, {}).setdefault("jobs", [])


def _record(rnd, entry):
    with _lock:
        receipts = _load_json(RECEIPTS, {})
        jobs = _jobs(receipts, rnd)
        for j in jobs:
            if j.get("job_id") == entry["job_id"]:
                j.update(entry)
                break
        else:
            jobs.append(entry)
        receipts[rnd].setdefault("submitted", datetime.date.today().isoformat())
        _save_json(RECEIPTS, receipts)


def _done(receipts, rnd):
    """(line, take) -> receipt of a completed, downloaded take."""
    out = {}
    for j in receipts.get(rnd, {}).get("jobs", []):
        if j.get("status") == "completed" and j.get("file") and os.path.exists(j["file"]):
            out[(j["line"], j["take"])] = j
    return out


def _pending(receipts, rnd):
    out = {}
    for j in receipts.get(rnd, {}).get("jobs", []):
        if j.get("status") in ("pending", "queued", "in_progress"):
            out[(j["line"], j["take"])] = j
    return out


def _submit(args):
    for attempt in range(5):
        try:
            res = _cli("generate", "create", *args, "--json")
            first = res[0] if isinstance(res, list) and res else res
            job = first if isinstance(first, str) else (first.get("id") if isinstance(first, dict) else None)
            if not job:
                raise RuntimeError("no job id in %s" % str(res)[:300])
            return job
        except RuntimeError as e:
            if "429" in str(e) or "rate" in str(e).lower():
                time.sleep(15 * (attempt + 1))
                continue
            raise
    raise RuntimeError("rate limited five times")


def _finish(rnd, line, take, job, spec):
    try:
        res = _cli("generate", "wait", job, "--json")
    except RuntimeError as e:
        # The CLI exits non-zero on a job that ended badly (`ended with status "nsfw"`).
        m = re.search(r'ended with status "([^"]+)"', str(e))
        if not m:
            raise
        res = {"status": m.group(1)}
    if isinstance(res, list):
        res = res[0]
    status = res.get("status")
    entry = {"job_id": job, "line": line["id"], "take": take, "status": status}
    if status != "completed" or not res.get("result_url"):
        _record(rnd, entry)
        return "%s take %d job %s: %s" % (line["id"], take, job, status)
    url = res["result_url"]
    ext = os.path.splitext(url.split("?")[0])[1] or ".mp3"
    os.makedirs(os.path.join(VDIR, rnd), exist_ok=True)
    dest = os.path.join(VDIR, rnd, "%s_%d%s" % (line["id"], take, ext))
    urllib.request.urlretrieve(url, dest)
    sent = res.get("params") or {}
    got = (sent.get("dialogue") or [{}])[0].get("text") or sent.get("prompt") or ""
    if got.strip() != _text(line).strip():
        entry["warning"] = "the job received %r" % got[:200]
    entry.update({"status": "completed", "file": dest, "model": res.get("job_type"),
                  "display_name": res.get("display_name"), "result_url": url})
    _record(rnd, entry)
    return "%s take %d job %s: %s%s" % (line["id"], take, job, dest, "  WARNING " + entry["warning"] if "warning" in entry else "")


def _run_take(rnd, line, take, spec, job=None):
    if job is None:
        job = _submit(_args(line, spec))
        _record(rnd, {"job_id": job, "line": line["id"], "take": take, "status": "pending",
                      "model": line.get("model", "elevenlabs_v4"), "speaker": _speaker(line, spec), "text": _text(line)})
    return _finish(rnd, line, take, job, spec)


def _duration(path):
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                             capture_output=True, text=True).stdout
        return round(float(out.strip()), 3)
    except (OSError, ValueError):
        return None


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _register(rnd, spec):
    """Every completed take of the round in candidates.json (new ones as candidates)."""
    lines = {l["id"]: l for l in spec["rounds"][rnd]["lines"]}
    receipts = _load_json(RECEIPTS, {})
    cands = _load_json(CANDIDATES, {})
    known = {t["id"] for lst in cands.values() for t in lst}
    added = 0
    for (lid, take), j in sorted(_done(receipts, rnd).items()):
        line = lines.get(lid)
        if line is None:
            continue
        cid = "hf_%s_%s_%d" % (rnd, lid, take)
        if cid in known:
            continue
        cands.setdefault(line["category"], []).append({
            "id": cid,
            "state": "candidate",
            "file": os.path.normpath(j["file"]),
            "kind": "master",
            "source": "Higgsfield %s (voice %s, job %s)" % (j.get("display_name") or j.get("model"), _speaker(line, spec), j["job_id"]),
            "url": None,
            "author": "Generated for Meridius",
            "license": LICENSE,
            "attribution": None,
            "notes": _text(line) + ("  [for: %s]" % line["for"] if line.get("for") else ""),
            "duration_s": _duration(j["file"]),
            "tech": {"sha256": _sha256(j["file"])},
        })
        added += 1
    if added:
        _save_json(CANDIDATES, cands)
    return added


def main(argv):
    spec = _load_json(VOICES, None)
    if not argv or argv[0] not in spec["rounds"]:
        raise SystemExit("usage: hfvoice.py <round> [--cost] [line ...] | <round> --adopt <line> <job_id>\nrounds: %s"
                         % ", ".join(spec["rounds"]))
    rnd, rest = argv[0], argv[1:]
    lines = spec["rounds"][rnd]["lines"]
    by_id = {l["id"]: l for l in lines}
    receipts = _load_json(RECEIPTS, {})
    if rest[:1] == ["--adopt"]:
        line = by_id[rest[1]]
        done = _done(receipts, rnd)
        take = next(n for n in range(1, 100) if (line["id"], n) not in done)
        print(_run_take(rnd, line, take, spec, job=rest[2]))
        print("registered", _register(rnd, spec), "new candidates")
        return
    cost = "--cost" in rest
    only = [a for a in rest if not a.startswith("--")]
    unknown = [a for a in only if a not in by_id]
    if unknown:
        raise SystemExit("unknown lines: %s" % ", ".join(unknown))
    done, pending = _done(receipts, rnd), _pending(receipts, rnd)
    # A take whose job ended badly (refused as "nsfw", failed) is tried again only when its line is named.
    ended = {(j["line"], j["take"]): j["status"] for j in receipts.get(rnd, {}).get("jobs", [])
             if j.get("status") not in (None, "completed", "pending", "queued", "in_progress")}
    todo = []
    for line in lines:
        if only and line["id"] not in only:
            continue
        for take in range(1, int(line.get("takes", 1)) + 1):
            key = (line["id"], take)
            if key in done:
                continue
            if key in ended and key not in pending and not only:
                print("%s take %d: skipped, its job ended %s (name the line to try again)" % (*key, ended[key]))
                continue
            todo.append((line, take, pending.get(key, {}).get("job_id")))
    if cost:
        total = 0.0
        for line, take, job in todo:
            if job:
                continue
            c = _cli("generate", "cost", *_args(line, spec), "--json")
            total += float(c.get("credits", 0))
            print("%-28s take %d  %.2f" % (line["id"], take, float(c.get("credits", 0))))
        print("%d takes to make, %.2f credits; balance: %s" % (len(todo), total, _cli("account", "status")))
        return
    print("%d takes to make (%d already submitted)" % (len(todo), sum(1 for t in todo if t[2])))
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futs = {pool.submit(_run_take, rnd, line, take, spec, job): (line["id"], take) for line, take, job in todo}
        for f in concurrent.futures.as_completed(futs):
            try:
                print(f.result(), flush=True)
            except Exception as e:  # keep the others going; the receipt keeps the job id
                print("%s take %d: FAILED %s" % (*futs[f], e), flush=True)
    print("registered", _register(rnd, spec), "new candidates")


if __name__ == "__main__":
    main(sys.argv[1:])
