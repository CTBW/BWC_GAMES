// The Sovereign Kiss's fog heart and its puffs in the 3D sandbox
// (prototypes/sandbox3d/scripts/kiss_fx3d.gd), ported from the SK_Heart and
// SK_Puff materials of art/succubus_3d/tools/kiss_heart.py. A card turned to
// the camera whose shape is a distance field (`sdf`: R is 0.5 at the edge and
// rises inwards; G is the heart's highlight on its upper left lobe). Moving
// noise is added to the distance before it is thresholded, so the shape stays
// crisp while dense and is eaten from the edge into holes as it erodes.
// Each card's density, erosion and noise seed are its instance uniforms; the
// heart and the puffs share one material each.
// Colours are the handoff's sRGB palette (blender-handoff-fog.md) and go out
// as they are: the sandbox's 3D pipeline (Compatibility) shows ALBEDO's values
// unconverted.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform sampler2D sdf : filter_linear_mipmap, repeat_disable;
// The colour bands inwards from the edge over `depth` of distance (cel steps).
uniform sampler2D bands : filter_linear, repeat_disable;
uniform float depth = 0.3;
// The soft edge's width outside and inside the threshold, and the glow outside it.
uniform vec2 edge = vec2(0.025, 0.035);
uniform float halo_k = 0.5;
// The heart's darker point and its highlight; a puff has neither.
uniform bool heart = true;
uniform vec3 rose = vec3(0.957, 0.298, 0.616);
uniform vec3 raspberry = vec3(0.784, 0.153, 0.467);
uniform vec3 pale = vec3(1.0, 0.890, 0.945);

instance uniform float density = 1.0;
instance uniform float erosion = 0.0;
instance uniform float seed = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Blender's noise texture at detail 3: four octaves, each half the last, in 0..1.
float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	float n = 0.0;
	for (int i = 0; i < 4; i++) {
		s += value_noise(p) * a;
		n += a;
		p *= 2.0;
		a *= 0.5;
	}
	return s / n;
}

void vertex() {
	// Turned to the camera, keeping the card's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 sh = texture(sdf, UV).rg;
	float n = fbm(vec3(UV * 3.5, seed * 10.0 + TIME * 0.9));
	float f = sh.r + (n * 2.0 - 1.0) * (0.07 + 0.45 * erosion);
	float th = 0.5 + 0.3 * erosion;
	float body = smoothstep(th - edge.x, th + edge.y, f);
	float halo = smoothstep(th - 0.12, th, f) * (1.0 - body) * (1.0 - erosion) * halo_k;
	vec3 col = texture(bands, vec2(clamp((f - th) / depth, 0.0, 1.0), 0.5)).rgb;
	if (heart) {
		col = mix(col, raspberry, UV.y * UV.y * 0.45);
		col = mix(col, pale, sh.g * 0.85 * (1.0 - erosion));
	}
	ALBEDO = mix(rose, col, body);
	ALPHA = min((body + halo) * density, 1.0);
}
