// Light grading of src/render/atmosphere.ts drawGrade, over everything drawn
// so far (screen texture):
//   day:   a linear gradient (0,0)->(w,h) composited 'soft-light', then the sun
//          glow (radial, from the upper left) composited 'screen';
//   night: rgba(70,80,140,0.55) composited 'multiply' (unless the scene draws
//          its own night mask, then nothing).
// Canvas gradients interpolate colour stops without premultiplying alpha.
// Blend formulas are the W3C compositing ones over an opaque backdrop.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 view_size = vec2(1920.0, 1080.0);

varying vec2 pos;

void vertex() {
	pos = VERTEX;
}
uniform float warmth = 1.0;
uniform int mode = 0; // 0 day, 1 night tint, 2 nothing

float soft(float cb, float cs) {
	if (cs <= 0.5) {
		return cb - (1.0 - 2.0 * cs) * cb * (1.0 - cb);
	}
	float d = cb <= 0.25 ? ((16.0 * cb - 12.0) * cb + 4.0) * cb : sqrt(cb);
	return cb + (2.0 * cs - 1.0) * (d - cb);
}

void fragment() {
	vec3 cb = texture(screen_tex, SCREEN_UV).rgb;
	vec2 p = pos;
	float w = view_size.x;
	float h = view_size.y;
	if (mode == 0) {
		float t = clamp((p.x * w + p.y * h) / (w * w + h * h), 0.0, 1.0);
		vec4 s0 = vec4(255.0, 214.0, 140.0, 0.45 * warmth * 255.0) / 255.0;
		vec4 s1 = vec4(255.0, 240.0, 210.0, 0.05 * 255.0) / 255.0;
		vec4 s2 = vec4(60.0, 90.0, 130.0, 0.35 * 255.0) / 255.0;
		vec4 g = t < 0.55 ? mix(s0, s1, t / 0.55) : mix(s1, s2, (t - 0.55) / 0.45);
		vec3 bl = vec3(soft(cb.r, g.r), soft(cb.g, g.g), soft(cb.b, g.b));
		cb = mix(cb, bl, g.a);
		// Sun glow from the upper left ('screen').
		vec2 c = vec2(w * 0.08, -h * 0.1);
		float r1 = max(w, h) * 0.75;
		float ts = clamp((length(p - c) - 10.0) / (r1 - 10.0), 0.0, 1.0);
		float a = 0.22 * (1.0 - ts);
		vec3 sc = vec3(255.0, 225.0, 160.0) / 255.0;
		cb = cb + a * sc * (1.0 - cb);
	} else if (mode == 1) {
		cb = cb * (0.45 + 0.55 * vec3(70.0, 80.0, 140.0) / 255.0);
	}
	COLOR = vec4(cb, 1.0);
}
