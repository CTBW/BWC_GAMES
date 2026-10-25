// The battle ground with relief (scripts/render/relief.gd, relief_terrain.gd).
// Drawn once into the terrain layer on a grid mesh whose UV is the grid point
// (tile centres at integers):
//  - vertex: lifts the mesh by the surface (surf() is relief.gd surface(),
//    keep the two identical);
//  - fragment: the ground's material from the tile categories (painted
//    top-down textures at their painted scale, two scales and turns mixed so
//    no repeat shows, dry golden patches on crests and sunny slopes, worn
//    earth), crumbling earth banks with strata and a grass lip where a slope
//    falls steeply toward the camera, then light: the sun of the sprites' cast
//    shadows (from grid -x, about 50 degrees up) on exaggerated normals so the
//    hills read, the hills' own shadows, warm high ground and cool hollows,
//    pools of shade under the trees. Water last.
// Noise here is shading only and has no CPU twin.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D h_tex : filter_nearest;
uniform sampler2D cat_tex : filter_nearest;
uniform sampler2D occ_tex : filter_linear;
uniform int gw;
uniform int gh;
uniform int border;
uniform vec4 phase;
uniform int seed;
uniform bool camp;
uniform bool height_view = false;
// Highest surface level on the map (relief.gd max_h): the height tint's range.
uniform float hmax = 4.0;

uniform sampler2D tex_grass : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_dry : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_dirt : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_forest : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_rock : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_mud : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_stone : repeat_enable, filter_linear_mipmap_anisotropic;

const float LH = 26.0;
const float WARP = 0.0;
// Grid units of true height per level (26 px over 78.4 px per vertical unit).
const float TRUE_K = 0.3316;
// Height scale of the shading normals: about three times true, so gentle
// hills still turn a lit and a shaded face to the sun.
const float SHADE_K = 1.1;
// Mip bias of the painted textures: a touch softer than full detail.
const float TEX_BIAS = 0.4;

varying vec2 grid;

// ---------------------------------------------------------------- surface

float tile_h(int x, int y) {
	ivec2 q = ivec2(clamp(x + border, 0, gw - 1), clamp(y + border, 0, gh - 1));
	return texelFetch(h_tex, q, 0).r;
}

// Catmull-Rom weights of the four samples around fraction t.
vec4 cr(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return vec4(-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2);
}

float surf(vec2 p) {
	float wx = p.x + WARP * (0.6 * sin(p.x * 0.91 + p.y * 0.37 + phase.x) + 0.4 * sin(p.x * 0.23 - p.y * 1.31 + phase.y));
	float wy = p.y + WARP * (0.6 * sin(p.y * 0.87 - p.x * 0.41 + phase.z) + 0.4 * sin(p.y * 0.29 + p.x * 1.17 + phase.w));
	float fxi = floor(wx);
	float fyi = floor(wy);
	int ix = int(fxi);
	int iy = int(fyi);
	vec4 wxs = cr(wx - fxi);
	vec4 wys = cr(wy - fyi);
	float sum = 0.0;
	for (int j = 0; j < 4; j++) {
		vec4 row = vec4(tile_h(ix - 1, iy - 1 + j), tile_h(ix, iy - 1 + j), tile_h(ix + 1, iy - 1 + j), tile_h(ix + 2, iy - 1 + j));
		sum += wys[j] * dot(wxs, row);
	}
	return sum;
}

void vertex() {
	grid = UV;
	VERTEX.y -= surf(UV) * LH;
}

// ---------------------------------------------------------------- noise

uint uhash(ivec2 p, uint s) {
	uvec2 q = uvec2(p + ivec2(20000)) * uvec2(1597334677u, 3812015801u);
	uint n = (q.x ^ q.y ^ (s * 2654435761u)) * 1597334677u;
	return n ^ (n >> 16u);
}

float hash(ivec2 p, uint s) {
	return float(uhash(p, s) >> 8u) / 16777215.0;
}

