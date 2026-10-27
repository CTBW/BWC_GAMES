// World-anchored woodland haze. Drawn over the scene, beneath the desktop UI.
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D scene : hint_screen_texture, filter_linear;
uniform vec2 camera;
uniform vec2 view_size;
uniform float zoom = 1.0;
uniform float clock = 0.0;
uniform bool night = false;
uniform float strength = 1.0;
uniform vec2 patrol_a;
uniform vec2 patrol_b;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1,0)), f.x), mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}
void fragment() {
	vec2 world = (UV * view_size - view_size * 0.5) / zoom + camera;
	vec2 p = world / vec2(420.0, 105.0) + vec2(clock * 0.012, clock * 0.005);
	float cloud = noise(p) * 0.65 + noise(p * 2.1) * 0.25 + noise(p * 4.0) * 0.1;
	float pockets = smoothstep(0.44, 0.76, cloud);
	float distance_to_patrol = min(length(world - patrol_a), length(world - patrol_b));
	float clear = mix(0.25, 1.0, smoothstep(90.0, 260.0, distance_to_patrol));
	float far = 1.0 - smoothstep(0.2, 0.95, UV.y);
	float fog = (pockets * 0.22 + far * 0.035) * clear * strength;
	float shaft = pow(max(0.0, sin((world.x * 0.72 - world.y * 0.28) * 0.008 + 0.7)), 14.0);
	float gold = shaft * (1.0 - UV.y * 0.6) * 0.09 * strength;
	vec3 mist = night ? vec3(0.48, 0.65, 0.68) : vec3(0.64, 0.73, 0.68);
	vec3 light = night ? vec3(0.64, 0.78, 0.78) : vec3(1.0, 0.81, 0.38);
	float alpha = fog + gold;
	vec3 col = texture(scene, SCREEN_UV).rgb;
	// Grade the final pixels: modulating sprite vertices would corrupt the
	// production renderer's encoded outline/breathing draw modes.
	if (night) {
		col *= vec3(0.64, 0.78, 0.84);
	} else {
		float glow = exp(-length(UV - vec2(0.12, -0.1)) * 1.9) * 0.14;
		col += vec3(1.0, 0.81, 0.38) * glow * (1.0 - col);
	}
	vec2 px = SCREEN_PIXEL_SIZE * 4.0;
	vec3 bloom = (texture(scene, SCREEN_UV + vec2(px.x, 0)).rgb + texture(scene, SCREEN_UV - vec2(px.x, 0)).rgb
		+ texture(scene, SCREEN_UV + vec2(0, px.y)).rgb + texture(scene, SCREEN_UV - vec2(0, px.y)).rgb) * 0.25;
	col += max(bloom - vec3(0.62), vec3(0.0)) * (night ? 0.08 : 0.18);
	col = mix(col, mix(mist, light, gold / max(alpha, 0.001)), alpha);
	float edge = smoothstep(0.25, 0.85, length((UV - 0.5) * vec2(1.0, 0.75)));
	col *= 1.0 - edge * 0.12;
	COLOR = vec4(col, 1.0);
}
