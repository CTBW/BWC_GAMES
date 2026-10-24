// Painted colour field of src/render/terrain.ts buildTerrain (step 1), one
// fragment per field pixel. Bit-exact port of the per-pixel loop: value noise
// and fbm over hash2 (rng.ts), the category weights sampled bilinearly from a
// per-tile category map, flagstones, shallows, water and banks, and the fine
// grain. Campaign roads (soft dirt ribbons, drawn by the original with round
// caps and joins after the pixels) are composited here too, road by road and
// layer by layer, with analytic anti-aliasing.
//
// hash2 is exact: the original sums x*374761393 + y*668265263 + seed*2147483647
// in doubles before `>>> 0`; seeds reach 2^31, so the sum exceeds 2^53 and is
// rounded. The rounding is reproduced with 64-bit integer arithmetic on uint
// pairs (lo, hi).
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D cat_tex : filter_nearest; // GW x GH, category index / 255
uniform int gw;
uniform int gh;
uniform int res; // R: field pixels per tile
uniform int field_w;
uniform int field_h;
uniform int seed;
uniform bool camp;
// Roads: road_tex is (points, roads) RG float, field-pixel coordinates.
uniform sampler2D road_tex : filter_nearest;
uniform int road_count;
uniform int road_points;

// ---------------------------------------------------------------- 64-bit helpers

uvec2 umul32(uint a, uint b) {
	uint a0 = a & 0xFFFFu;
	uint a1 = a >> 16u;
	uint b0 = b & 0xFFFFu;
	uint b1 = b >> 16u;
	uint p00 = a0 * b0;
	uint p01 = a0 * b1;
	uint p10 = a1 * b0;
	uint p11 = a1 * b1;
	uint mid = (p00 >> 16u) + (p01 & 0xFFFFu) + (p10 & 0xFFFFu);
	uint lo = (p00 & 0xFFFFu) | (mid << 16u);
	uint hi = p11 + (p01 >> 16u) + (p10 >> 16u) + (mid >> 16u);
	return uvec2(lo, hi);
}

uvec2 add64(uvec2 a, uvec2 b) {
	uint lo = a.x + b.x;
	uint carry = lo < a.x ? 1u : 0u;
	return uvec2(lo, a.y + b.y + carry);
}

uvec2 neg64(uvec2 a) {
	return add64(uvec2(~a.x, ~a.y), uvec2(1u, 0u));
}

// Signed int32 times a constant below 2^31, as a two's complement 64-bit value.
uvec2 smul(int a, uint k) {
	uvec2 p = umul32(uint(abs(a)), k);
	return a < 0 ? neg64(p) : p;
}

// Round a two's complement 64-bit integer to the nearest double (ties to even).
uvec2 round53(uvec2 s) {
	bool neg = (s.y >> 31u) != 0u;
	uvec2 m = neg ? neg64(s) : s;
	if (m.y < 0x200000u) {
		return s; // below 2^53: exact
	}
	int bl = 22;
	for (int i = 31; i >= 22; i--) {
		if ((m.y >> uint(i)) != 0u) {
			bl = i + 1;
			break;
		}
	}
	uint sh = uint(bl - 21); // bit length (32 + bl) - 53
	uint mask = (1u << sh) - 1u;
	uint rem = m.x & mask;
	uint halfw = 1u << (sh - 1u);
	m.x = m.x & ~mask;
	bool up = rem > halfw || (rem == halfw && ((m.x >> sh) & 1u) == 1u);
	if (up) {
		m = add64(m, uvec2(1u << sh, 0u));
	}
	return neg ? neg64(m) : m;
}

// rng.ts hash2 for integer x, y and a non-negative integer seed.
float hash2(int x, int y, uint s) {
	uvec2 p = add64(smul(x, 374761393u), smul(y, 668265263u));
	uvec2 d = round53(umul32(s, 2147483647u));
	uint h = round53(add64(p, d)).x;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float(h ^ (h >> 16u)) / 4294967296.0;
}

// ---------------------------------------------------------------- noise

