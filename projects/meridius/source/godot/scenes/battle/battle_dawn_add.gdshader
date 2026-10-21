// Dawn / sunrise 'screen', second pass: add S (battle_dawn.gdshaderinc).
shader_type canvas_item;
render_mode blend_add;

#include "res://scenes/battle/battle_dawn.gdshaderinc"

void fragment() {
	COLOR = vec4(source(UV * view_size), 1.0);
}