float vnoise(vec2 p, uint s) {
	vec2 i = floor(p);
	vec2 f = p - i;
	ivec2 q = ivec2(i);
	float a = hash(q, s);
	float b = hash(q + ivec2(1, 0), s);
	float c = hash(q + ivec2(0, 1), s);
	float d = hash(q + ivec2(1, 1), s);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, uint s) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * vnoise(p, s + uint(i) * 13u);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum / 0.9375;
}

// ---------------------------------------------------------------- categories
// grass 0, dirt 1, brush 2, forest 3, stone 4, water 5, shallows 6, floor 7, mud 8

int cat_at(int x, int y) {
	ivec2 q = ivec2(clamp(x + border, 0, gw - 1), clamp(y + border, 0, gh - 1));
	return int(texelFetch(cat_tex, q, 0).r * 255.0 + 0.5);
}

void corners(vec2 p, out ivec4 cats, out vec2 t) {
	vec2 i = floor(p);
	t = p - i;
	int x = int(i.x);
	int y = int(i.y);
	cats = ivec4(cat_at(x, y), cat_at(x + 1, y), cat_at(x, y + 1), cat_at(x + 1, y + 1));
}

float wcat(ivec4 c, vec2 t, int k) {
	float a = c.x == k ? 1.0 : 0.0;
	float b = c.y == k ? 1.0 : 0.0;
	float cc = c.z == k ? 1.0 : 0.0;
	float d = c.w == k ? 1.0 : 0.0;
	return a + (b - a) * t.x + (cc - a) * t.y + (a - b - cc + d) * t.x * t.y;
}

// A patchy edge: the weight as a soft step bent by noise.
float patchy(float w, float n, float soft) {
	return smoothstep(0.5 - soft, 0.5 + soft, w + (n - 0.5) * 0.55);
}

// ---------------------------------------------------------------- materials

// A texture spanning `scale` grid units, mixed with a turned, larger copy of
// itself. Mips follow the screen, so the painted detail stays crisp without
// sparkling.
vec3 tex2(sampler2D t, vec2 p, float scale, float mixn) {
	vec3 a = texture(t, p / scale, TEX_BIAS).rgb;
	vec2 q = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8) / (scale * 1.37) + vec2(0.37, 0.71);
	vec3 b = texture(t, q, TEX_BIAS).rgb;
	return mix(a, b, mixn);
}

