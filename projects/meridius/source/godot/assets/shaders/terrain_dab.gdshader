// Painterly dabs of src/render/terrain.ts: tiny axis-aligned rects drawn with
// canvas fillRect at fractional positions. Drawn as one MultiMesh of unit
// quads; INSTANCE_CUSTOM holds the rect (x, y, w, h) in field pixels and the
// fragment computes the exact pixel coverage of the rect (box filter), which
// is how canvas anti-aliases an axis-aligned rect.
shader_type canvas_item;
render_mode unshaded;

varying vec2 lp;
varying vec2 sz;

void vertex() {
	vec4 r = INSTANCE_CUSTOM;
	vec2 pos = r.xy - vec2(1.0) + VERTEX * (r.zw + vec2(2.0));
	VERTEX = pos;
	lp = pos - r.xy;
	sz = r.zw;
}

void fragment() {
	float cx = clamp(min(lp.x + 0.5, sz.x) - max(lp.x - 0.5, 0.0), 0.0, 1.0);
	float cy = clamp(min(lp.y + 0.5, sz.y) - max(lp.y - 0.5, 0.0), 0.0, 1.0);
	COLOR = vec4(COLOR.rgb, COLOR.a * cx * cy);
}
