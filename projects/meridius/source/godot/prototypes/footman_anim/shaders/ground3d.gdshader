// Sandbox ground for the 3D footman: the battle map's grass texture sampled
// as the game's relief shader does (two scales and a turn, painted rather
// than gritty, tile units), a faint light line on every tile edge and the
// picked tile outlined. Lit only by the sun's shadow: flat ground in the sun
// shows the texture's own colour, as in the game; in shadow it goes cool.
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

// The Compatibility renderer lights in display (sRGB) values, as the game's 2D
// shader mixes them, so nothing is converted.
uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap;
// Brightness to meet the battle map's meadow as captured (its relief light and grading).
uniform float gain = 1.3;
uniform float tile = 2.72;
uniform vec3 grass_tint = vec3(0.36, 0.43, 0.19);
uniform vec3 shade = vec3(0.58, 0.66, 0.78);
uniform vec2 focus = vec2(0.0);
uniform float focus_on = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz / tile;
	vec3 a = textureLod(grass_tex, p / 2.1, 4.5).rgb;
	vec2 q = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8) / (2.1 * 1.43) + vec2(0.37, 0.71);
	vec3 b = textureLod(grass_tex, q, 4.5).rgb;
	vec3 c = mix(mix(a, b, 0.5), grass_tint, 0.48) * gain;
	vec2 g = p + 0.5;
	vec2 f = abs(fract(g) - 0.5);
	float e = max(f.x, f.y);
	float lw = fwidth(e) * 1.2;
	c = mix(c, vec3(0.7, 0.78, 0.5), smoothstep(0.5 - lw, 0.5, e) * 0.16);
	if (focus_on > 0.5 && all(equal(floor(g), focus))) {
		c = mix(c, vec3(1.0, 0.95, 0.7), smoothstep(0.5 - lw * 2.5, 0.5, e) * 0.7);
	}
	ALBEDO = c;
}

void light() {
	// Only the sun's shadow darkens it; its colour stays the painted one.
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, mix(shade, vec3(1.0), ATTENUATION));
}
