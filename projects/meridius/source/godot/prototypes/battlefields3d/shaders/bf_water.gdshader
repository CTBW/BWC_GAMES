// The open water of the 3D battlefields (scripts/bf_water.gd): a flat sheet at
// the field's water level over the river or lake the relief ground carved and
// painted (terrain_relief.gdshader's water: its banks, bed and foam). The
// sheet adds what a baked picture cannot: the current, glints that move, the
// sky brightening toward the far bank, and foam that comes and goes along the
// banks. Vertex colour R is the depth (0 at the bank, 1 where deep), G the
// flow's x and B its z, mapped from -1..1 to 0..1. Transparent where shallow,
// so the painted bed and the bank show through. Fog of war and night as the
// ground. Colours are sRGB and go out unconverted, as the ground's.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, ambient_light_disabled, depth_draw_never;

uniform vec2 map_size;
uniform float tile_m = 2.72;
// A tile's width on screen at zoom 1 (px); the battle's are 128.
uniform float tile_px = 128.0;
uniform float level_m = 0.9;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform bool fog_on = false;
uniform sampler2D fog_grain : filter_nearest, repeat_enable;
uniform vec3 night = vec3(1.0);
uniform vec3 shallow_col = vec3(0.36, 0.62, 0.6);
uniform vec3 deep_col = vec3(0.1, 0.33, 0.44);
// How fast the current runs (the battle's tiles a second).
uniform float speed = 0.35;

varying vec2 grid;
varying vec2 px;
varying float depth;
varying vec2 flow;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

vec3 grain_patch(vec2 pixel, vec2 id) {
	float angle = hash(id + 17.3) * 6.2831853;
	mat2 rotation = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
	vec2 offset = vec2(hash(id + 41.7), hash(id - 12.8)) * vec2(905.0, 563.0);
	return texture(fog_grain, (rotation * pixel + offset) / vec2(905.0, 563.0)).rgb;
}

vec3 irregular_grain(vec2 pixel) {
	vec2 patch = pixel / 370.0;
	vec2 id = floor(patch), f = fract(patch);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(grain_patch(pixel, id), grain_patch(pixel, id + vec2(1, 0)), f.x),
		mix(grain_patch(pixel, id + vec2(0, 1)), grain_patch(pixel, id + vec2(1, 1)), f.x), f.y);
}

vec2 mask_at(vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return vec2(0.0);
	return texture(fog_tex, uv).rg;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	grid = w.xz / tile_m;
	depth = COLOR.r;
	flow = COLOR.gb * 2.0 - 1.0;
	px = vec2((w.x - w.z) / tile_m * tile_px * 0.5, (w.x + w.z) / tile_m * tile_px * 0.25 - w.y / level_m * 26.0);
}

void fragment() {
	// The water's patterns are measured in the battle's tiles.
	vec2 pg = grid * tile_px / 128.0;
	// Streaks along the current, drawn in its own frame so they run with it.
	vec2 f = length(flow) > 0.01 ? normalize(flow) : vec2(1.0, 0.0);
	vec2 q = vec2(dot(pg, f), dot(pg, vec2(-f.y, f.x)));
	float t = TIME * speed * (0.4 + length(flow));
	float streak = vnoise(vec2(q.x * 1.1 - t * 1.6, q.y * 5.0)) * 0.6 + vnoise(vec2(q.x * 2.7 - t * 2.4, q.y * 11.0)) * 0.4;
	float d = smoothstep(0.0, 1.0, depth);
	vec3 col = mix(shallow_col, deep_col, d * 0.9 + (streak - 0.5) * 0.15);
	// The sky in the water, brighter toward the far (upper) bank.
	float sky = vnoise(pg * 0.15 + vec2(TIME * 0.01, 0.0));
	col += vec3(0.08, 0.11, 0.12) * (sky - 0.3);
	col = mix(col, col * 1.18 + vec3(0.02, 0.04, 0.04), smoothstep(0.55, 0.8, streak) * 0.5);
	// Glints: small bright flecks that drift with the current and blink.
	float g = vnoise(vec2(q.x * 6.0 - t * 3.0, q.y * 14.0) + floor(TIME * 1.5) * 0.37);
	col += vec3(1.0, 0.96, 0.84) * pow(g, 14.0) * 1.4 * d;
	// Foam along the banks, coming and going.
	float edge = 1.0 - smoothstep(0.04, 0.25, depth);
	float foam = edge * smoothstep(0.45, 0.75, vnoise(vec2(q.x * 3.0 - t * 2.0, q.y * 3.0) + TIME * 0.2));
	col = mix(col, vec3(0.9, 0.95, 0.93), foam * 0.6);
	col *= night;
	if (fog_on) {
		vec2 uv = (grid + 0.5) / map_size;
		vec2 dd = vec2(0.42) / map_size;
		vec2 m = mask_at(uv) * 0.4;
		m += (mask_at(uv + vec2(dd.x, 0.0)) + mask_at(uv - vec2(dd.x, 0.0)) + mask_at(uv + vec2(0.0, dd.y)) + mask_at(uv - vec2(0.0, dd.y))) * 0.15;
		float clear = smoothstep(0.08, 0.84, m.r);
		float known = smoothstep(0.04, 0.85, m.g);
		vec3 tint = irregular_grain(px) * 1.35 + vec3(0.002, 0.003, 0.007) * known;
		col = mix(col, tint, (1.0 - clear) * mix(1.0, 0.64, known));
	}
	ALBEDO = clamp(col, 0.0, 1.0);
	// Clear at the bank, so the painted shore shows through; never quite opaque.
	ALPHA = smoothstep(0.02, 0.3, depth) * 0.82 + foam * 0.15;
}