// tex2 with its painted detail at `k` of its contrast around the local mean
// (a far mip): the strokes stay crisp and the hills' light carries over them.
vec3 soft2(sampler2D t, vec2 p, float scale, float mixn, float k) {
	vec3 m = texture(t, p / scale, TEX_BIAS + 3.5).rgb;
	return mix(m, tex2(t, p, scale, mixn), k);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 saturate_by(vec3 c, float k) {
	return mix(vec3(luma(c)), c, k);
}

// A block fallen from a bank, in its own frame q (x right, y down, about
// -1..1), cut like the slabs in concept A: a flat top turned to the sky over
// a lit left face and a shaded right face, its outline broken, moss on top.
// Returns the colour and the coverage.
vec4 fallen_block(vec2 q, ivec2 id, uint k, vec3 stone, vec3 moss) {
	float d = pow(pow(abs(q.x), 3.2) + pow(abs(q.y), 3.2), 1.0 / 3.2) + (fbm(q * 2.4 + vec2(id) * 3.7, k) - 0.5) * 0.22;
	if (d >= 1.0) {
		return vec4(0.0);
	}
	// The front corner, and the top's lower edge falling away from it.
	float xc = (hash(id, k + 1u) - 0.5) * 0.5;
	float ty = mix(-0.05, 0.2, hash(id, k + 2u)) - 0.45 * abs(q.x - xc) + (fbm(q * 4.0 + 9.0, k + 3u) - 0.5) * 0.12;
	// The faces meet in softened edges, as a brush would leave them.
	float wTop = smoothstep(-0.025, 0.025, ty - q.y);
	float wLeft = smoothstep(-0.04, 0.04, xc + (fbm(q * 3.0, k + 5u) - 0.5) * 0.15 - q.x);
	vec3 L = normalize(vec3(-0.55, -0.65, 0.55));
	float lTop = max(dot(normalize(vec3((hash(id, k + 4u) - 0.5) * 0.5, -0.6, 0.8)), L), 0.0);
	float lLeft = max(dot(normalize(vec3(-0.75, 0.3, 0.5)), L), 0.0);
	float lRight = max(dot(normalize(vec3(0.75, 0.3, 0.5)), L), 0.0);
	float lum = 0.45 + 0.8 * mix(mix(lRight, lLeft, wLeft), lTop, wTop);
	// A lit rim along the top's edge, a crisp shade just under it.
	lum *= 1.0 + (1.0 - smoothstep(0.0, 0.08, ty - q.y)) * 0.14 * wTop - (1.0 - smoothstep(0.0, 0.06, q.y - ty)) * 0.18 * (1.0 - wTop);
	lum *= 0.93 + 0.14 * fbm(q * 3.0 + vec2(id), k + 6u);
	// Warm where the sun strikes, cool in the shaded face.
	vec3 col = stone * lum * mix(vec3(0.9, 0.95, 1.06), vec3(1.04, 1.0, 0.94), max(wTop, wLeft));
	// A little moss at the back of the top, not a cushion.
	float m = wTop * smoothstep(0.0, 0.3, ty - q.y) * smoothstep(0.56, 0.68, fbm(q * 2.2 + vec2(id) * 1.9, k + 7u));
	col = mix(col, moss * mix(0.9, 1.1, lum - 0.6), m * 0.75);
	col *= 1.0 - smoothstep(0.84, 1.0, d) * mix(0.45, 0.15, wTop);
	return vec4(col, 1.0 - smoothstep(0.94, 1.0, d));
}

void fragment() {
	vec2 p = grid;
	uint s = uint(seed) % 9973u;

	// Shape: height, slope and curvature of the surface here.
	float e = 0.08;
	float hC = surf(p);
	float hxp = surf(p + vec2(e, 0.0));
	float hxm = surf(p - vec2(e, 0.0));
	float hyp = surf(p + vec2(0.0, e));
	float hym = surf(p - vec2(0.0, e));
	vec2 grad = vec2(hxp - hxm, hyp - hym) / (2.0 * e);
	float lap = (hxp + hxm + hyp + hym - 4.0 * hC) / (e * e);
	float slope = length(grad);
	// 1 where the ground falls straight toward the camera (+x+y).
	float facing = slope > 1e-3 ? -(grad.x + grad.y) / (slope * 1.41421) : 0.0;
	float hn = clamp(hC / max(hmax, 1.0), 0.0, 1.0);
	// Curvature in levels per tile squared: a broad hilltop is about -0.4,
	// the lip of a bank -5 or more.
	float crest = clamp(-lap * 1.4, 0.0, 1.0);
	float hollow = clamp(lap * 1.4, 0.0, 1.0);

	// Noise fields.
	float nMacro = fbm(p * 0.09, s + 3u);
	float nMid = fbm(p * 0.38, s + 9u);
	float nSwap = smoothstep(0.3, 0.7, vnoise(p * 0.3, s + 21u));
	float nEdge = fbm(p * 2.2, s + 5u);
	float nFine = fbm(p * 5.5, s + 87u);

	// Categories, with organic edges (the sample point wanders).
	vec2 pj = p + (vec2(fbm(p * 1.4, s + 5u), fbm(p * 1.4, s + 77u)) - 0.5) * 0.9;
	ivec4 cj;
	vec2 tj;
	corners(pj, cj, tj);
	ivec4 cp;
	vec2 tp;
	corners(p, cp, tp);
	float wDirt = wcat(cj, tj, 1);
	float wBrush = wcat(cj, tj, 2);
	float wForest = wcat(cj, tj, 3);
	float wStone = wcat(cj, tj, 4);
	float wWater = wcat(cp, tp, 5);
	float wShallow = wcat(cj, tj, 6);
	float wFloor = wcat(cj, tj, 7);
	float wMud = wcat(cj, tj, 8);

	// Light first (the meadow dries where the sun bakes it).
	vec3 L = normalize(vec3(-0.65, 0.05, 0.76));
	vec2 ub = (vec2(fbm(p * 1.1 + 3.1, s + 41u), fbm(p * 1.1 - 7.3, s + 43u)) - 0.5) * 0.3;
	vec3 n = normalize(vec3(-(grad + ub) * SHADE_K, 1.0));
	float ndl = max(dot(n, L), 0.0);
	float sunny = ndl / L.z; // 1 on the flat

	// ---- the meadow: sunny yellow-green, lusher and bluer in the low ground
	vec3 grass = saturate_by(soft2(tex_grass, p, 5.5, nSwap, 0.68), 0.86) + vec3(0.0, 0.0, 0.025);
	grass *= mix(vec3(1.12, 1.18, 1.0), vec3(1.42, 1.36, 0.98), smoothstep(0.25, 0.75, nMacro * 0.7 + hn * 0.3));
	grass = mix(grass, grass * vec3(0.82, 0.94, 0.9), hollow * 0.6);
	vec3 dry = saturate_by(soft2(tex_dry, p, 5.0, nSwap, 0.75), 0.82) * vec3(1.04, 1.1, 1.2);
	// Dry golden grass on crests, sunny slopes and high ground, in patches.
	float dryness = nMid * 0.75 + crest * 0.3 + (sunny - 1.0) * 0.4 + hn * 0.12 + (nMacro - 0.5) * 0.3;
	float dryMask = smoothstep(0.54, 0.64, dryness + (nEdge - 0.5) * 0.28 + (nFine - 0.5) * 0.12);
	vec3 col = mix(grass, dry, dryMask * 0.9);
	// A wash of warm straw through the green where it is only half dry.
	col = mix(col, col * vec3(1.1, 1.04, 0.82), smoothstep(0.38, 0.5, dryness) * (1.0 - dryMask) * 0.6);
	// Worn earth even on grass (camps are trampled everywhere).
	vec3 dirt = tex2(tex_dirt, p, 4.0, nSwap);
	dirt = saturate_by(dirt, 0.72) * vec3(0.98, 0.96, 0.98);
	float wear = max(0.0, fbm(p * 0.6, s + 31u) - (camp ? 0.5 : 0.62)) * 4.0;
	if (camp) {
		wDirt = min(1.0, wDirt * 1.15 + 0.15 * nMid);
	}
	col = mix(col, dirt, patchy(min(1.0, wDirt * 1.2 + wear * 0.5), nEdge, 0.1));
	// Thickets: dark lush grass over leaf litter.
	vec3 floorTex = tex2(tex_forest, p, 3.2, nSwap) * vec3(1.05, 1.08, 1.0);
	vec3 thicket = mix(grass * vec3(0.7, 0.84, 0.7), floorTex, smoothstep(0.45, 0.6, nEdge) * 0.55);
	col = mix(col, thicket, patchy(wBrush, nEdge, 0.16));
	// Woods: leaf litter, needles and moss, with green where light falls through.
	vec3 woods = mix(floorTex, grass * vec3(0.66, 0.8, 0.62), smoothstep(0.5, 0.7, nMid) * 0.5);
	col = mix(col, woods, patchy(wForest, nEdge, 0.16));
	// Beyond the field: the forest floor under the ring of trees.
	col = mix(col, floorTex * vec3(0.8, 0.84, 0.76), patchy(wFloor, nEdge, 0.2));
	vec3 mud = soft2(tex_mud, p, 3.4, nSwap, 0.7) * vec3(1.14, 1.05, 0.92);
	col = mix(col, mud, patchy(wMud, nEdge, 0.12));
	if (wStone > 0.02) {
		vec3 stone = texture(tex_stone, p / 1.6, TEX_BIAS).rgb * vec3(0.86, 0.85, 0.82);
		col = mix(col, stone, clamp(wStone * 1.3 * (0.75 + nEdge * 0.4), 0.0, 1.0));
	}

	// ---- crumbling earth banks where a slope falls steeply toward the camera
	vec3 rock = tex2(tex_rock, p, 3.0, nSwap) * vec3(1.18, 1.14, 1.08);
	float steep = smoothstep(0.8, 1.2, slope + (nEdge - 0.5) * 0.3);
	float bankMask = steep * smoothstep(-0.5, 0.1, facing);
	bankMask = max(bankMask, smoothstep(2.0, 2.6, slope));
	// Earth: level beds of ochre soil and grey stone, broken into blocks, each
	// with a lit ledge on top, a dark seam under it and cracks between.
	// The face is painted upright, in screen space (units of half a tile's
	// width, Iso: 64 px across, 26 px a level), so nothing is stretched down
	// the steep ground and the joints between blocks stand vertical.
	vec2 fq = vec2(p.x - p.y, (p.x + p.y) * 0.5 - hC * 0.406);
	vec3 faceRock = tex2(tex_rock, fq, 4.0, nSwap) * vec3(1.18, 1.14, 1.08);
	vec3 soil = mix(saturate_by(tex2(tex_dirt, fq, 5.0, nSwap), 0.61), vec3(0.6, 0.45, 0.3), 0.3);
	// Thick beds of uneven thickness, gently wavy: sandy soil and darker loam,
	// and now and then a pale stone slab running the length of the face.
	float bv = hC * 1.5 + 0.3 * sin(hC * 2.3 + phase.x) + (fbm(vec2(fq.x * 0.9, hC * 0.3), s + 67u) - 0.5) * 0.6;
	float bi = floor(bv);
	float bed = bv - bi;
	float slab = smoothstep(0.55, 0.65, hash(ivec2(int(bi), 5), s + 63u));
	// Strata show on the steep faces only: on gentler ground they would read
	// as contour rings.
	float strata = smoothstep(1.2, 2.0, slope);
	// Long blocks; only some joints are open, and those crack down from the
	// top of the bed only part of the way.
	float bu = fq.x * 0.55 + hash(ivec2(int(bi), 3), s + 61u) * 9.0
		+ (fbm(vec2(fq.x * 0.7, bi * 1.7), s + 62u) - 0.5) * 1.2;
	float bj = floor(bu);
	float bx = bu - bj;
	ivec2 block = ivec2(int(bj), int(bi));
	float jOpen = step(0.45, hash(block, s + 66u));
	float crackTo = 1.0 - mix(0.3, 1.0, hash(block, s + 68u));
	float joint = (1.0 - smoothstep(0.0, 0.03, min(bx, 1.0 - bx))) * jOpen * smoothstep(crackTo - 0.1, crackTo, bed);
	float sandy = smoothstep(0.35, 0.5, fbm(vec2(fq.x * 0.5, hC * 2.1), s + 69u));
	vec3 earth = mix(soil * vec3(0.9, 0.82, 0.72), soil * vec3(1.14, 1.08, 0.94), sandy);
	earth = mix(earth, faceRock * vec3(1.12, 1.1, 1.06), slab * 0.9);
	// Each bed bulges: a lit ledge along its top, rounding into shade below,
	// and a crack with a soft undercut under it, broken where the soil has
	// slumped. The crack is antialiased (beds meet with a jump in `bed`).
	earth *= 0.95 + 0.1 * hash(block, s + 65u);
	earth *= mix(1.0, mix(0.8, 1.04, smoothstep(0.0, 0.55, bed)), strata);
	earth = mix(earth, earth * vec3(1.26, 1.2, 1.06), smoothstep(0.78, 0.93, bed) * mix(0.5, 1.0, slab) * strata);
	float aw = fwidth(bv) + 0.01;
	float crack = 1.0 - smoothstep(aw * 0.5, aw * 1.5, min(bed, 1.0 - bed));
	float seam = smoothstep(0.3, 0.65, fbm(vec2(fq.x * 1.6, bi * 2.3), s + 64u)) * (0.75 + 0.25 * slab) * strata;
	earth *= 1.0 - (crack * 0.45 + (1.0 - smoothstep(0.0, 0.22, bed)) * 0.3) * seam;
	// Open joints, the block right of each lit on its left edge like the sprites.
	earth *= 1.0 - joint * 0.5;
	earth *= 1.0 + (1.0 - smoothstep(0.03, 0.1, bx)) * jOpen * smoothstep(crackTo - 0.1, crackTo, bed) * 0.1;
	// Gullies worn down the face.
	float gully = fbm(vec2(fq.x * 2.6, hC * 0.35), s + 73u);
	earth *= mix(0.84, 1.06, smoothstep(0.25, 0.7, gully));
	// Stones bedded in the soil, and tufts of grass clinging on.
	float stones = smoothstep(0.6, 0.72, fbm(vec2(fq.x * 2.0, hC * 2.6), s + 71u));
	earth = mix(earth, faceRock * vec3(1.08, 1.06, 1.02), stones * 0.9);
	float tufts = smoothstep(0.66, 0.76, fbm(p * 3.6, s + 75u)) * (1.0 - stones);
	earth = mix(earth, grass * vec3(0.9, 1.0, 0.8), tufts * 0.85);
	col = mix(col, earth, bankMask);
	// The turf hangs over the top of the face in ragged tongues, a dark
	// undercut beneath. r says how far down the face this is, whatever the
	// bank's height: about 4 a twentieth of the way down from the crest, 3 a
	// tenth, 1.8 a fifth, 0 halfway, negative below.
	float r = -lap / max(slope, 0.4);
	float tongue = fbm(vec2(fq.x * 1.7, 0.5), s + 81u) * 0.8 + fbm(vec2(fq.x * 7.0, 1.5), s + 83u) * 0.4;
	float dr = r - mix(4.0, 2.0, tongue);
	float turfK = smoothstep(-0.05, 0.05, dr) * bankMask;
	vec3 turf = mix(grass * vec3(0.62, 0.74, 0.5), grass * vec3(1.1, 1.12, 0.9), smoothstep(0.0, 0.6, dr));
	col = mix(col, turf, turfK);
	col *= 1.0 - smoothstep(-0.45, -0.03, dr) * (1.0 - smoothstep(-0.05, 0.05, dr)) * bankMask * 0.5;
	// The grass lip along the crest of a bank, with the shadow of its overhang
	// on the face just under it; scree and shade at the bank's foot.
	float edge = bankMask * (1.0 - bankMask) * 4.0;
	float rim = smoothstep(0.35, 0.8, slope) * (1.0 - bankMask) * smoothstep(-0.5, -3.0, lap);
	col = mix(col, grass * vec3(1.3, 1.3, 0.95), rim * 0.6);
	col *= 1.0 - edge * smoothstep(-0.5, -3.0, lap) * 0.45 * (1.0 - smoothstep(-0.05, 0.05, dr));
	float foot = smoothstep(0.3, 0.8, slope) * (1.0 - bankMask) * smoothstep(0.5, 3.0, lap);
	col = mix(col, mix(rock, dirt * 0.7, 0.45) * 0.8, foot * smoothstep(0.35, 0.65, nFine) * 0.6);
	// Blocks fallen from the face lie along its foot: drawn upright in screen
	// space like the face, lit from the upper left, each with its shadow. A
	// block stands where the ground under its centre is the concave foot of a
	// bank facing the camera, so none is cut off. Laid over the ground after
	// its light (below): a block keeps its own light, not the face's.
	float bA = 0.0;
	vec3 bCol = vec3(0.0);
	if (slope > 0.08 || lap > 0.3) {
		// A cell holds one block with its shadow: half a tile across or more,
		// like the slabs in concept A.
		vec2 cs = vec2(2.3, 1.6);
		ivec2 cell = ivec2(floor(fq / cs));
		if (hash(cell, s + 91u) < 0.8) {
			vec2 rad = vec2(1.0, 0.7) * mix(0.36, 0.6, hash(cell, s + 92u));
			vec2 c = (vec2(cell) + 0.5 + (vec2(hash(cell, s + 93u), hash(cell, s + 94u)) - 0.5) * 0.2) * cs;
			// The grid point under the centre, at this fragment's height.
			vec2 dq = c - fq;
			vec2 pc = p + vec2(dq.y + dq.x * 0.5, dq.y - dq.x * 0.5);
			float c0 = surf(pc);
			float cxp = surf(pc + vec2(e, 0.0));
			float cxm = surf(pc - vec2(e, 0.0));
			float cyp = surf(pc + vec2(0.0, e));
			float cym = surf(pc - vec2(0.0, e));
			vec2 cg = vec2(cxp - cxm, cyp - cym) / (2.0 * e);
			float cl = (cxp + cxm + cyp + cym - 4.0 * c0) / (e * e);
			float csl = length(cg);
			float cf = csl > 1e-3 ? -(cg.x + cg.y) / (csl * 1.41421) : 0.0;
			float fallen = step(0.6, cl) * step(0.2, csl) * step(-0.2, cf);
			// Often a smaller stone beside it, a little in front.
			bool pair = hash(cell, s + 100u) < 0.6;
			vec2 rad2 = rad * 0.42;
			vec2 c2 = c + rad * vec2(hash(cell, s + 101u) < 0.5 ? -0.9 : 0.9, 0.35);
			float shB = 1.0 - smoothstep(0.6, 1.0, length((fq - c - rad * vec2(0.2, 0.3)) / (rad * 1.2)));
			if (pair) {
				shB = max(shB, 1.0 - smoothstep(0.6, 1.0, length((fq - c2 - rad2 * vec2(0.2, 0.3)) / (rad2 * 1.2))));
			}
			col *= 1.0 - fallen * shB * 0.45;
			if (fallen > 0.0) {
				vec3 stoneC = mix(mix(vec3(0.74, 0.7, 0.62), faceRock, 0.35), soil * 1.1, hash(cell, s + 96u) * 0.3);
				vec3 moss = grass * vec3(0.95, 1.05, 0.8);
				vec4 b = fallen_block((fq - c) / rad, cell, s + 95u, stoneC, moss);
				if (pair) {
					vec4 b2 = fallen_block((fq - c2) / rad2, cell + ivec2(17, 31), s + 95u, stoneC * 0.95, moss);
					b = vec4(mix(b.rgb, b2.rgb, b2.a), max(b.a, b2.a));
				}
				bCol = b.rgb;
				bA = b.a;
			}
		}
	}
	// A rocky outcrop on the steepest ground, whatever its facing.
	float crag = smoothstep(2.5, 3.3, slope) * smoothstep(0.4, 0.6, nEdge + 0.2);
	col = mix(col, rock, crag * 0.8);

	// Large-scale variation of hue and value (no two acres alike).
	float tint = (nMacro - 0.5) * 2.0;
	col *= 1.0 + tint * 0.06;

	// ---- light
	// Banks take their light from the true, steep face, wrapped as a painter
	// would: a face the sun only grazes still glows, one turned away keeps
	// the light bounced off the meadow.
	vec3 nb = normalize(vec3(-grad * 0.95, 1.0));
	vec3 nl = normalize(mix(n, nb, bankMask * 0.7));
	float ndl2 = mix(max(dot(nl, L), 0.0), clamp((dot(nl, L) + 0.75) / 1.6, 0.0, 1.0), bankMask);
	// The hills' own shadows, marched toward the sun at its true height.
	vec2 ld = normalize(L.xy);
	float rise = L.z / length(L.xy) / TRUE_K;
	float sh = 1.0;
	for (int i = 1; i <= 12; i++) {
		float t = float(i) * 0.075;
		float d = hC + rise * t - surf(p + ld * t);
		sh = min(sh, smoothstep(-0.06, 0.1, d));
	}
	// Occlusion: hollows, slope feet, the trees' canopy, the forest ring.
	float ao = 1.0 - clamp(lap * 0.03, 0.0, 0.24);
	vec2 ouv = (p + float(border) + 0.5) / vec2(float(gw), float(gh));
	float occ = texture(occ_tex, ouv + (vec2(nEdge, nMid) - 0.5) * 0.6 / vec2(float(gw), float(gh))).r;
	ao *= 1.0 - occ * 0.42;
	ao *= 1.0 - wFloor * 0.12;
	vec3 amb = vec3(0.4, 0.5, 0.62);
	vec3 sun = vec3(1.12, 0.98, 0.7);
	vec3 flat_light = amb + sun * L.z;
	vec3 lit = (amb * (0.75 + 0.25 * nl.z) * ao + sun * ndl2 * sh * mix(1.0, ao, 0.6)) / flat_light;
	col *= lit;
	// Warm light on high ground and along sunlit crests; the low ground cooler.
	col *= mix(vec3(0.88, 0.94, 1.0), vec3(1.08, 1.04, 0.92), hn);
	col += vec3(1.0, 0.84, 0.5) * crest * (1.0 - bankMask) * sh * clamp(sunny, 0.0, 1.3) * 0.07;
	// As painted: a slope turned to the sun goes golden, one turned away goes
	// cool teal, never grey; the hue tells the shape where the value is subtle.
	float warm = smoothstep(1.02, 1.25, sunny) * sh * (1.0 - bankMask);
	col = mix(col, col * vec3(1.12, 1.05, 0.78) + vec3(0.03, 0.02, 0.0), warm * 0.7);
	float shade = clamp(1.0 - min(sh, ao) * clamp(sunny, 0.0, 1.0), 0.0, 1.0);
	col = mix(col, col * vec3(0.72, 0.9, 1.2) + vec3(0.0, 0.02, 0.045), shade * mix(0.8, 0.15, bankMask));
	// Fallen blocks: their own light, dimmed by the hills' shadows and the trees.
	bCol *= mix(0.55, 1.0, sh) * mix(1.0, ao, 0.5) * mix(vec3(0.88, 0.94, 1.0), vec3(1.08, 1.04, 0.92), hn);
	col = mix(col, bCol, bA);

	// ---- shallows and water (flat; their own light)
	if (wShallow > 0.02) {
		vec3 bed = mix(mud, rock, 0.45) * 0.85;
		vec3 shallow = mix(bed, vec3(0.38, 0.6, 0.58), 0.55 + (nMid - 0.5) * 0.2);
		col = mix(col, shallow, clamp(wShallow * 1.2, 0.0, 1.0));
	}
	if (wWater > 0.02) {
		float bnk = clamp((wWater - 0.15) * 3.0, 0.0, 1.0);
		vec3 wet = mix(mud, dirt, 0.35) * vec3(0.7, 0.68, 0.62);
		col = mix(col, wet, min(1.0, wWater * 2.0) * (1.0 - bnk) * 0.85);
		float depth = smoothstep(0.35, 1.0, wWater);
		vec3 water = mix(vec3(0.33, 0.58, 0.56), vec3(0.1, 0.32, 0.42), depth * 0.9 + (nMid - 0.5) * 0.25);
		// Sky in the water, brighter toward the far bank.
		water += vec3(0.1, 0.12, 0.12) * (nMacro - 0.3);
		float glint = pow(vnoise(p * vec2(7.0, 2.5) + vec2(nMid * 3.0, 0.0), s + 47u), 10.0);
		water += vec3(1.0, 0.95, 0.8) * glint * 0.55 * depth;
		// Foam where the water meets the bank.
		float foam = (1.0 - smoothstep(0.0, 0.16, abs(bnk - 0.1))) * (0.5 + 0.5 * nEdge);
		water = mix(water, vec3(0.86, 0.9, 0.86), foam * 0.45);
		col = mix(col, water, bnk);
	}

	if (height_view) {
		vec3 low = vec3(0.14, 0.32, 0.32);
		vec3 high = vec3(0.88, 0.76, 0.46);
		col = mix(low, high, clamp(hC / 4.5, 0.0, 1.0)) * lit;
		float line = 1.0 - smoothstep(0.015, 0.055, abs(fract(hC + 0.5) - 0.5));
		col *= 1.0 - line * 0.32;
	}
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
