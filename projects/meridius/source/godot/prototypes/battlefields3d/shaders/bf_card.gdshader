// A painted cut-out of the 3D battlefields (tree, shrub, fern, rock, house,
// ruin, bridge, harvest) as a card (prototypes/battlefields3d/scripts/bf_field.gd
// _card), grown from the 3D sandbox's painted_card.gdshader. Vertex colour R
// marks the upright part (1) from the painted shadow draped on the ground (0);
// G is the height up the upright part, 0 at the foot.
//  - The upright part bends in the wind, more toward the top.
//  - The fog of war lies on the screen as on the ground: each point of the
//    upright part takes the fog of the ground seen behind it (its view ray
//    marched over the relief, `h_tex`), so the edge of the shroud cuts a
//    house or a tree as it cuts the ground, and what stands behind it in the
//    shroud is lost in the same grain. The ground under the foot still counts:
//    a thing standing on ground not seen now is dimmed as that ground is, and
//    one on unexplored ground is not drawn at all, so no lone top shows over
//    clear ground behind it; its shadow goes with it. The shadow takes the fog
//    of the ground it lies on.
//  - The season, for summer paintings in another season: `autumn` turns their
//    greens to gold and russet, `snow_cap` lays snow along their top edges.
//  - At night, `glow` keeps a lit window's warm light while the rest dims
//    (warm, saturated paint above the painted base only).
// Colours are mixed in sRGB as in the battle and go out as they are: the
// viewer's 3D pipeline (Compatibility, 2x supersampled) shows ALBEDO's values
// unconverted, so a pixel of the painting stays that pixel on screen.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha, shadows_disabled, ambient_light_disabled;

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
// Wind: how far the top leans, as a fraction of the card's height.
uniform float sway = 0.0;
uniform float fade = 1.0;
uniform vec2 map_size;
uniform float tile_m = 2.72;
// A tile's width on screen at zoom 1 (px); the battle's are 128.
uniform float tile_px = 128.0;
uniform float level_m = 0.9;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform bool fog_on = false;
uniform sampler2D fog_grain : filter_nearest, repeat_enable;
// The ground's height in levels at `h_sub` points a tile from grid point
// `h_origin` (the ground mesh's own points), for the fog behind upright parts.
uniform sampler2D h_tex : filter_linear, repeat_disable;
uniform vec2 h_origin;
uniform float h_sub = 4.0;
uniform vec3 night = vec3(1.0);
// The painted shadow's alpha is darkened by this power (1: as painted).
uniform float shadow_gamma = 1.0;
// Grass strokes: the colour is the vertex colour, UV.y the height up the blade.
uniform bool blades = false;
uniform float autumn = 0.0;
uniform float snow_cap = 0.0;
// 0 by day; at night 1 where the painting has lit windows.
uniform float glow = 0.0;

varying vec2 grid;
varying vec2 foot_grid;
varying vec2 px;
varying float foot_y;
varying float upright;
varying float rise;

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

// The fog mask at grid point g, softened as the ground softens it.
vec2 fog_at(vec2 g) {
	vec2 uv = (g + 0.5) / map_size;
	vec2 d = vec2(0.42) / map_size;
	vec2 m = mask_at(uv) * 0.4;
	return m + (mask_at(uv + vec2(d.x, 0.0)) + mask_at(uv - vec2(d.x, 0.0)) + mask_at(uv + vec2(0.0, d.y)) + mask_at(uv - vec2(0.0, d.y))) * 0.15;
}

float ground_m(vec3 q) {
	vec2 n = vec2(textureSize(h_tex, 0));
	return texture(h_tex, ((q.xz / tile_m - h_origin) * h_sub + 0.5) / n).r * level_m;
}

// The ground point seen behind world point p along the view direction d:
// marched in 20 steps to three levels below the foot, then bisected.
vec3 ground_behind(vec3 p, vec3 d) {
	float a = 0.0;
	float b = (p.y - foot_y + 3.0 * level_m) / max(-d.y, 0.05);
	float s = b / 20.0;
	for (int i = 1; i <= 20; i++) {
		float t = s * float(i);
		if (p.y + d.y * t <= ground_m(p + d * t)) {
			b = t;
			break;
		}
		a = t;
	}
	for (int k = 0; k < 6; k++) {
		float t = (a + b) * 0.5;
		if (p.y + d.y * t <= ground_m(p + d * t)) {
			b = t;
		} else {
			a = t;
		}
	}
	return p + d * b;
}

