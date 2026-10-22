// The battle view's air FX and its screen flash (fx.gd draw_air,
// battle_draw.gd draw_screen_flash): the original interleaves ordinary
// source-over draws (puffs, sparks, stones, tendrils) with 'lighter' ones
// (glow particles, lightning, magic missiles, the flash) in one pass.
//  - ordinary draws: source-over (premultiplied here);
//  - vertex red above 2 (Fx.ADD added to red): 'lighter', the colour
//    (r - 4, g, b) at its alpha added (premultiplied, zero alpha).
shader_type canvas_item;
render_mode blend_premul_alpha;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	if (vcol.r > 2.0) {
		vec4 t = texture(TEXTURE, UV);
		float a = t.a * clamp(vcol.a, 0.0, 1.0);
		COLOR = vec4(vec3(vcol.r - 4.0, vcol.g, vcol.b) * t.rgb * a, 0.0);
	} else {
		COLOR = vec4(COLOR.rgb * COLOR.a, COLOR.a);
	}
}
