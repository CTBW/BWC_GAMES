// Height chart for the Meridius units (unit-heights.html): every sandbox unit to one scale,
// from the front and the side, with its measured height, width and depth, and a way to try
// other sizes. The data and pictures (units.js, img/) are written by
// projects/meridius/source/godot/tests/visual/unit_heights.gd.
(() => {
  const D = window.UNIT_HEIGHTS;
  const $ = (id) => document.getElementById(id);
  if (!D) { $("lineup").textContent = "The measurements (unit-heights/units.js) could not be read. Reload the tab to try again."; return; }
  const BASE = "unit-heights/";
  const KEY = "meridius-unit-heights";
  const FACTION = { player: "Garrison", enemy: "Hillsvain Host" };
  // Loadouts and variants that share the charted unit's body, so a change to it applies to them too.
  const SHARED = { goblin_rabble_knife: ["goblin_rabble_hatchet", "goblin_rabble_cleaver"], orc_brute: ["orc_brute_dual"] };
  const NOTES = { goblin_rabble_knife: "Knife loadout; the hatchet and cleaver goblins share the body.",
    orc_brute: "One club; the two-club brute shares the body. Bare face, both pauldrons.",
    footman: "In his squad's dress (line kit), a man of the line, not the captain.",
    wolf_scout: "The first Wolf Scout export; the ears are counted in the height." };
  const state = { view: "front", gear: true, sort: "roster", paper: "paper", size: 0, sel: null, adj: {} };
  try { Object.assign(state, JSON.parse(localStorage.getItem(KEY) || "{}")); } catch (e) {}
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) {} };
  const U = D.units;
  const byId = Object.fromEntries(U.map((u) => [u.id, u]));
  if (state.sel && !byId[state.sel]) state.sel = null;
  for (const id of Object.keys(state.adj)) if (!byId[id]) delete state.adj[id];
  const cosE = Math.cos(D.game.elevation_deg * Math.PI / 180);
  const f2 = (v) => v.toFixed(2);
  const m = (v) => f2(v) + " m";
  const name = (u) => u.title.replace(/ · .*/, "");
  const el = (tag, cls, parent) => { const e = document.createElement(tag); if (cls) e.className = cls; if (parent) parent.appendChild(e); return e; };
  const svgEl = (tag, attrs, parent) => {
    const e = document.createElementNS("http://www.w3.org/2000/svg", tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  };

  // A unit's size as charted: measured, then the tried height (h, uniform scale) and width (w, on top, width and depth).
  function dims(u) {
    const a = state.adj[u.id] || { h: 1, w: 1 };
    const fb = u.front.body, sb = u.side.body, ff = u.front.full, sf = u.side.full;
    const sx = a.h * a.w, sy = a.h;
    return { a, sx, sy, adjusted: a.h !== 1 || a.w !== 1,
      h: fb.top * sy, w: (fb.right - fb.left) * sx, d: (sb.right - sb.left) * sx,
      gh: Math.max(ff.top, sf.top) * sy, gw: (ff.right - ff.left) * sx, gd: (sf.right - sf.left) * sx,
      h0: fb.top, w0: fb.right - fb.left, d0: sb.right - sb.left,
      sink: -Math.min(fb.bottom, sb.bottom) * sy };
  }
  const px = (h) => h * D.game.ppu * cosE;
  const room = (u, s) => u.squad.file_m - s.w;
  const sorted = () => {
    const list = U.slice();
    if (state.sort === "height") list.sort((a, b) => dims(b).h - dims(a).h);
    return list;
  };
  const pic = (u, v) => (state.gear ? u[v].img : u[v].img_body);

  // --- Toolbar ----------------------------------------------------------------------------
  function chips(id, key, items) {
    const box = $(id);
    box.querySelectorAll("button").forEach((b) => b.remove());
    for (const [val, label] of items) {
      const b = el("button", "hc-chip", box);
      b.type = "button"; b.textContent = label;
      b.setAttribute("aria-pressed", String(state[key] === val));
      b.addEventListener("click", () => { state[key] = val; save(); render(); });
    }
  }
  function toolbar() {
    chips("viewChips", "view", [["front", "Front"], ["side", "Side"], ["both", "Front + side"]]);
    chips("gearChips", "gear", [[true, "Shown"], [false, "Hidden"]]);
    chips("sortChips", "sort", [["roster", "Roster"], ["height", "Tallest first"]]);
    chips("paperChips", "paper", [["paper", "Paper"], ["dark", "Dark"]]);
    $("size").value = String(state.size);
    $("hc").dataset.paper = state.paper;
  }
  $("size").addEventListener("change", (e) => { state.size = Number(e.target.value); save(); lineup(); });

  // --- The lineup -------------------------------------------------------------------------
  let ppmNow = 100;
  function lineup() {
    const box = $("lineup");
    const views = state.view === "both" ? ["front", "side"] : [state.view];
    const list = sorted();
    const GAP = 0.3, PAIR = 0.1, PAD = 0.3;
    let topM = 2.1;
    for (const u of list) {
      const s = dims(u);
      for (const v of views) topM = Math.max(topM, pic(u, v).top * s.sy);
      topM = Math.max(topM, s.h * u.squad.scale_range[1] + 0.25);
    }
    topM = Math.ceil((topM + 0.2) * 10) / 10;
    let x = PAD;
    const cols = [];
    for (const u of list) {
      const s = dims(u), col = { u, s, figs: [], x0: x };
      views.forEach((v, i) => {
        const r = pic(u, v), w = r.w * s.sx;
        col.figs.push({ v, r, x, w, cx: x - r.left * s.sx });
        x += w + (i < views.length - 1 ? PAIR : 0);
      });
      col.x1 = x; x += GAP; cols.push(col);
    }
    const widthM = x - GAP + PAD;
    const axisPx = 54;
    const avail = Math.max(400, box.clientWidth - axisPx - 2);
    const ppm = state.size || Math.max(55, Math.min(240, avail / widthM));
    ppmNow = ppm;
    // With both views the depth's line sits a row below the width's, so narrow units' labels don't meet.
    const both = views.length > 1, below = both ? 78 : 60;
    // 10 px over the top line keeps a label there whole.
    const groundY = Math.round(topM * ppm) + 10;
    const H = groundY + below, W = Math.ceil(widthM * ppm);
    box.innerHTML = "";
    const board = el("div", "hc-board", box);
    board.style.height = H + "px";
    const axis = el("div", "hc-axis", board);
    axis.style.height = H + "px";
    const plot = el("div", "hc-plot", board);
    plot.style.width = W + "px"; plot.style.height = H + "px";
    const svg = svgEl("svg", { class: "grid", width: W, height: H, viewBox: `0 0 ${W} ${H}` }, plot);
    for (let k = 1; k <= Math.round(topM * 10); k++) {
      const y = groundY - k * 0.1 * ppm + 0.5;
      const major = k % 5 === 0;
      svgEl("line", { x1: 0, x2: W, y1: y, y2: y, class: major ? "major" : "minor" }, svg);
      if (major) { const t = el("span", "", axis); t.style.top = y + "px"; t.textContent = (k / 10).toFixed(1) + " m"; }
    }
    svgEl("line", { x1: 0, x2: W, y1: groundY, y2: groundY, class: "ground" }, svg);
    const t0 = el("span", "", axis); t0.style.top = groundY + "px"; t0.textContent = "0";
    const P = (vm) => vm * ppm;
    for (const c of cols) {
      const { u, s } = c;
      const hit = el("div", "hc-col" + (state.sel === u.id ? " sel" : ""), plot);
      hit.style.left = P(c.x0 - 0.12) + "px"; hit.style.width = P(c.x1 - c.x0 + 0.24) + "px";
      hit.title = `${u.title}: ${m(s.h)} tall, ${m(s.w)} wide, ${m(s.d)} deep. Click to try another size.`;
      hit.addEventListener("mouseenter", () => showRef(axis, plot, groundY, ppm, u, false));
      hit.addEventListener("mouseleave", () => showRef(axis, plot, groundY, ppm, null, false));
      hit.addEventListener("click", () => { state.sel = u.id; save(); render(); $("adjust").scrollIntoView({ block: "nearest", behavior: "smooth" }); });
      const [lo, hi] = u.squad.scale_range;
      if (hi - lo > 0.001) {
        const b = el("div", "hc-band", plot);
        b.style.left = P(c.x0 - 0.06) + "px"; b.style.width = P(c.x1 - c.x0 + 0.12) + "px";
        b.style.top = (groundY - P(s.h * hi)) + "px"; b.style.height = P(s.h * (hi - lo)) + "px";
      }
      for (const f of c.figs) {
        const d = el("div", "hc-fig", plot);
        d.style.left = P(f.x) + "px"; d.style.width = P(f.w) + "px";
        d.style.top = (groundY - P(f.r.top * s.sy)) + "px"; d.style.height = P(f.r.h * s.sy) + "px";
        d.style.backgroundImage = `url("${BASE}${f.r.file}")`;
        d.setAttribute("role", "img");
        d.setAttribute("aria-label", `${u.title}, ${f.v === "front" ? "front" : "right side"}`);
        const b = u[f.v].body;
        const dl = el("div", "hc-dim", plot);
        dl.style.left = P(f.cx + b.left * s.sx) + "px"; dl.style.width = P((b.right - b.left) * s.sx) + "px";
        dl.style.top = (groundY + (both && f.v === "side" ? 30 : 12)) + "px";
        el("span", "", dl).textContent = f.v === "front" ? `${f2(s.w)} wide` : `${f2(s.d)} deep`;
      }
      if (s.adjusted && Math.abs(s.h - s.h0) > 0.004) {
        const was = el("div", "hc-top was", plot);
        was.style.left = P(c.x0 - 0.06) + "px"; was.style.width = P(c.x1 - c.x0 + 0.12) + "px";
        was.style.top = (groundY - P(s.h0)) + "px";
      }
      const top = el("div", "hc-top", plot);
      top.style.left = P(c.x0 - 0.06) + "px"; top.style.width = P(c.x1 - c.x0 + 0.12) + "px";
      top.style.top = (groundY - P(s.h)) + "px";
      const pill = el("div", "hc-pill" + (s.adjusted ? " adj" : ""), plot);
      // Above the size spread's band, when the squad has one.
      pill.style.left = P((c.x0 + c.x1) / 2) + "px"; pill.style.top = (groundY - P(s.h * Math.max(1, hi))) + "px";
      pill.textContent = m(s.h);
      if (s.adjusted) el("small", "", pill).textContent = "was " + f2(s.h0);
      const nm = el("div", "hc-name", plot);
      nm.style.left = P((c.x0 + c.x1) / 2) + "px"; nm.style.top = (groundY + below - 22) + "px";
      el("i", "dot-" + u.faction, nm);
      nm.appendChild(document.createTextNode(name(u)));
    }
    if (state.sel) showRef(axis, plot, groundY, ppm, byId[state.sel], true);
    legend();
  }
  // The dashed line across the chart at a unit's height (hover), or the chosen unit's (pinned).
  function showRef(axis, plot, groundY, ppm, u, pinned) {
    const cls = pinned ? "pinned" : "hover";
    plot.querySelectorAll(".hc-ref." + cls).forEach((e) => e.remove());
    axis.querySelectorAll(".ref." + cls).forEach((e) => e.remove());
    if (!u) return;
    const h = dims(u).h, y = groundY - h * ppm;
    const line = el("div", "hc-ref " + cls, plot);
    line.style.top = y + "px";
    const t = el("span", "ref " + cls, axis);
    t.style.top = y + "px"; t.textContent = f2(h);
  }
  function legend() {
    const lg = $("legend");
    const tile = D.game.tile_m;
    lg.innerHTML = "";
    const add = (html) => { const s = el("span", "", lg); s.innerHTML = html; return s; };
    add('<i class="lg-gar"></i>Garrison');
    add('<i class="lg-host"></i>Hillsvain Host');
    add('<i class="lg-band" style="display:inline-block;vertical-align:-1px;margin-right:6px"></i>How much the men of a squad differ in size');
    const sc = add("");
    sc.className = "scale";
    sc.innerHTML = `<b style="width:${Math.round(ppmNow)}px"></b>1 m <b style="width:${Math.round(tile * ppmNow)}px"></b>1 tile = ${f2(tile)} m`;
  }

  // --- Try a size -------------------------------------------------------------------------
  function adjustPanel() {
    const u = state.sel ? byId[state.sel] : null;
    const on = !!u;
    for (const id of ["hRange", "hNum", "wRange", "wNum", "adjReset"]) $(id).disabled = !on;
    if (!u) {
      $("adjName").textContent = "Click a unit in the chart";
      $("adjHint").textContent = "Then set its height and width here. The chart, the unit's card and the table follow, and the change is listed on the right to send on.";
      $("hOut").textContent = $("wOut").textContent = ""; $("adjFacts").innerHTML = "";
      return;
    }
    const s = dims(u);
    $("adjName").textContent = u.title;
    $("adjHint").textContent = `Measured ${m(s.h0)} tall, ${m(s.w0)} wide and ${m(s.d0)} deep. Height scales the whole unit; width widens it on top of that (width and depth together).`;
    $("hRange").value = $("hNum").value = f2(s.h);
    $("wRange").value = $("wNum").value = f2(s.w);
    $("hOut").textContent = `scale ×${s.a.h.toFixed(3)} · ≈${Math.round(px(s.h))} px tall on screen at zoom 1`;
    $("wOut").textContent = `width ×${(s.w / s.w0).toFixed(3)} (×${s.a.w.toFixed(3)} on top of the height's) · ${m(s.d)} deep`;
    const r = room(u, s);
    const sq = u.squad;
    const spread = sq.scale_range[1] - sq.scale_range[0] > 0.001
      ? `<br>In the squad the men vary ×${f2(sq.scale_range[0])}–${f2(sq.scale_range[1])}: ${m(s.h * sq.scale_range[0])} to ${m(s.h * sq.scale_range[1])}.` : "";
    $("adjFacts").innerHTML = `${sq.title}: ${sq.size} men, ${f2(sq.file_m)} m apart in a rank, ` +
      (r < 0.05 ? `<span class="warn">${r < 0 ? `their bodies overlap by ${m(-r)}` : `only ${m(r)} between them`}</span>.` : `${m(r)} between their bodies.`) + spread;
  }
  function setAdj(h, w) {
    const u = byId[state.sel]; if (!u) return;
    const s = dims(u);
    const a = { h: h / s.h0, w: w / (s.w0 * (h / s.h0)) };
    if (Math.abs(a.h - 1) < 0.0005) a.h = 1;
    if (Math.abs(a.w - 1) < 0.0005) a.w = 1;
    if (a.h === 1 && a.w === 1) delete state.adj[u.id]; else state.adj[u.id] = a;
    save(); render(false);
  }
  const num = (v, fb) => (Number.isFinite(v) && v > 0 ? v : fb);
  $("hRange").addEventListener("input", (e) => { const s = dims(byId[state.sel]); setAdj(Number(e.target.value), s.w / s.h * Number(e.target.value)); });
  $("hNum").addEventListener("change", (e) => { const s = dims(byId[state.sel]); const h = num(Number(e.target.value), s.h); setAdj(h, s.w / s.h * h); });
  $("wRange").addEventListener("input", (e) => { setAdj(dims(byId[state.sel]).h, Number(e.target.value)); });
  $("wNum").addEventListener("change", (e) => { const s = dims(byId[state.sel]); setAdj(s.h, num(Number(e.target.value), s.w)); });
  $("adjReset").addEventListener("click", () => { delete state.adj[state.sel]; save(); render(); });
  $("resetAll").addEventListener("click", () => { state.adj = {}; save(); render(); });
  // Copies in the click itself: the clipboard API can wait on a permission that is never asked.
  // If the browser refuses, the text stays selected for Ctrl+C.
  $("copy").addEventListener("click", () => {
    const r = document.createRange(); r.selectNodeContents($("changes"));
    const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r);
    let ok = false;
    try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
    if (ok) sel.removeAllRanges();
    $("copied").textContent = ok ? "Copied" : "Selected: press Ctrl+C";
    $("copied").hidden = false; setTimeout(() => { $("copied").hidden = true; }, 2400);
  });
  function changes() {
    const ids = U.map((u) => u.id).filter((id) => state.adj[id]);
    $("copy").disabled = $("resetAll").disabled = !ids.length;
    if (!ids.length) { $("changes").textContent = "No changes yet. Sizes you try in the chart are listed here."; return; }
    const lines = [`Meridius unit sizes to set (height chart, measured ${D.captured}, idle first frame, body without held gear):`];
    for (const id of ids) {
      const u = byId[id], s = dims(u);
      let t = `- ${u.title} (${id}${SHARED[id] ? ", also " + SHARED[id].join(", ") : ""}): `;
      t += Math.abs(s.a.h - 1) > 0.0005 ? `height ${f2(s.h0)} → ${f2(s.h)} m = scale ×${s.a.h.toFixed(3)}` : `height ${f2(s.h0)} m unchanged`;
      t += Math.abs(s.a.w - 1) > 0.0005
        ? `; then width and depth ×${s.a.w.toFixed(3)} on top: width ${f2(s.w0)} → ${f2(s.w)} m, depth ${f2(s.d0)} → ${f2(s.d)} m`
        : `; width ${f2(s.w0)} → ${f2(s.w)} m, depth ${f2(s.d0)} → ${f2(s.d)} m`;
      lines.push(t + ".");
    }
    $("changes").textContent = lines.join("\n");
  }

  // --- Each unit --------------------------------------------------------------------------
  const CPPM = 112;
  function cards() {
    const box = $("cards");
    box.innerHTML = "";
    for (const u of U) {
      const s = dims(u);
      const card = el("article", "hc-card", box);
      card.id = "unit-" + u.id;
      const hd = el("header", "", card);
      el("h3", "", hd).textContent = u.title;
      const tag = el("span", "tag", hd);
      el("i", "dot-" + u.faction, tag); tag.appendChild(document.createTextNode(FACTION[u.faction]));
      if (s.adjusted) el("span", "adjmark", hd).textContent = "trying a new size";
      const rf = pic(u, "front"), rs = pic(u, "side");
      const L = 74, GAP = 36, RPAD = 18, TOPPAD = 24, BELOW = 50;
      const topM = Math.max(2.05, rf.top * s.sy, rs.top * s.sy, s.h + 0.12);
      const groundY = Math.round(TOPPAD + topM * CPPM);
      const fx = L, fw = rf.w * s.sx * CPPM, sxp = fx + fw + GAP, sw = rs.w * s.sx * CPPM;
      const W = Math.ceil(sxp + sw + RPAD), H = groundY + BELOW;
      const stage = el("div", "hc-stage", card);
      stage.style.height = H + "px"; stage.style.width = W + "px"; stage.style.maxWidth = "100%";
      const place = (r, x, alt) => {
        const img = el("img", "", stage);
        img.src = BASE + r.file; img.alt = alt; img.loading = "lazy"; img.decoding = "async";
        img.width = r.px[0]; img.height = r.px[1];
        img.style.left = x + "px"; img.style.top = (groundY - r.top * s.sy * CPPM) + "px";
        img.style.width = r.w * s.sx * CPPM + "px"; img.style.height = r.h * s.sy * CPPM + "px";
      };
      const gearTxt = state.gear ? "" : ", without its weapons";
      place(rf, fx, `${u.title} from the front${gearTxt}, idle`);
      place(rs, sxp, `${u.title} from the right side${gearTxt}, idle`);
      const svg = svgEl("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}` }, stage);
      for (let k = 1; k * 0.5 <= topM; k++) {
        const y = groundY - k * 0.5 * CPPM + 0.5;
        svgEl("line", { x1: 0, x2: W, y1: y, y2: y, class: "gm" }, svg);
        svgEl("text", { x: W - 6, y: y - 4, "text-anchor": "end", class: "small" }, svg).textContent = (k * 0.5).toFixed(1);
      }
      svgEl("line", { x1: 0, x2: W, y1: groundY, y2: groundY, class: "gr" }, svg);
      const cxF = fx - rf.left * s.sx * CPPM, cxS = sxp - rs.left * s.sx * CPPM;
      const bF = u.front.body, bS = u.side.body;
      const topY = groundY - s.h * CPPM;
      // Height: a dimension line left of the front view, and a dashed line across both views.
      const hx = 30;
      svgEl("line", { x1: hx - 5, x2: W - 40, y1: topY, y2: topY, class: "ext" }, svg);
      svgEl("path", { d: `M${hx} ${groundY}V${topY}M${hx - 6} ${groundY}h12M${hx - 6} ${topY}h12`, class: "dl" }, svg);
      const midY = (groundY + topY) / 2;
      const hl = svgEl("g", { transform: `translate(${hx} ${midY}) rotate(-90)` }, svg);
      svgEl("rect", { x: -30, y: -10, width: 60, height: 20, rx: 10, class: "bg" }, hl);
      const ht = svgEl("text", { x: 0, y: 4.5, "text-anchor": "middle" }, hl);
      ht.textContent = m(s.h);
      if (s.adjusted) ht.setAttribute("class", "acc");
      // Width under the front view, depth under the side view.
      const dim = (x1, x2, label) => {
        const y = groundY + 14;
        svgEl("path", { d: `M${x1} ${y}H${x2}M${x1} ${y - 5}v10M${x2} ${y - 5}v10`, class: "dl" }, svg);
        svgEl("text", { x: (x1 + x2) / 2, y: y + 18, "text-anchor": "middle" }, svg).textContent = label;
      };
      dim(cxF + bF.left * s.sx * CPPM, cxF + bF.right * s.sx * CPPM, `${m(s.w)} wide`);
      dim(cxS + bS.left * s.sx * CPPM, cxS + bS.right * s.sx * CPPM, `${m(s.d)} deep`);
      svgEl("text", { x: fx, y: 15, class: "cap" }, svg).textContent = "FRONT";
      svgEl("text", { x: sxp, y: 15, class: "cap" }, svg).textContent = "SIDE";
      // The facts.
      const dl = el("dl", "", card);
      const row = (k, v) => { el("dt", "", dl).textContent = k; const d = el("dd", "", dl); d.innerHTML = v; };
      row("With weapons", `${m(s.gh)} tall, ${m(s.gw)} wide, ${m(s.gd)} deep`);
      const diff = u.height_m * s.a.h - s.h;
      row("Game height", `${m(u.height_m * s.a.h)} <span class="${Math.abs(diff) > 0.05 ? "warn" : ""}">(${Math.abs(diff) > 0.05 ? (diff > 0 ? f2(diff) + " m above" : f2(-diff) + " m below") + " the figure's top" : "matches the figure"})</span>`);
      row("On screen", `≈${Math.round(px(s.h))} px tall at the sandbox's zoom 1 (the footman ≈${Math.round(px(dims(byId.footman || u).h))} px)`);
      const r = room(u, s);
      row("In its squad", `${u.squad.size} men, ${f2(u.squad.file_m)} m apart: ${r < 0.05 ? `<span class="warn">${r < 0 ? "bodies overlap by " + m(-r) : "only " + m(r) + " between them"}</span>` : m(r) + " between their bodies"}`);
      const [lo, hi] = u.squad.scale_range;
      if (hi - lo > 0.001) row("Size spread", `×${f2(lo)}–${f2(hi)}: ${m(s.h * lo)} to ${m(s.h * hi)}`);
      if (s.sink > 0.03) row("Feet", `<span class="warn">${m(s.sink)} below the ground in this idle</span>: ${m(s.h + s.sink)} from sole to top`);
      if (NOTES[u.id]) row("Note", NOTES[u.id]);
    }
  }

  // --- The table --------------------------------------------------------------------------
  const COLS = [
    ["Unit", (u) => name(u), (u) => `${u.title}`],
    ["Height", (u, s) => s.h, (u, s) => m(s.h), true],
    ["Width", (u, s) => s.w, (u, s) => m(s.w), true],
    ["Depth", (u, s) => s.d, (u, s) => m(s.d), true],
    ["With weapons (H × W × D)", (u, s) => s.gh, (u, s) => `${f2(s.gh)} × ${f2(s.gw)} × ${f2(s.gd)} m`, false],
    ["Game height", (u, s) => u.height_m * s.a.h, (u, s) => m(u.height_m * s.a.h), false],
    ["On screen", (u, s) => px(s.h), (u, s) => `≈${Math.round(px(s.h))} px`, false],
    ["Rank spacing", (u) => u.squad.file_m, (u) => m(u.squad.file_m), false],
    ["Room between men", (u, s) => room(u, s), (u, s) => { const r = room(u, s); return r < 0.05 ? `<span class="warn">${m(r)}</span>` : m(r); }, true],
  ];
  let tsort = { i: 1, dir: -1 };
  function table() {
    const t = $("table");
    t.innerHTML = "";
    const thead = el("thead", "", t), tr = el("tr", "", thead);
    COLS.forEach(([label], i) => {
      const th = el("th", i ? "num" : "", tr);
      th.textContent = label; th.tabIndex = 0;
      if (tsort.i === i) th.setAttribute("aria-sort", tsort.dir > 0 ? "ascending" : "descending");
      const go = () => { tsort = { i, dir: tsort.i === i ? -tsort.dir : (i ? -1 : 1) }; table(); };
      th.addEventListener("click", go);
      th.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); go(); } });
    });
    const rows = U.map((u) => ({ u, s: dims(u) }));
    rows.sort((a, b) => {
      const ka = COLS[tsort.i][1](a.u, a.s), kb = COLS[tsort.i][1](b.u, b.s);
      return (ka < kb ? -1 : ka > kb ? 1 : 0) * tsort.dir;
    });
    const tb = el("tbody", "", t);
    for (const { u, s } of rows) {
      const r = el("tr", "", tb);
      COLS.forEach(([, , show, adj], i) => {
        const td = el("td", (i ? "num" : "") + (adj && s.adjusted ? " adj" : ""), r);
        td.innerHTML = show(u, s);
      });
    }
  }

  function render(all = true) {
    if (all) toolbar();
    lineup(); adjustPanel(); changes(); cards(); table();
  }
  let rz;
  window.addEventListener("resize", () => { clearTimeout(rz); rz = setTimeout(() => { if (!state.size) lineup(); }, 120); });
  render();
})();
