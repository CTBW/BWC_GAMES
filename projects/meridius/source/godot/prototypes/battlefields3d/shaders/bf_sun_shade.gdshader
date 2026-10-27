// The sun's shadows on the 3D battlefields' ground (prototypes/battlefields3d
// scripts/bf_field.gd, `sun_shadows`): the ground's overlay material. The
// ground itself is unshaded (bf_ground.gdshader); this draws the same mesh over
// it and multiplies what is there by the shade: 1 in the sun, `shadow_tint`
// where something stands in the sun's way. The light's shadow opacity (which
// lets light through the men's own shadows) is taken back out, so the ground's
// shadows are as deep as `shadow_tint` says. Under the fog of war a shadow goes
// as the painted ones went (bf_card.gdshader): none on ground never seen,
// fainter on ground not seen now.
shader_type spatial;
render_mode blend_mul, depth_draw_never, specular_disabled, ambient_light_disabled;

// The ground's colour in full shadow as a share of it in the sun, on screen.
uniform vec3 shadow_tint = vec3(0.44, 0.47, 0.58);
// The light's shadow_opacity.
uniform float sun_opacity = 1.0;
uniform vec2 map_size;
uniform float tile_m = 2.72;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform bool fog_on = false;

varying vec2 grid;
varying float seen;

void vertex() {
	grid = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz / tile_m;
}

void fragment() {
	ALBEDO = vec3(1.0);
	seen = 1.0;
	if (fog_on) {
		vec2 uv = (grid + 0.5) / map_size;
		vec2 m = vec2(0.0);
		if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
			m = texture(fog_tex, uv).rg;
		}
		seen = smoothstep(0.03, 0.55, m.g) * mix(0.36, 1.0, smoothstep(0.08, 0.84, m.r));
	}
}

void light() {
	float s = clamp((1.0 - ATTENUATION) / max(sun_opacity, 0.01), 0.0, 1.0) * seen;
	// A lit material's light goes to the screen converted to sRGB: the shade
	// is given as on screen and goes out linear.
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, pow(mix(vec3(1.0), shadow_tint, s), vec3(2.2)));
}
