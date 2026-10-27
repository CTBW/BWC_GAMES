// The battle view's depth-sorted pass (battle_draw.gd draw_sorted): props,
// squads, corpses, the host, cast shadows and hit flashes in one CanvasItem,
// each with the original's compositing:
//  - ordinary draws: source-over (premultiplied here);
//  - Assets.draw_flash (vertex red far above 1): 'lighter' + flashOf, an
//    additive white silhouette;
//  - vertex blue far above 1: a premultiplied texture (a SubViewport's: the
//    massed host) drawn at alpha vcol.a;
//  - vertex green above 2 (Assets.draw_tint, tintOf): the sprite's silhouette
//    in the colour (r, g - Assets.TINT, b), source-over (frost, a frenzy's red);
//  - vertex red below -2 (a breathing soldier, battle_draw._draw_squad): the
//    sprite with its upper body sunk by -g of its height (an out-breath) and
//    leant sideways by b (in heights), feet pinned; r = -4 - the frame's middle
//    row in atlas UV, which tells the quad's top vertices from its feet.
shader_type canvas_item;
render_mode blend_premul_alpha;

varying vec4 vcol;
// 1 at a breathing sprite's top edge, 0 at its feet (exact: the vertices are 0 or 1).
varying float vtop;

void vertex() {
	vcol = COLOR;
	vtop = 0.0;
	if (COLOR.r < -2.0) {
		vtop = UV.y < -COLOR.r - 4.0 ? 1.0 : 0.0;
	}
}

void fragment() {
	if (vcol.r < -2.0) {
		// The sprite's height in atlas UV, from how UV.y runs against vtop on screen.
		vec2 dt = vec2(dFdx(vtop), dFdy(vtop));
		vec2 du = vec2(dFdx(UV.y), dFdy(UV.y));
		float h = -dot(du, dt) / max(dot(dt, dt), 1e-12);
		// Hips to head move, legs stay: the chest sinks, the shoulders and head with it.
		float k = smoothstep(0.3, 0.78, vtop);
		float src = vtop - vcol.g * k;
		vec2 uv = UV;
		uv.y += (vtop - src) * h;
		uv.x -= vcol.b * k * k * (h / TEXTURE_PIXEL_SIZE.y) * TEXTURE_PIXEL_SIZE.x;
		vec4 c = texture(TEXTURE, uv);
		float a = src > 1.0 ? 0.0 : c.a * clamp(vcol.a, 0.0, 1.0);
		COLOR = vec4(c.rgb * a, a);
	} else if (vcol.b >= 8.0 && vcol.b <= 9.1) {
		// Terrain-lab painted sources: key only explicitly marked foliage draws.
		// The original texture is retained; unit palettes never enter this branch.
		vec4 c = texture(TEXTURE, UV);
		float chroma = min(c.r, c.b) - c.g;
		float a = c.a * (1.0 - smoothstep(0.1, 0.58, chroma)) * vcol.a;
		// Mip filtering mixes the backdrop into thin needles. Remove its red
		// and blue excess before tinting, including partially transparent edges.
		c.r -= max(chroma, 0.0);
		c.b -= max(chroma, 0.0);
		COLOR = vec4(c.rgb * vec3(vcol.r, vcol.g, vcol.b - 8.0) * a, a);
	} else if (vcol.r > 2.0) {
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
