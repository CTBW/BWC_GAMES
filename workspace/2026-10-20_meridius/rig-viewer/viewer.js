// Pose viewer for the Meridius 3D rig tabs (footman, crossbowman, spearman, succubus, mage).
// The page supplies #viewer-config ({base, clips, start, key}) and #frames-data
// (the frames.json of its sheets) as JSON script tags, and the viewer markup.
// The detail zoom (up to 4x, at the pointer) is added here, so every page loading this file has it.
// Sheets may be rendered larger than the canvas: frames.json "scale" is sheet pixels per canvas
// pixel (default 1), and then a frame's x, y, w and h are in sheet pixels. A long clip's sheet may
// be split into bands of whole rows: "files" in place of "file", with "per" frames in each. See README.md.
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
  // Detail zoom: magnification d over the fitted picture and the canvas point (ox, oy) at its top left.
  // Every facing shares it, so "All four" shows the same region of each.
  const MAX_DETAIL = 4;
  const view = { d: 1, ox: 0, oy: 0 };

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
    if (!sheets[k]) {
      const m = meta.clips[clip][face];
      if (m.files) sheets[k] = m.files.map((file) => ({ url: cfg.base + file }));
      else { const img = new Image(); img.onload = () => draw(); img.src = cfg.base + m.file; sheets[k] = [img]; }
    }
    return sheets[k];
  }
  // A band is fetched and decoded off the main thread into a bitmap: an <img> decodes on the main
  // thread when first drawn, some 45 ms for a band of 4 Mpx. Only the band shown and the next stay
  // decoded, as all of a long clip's bands would take hundreds of MB. Without fetch (file://) a
  // band is an <img>.
  function band(part, keep) {
    part.keep = keep;
    if (!keep && part.bmp) { if (part.bmp.close) part.bmp.close(); part.bmp = null; }
    if (!keep || part.bmp || part.wait) return;
    const done = (b) => { part.wait = null; if (!part.keep) { if (b.close) b.close(); return; } part.bmp = b; draw(); };
    part.wait = fetch(part.url).then((r) => r.blob()).then(createImageBitmap).then(done, () => {
      const img = new Image(); img.onload = () => done(img); img.src = part.url;
    });
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
    // With "sameScale", a clip wider than the first is drawn at the same scale as the others and
    // the stage scrolls sideways, instead of the picture shrinking to the column.
    const wide = cfg.sameScale && W > meta.canvas[0];
    const dpr = Math.min(Math.max(window.devicePixelRatio || 1, 1), 3);
    for (const f of faces()) {
      const cell = document.createElement("div"); cell.className = "cell";
      const cv = document.createElement("canvas"); cv.width = Math.round(W * z * dpr); cv.height = Math.round(H * z * dpr);
      cv.style.width = Math.round(W * z) + "px";
      if (wide) { cell.style.maxWidth = "none"; cell.style.flex = "none"; cell.style.width = `min(${Math.round(W * z)}px, ${(100 * W / meta.canvas[0]).toFixed(2)}%)`; cv.style.width = "100%"; }
      const tag = document.createElement("span"); tag.className = "tag"; tag.textContent = f.toUpperCase();
      const stamp = document.createElement("span"); stamp.className = "stamp";
      cell.append(cv, tag, stamp); stage.appendChild(cell);
      cells.push({ f, cv, stamp, k: z * dpr }); sheet(state.clip, f);
    }
    const shown = cells.map((c) => state.clip + "_" + c.f);
    for (const [k, parts] of Object.entries(sheets)) if (!shown.includes(k)) for (const b of parts) if (b.url) band(b, false);
    stage.scrollLeft = (stage.scrollWidth - stage.clientWidth) / 2;
    const n = count(); $("scrub").max = String(n - 1); state.frame = Math.min(state.frame, n - 1); clampView(); draw();
  }
  function label() {
    const n = count(); const name = CLIPS.find(c => c[0] === state.clip)[1];
    const face = state.face === "all" ? "all facings" : state.face.toUpperCase();
    return `${name} · ${face} · frame ${state.frame + 1} / ${n} · ${(state.frame / meta.fps).toFixed(2)} s${state.playing ? "" : " · paused"}`;
  }
  function draw() {
    for (const c of cells) {
      const m = meta.clips[state.clip][c.f];
      const parts = sheets[state.clip + "_" + c.f] || [], per = m.per || m.frames, p = Math.floor(state.frame / per);
      let img = parts[p];
      if (m.files) {
        parts.forEach((b, j) => band(b, j === p || j === (p + 1) % parts.length)); img = img && img.bmp;
        // Until its band is decoded (after a jump), a cell keeps the frame it shows.
        if (!img && c.drawn) continue;
      }
      const ctx = c.cv.getContext("2d");
      ctx.fillStyle = GROUND[state.ground]; ctx.fillRect(0, 0, c.cv.width, c.cv.height);
      if (img && (img.naturalWidth ?? img.width)) {
        const i = state.frame % per; const sx = (i % m.cols) * m.w, sy = Math.floor(i / m.cols) * m.h;
        const s = meta.scale || 1, k = c.k * view.d;
        // Smooth while a sheet pixel covers under 4 canvas pixels; beyond that show the pixels as rendered.
        ctx.imageSmoothingEnabled = k / s < 4; ctx.imageSmoothingQuality = "high";
        ctx.drawImage(img, sx, sy, m.w, m.h, (m.x / s - view.ox) * k, (m.y / s - view.oy) * k, m.w / s * k, m.h / s * k);
        c.drawn = true;
      }
      c.stamp.textContent = `${state.clip} ${c.f.toUpperCase()} f${state.frame + 1}${view.d > 1 ? " · " + detailText() : ""}`;
    }
    detailValue.textContent = detailText(); $("stage").classList.toggle("zoomed", view.d > 1);
    $("scrub").value = String(state.frame); $("readout").textContent = label(); $("play").textContent = state.playing ? "❚❚" : "▶";
  }
  const detailText = () => view.d.toFixed(1).replace(/\.0$/, "") + "×";
  function clampView() {
    const [W, H] = canvasSize();
    view.d = Math.min(Math.max(view.d, 1), MAX_DETAIL);
    view.ox = Math.min(Math.max(view.ox, 0), W - W / view.d);
    view.oy = Math.min(Math.max(view.oy, 0), H - H / view.d);
  }
  // Zoom by factor, keeping the picture point at (fx, fy), fractions of the picture, in place.
  function zoomAt(fx, fy, factor) {
    const [W, H] = canvasSize();
    const lx = view.ox + fx * W / view.d, ly = view.oy + fy * H / view.d;
    view.d = Math.min(Math.max(view.d * factor, 1), MAX_DETAIL);
    view.ox = lx - fx * W / view.d; view.oy = ly - fy * H / view.d;
    clampView(); draw();
  }
  function fit() { view.d = 1; view.ox = 0; view.oy = 0; draw(); }
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
  // The page's Zoom select sets the picture size; the detail controls are added here.
  const size = $("zoom").closest("label");
  if (size && size.firstChild && size.firstChild.nodeType === 3) size.firstChild.textContent = "Size ";
  const bar = document.createElement("div");
  bar.className = "vbar vdetail"; bar.setAttribute("role", "group"); bar.setAttribute("aria-label", "Detail zoom");
  bar.innerHTML = '<span class="vlbl">Detail</span>' +
    '<button class="vbtn" data-detail="out" title="Zoom out (−)" aria-label="Zoom out">−</button>' +
    '<span class="vdetail-value" aria-live="polite">1×</span>' +
    '<button class="vbtn" data-detail="in" title="Zoom in (+)" aria-label="Zoom in">+</button>' +
    '<button class="vbtn" data-detail="fit" title="Fit the picture (0)">Fit</button>' +
    '<span class="vhint">Scroll up on the picture to zoom in where you point, up to 4×. Drag to move, double-click to fit.</span>';
  ($("readout").closest(".readout") || $("stage")).before(bar);
  const detailValue = bar.querySelector(".vdetail-value");
  bar.addEventListener("click", (e) => {
    const b = e.target.closest("[data-detail]"); if (!b) return;
    if (b.dataset.detail === "fit") fit(); else zoomAt(0.5, 0.5, b.dataset.detail === "in" ? 1.5 : 1 / 1.5);
  });
  const stage = $("stage");
  const cellOf = (e) => cells.find(c => c.cv === e.target);
  stage.addEventListener("wheel", (e) => {
    const c = cellOf(e);
    // Scrolling down at fit still scrolls the page, and Shift scrolls a wide picture sideways, so the viewer never traps either.
    if (!c || e.shiftKey || !e.deltaY || e.deltaY > 0 && view.d === 1) return;
    e.preventDefault();
    const r = c.cv.getBoundingClientRect(), dy = e.deltaY * (e.deltaMode === 1 ? 33 : 1);
    zoomAt((e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height, Math.exp(-Math.max(-300, Math.min(300, dy)) * 0.003));
  }, { passive: false });
  let drag = null;
  stage.addEventListener("pointerdown", (e) => {
    const c = cellOf(e); if (!c || view.d === 1 || e.button !== 0) return;
    e.preventDefault(); c.cv.setPointerCapture(e.pointerId);
    const r = c.cv.getBoundingClientRect();
    drag = { x: e.clientX, y: e.clientY, ox: view.ox, oy: view.oy, w: r.width, h: r.height };
    stage.classList.add("dragging");
  });
  stage.addEventListener("pointermove", (e) => {
    if (!drag) return;
    const [W, H] = canvasSize();
    view.ox = drag.ox - (e.clientX - drag.x) / drag.w * W / view.d;
    view.oy = drag.oy - (e.clientY - drag.y) / drag.h * H / view.d;
    clampView(); draw();
  });
  const endDrag = () => { drag = null; stage.classList.remove("dragging"); };
  stage.addEventListener("pointerup", endDrag); stage.addEventListener("pointercancel", endDrag);
  stage.addEventListener("dblclick", (e) => { if (cellOf(e)) fit(); });
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
    else if (e.key === "+" || e.key === "=") { e.preventDefault(); zoomAt(0.5, 0.5, 1.5); }
    else if (e.key === "-" || e.key === "_") { e.preventDefault(); zoomAt(0.5, 0.5, 1 / 1.5); }
    else if (e.key === "0") { e.preventDefault(); fit(); }
  });
  build(); setPlay(true); requestAnimationFrame(tick);
})();
