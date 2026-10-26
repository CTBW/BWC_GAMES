// A painted cut-out's shadow on the 3D battlefields (prototypes/battlefields3d
// scripts/bf_field.gd, `sun_shadows`): an unseen copy of its upright part
// turned to the sun, drawn only into the sun's shadow map, cut out where the
// painting is clear. The casters of one picture are one mesh in the field's
// space. Each bends in the wind as its card does (bf_card.gdshader): UV2.x is
// its card's phase less this mesh's place, UV2.y how far the point sways.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform float sway = 0.0;

void vertex() {
	vec3 node = NODE_POSITION_WORLD;
	float ph = UV2.x + node.x * 0.37 + node.z * 0.53;
	float w = sin(TIME * 0.9 + ph) * 0.65 + sin(TIME * 2.1 + ph * 1.7) * 0.25 + sin(TIME * 4.3 + ph * 2.9) * 0.1;
	VERTEX += vec3(0.70710678, 0.0, -0.70710678) * w * sway * UV2.y;
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = texture(tex, UV).a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
