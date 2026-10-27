// A man's shield in his squad's heraldry (prototypes/squad_looks/scripts/unit_look.gd).
// The painted field (the texture's blue band) takes the squad's tinctures,
// split by a division drawn on the shield's front in its own space; the charge
// (the eagle: `charge_tex`, found once from the texture by unit_look.gd) takes
// the charge's colour. Colour by per-instance uniforms, as unit_variant.gdshader.
// Divisions: 0 plain, 1 per pale, 2 per fess, 3 quarterly, 4 per bend,
// 5 chevron, 6 pale, 7 fess.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform sampler2D albedo_tex : filter_linear_mipmap_anisotropic, repeat_enable;
// The charge's mask over the texture's front island (`charge_lo` .. `charge_hi` in UV).
uniform sampler2D charge_tex : filter_linear, repeat_disable;
uniform vec2 charge_lo = vec2(0.0);
uniform vec2 charge_hi = vec2(1.0);
uniform vec3 ref_field = vec3(0.231, 0.326, 0.495);
uniform float ref_charge_v = 0.86;
// The front's extent in the shield's own space (x across, y up).
uniform vec2 face_lo = vec2(-0.25, -0.45);
uniform vec2 face_hi = vec2(0.25, 0.45);
uniform float roughness = 1.0;

instance uniform vec4 field = vec4(0.231, 0.326, 0.495, 1.0);
instance uniform vec4 field2 = vec4(0.231, 0.326, 0.495, 1.0);
instance uniform vec4 charge = vec4(0.86, 0.86, 0.86, 1.0);
instance uniform float division = 0.0;
instance uniform float wear = 0.0;

varying vec3 obj;

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

// Which side of the division a point of the front (q: 0..1 across and up) is
// on: > 0 the second tincture.
float side(vec2 q, int d) {
	if (d == 1) return q.x - 0.5;
	if (d == 2) return q.y - 0.56;
	if (d == 3) return (q.x - 0.5) * (q.y - 0.56);
	if (d == 4) return (q.x + q.y) - 1.06;
	if (d == 5) {
		float k = q.y - (0.56 - abs(q.x - 0.5) * 0.9);
		return 0.075 - abs(k - 0.075);
	}
	if (d == 6) return 0.13 - abs(q.x - 0.5);
	if (d == 7) return 0.09 - abs(q.y - 0.5);
	return -1.0;
}

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(c);
	vec3 rf = rgb2hsv(ref_field);
	vec2 cuv = (UV - charge_lo) / (charge_hi - charge_lo);
	float inside = step(0.0, cuv.x) * step(cuv.x, 1.0) * step(0.0, cuv.y) * step(cuv.y, 1.0);
	float ch = texture(charge_tex, clamp(cuv, 0.0, 1.0)).r * inside;
	float blue = (1.0 - smoothstep(0.075, 0.115, abs(fract(hsv.x - rf.x + 0.5) - 0.5))) * smoothstep(0.13, 0.22, hsv.y);
	vec2 q = (obj.xy - face_lo) / (face_hi - face_lo);
	float s = side(q, int(division + 0.5));
	float w = max(fwidth(s), 1e-4);
	float k = smoothstep(-w, w, s);
	vec3 paint = mix(remap(hsv, rf, field.rgb), remap(hsv, rf, field2.rgb), k);
	// Wear: chips where the paint is gone to the wood, more on a worn shield.
	float n = noise(UV * 160.0) * 0.65 + noise(UV * 520.0) * 0.35;
	float chip = smoothstep(0.86 - wear * 0.22, 0.9 - wear * 0.22, n) * step(0.05, wear);
	paint = mix(paint, vec3(0.46, 0.35, 0.24) * (0.6 + hsv.z), chip * 0.85);
	vec3 o = mix(c, paint, blue * (1.0 - ch));
	vec3 t = rgb2hsv(charge.rgb);
	vec3 gilt = hsv2rgb(vec3(t.x, t.y, clamp(hsv.z * t.z / ref_charge_v, 0.0, 1.0)));
	o = mix(o, gilt, ch);
	float l = dot(o, vec3(0.3, 0.59, 0.11));
	o = mix(o, vec3(l), wear * 0.15);
	ALBEDO = o;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
