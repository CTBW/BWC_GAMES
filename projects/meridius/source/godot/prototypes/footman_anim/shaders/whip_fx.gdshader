// The succubus's whip effects (whip_fx.gd), all in one immediate mesh: flat
// cel colours, no light. COLOR.r picks the element, COLOR.g is its parameter
// and COLOR.a its fade; the fade is stepped in thirds, like the cel shading.
//   0.0  slash crescent: UV.y 0 inner edge -> 1 outer edge; COLOR.g head weight
//   0.25 streak / tip trail: UV.x 0 old end -> 1 new end, UV.y across
//   0.5  crack star: UV -1..1, x along the tip's travel
//   0.75 ring: UV -1..1; COLOR.g its thickness (of the radius)
//   1.0  dust puff: UV -1..1
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform vec4 ink : source_color = vec4(0.231, 0.071, 0.196, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 0.949, 0.973, 1.0);
uniform vec4 hot : source_color = vec4(0.949, 0.369, 0.686, 1.0);
uniform vec4 deep : source_color = vec4(0.604, 0.239, 0.769, 1.0);
uniform vec4 dust : source_color = vec4(0.914, 0.843, 0.698, 1.0);
uniform vec4 dust_ink : source_color = vec4(0.361, 0.251, 0.153, 1.0);

float star_r(vec2 p) {
	float a = atan(p.y, p.x);
	float main = pow(abs(cos(a)), 14.0);
	float side = 0.62 * pow(abs(sin(a)), 14.0);
	float diag = 0.4 * max(pow(abs(cos(a - 0.785)), 18.0), pow(abs(cos(a + 0.785)), 18.0));
	return 0.26 + 0.74 * max(main, max(side, diag));
}

void fragment() {
	int kind = int(COLOR.r * 4.0 + 0.5);
	vec3 c = rim.rgb;
	float a = 1.0;
	if (kind == 0) {
		float v = UV.y;
		float rim_from = mix(0.8, 0.62, COLOR.g);
		c = v > 0.94 ? ink.rgb : (v > rim_from ? rim.rgb : (v > 0.45 ? hot.rgb : deep.rgb));
		a = v > 0.25 ? 1.0 : (v > 0.12 ? 0.45 : 0.0);
	} else if (kind == 1) {
		float d = abs(UV.y - 0.5) * 2.0;
		c = d < 0.45 ? rim.rgb : hot.rgb;
		a = UV.x > 0.5 ? 1.0 : (UV.x > 0.2 ? 0.55 : 0.0);
	} else if (kind == 2) {
		float s = length(UV) / star_r(UV);
		c = s < 0.5 ? rim.rgb : (s < 0.78 ? hot.rgb : ink.rgb);
		a = s < 1.0 ? 1.0 : 0.0;
	} else if (kind == 3) {
		float th = max(COLOR.g, 0.02);
		float d = abs(length(UV) - (1.0 - th * 0.5)) / (th * 0.5);
		c = d < 0.5 ? rim.rgb : hot.rgb;
		a = d < 1.0 ? 1.0 : 0.0;
	} else {
		float r = length(UV);
		c = r < 0.74 ? dust.rgb : dust_ink.rgb;
		a = r < 1.0 ? 1.0 : 0.0;
	}
	float fade = ceil(clamp(COLOR.a, 0.0, 1.0) * 3.0) / 3.0;
	if (a * fade < 0.01) {
		discard;
	}
	ALBEDO = c;
	ALPHA = a * fade;
}
