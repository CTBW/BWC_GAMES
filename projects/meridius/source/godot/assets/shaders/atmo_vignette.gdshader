// Vignette of src/render/atmosphere.ts drawGrade: a radial gradient from
// transparent at min(w,h)*0.35 to rgba(20,12,6,0.55) at max(w,h)*0.75 from
// the screen centre, drawn source-over (stops interpolated unpremultiplied).
shader_type canvas_item;
render_mode unshaded;

uniform vec2 view_size = vec2(1920.0, 1080.0);

varying vec2 pos;

void vertex() {
	pos = VERTEX;
}

void fragment() {
	vec2 p = pos;
	float r0 = min(view_size.x, view_size.y) * 0.35;
	float r1 = max(view_size.x, view_size.y) * 0.75;
	float t = clamp((length(p - view_size * 0.5) - r0) / (r1 - r0), 0.0, 1.0);
	COLOR = vec4(vec3(20.0, 12.0, 6.0) / 255.0 * t, 0.55 * t);
}
