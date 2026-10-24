// Dawn / sunrise 'screen', first pass: multiply by 1 - S (battle_dawn.gdshaderinc).
shader_type canvas_item;
render_mode blend_mul;

#include "res://scenes/battle/battle_dawn.gdshaderinc"

void fragment() {
	COLOR = vec4(vec3(1.0) - source(UV * view_size), 1.0);
}
