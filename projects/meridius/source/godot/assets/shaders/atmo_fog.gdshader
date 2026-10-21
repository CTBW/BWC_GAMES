// Fog of war puffs of campaignScene.render: a 128 px mist texture drawn as a
// quad of radius r at (x + sin(time*0.2 + fx)*10, y), globalAlpha 0.85*a.
// One MultiMesh of unit quads; INSTANCE_CUSTOM = (x, y, r, fx), instance
// colour alpha = 0.85*a, `time` is the scene time.
shader_type canvas_item;

uniform float time = 0.0;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	vec2 centre = vec2(c.x + sin(time * 0.2 + c.w) * 10.0, c.y);
	VERTEX = centre + (VERTEX * 2.0 - vec2(1.0)) * c.z;
}
