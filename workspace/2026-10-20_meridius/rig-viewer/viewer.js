// Pose viewer for the Meridius 3D rig tabs (footman, crossbowman).
// The page supplies #viewer-config ({base, clips, start, key}) and #frames-data
// (the frames.json of its sheets) as JSON script tags, and the viewer markup.
(() => {
  const $ = (id) => document.getElementById(id);
  let cfg, meta;
  try {
    cfg = JSON.parse($("viewer-config").textContent);
    meta = JSON.parse($("frames-data").textContent);
  } catch (e) {
    $("readout").textContent = "The frame index could not be read. Reload the tab to try again.";
    return;
  }
  const CLIPS = cfg.clips;
  const FACES = [["sw", "SW"], ["se", "SE"], ["nw", "NW"], ["ne", "NE"], ["all", "All four"]];
  const GROUND = { paper: "#d8d2bf", grass: "#7b9a4c", dark: "#20242b" };
  const state = { clip: cfg.start, face: "se", frame: 0, playing: false, speed: 1, zoom: 1.5, ground: "paper" };
  try { const s = JSON.parse(localStorage.getItem(cfg.key) || "{}"); Object.assign(state, s, { playing: false }); } catch (e) {}
  const save = () => { try { localStorage.setItem(cfg.key, JSON.stringify({ clip: state.clip, face: state.face, zoom: state.zoom, ground: state.ground, speed: state.speed })); } catch (e) {} };
  if (!meta.clips[state.clip]) state.clip = cfg.start;
  if (!FACES.some(f => f[0] === state.face)) state.face = "se";
  const sheets = {};
  let cells = [];
  let acc = 0, last = 0;

  function chips(el, items, key) {
    el.innerHTML = "";
    for (const [id, label] of items) {
      const b = document.createElement("button");
      b.className = "vchip"; b.textContent = label; b.dataset.id = id;
      b.setAttribute("aria-pressed", String(state[key] === id));
      b.addEventListener("click", () => { state[key] = id; if (key === "clip") state.frame = 0; save(); build(); });
      el.appendChild(b);
    }
  }
  function sheet(clip, face) {
    const k = clip + "_" + face;
    if (!sheets[k]) { const img = new Image(); img.onload = () => draw(); img.src = cfg.base + meta.clips[clip][face].file; sheets[k] = img; }
    return sheets[k];
  }
  const faces = () => state.face === "all" ? ["sw", "se", "nw", "ne"] : [state.face];
  const count = () => meta.clips[state.clip].se.frames;
  const canvasSize = () => meta.clips[state.clip].canvas || meta.canvas;
  function build() {
    chips($("clipChips"), CLIPS, "clip"); chips($("faceChips"), FACES, "face");
    $("speed").value = String(state.speed); $("zoom").value = String(state.zoom); $("ground").value = state.ground;
    const stage = $("stage"); stage.innerHTML = ""; cells = [];
    const [W, H] = canvasSize();
    const z = state.face === "all" ? Math.min(state.zoom, 1) : state.zoom;
    for (const f of faces()) {
      const cell = document.createElement("div"); cell.className = "cell";
      const cv = document.createElement("canvas"); cv.width = Math.round(W * z); cv.height = Math.round(H * z);
      const tag = document.createElement("span"); tag.className = "tag"; tag.textContent = f.toUpperCase();
      const stamp = document.createElement("span"); stamp.className = "stamp";
      cell.append(cv, tag, stamp); stage.appendChild(cell);
      cells.push({ f, cv, stamp, z }); sheet(state.clip, f);
    }
    const n = count(); $("scrub").max = String(n - 1); state.frame = Math.min(state.frame, n - 1); draw();
  }
  function label() {
    const n = count(); const name = CLIPS.find(c => c[0] === state.clip)[1];
    const face = state.face === "all" ? "all facings" : state.face.toUpperCase();
    return `${name} · ${face} · frame ${state.frame + 1} / ${n} · ${(state.frame / meta.fps).toFixed(2)} s${state.playing ? "" : " · paused"}`;
  }
  function draw() {
    for (const c of cells) {
      const m = meta.clips[state.clip][c.f];
      const ctx = c.cv.getContext("2d");
      ctx.fillStyle = GROUND[state.ground]; ctx.fillRect(0, 0, c.cv.width, c.cv.height);
      const img = sheets[state.clip + "_" + c.f];
      if (img && img.complete && img.naturalWidth) {
        const i = state.frame; const sx = (i % m.cols) * m.w, sy = Math.floor(i / m.cols) * m.h;
        ctx.imageSmoothingQuality = "high";
        ctx.drawImage(img, sx, sy, m.w, m.h, m.x * c.z, m.y * c.z, m.w * c.z, m.h * c.z);
      }
      c.stamp.textContent = `${state.clip} ${c.f.toUpperCase()} f${state.frame + 1}`;
    }
    $("scrub").value = String(state.frame); $("readout").textContent = label(); $("play").textContent = state.playing ? "❚❚" : "▶";
  }
  function step(d) { const n = count(); state.frame = (state.frame + d + n) % n; draw(); }
  function setPlay(p) { state.playing = p; last = performance.now(); acc = 0; draw(); }
  function tick(t) {
    if (state.playing) {
      acc += (t - last) / 1000 * state.speed; last = t;
      const dt = 1 / meta.fps; let moved = false;
      while (acc >= dt) { acc -= dt; state.frame = (state.frame + 1) % count(); moved = true; }
      if (moved) draw();
    } else { last = t; }
    requestAnimationFrame(tick);
  }
  $("play").addEventListener("click", () => setPlay(!state.playing));
  $("prev").addEventListener("click", () => { setPlay(false); step(-1); });
  $("next").addEventListener("click", () => { setPlay(false); step(1); });
  $("first").addEventListener("click", () => { setPlay(false); state.frame = 0; draw(); });
  $("scrub").addEventListener("input", (e) => { setPlay(false); state.frame = Number(e.target.value); draw(); });
  $("speed").addEventListener("change", (e) => { state.speed = Number(e.target.value); save(); });
  $("zoom").addEventListener("change", (e) => { state.zoom = Number(e.target.value); save(); build(); });
  $("ground").addEventListener("change", (e) => { state.ground = e.target.value; save(); draw(); });
  function selectText() { const r = document.createRange(); r.selectNodeContents($("readout")); const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
  $("copy").addEventListener("click", () => {
    const text = label().replace(" · paused", "");
    const done = () => { $("copied").hidden = false; setTimeout(() => { $("copied").hidden = true; }, 1400); };
    if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text).then(done).catch(selectText); } else { selectText(); }
  });
  document.addEventListener("keydown", (e) => {
    const tag = (e.target.tagName || "").toLowerCase();
    if (tag === "select" || tag === "input" && e.target.type !== "range") return;
    if (e.target.matches && e.target.matches("img[data-mak-zoom]")) return;
    if (document.querySelector("dialog.mak-lightbox[open]")) return;
    if (e.code === "Space") { e.preventDefault(); setPlay(!state.playing); }
    else if (e.key === "ArrowLeft") { e.preventDefault(); setPlay(false); step(e.shiftKey ? -5 : -1); }
    else if (e.key === "ArrowRight") { e.preventDefault(); setPlay(false); step(e.shiftKey ? 5 : 1); }
    else if (e.key === "Home") { e.preventDefault(); setPlay(false); state.frame = 0; draw(); }
    else if (e.key === "End") { e.preventDefault(); setPlay(false); state.frame = count() - 1; draw(); }
  });
  build(); setPlay(true); requestAnimationFrame(tick);
})();
