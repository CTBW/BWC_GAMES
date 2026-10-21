// The warm glow where the light falls at night (drawNight's 'soft-light'
// pass): TEXTURE is the glows, premultiplied, painted at a quarter of the
// resolution; they are blended soft-light over what is drawn so far.
// The only pass of the battle view that reads the screen.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

vec3 soft_light(vec3 cb, vec3 cs) {
	vec3 d = mix(sqrt(cb), ((16.0 * cb - 12.0) * cb + 4.0) * cb, step(cb, vec3(0.25)));
	vec3 lo = cb - (1.0 - 2.0 * cs) * cb * (1.0 - cb);
	vec3 hi = cb + (2.0 * cs - 1.0) * (d - cb);
	return mix(hi, lo, step(cs, vec3(0.5)));
}

void fragment() {
	vec3 cb = texture(screen_tex, SCREEN_UV).rgb;
	vec4 g = texture(TEXTURE, UV);
	vec3 c = cb;
	if (g.a > 0.0001) {
		vec3 cs = clamp(g.rgb / g.a, 0.0, 1.0);
		c = mix(cb, soft_light(cb, cs), clamp(g.a, 0.0, 1.0));
	}
	COLOR = vec4(c, 1.0);
}
