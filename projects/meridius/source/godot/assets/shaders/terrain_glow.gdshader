// Fire glow along the host's front (campaignScene.drawHorde): a radial
// gradient rgba(255,140,50,0.55) at r0 to rgba(255,90,30,0) at r, composited
// 'lighter' (additive), clipped to the land like terrain_clip.gdshader.
// UV is the offset from the centre in units of r; COLOR.r carries r0 / r.
shader_type canvas_item;
render_mode blend_add;

uniform vec2 to_world_x = vec2(1.0, 0.0);
uniform vec2 to_world_y = vec2(0.0, 1.0);
uniform vec2 to_world_o = vec2(0.0, 0.0);
uniform float lo = -8.0;
uniform float hi = 46.0;

varying vec2 grid;
varying float k0;

void vertex() {
	vec2 c = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vec2 w = to_world_x * c.x + to_world_y * c.y + to_world_o;
	float a = w.x / 64.0;
	float b = w.y / 32.0;
	grid = vec2((a + b) * 0.5, (b - a) * 0.5);
	k0 = COLOR.r;
}

void fragment() {
	vec2 fw = max(fwidth(grid), vec2(1e-5));
	vec2 d = min(grid - vec2(lo), vec2(hi) - grid) / fw;
	float cov = clamp(min(d.x, d.y) + 0.5, 0.0, 1.0);
	float t = clamp((length(UV) - k0) / (1.0 - k0), 0.0, 1.0);
	vec4 g = mix(vec4(255.0, 140.0, 50.0, 0.55 * 255.0), vec4(255.0, 90.0, 30.0, 0.0), t) / 255.0;
	COLOR = vec4(g.rgb, g.a * cov);
}
