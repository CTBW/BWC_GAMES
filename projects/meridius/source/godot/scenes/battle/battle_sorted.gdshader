// The battle view's depth-sorted pass (battle_draw.gd draw_sorted): props,
// squads, corpses, the host, cast shadows and hit flashes in one CanvasItem,
// each with the original's compositing:
//  - ordinary draws: source-over (premultiplied here);
//  - Assets.draw_flash (vertex red far above 1): 'lighter' + flashOf, an
//    additive white silhouette;
//  - vertex blue far above 1: a premultiplied texture (a SubViewport's: the
//    massed host) drawn at alpha vcol.a;
//  - vertex green above 2 (Assets.draw_tint, tintOf): the sprite's silhouette
//    in the colour (r, g - Assets.TINT, b), source-over (frost, a frenzy's red).
shader_type canvas_item;
render_mode blend_premul_alpha;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	if (vcol.r > 2.0) {
		float a = texture(TEXTURE, UV).a * clamp(vcol.a, 0.0, 1.0);
		COLOR = vec4(a, a, a, 0.0);
	} else if (vcol.b > 2.0) {
		COLOR = texture(TEXTURE, UV) * clamp(vcol.a, 0.0, 1.0);
	} else if (vcol.g > 2.0) {
		float a = texture(TEXTURE, UV).a * clamp(vcol.a, 0.0, 1.0);
		COLOR = vec4(vec3(vcol.r, vcol.g - 4.0, vcol.b) * a, a);
	} else {
		COLOR = vec4(COLOR.rgb * COLOR.a, COLOR.a);
	}
}
