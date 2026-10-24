// Dawn breaking over a battle fought through the night (the 'screen' gradient
// at the end of battleScene.drawNight) and the sunrise behind the relief
// (drawSunrise). 'screen' with a premultiplied source S is Cb * (1 - S) + S, so
// it is drawn in two passes without reading the screen:
// battle_dawn_mul.gdshader multiplies by 1 - S, battle_dawn_add.gdshader adds S.
// Gradient stops are interpolated premultiplied, as the canvas does.

uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform float dawn_a = 0.0;
// Sunrise: centre (screen px), radius, glow (0 = off).
uniform vec4 sun = vec4(0.0);

vec4 pm(vec3 rgb, float a) {
	return vec4(rgb / 255.0 * a, a);
}

// The source after the dawn gradient and then the sunrise:
// screen(screen(c, A), B) = 1 - (1 - c)(1 - A)(1 - B), i.e. S = 1 - (1 - A)(1 - B).
vec3 source(vec2 p) {
	vec3 keep = vec3(1.0);
	if (dawn_a > 0.0) {
		float t = clamp(p.y / (view_size.y * 0.7), 0.0, 1.0);
		vec4 s0 = pm(vec3(255.0, 170.0, 120.0), dawn_a);
		vec4 s1 = pm(vec3(255.0, 140.0, 110.0), dawn_a * 0.35);
		vec4 g = t < 0.5 ? mix(s0, s1, t / 0.5) : mix(s1, vec4(0.0), (t - 0.5) / 0.5);
		keep *= 1.0 - g.rgb;
	}
	if (sun.w > 0.0) {
		float t = clamp(length(p - sun.xy) / sun.z, 0.0, 1.0);
		vec4 s0 = pm(vec3(255.0, 214.0, 150.0), 0.42 * sun.w);
		vec4 s1 = pm(vec3(255.0, 190.0, 120.0), 0.16 * sun.w);
		vec4 g = t < 0.5 ? mix(s0, s1, t / 0.5) : mix(s1, vec4(0.0), (t - 0.5) / 0.5);
		keep *= 1.0 - g.rgb;
	}
	return 1.0 - keep;
}
