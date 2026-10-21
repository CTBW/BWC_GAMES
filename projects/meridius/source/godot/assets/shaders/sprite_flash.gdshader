// Sprite material for CanvasItems that draw hit flashes (scripts/render/assets.gd).
// Assets.draw_flash() draws the sprite with a vertex colour whose red channel is
// far above 1 (Assets.FLASH); this shader turns such draws into the original's
// flashOf(): a white silhouette with the sprite's alpha times the draw alpha.
// Every other draw (sprites, polygons, text) keeps Godot's default colour.
shader_type canvas_item;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	if (vcol.r > 2.0) {
		COLOR = vec4(1.0, 1.0, 1.0, texture(TEXTURE, UV).a * clamp(vcol.a, 0.0, 1.0));
	}
}
