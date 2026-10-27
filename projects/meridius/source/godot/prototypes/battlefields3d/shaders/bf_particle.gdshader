// The weather and smoke of the 3D battlefields (scripts/bf_weather.gd): each
// particle a small card turned to the camera, drawn as a soft shape in the
// particle's colour. `kind`: 0 snowflake, 1 leaf, 2 petal, 3 smoke puff,
// 4 ember. The fog of war of the ground under a particle hides it where the
// ground is unexplored and thins it where the ground is not seen now; the
// night dims all but the embers. Colours are sRGB and go out unconverted, as
// the cards' (bf_card.gdshader).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, ambient_light_disabled, depth_draw_never;

uniform int kind = 0;
uniform vec2 map_size;
uniform float tile_m = 2.72;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform bool fog_on = false;
uniform vec3 night = vec3(1.0);

varying vec3 centre;
varying float spin;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	centre = MODEL_MATRIX[3].xyz;
	spin = INSTANCE_CUSTOM.x;
	// Turned to the camera, keeping the particle's size and its spin.
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	world = world * mat4(vec4(cos(spin), -sin(spin), 0.0, 0.0), vec4(sin(spin), cos(spin), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a;
	vec3 col = COLOR.rgb;
	if (kind == 1) {
		// A leaf: pointed at both ends, a darker midrib, lit on one side.
		float body = length(q * vec2(1.0, 2.1)) + abs(q.x) * 0.25;
		a = 1.0 - smoothstep(0.78, 0.98, body);
		col *= mix(1.12, 0.82, step(0.0, q.y)) * (1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.08, abs(q.y))));
	} else if (kind == 3) {
		// A smoke puff: soft, lumpy, lighter at the top.
		float r = length(q);
		float lump = hash(floor(UV * 5.0) + floor(centre.xz * 3.0)) * 0.18;
		a = (1.0 - smoothstep(0.15, 1.0, r + lump)) * 0.9;
		col *= 1.0 + (-q.y) * 0.12;
	} else if (kind == 4) {
		a = 1.0 - smoothstep(0.2, 1.0, length(q));
		col = mix(col, vec3(1.0, 0.95, 0.7), 1.0 - smoothstep(0.0, 0.4, length(q)));
	} else {
		// A snowflake or a petal: a soft round dot.
		a = 1.0 - smoothstep(kind == 2 ? 0.55 : 0.35, 1.0, length(q * (kind == 2 ? vec2(1.0, 1.5) : vec2(1.0))));
	}
	a *= COLOR.a;
	if (kind != 4) {
		col *= night;
	}
	if (fog_on) {
		vec2 uv = (centre.xz / tile_m + 0.5) / map_size;
		vec2 m = vec2(0.0);
		if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
			m = texture(fog_tex, uv).rg;
		}
		a *= smoothstep(0.05, 0.6, m.g) * mix(0.35, 1.0, smoothstep(0.1, 0.8, m.r));
	}
	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
