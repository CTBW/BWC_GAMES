// Inverted-hull outline for the 3D footman: the back faces pushed out along
// the normal by `width` metres, drawn flat. The sandbox sets `width` from the
// zoom so the line stays about the same number of pixels on screen.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 color : source_color = vec4(0.09, 0.07, 0.07, 1.0);
uniform float width = 0.03;

void vertex() {
	VERTEX += normalize(NORMAL) * width;
}

void fragment() {
	ALBEDO = color.rgb;
}
