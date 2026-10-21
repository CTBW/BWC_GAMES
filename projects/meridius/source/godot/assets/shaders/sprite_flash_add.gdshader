// Additive variant of sprite_flash.gdshader: the garrison's hover highlight,
// drawn in the original with globalCompositeOperation 'lighter' and flashOf().
// Use on a CanvasItem that draws only that highlight (Assets.additive_material()).
shader_type canvas_item;
render_mode blend_add;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	if (vcol.r > 2.0) {
		COLOR = vec4(1.0, 1.0, 1.0, texture(TEXTURE, UV).a * clamp(vcol.a, 0.0, 1.0));
	}
}
