// The 3D sandbox's ground (prototypes/sandbox3d/scripts/field3d.gd). The colour
// is the battle's relief ground, painted once into two top-down pictures by
// assets/shaders/terrain_relief.gdshader (its sun, hill shadows and banks
// included); this shader looks them up on the 3D relief and adds what changes:
//  - the shadows the 3D figures cast, through light() (the ground has its own
//    painted light, so the sun only darkens where something blocks it);
//  - the fog of war of the battle (battle_fog.gdshader's shroud and grain,
//    sampled at the ground's own grid point, so it needs no inverse projection);
//  - the tile grid, the hovered tile and a marched route;
//  - night.
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

// Both pictures, the grain and the colours below are sRGB and mixed as the
// battle mixes them (in sRGB). They go out unconverted: the sandbox's 3D
// pipeline shows ALBEDO's values as they are, so the ground on screen is the
// baked picture to the pixel (converting to linear here made it dark and burnt).
uniform sampler2D near_tex : filter_linear, repeat_disable;
uniform sampler2D far_tex : filter_linear, repeat_disable;
// Grid rectangles of the two pictures: origin xy, size zw.
uniform vec4 near_rect;
uniform vec4 far_rect;
uniform vec2 map_size;
uniform float tile_m = 2.72;
uniform float level_m = 0.9;

// Fog of war: R seen now, G explored, one texel a tile (fog3d.gd eases it).
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform bool fog_on = false;
uniform sampler2D fog_grain : filter_nearest, repeat_enable;

// Marks: per tile, 0.5 a route, 1 the goal.
uniform sampler2D mark_tex : filter_nearest, repeat_disable;
uniform bool grid_on = false;
uniform vec2 hover = vec2(-99.0);
uniform vec3 mark_color = vec3(1.0, 0.86, 0.45);

// Night: the colour the painted day is multiplied by.
uniform vec3 night = vec3(1.0);
// Beyond the field the ground sinks into the dark of the forest.
uniform vec3 deep = vec3(0.07, 0.09, 0.07);
// What a figure's shadow leaves of the ground's colour, a cool shade.
uniform vec3 shadow_tint = vec3(0.5, 0.56, 0.7);

varying vec2 grid;
varying vec2 px;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

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
	grid = UV;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The point's place on screen at zoom 1, in the battle's pixels: the grain
	// of the fog lies on the screen, the same on ground, trees and figures.
	px = vec2((w.x - w.z) / tile_m * 64.0, (w.x + w.z) / tile_m * 32.0 - w.y / level_m * 26.0);
}

void fragment() {
	vec2 nuv = (grid - near_rect.xy) / near_rect.zw;
	vec2 fuv = (grid - far_rect.xy) / far_rect.zw;
	vec3 col = texture(far_tex, fuv).rgb;
	float inner = min(min(nuv.x, 1.0 - nuv.x), min(nuv.y, 1.0 - nuv.y));
	col = mix(col, texture(near_tex, nuv).rgb, smoothstep(0.0, 0.02, inner));
	// The forest beyond the field darkens toward the edge of the world.
	vec2 lo = -0.5 - grid;
	vec2 hi = grid - (map_size - 0.5);
	float out_d = max(max(lo.x, hi.x), max(lo.y, hi.y));
	col = mix(col, deep, smoothstep(5.0, 11.5, out_d) * 0.92);

	// The tile grid, the hovered tile, the route.
	vec2 cell = floor(grid + 0.5);
	vec2 f = grid + 0.5 - cell;
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float aa = fwidth(grid.x) * 1.2;
	bool inside = all(greaterThanEqual(cell, vec2(0.0))) && all(lessThan(cell, map_size));
	if (grid_on && inside) {
		col = mix(col, vec3(1.0, 0.96, 0.82), (1.0 - smoothstep(0.0, aa, edge)) * 0.28);
	}
	if (inside) {
		float m = texelFetch(mark_tex, ivec2(cell), 0).r;
		float r = length(f - 0.5);
		if (m > 0.75) {
			// The goal: a ring with a soft glow inside.
			float ring = 1.0 - smoothstep(0.0, aa * 1.5, abs(r - 0.34) - 0.035);
			col = mix(col, mark_color, ring * 0.85 + (1.0 - smoothstep(0.0, 0.34, r)) * 0.18);
		} else if (m > 0.25) {
			float dot_ = 1.0 - smoothstep(0.08, 0.08 + aa * 1.5, r);
			col = mix(col, mark_color, dot_ * 0.7);
		}
		if (cell == hover) {
			float line = 1.0 - smoothstep(0.0, aa * 1.5, edge - 0.02);
			col = mix(col, vec3(1.0, 0.97, 0.86), line * 0.75 + 0.07);
		}
	}

	col *= night;

	// The battle's shroud: unseen ground dimmed, unexplored ground lost.
	if (fog_on) {
		vec2 uv = (grid + 0.5) / map_size;
		vec2 d = vec2(0.42) / map_size;
		vec2 m = mask_at(uv) * 0.4;
		m += (mask_at(uv + vec2(d.x, 0.0)) + mask_at(uv - vec2(d.x, 0.0)) + mask_at(uv + vec2(0.0, d.y)) + mask_at(uv - vec2(0.0, d.y))) * 0.15;
		float clear = smoothstep(0.08, 0.84, m.r);
		float known = smoothstep(0.04, 0.85, m.g);
		vec3 tint = irregular_grain(px) * 1.35 + vec3(0.002, 0.003, 0.007) * known;
		col = mix(col, tint, (1.0 - clear) * mix(1.0, 0.64, known));
	}
	ALBEDO = clamp(col, 0.0, 1.0);
}

void light() {
	// Lit everywhere by its own paint; the sun only takes light away where a
	// figure stands in its way.
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, mix(shadow_tint, vec3(1.0), ATTENUATION));
}