void vertex() {
	upright = blades ? 1.0 : COLOR.r;
	rise = blades ? UV.y : COLOR.g;
	vec3 node = blades ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz : NODE_POSITION_WORLD;
	foot_grid = node.xz / tile_m;
	foot_y = node.y;
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
	px = vec2((w.x - w.z) / tile_m * tile_px * 0.5, (w.x + w.z) / tile_m * tile_px * 0.25 - w.y / level_m * 26.0);
}

void fragment() {
	vec4 c = blades ? COLOR : texture(tex, UV);
	vec3 base = c.rgb;
	if (!blades && upright > 0.5) {
		if (autumn > 0.0) {
			// Greens go gold, olive and russet by how green they are; browns stay.
			float green = clamp((base.g - max(base.r, base.b)) * 4.0, 0.0, 1.0);
			float l = dot(base, vec3(0.3, 0.55, 0.15));
			vec3 gold = mix(vec3(0.62, 0.3, 0.1), vec3(1.0, 0.72, 0.24), smoothstep(0.15, 0.6, l)) * (0.7 + l * 0.7);
			float pick = hash(floor(UV * 24.0) + floor(NODE_POSITION_WORLD.xz));
			gold = mix(gold, gold * vec3(1.05, 0.62, 0.42), step(0.6, pick));
			base = mix(base, gold, green * autumn);
		}
		if (snow_cap > 0.0) {
			// Snow where the painting has open sky a little above: along the
			// top edge of each leaf mass, broken up.
			vec2 ts = vec2(textureSize(tex, 0));
			float above = texture(tex, UV - vec2(0.0, 7.0 / ts.y)).a;
			float above2 = texture(tex, UV - vec2(0.0, 13.0 / ts.y)).a;
			float cap = c.a * clamp((1.0 - min(above, above2)) * 1.6, 0.0, 1.0);
			cap *= step(0.3, hash(floor(UV * ts / 6.0)));
			vec3 snow = mix(vec3(0.74, 0.8, 0.94), vec3(1.0, 0.99, 0.96), smoothstep(0.2, 0.7, dot(base, vec3(0.33))));
			base = mix(base, snow, cap * snow_cap);
		}
	}
	vec3 col = base * night;
	if (glow > 0.0 && upright > 0.5) {
		// Lit windows: warm, bright, saturated paint keeps its light.
		float warm = smoothstep(0.7, 0.88, base.r) * smoothstep(0.45, 0.62, base.g) * (1.0 - smoothstep(0.18, 0.34, base.b));
		warm *= smoothstep(0.45, 0.62, base.r - base.b) * smoothstep(0.16, 0.26, rise);
		col = mix(col, base * vec3(1.25, 1.1, 0.85), warm * glow);
	}
	float a = c.a;
	if (upright > 0.5) {
		a *= fade;
	} else {
		a = 1.0 - pow(1.0 - a, shadow_gamma);
	}
	if (fog_on) {
		// The ground this point covers on screen: under it for the shadow and
		// the grass strokes, behind it along the view for an upright part.
		vec2 g = grid;
		vec2 gpx = px;
		if (upright > 0.5 && !blades) {
			vec3 q = ground_behind((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, -INV_VIEW_MATRIX[2].xyz);
			g = q.xz / tile_m;
			gpx = vec2((q.x - q.z) / tile_m * tile_px * 0.5, (q.x + q.z) / tile_m * tile_px * 0.25 - q.y / level_m * 26.0);
		}
		vec2 m = fog_at(g);
		float clear = smoothstep(0.08, 0.84, m.r);
		float known = smoothstep(0.04, 0.85, m.g);
		// The ground's own shroud and grain there, so a point over the shroud
		// is lost in it as the ground is.
		vec3 tint = irregular_grain(gpx) * 1.35 + vec3(0.002, 0.003, 0.007) * known;
		float cover = (1.0 - clear) * mix(1.0, 0.64, known);
		vec2 f = fog_at(foot_grid);
		if (upright > 0.5) {
			cover = max(cover, (1.0 - smoothstep(0.08, 0.84, f.r)) * 0.64);
			a *= smoothstep(0.2, 0.7, f.g);
		} else {
			a *= smoothstep(0.03, 0.55, m.g) * smoothstep(0.2, 0.7, f.g);
		}
		col = mix(col, tint, cover);
	}
	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = a;
}
