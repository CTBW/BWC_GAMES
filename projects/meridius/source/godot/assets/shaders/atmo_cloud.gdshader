// Cloud shadows of src/render/atmosphere.ts drawClouds: an ellipse (r, 0.55r,
// rotated 0.3) filled with a circular radial gradient rgba(70,90,110,0.22) at
// 0.1r to transparent at r, composited 'multiply'. UV is the offset from the
// cloud centre in units of r (the quad covers the ellipse plus a margin);
// the ellipse edge is anti-aliased like a canvas fill.
shader_type canvas_item;
render_mode unshaded, blend_mul;

void fragment() {
	vec2 p = UV;
	float c = cos(0.3);
	float s = sin(0.3);
	vec2 q = vec2(p.x * c + p.y * s, -p.x * s + p.y * c);
	float e = length(vec2(q.x, q.y / 0.55));
	float cov = clamp((1.0 - e) / max(fwidth(e), 1e-5) + 0.5, 0.0, 1.0);
	float t = clamp((length(p) - 0.1) / 0.9, 0.0, 1.0);
	float a = 0.22 * (1.0 - t) * cov;
	COLOR = vec4(mix(vec3(1.0), vec3(70.0, 90.0, 110.0) / 255.0, a), 1.0);
}