float vnoise(float x, float y, uint s) {
	float xi = floor(x);
	float yi = floor(y);
	float xf = x - xi;
	float yf = y - yi;
	int ix = int(xi);
	int iy = int(yi);
	float a = hash2(ix, iy, s);
	float b = hash2(ix + 1, iy, s);
	float c = hash2(ix, iy + 1, s);
	float d = hash2(ix + 1, iy + 1, s);
	float u = xf * xf * (3.0 - 2.0 * xf);
	float v = yf * yf * (3.0 - 2.0 * yf);
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

float fbm(float x, float y, uint s) {
	float sum = 0.0;
	float amp = 0.5;
	float f = 1.0;
	for (int i = 0; i < 4; i++) {
		sum += amp * vnoise(x * f, y * f, s + uint(i) * 17u);
		f *= 2.03;
		amp *= 0.5;
	}
	return sum / 0.9375;
}

// ---------------------------------------------------------------- categories
// grass 0, dirt 1, brush 2, forest 3, stone 4, water 5, shallows 6, floor 7, mud 8

int cat_at(int x, int y) {
	return int(texelFetch(cat_tex, ivec2(x, y), 0).r * 255.0 + 0.5);
}

// sampleW: the four tiles around a sample point and the bilinear weights.
void corners(float u, float v, out ivec4 cats, out vec2 t) {
	float gx = u - 0.5;
	float gy = v - 0.5;
	int x0 = clamp(int(floor(gx)), 0, gw - 1);
	int y0 = clamp(int(floor(gy)), 0, gh - 1);
	int x1 = min(gw - 1, x0 + 1);
	int y1 = min(gh - 1, y0 + 1);
	t = vec2(clamp(gx - float(x0), 0.0, 1.0), clamp(gy - float(y0), 0.0, 1.0));
	cats = ivec4(cat_at(x0, y0), cat_at(x1, y0), cat_at(x0, y1), cat_at(x1, y1));
}

float wcat(ivec4 c, vec2 t, int k) {
	float a = c.x == k ? 1.0 : 0.0;
	float b = c.y == k ? 1.0 : 0.0;
	float cc = c.z == k ? 1.0 : 0.0;
	float d = c.w == k ? 1.0 : 0.0;
	return a + (b - a) * t.x + (cc - a) * t.y + (a - b - cc + d) * t.x * t.y;
}

vec3 mixc(vec3 a, vec3 b, float t) {
	return a + (b - a) * t;
}

// ---------------------------------------------------------------- roads

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float l2 = dot(ab, ab);
	float t = l2 > 0.0 ? clamp(dot(p - a, ab) / l2, 0.0, 1.0) : 0.0;
	return length(p - (a + ab * t));
}

