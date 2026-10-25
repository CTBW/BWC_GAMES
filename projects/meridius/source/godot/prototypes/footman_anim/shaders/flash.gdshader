// Hit flash for the prototype's dummy and soldiers: blends the sprite toward
// warm white while keeping its alpha (and so its outline shape).
shader_type canvas_item;

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.97, 0.9);

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(c.rgb, flash_color, flash), c.a);
}
