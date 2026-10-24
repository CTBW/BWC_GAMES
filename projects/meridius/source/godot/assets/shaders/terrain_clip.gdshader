// Clip to a square of the tile grid (the campaign map's `ctx.clip()` to the
// land, grid [lo, hi] on both axes), anti-aliased like a canvas clip path.
// to_world_* map the canvas position (MODEL_MATRIX * VERTEX) back to world px;
// the view sets them from its world node's inverse global transform.
shader_type canvas_item;

uniform vec2 to_world_x = vec2(1.0, 0.0);
uniform vec2 to_world_y = vec2(0.0, 1.0);
uniform vec2 to_world_o = vec2(0.0, 0.0);
uniform float lo = -8.0;
uniform float hi = 46.0;

varying vec2 grid;

void vertex() {
	vec2 c = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vec2 w = to_world_x * c.x + to_world_y * c.y + to_world_o;
	float a = w.x / 64.0;
	float b = w.y / 32.0;
	grid = vec2((a + b) * 0.5, (b - a) * 0.5);
}

void fragment() {
	vec2 fw = max(fwidth(grid), vec2(1e-5));
	vec2 d = min(grid - vec2(lo), vec2(hi) - grid) / fw;
	float cov = clamp(min(d.x, d.y) + 0.5, 0.0, 1.0);
	COLOR.a *= cov;
}