void fragment() {
	int px = int(floor(UV.x * float(field_w)));
	int py = int(floor(UV.y * float(field_h)));
	float R = float(res);
	float u = float(px) / R;
	float v = float(py) / R;
	uint s = uint(seed);

	const vec3 grassA = vec3(134.0, 168.0, 60.0);
	const vec3 grassB = vec3(163.0, 184.0, 74.0);
	const vec3 grassC = vec3(108.0, 147.0, 52.0);
	const vec3 grassD = vec3(189.0, 184.0, 90.0);
	const vec3 dirtA = vec3(184.0, 151.0, 92.0);
	const vec3 dirtB = vec3(154.0, 122.0, 72.0);
	const vec3 brushC = vec3(85.0, 125.0, 44.0);
	const vec3 forestC = vec3(63.0, 98.0, 39.0);
	const vec3 floorC = vec3(52.0, 82.0, 31.0);
	const vec3 stoneC = vec3(168.0, 165.0, 148.0);
	const vec3 waterC = vec3(63.0, 134.0, 166.0);
	const vec3 waterDeep = vec3(44.0, 106.0, 138.0);
	const vec3 shallowC = vec3(94.0, 162.0, 168.0);
	const vec3 mudC = vec3(111.0, 93.0, 60.0);
	const vec3 bankC = vec3(107.0, 106.0, 58.0);

	float n1 = fbm(u * 0.35, v * 0.35, s);
	float n2 = fbm(u * 1.4, v * 1.4, s + 5u);
	float n3 = fbm(u * 4.5, v * 4.5, s + 9u);
	// Organic edges: jitter the sample point.
	float ju = u + (n2 - 0.5) * 0.9;
	float jv = v + (fbm(u * 1.4, v * 1.4, s + 77u) - 0.5) * 0.9;
	vec3 col = mixc(mixc(grassC, grassA, n1), mixc(grassB, grassD, n2), max(0.0, n1 * 1.2 - 0.25));
	ivec4 cj;
	vec2 tj;
	corners(ju, jv, cj, tj);
	ivec4 cp;
	vec2 tp;
	corners(u, v, cp, tp);
	float wDirt = min(1.0, wcat(cj, tj, 1) * 1.15 + (camp ? 0.15 : 0.0) * n2);
	float wBrush = wcat(cj, tj, 2);
	float wForest = wcat(cj, tj, 3);
	float wFloor = wcat(cj, tj, 7);
	float wStone = wcat(cj, tj, 4);
	float wWater = wcat(cp, tp, 5);
	float wShallow = wcat(cj, tj, 6);
	float wMud = wcat(cj, tj, 8);
	// Natural dirt patches even on grass.
	float patch = max(0.0, fbm(u * 0.6, v * 0.6, s + 31u) - 0.62) * 2.2;
	vec3 dirtCol = mixc(dirtB, dirtA, n3);
	col = mixc(col, dirtCol, min(1.0, max(0.0, wDirt * 1.2 - 0.1 + (n3 - 0.5) * 0.5) + patch * 0.6));
	col = mixc(col, mixc(brushC, grassC, n3 * 0.6), min(1.0, wBrush * 1.1));
	col = mixc(col, mixc(forestC, brushC, n3 * 0.5), min(1.0, wForest));
	col = mixc(col, mixc(floorC, forestC, n2 * 0.7), min(1.0, wFloor));
	col = mixc(col, mixc(mudC, dirtB, n3 * 0.5), min(1.0, wMud));
	if (wStone > 0.05) {
		// Flagstones: cell pattern.
		float row = mod(floor(v * 3.0), 2.0);
		float cu = floor(u * 3.0 + row * 0.5);
		float cv = floor(v * 3.0);
		float cell = hash2(int(cu), int(cv), s + 3u);
		float edge = min(abs(fract(u * 3.0 + row * 0.5) - 0.5), abs(fract(v * 3.0) - 0.5));
		vec3 sc = mixc(stoneC, vec3(196.0, 192.0, 173.0), cell * 0.8);
		if (edge > 0.42) {
			sc = mixc(sc, vec3(94.0, 92.0, 78.0), 0.6);
		}
		col = mixc(col, sc, min(1.0, wStone * 1.3 * (0.7 + n3 * 0.4)));
	}
	if (wShallow > 0.05) {
		col = mixc(col, mixc(shallowC, waterC, n2), min(1.0, wShallow * 1.2));
	}
	if (wWater > 0.02) {
		float bank = max(0.0, min(1.0, (wWater - 0.15) * 3.0));
		col = mixc(col, bankC, min(1.0, wWater * 2.0) * (1.0 - bank) * 0.8);
		col = mixc(col, mixc(waterDeep, waterC, n2), bank);
	}
	// Fine painterly grain.
	float grain = (n3 - 0.5) * 22.0 + (hash2(px, py, s) - 0.5) * 8.0;
	vec3 o = clamp(vec3(col.r + grain, col.g + grain, col.b + grain * 0.6), 0.0, 255.0);
	// Uint8ClampedArray rounds to the nearest integer.
	o = floor(o + 0.5) / 255.0;

	// Roads on the campaign map: soft dirt ribbons, three strokes per road.
	if (road_count > 0) {
		vec2 p = vec2(float(px) + 0.5, float(py) + 0.5);
		for (int r = 0; r < road_count; r++) {
			float d = 1e9;
			vec2 a = texelFetch(road_tex, ivec2(0, r), 0).rg;
			for (int i = 1; i < road_points; i++) {
				vec2 b = texelFetch(road_tex, ivec2(i, r), 0).rg;
				d = min(d, seg_dist(p, a, b));
				a = b;
			}
			if (d > R) {
				continue;
			}
			float c0 = clamp(R * 0.75 * 0.5 - d + 0.5, 0.0, 1.0);
			o = mix(o, vec3(120.0, 95.0, 55.0) / 255.0, 0.55 * c0);
			float c1 = clamp(R * 0.5 * 0.5 - d + 0.5, 0.0, 1.0);
			o = mix(o, vec3(184.0, 152.0, 96.0) / 255.0, 0.95 * c1);
			float c2 = clamp(R * 0.12 * 0.5 - d + 0.5, 0.0, 1.0);
			o = mix(o, vec3(210.0, 185.0, 130.0) / 255.0, 0.6 * c2);
		}
	}
	COLOR = vec4(o, 1.0);
}
