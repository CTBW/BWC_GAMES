// One man of a squad (prototypes/squad_looks/scripts/unit_look.gd): one material
// shared by every man, each man's colours set on his mesh as per-instance
// uniforms (GeometryInstance3D.set_instance_shader_parameter).
// The Tripo texture has no masks, so its parts are told apart by colour band
// (the blue cloth, the cream linen, the brown leather and hair, the skin; the
// `ref_` means are measured from the texture) and by body region, baked into
// the vertex colour from the skin weights: R head and neck, G legs, B the
// lower face (beard), A the height at rest (m / 2).
// Each band is recoloured in HSV relative to its mean, so the paint's own
// strokes and shading carry over; a target equal to the mean leaves the
// texture as it is. Colours are display (sRGB) values and go out as they are:
// the Compatibility renderer shows ALBEDO unconverted (as the footman's
// StandardMaterial3D shows its texture).
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform sampler2D albedo_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 ref_cloth = vec3(0.234, 0.276, 0.418);
uniform vec3 ref_linen = vec3(0.800, 0.713, 0.618);
uniform vec3 ref_brown = vec3(0.344, 0.238, 0.180);
uniform vec3 ref_skin = vec3(0.848, 0.638, 0.482);
uniform float roughness = 1.0;

instance uniform vec4 cloth = vec4(0.234, 0.276, 0.418, 1.0);
instance uniform vec4 trousers = vec4(0.234, 0.276, 0.418, 1.0);
instance uniform vec4 linen = vec4(0.800, 0.713, 0.618, 1.0);
instance uniform vec4 leather = vec4(0.344, 0.238, 0.180, 1.0);
instance uniform vec4 hair = vec4(0.344, 0.238, 0.180, 1.0);
instance uniform vec4 skin = vec4(0.848, 0.638, 0.482, 1.0);
instance uniform float beard = 0.0;
instance uniform float grime = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

float hue_dist(float a, float b) {
	return abs(fract(a - b + 0.5) - 0.5);
}

// A texel of a band (mean `ref`, HSV) moved to `target` (RGB): half its hue
// offset, its saturation and value in proportion.
vec3 remap(vec3 hsv, vec3 ref, vec3 target) {
	vec3 t = rgb2hsv(target);
	float dh = (fract(hsv.x - ref.x + 0.5) - 0.5) * 0.5;
	float s = clamp(hsv.y * t.y / max(ref.y, 0.02), 0.0, 1.0);
	float v = clamp(hsv.z * t.z / max(ref.z, 0.02), 0.0, 1.0);
	return hsv2rgb(vec3(fract(t.x + dh), s, v));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(c);
	vec3 rc = rgb2hsv(ref_cloth);
	float head = COLOR.r;
	float legs = COLOR.g;
	// The bands, soft-edged so the paint's anti-aliasing blends between them.
	float blue = (1.0 - smoothstep(0.075, 0.115, hue_dist(hsv.x, rc.x))) * smoothstep(0.13, 0.22, hsv.y);
	float warm = 1.0 - smoothstep(0.075, 0.12, hue_dist(hsv.x, 0.07));
	float bright = smoothstep(0.48, 0.6, hsv.z);
	float sat = smoothstep(0.26, 0.33, hsv.y);
	float skin_m = warm * bright * sat * head;
	float linen_m = warm * bright * (1.0 - sat) * smoothstep(0.07, 0.13, hsv.y);
	float brown_m = warm * (1.0 - bright) * smoothstep(0.18, 0.28, hsv.y);
	vec3 o = c;
	o = mix(o, remap(hsv, rc, cloth.rgb), blue * (1.0 - legs));
	o = mix(o, remap(hsv, rc, trousers.rgb), blue * legs);
	o = mix(o, remap(hsv, rgb2hsv(ref_linen), linen.rgb), linen_m);
	o = mix(o, remap(hsv, rgb2hsv(ref_brown), leather.rgb), brown_m * (1.0 - head));
	o = mix(o, remap(hsv, rgb2hsv(ref_brown), hair.rgb), brown_m * head);
	vec3 face = remap(hsv, rgb2hsv(ref_skin), skin.rgb);
	// The beard: the lower face painted in a darker shade of his hair, by its shading.
	vec3 whisker = hair.rgb * 0.82 * clamp(hsv.z / rgb2hsv(ref_skin).z, 0.4, 1.1);
	float b = beard * smoothstep(0.15, 0.6, COLOR.b) * (0.75 + 0.25 * noise(UV * 900.0));
	face = mix(face, whisker, clamp(b, 0.0, 1.0));
	o = mix(o, face, skin_m);
	// Dirt: mud splashed up the boots and trousers, dust over everything.
	float n = noise(UV * 70.0) * 0.6 + noise(UV * 260.0) * 0.4;
	float mud = grime * (1.0 - smoothstep(0.03, 0.22 + 0.06 * n, COLOR.a)) * smoothstep(0.25, 0.65, n + grime * 0.3);
	o = mix(o, vec3(0.30, 0.24, 0.17) * (0.75 + 0.5 * n), clamp(mud, 0.0, 0.85));
	float l = dot(o, vec3(0.3, 0.59, 0.11));
	o = mix(o, vec3(l) * vec3(1.0, 0.95, 0.86), grime * 0.18);
	ALBEDO = o;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
