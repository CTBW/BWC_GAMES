// The captain's winged helmet (art/footman_3d/tools/captain_helmet.py builds
// it), gold and silver in the footman's toon light. Polished metal shows what
// it mirrors more than its own colour, so the mirror is painted in: the view
// reflected off the surface (world space) sees a bright sky above the horizon
// and the ground below, cut sharp at the horizon as chrome is drawn, all
// tinted by the metal: `band` just under the horizon, `deep` further down (his
// sides and the wings, upright, mirror the ground from the game's camera, so
// it is the metal's main colour), `metal` in the sky and `bright` toward the
// top. The vertex colour's R is the baked occlusion: dark between the
// feathers and under the rims.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec3 band : source_color = vec3(0.42, 0.2, 0.04);
uniform vec3 deep : source_color = vec3(0.8, 0.5, 0.14);
uniform vec3 metal : source_color = vec3(1.0, 0.72, 0.22);
uniform vec3 bright : source_color = vec3(1.0, 0.86, 0.45);
// The horizon (the reflected ray's world up), how soft its cut is, and how
// far below it the ground turns from `band` to `deep`.
uniform float horizon = 0.05;
uniform float edge = 0.03;
uniform float drop = 0.45;
// The sky's brightest part, from this far up to straight up.
uniform float zenith = 0.55;
uniform float occlusion : hint_range(0.0, 1.0) = 0.6;
// The sun's highlight: its strength and size (toon: a hard spot).
uniform float spec : hint_range(0.0, 1.0) = 0.35;
uniform float gloss : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	vec3 r = reflect(-VIEW, NORMAL);
	float up = (INV_VIEW_MATRIX * vec4(r, 0.0)).y;
	float sky = smoothstep(horizon - edge, horizon + edge, up);
	vec3 ground = mix(band, deep, smoothstep(horizon, horizon - drop, up));
	vec3 c = mix(ground, mix(metal, bright, smoothstep(horizon, zenith, up)), sky);
	ALBEDO = c * mix(1.0, COLOR.r, occlusion);
	ROUGHNESS = gloss;
	SPECULAR = spec;
	METALLIC = 0.0;
}
