// Clip to the water of a terrain layer (the original's `ctx.clip(layer.water)`:
// the union of the water, shallows and bridge diamonds at their height).
// The node draws in world pixels; each fragment finds the tile under it at
// every height level and keeps itself when that tile is water at that level.
// water_tex holds (h + 1) / 255 for water tiles, 0 elsewhere, over the grid
// from (gx0, gy0).
shader_type canvas_item;

uniform sampler2D water_tex : filter_nearest;
uniform int gx0;
uniform int gy0;
uniform int gw;
uniform int gh;
uniform int max_h;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	float keep = 0.0;
	for (int l = 0; l <= max_h; l++) {
		vec2 s = vec2(world.x, world.y + float(l) * 26.0);
		float a = s.x / 64.0;
		float b = s.y / 32.0;
		vec2 g = vec2((a + b) * 0.5, (b - a) * 0.5);
		ivec2 t = ivec2(floor(g + 0.5)) - ivec2(gx0, gy0);
		if (t.x >= 0 && t.y >= 0 && t.x < gw && t.y < gh) {
			int v = int(texelFetch(water_tex, t, 0).r * 255.0 + 0.5);
			if (v == l + 1) {
				keep = 1.0;
			}
		}
	}
	COLOR.a *= keep;
}
