// A squad man's helmet, cap or plume (prototypes/squad_looks/scripts/unit_look.gd
// builds the meshes): one colour per instance, the vertex colour's R a baked
// shade (dark under a brim, inside a rim). Metal gets a hard toon highlight
// and a sky-and-ground sheen.
shader_type spatial;
// Two-sided: the brims' undersides and the nasal bar show either face.
render_mode diffuse_toon, specular_toon, cull_disabled;

instance uniform vec4 tint = vec4(0.70, 0.72, 0.74, 1.0);
instance uniform float metal = 1.0;

void fragment() {
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 c = tint.rgb * mix(0.45, 1.0, COLOR.r);
	// Polished metal mirrors the sky above and the dark ground below: lighter
	// where it faces up, darker on its sides (view space; the camera looks down).
	c *= mix(1.0, mix(0.62, 1.18, smoothstep(0.0, 0.7, NORMAL.y)), metal);
	ALBEDO = c;
	ROUGHNESS = mix(1.0, 0.42, metal);
	SPECULAR = mix(0.0, 0.45, metal);
	METALLIC = 0.0;
}
