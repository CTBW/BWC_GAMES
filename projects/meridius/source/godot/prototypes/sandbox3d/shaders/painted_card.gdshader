// A painted woodland cut-out of the battle (tree, shrub, fern, rock, stump) as
// a card in the 3D sandbox (prototypes/sandbox3d/scripts/field3d.gd _card).
// Vertex colour R marks the upright part (1) from the painted shadow draped on
// the ground (0); G is the height up the upright part, 0 at the foot.
//  - The upright part bends in the wind, more toward the top.
//  - The fog of war of the ground under the foot covers the whole upright
//    part; the shadow takes the fog of the ground it lies on. The grain is the
//    ground's (the same screen pixels), so a card in full fog vanishes in it.
//  - A figure behind the canopy fades it (`fade`).
// Colours are mixed in sRGB as in the battle and go out as they are: the
// sandbox's 3D pipeline (Compatibility, 2x supersampled) shows ALBEDO's values
// unconverted, so a pixel of the painting stays that pixel on screen.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha, shadows_disabled, ambient_light_disabled;

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
// Wind: how far the top leans, as a fraction of the card's height.
uniform float sway = 0.0;
uniform float fade = 1.0;
uniform vec2 map_size;
uniform float tile_m = 2.72;
uniform float level_m = 0.9;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform bool fog_on = false;
uniform sampler2D fog_grain : filter_nearest, repeat_enable;
uniform vec3 night = vec3(1.0);
// The painted shadow's alpha is darkened by this power (1: as painted).
uniform float shadow_gamma = 1.0;
// Grass strokes: the colour is the vertex colour, UV.y the height up the blade.
uniform bool blades = false;

varying vec2 grid;
varying vec2 px;
varying float upright;

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
	upright = blades ? 1.0 : COLOR.r;
	vec3 node = blades ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz : NODE_POSITION_WORLD;
	if (upright > 0.5) {
		float h = blades ? UV.y : COLOR.g;
		float ph = node.x * 0.37 + node.z * 0.53;
		float w = sin(TIME * 0.9 + ph) * 0.65 + sin(TIME * 2.1 + ph * 1.7) * 0.25 + sin(TIME * 4.3 + ph * 2.9) * 0.1;
		// Leaning along the screen's right (world (1, 0, -1)).
		float tall = blades ? 0.4 : VERTEX.y;
		VERTEX += vec3(0.70710678, 0.0, -0.70710678) * w * sway * h * h * tall;
		grid = node.xz / tile_m;
	}
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (upright <= 0.5) {
		grid = w.xz / tile_m;
	}
	px = vec2((w.x - w.z) / tile_m * 64.0, (w.x + w.z) / tile_m * 32.0 - w.y / level_m * 26.0);
}

void fragment() {
	vec4 c = blades ? COLOR : texture(tex, UV);
	vec3 col = c.rgb * night;
	float a = c.a;
	if (upright > 0.5) {
		a *= fade;
	} else {
		a = 1.0 - pow(1.0 - a, shadow_gamma);
	}
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
	ALPHA = a;
}
