// Marching dashes along static strokes (the held ground's outline in
// battleScene.drawZone: setLineDash([10, 7]), lineDashOffset = -time * 12).
// UV.x is the distance along the stroke's own subpath; the vertex alpha
// feathers the stroke's sides. Only `offset` and `tint` change per frame.
shader_type canvas_item;

uniform float offset = 0.0;
uniform float on_len = 10.0;
uniform float off_len = 7.0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	float ph = mod(UV.x + offset, on_len + off_len);
	float on = step(ph, on_len);
	COLOR = vec4(tint.rgb, tint.a * COLOR.a * on);
}
