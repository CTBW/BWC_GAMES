// The darkness of a night battle (battleScene.drawNight): the blue-black mask
// with torch-light holes cut out of it, drawn over the world. TEXTURE is the
// mask (painted at a quarter of the resolution, holes multiplied out of its
// alpha); the colour is the night's.
shader_type canvas_item;

uniform vec3 night_rgb;

void fragment() {
	COLOR = vec4(night_rgb, texture(TEXTURE, UV).a);
}
