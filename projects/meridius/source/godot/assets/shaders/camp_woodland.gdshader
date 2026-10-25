shader_type canvas_item;
render_mode unshaded;

uniform sampler2D night_texture : source_color, filter_linear_mipmap;
uniform float night_mix : hint_range(0.0, 1.0) = 0.0;
uniform float elapsed = 0.0;
uniform float atmosphere_strength : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1,0)), f.x), mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}
float haze_band(vec2 uv, vec2 center, vec2 radius) {
	vec2 d = (uv - center) / radius;
	return exp(-dot(d,d) * 2.4);
}
// Smooth local vegetation envelopes. Bend increases up the trunk; the base is
// stationary. No global image wobble, repeated sprites or displaced buildings.
vec2 tree_wind(vec2 uv, vec2 root, float height, float width, float phase, float gust) {
	float h = clamp((root.y - uv.y) / height, 0.0, 1.2);
	vec2 q = (uv - root + vec2(0.0, height * .67)) / vec2(width, height * .76);
	float mask = 1.0 - smoothstep(.38, 1.0, dot(q,q));
	float bend = sin(elapsed * 1.12 + phase) * .55 + sin(elapsed * .49 + phase * .6) * .45;
	float rustle = sin(elapsed * 5.2 + uv.y * 190.0 + phase) * sin(uv.x * 260.0 + elapsed * 2.1);
	return vec2((bend * (2.5 + gust * 6.0) + rustle * .85) / 2752.0,
		(bend * .7 + rustle * .3) / 1536.0) * mask * h * h;
}
float camp_side(vec2 p, vec2 a, vec2 b) {
	vec2 edge = b - a;
	return step(0.0, edge.x * (p.y-a.y) - edge.y * (p.x-a.x));
}
float protected_camp(vec2 p) {
	return camp_side(p, vec2(.51,.14), vec2(.85,.46))
		* camp_side(p, vec2(.85,.46), vec2(.51,.84))
		* camp_side(p, vec2(.51,.84), vec2(.17,.48))
		* camp_side(p, vec2(.17,.48), vec2(.51,.14));
}
void fragment() {
	if (atmosphere_strength <= 0.0) {
		COLOR = vec4(mix(texture(TEXTURE, UV).rgb, texture(night_texture, UV).rgb, night_mix), 1.0);
	} else {
	float gust = .5 + .5 * sin(elapsed * .38 + sin(elapsed * .13));
	vec2 wind = tree_wind(UV, vec2(.150,.334), .292, .048, .3, gust)
		+ tree_wind(UV, vec2(.055,.525), .222, .037, 1.1, gust)
		+ tree_wind(UV, vec2(.036,.740), .250, .054, .8, gust)
		+ tree_wind(UV, vec2(.773,.927), .286, .047, 2.2, gust)
		+ tree_wind(UV, vec2(.835,.853), .266, .041, 1.8, gust)
		+ tree_wind(UV, vec2(.972,.740), .330, .050, 2.5, gust)
		+ tree_wind(UV, vec2(.907,.650), .235, .037, 2.0, gust)
		+ tree_wind(UV, vec2(.270,1.080), .265, .040, 1.0, gust)
		+ tree_wind(UV, vec2(.214,1.090), .215, .034, .5, gust);
	wind *= 1.0 - protected_camp(UV);
	vec2 sample_uv = clamp(UV + wind * atmosphere_strength, vec2(.0003), vec2(.9997));
	vec3 day = texture(TEXTURE, sample_uv).rgb;
	vec3 night = texture(night_texture, sample_uv).rgb;
	vec3 col = mix(day, night, night_mix);
	// Two advected layers curl at different scales. Narrow wisps follow the
	// existing woodland mist; the occupied enclosure remains clear.
	vec2 air = UV + vec2(0.0, sin(UV.x * 16.0 - elapsed * .22) * .008);
	float mask = haze_band(air, vec2(.17,.18), vec2(.26,.080))
		+ haze_band(air, vec2(.79,.085), vec2(.30,.070))
		+ haze_band(air, vec2(.94,.43), vec2(.12,.12))
		+ haze_band(air, vec2(.92,.88), vec2(.19,.14))
		+ haze_band(air, vec2(.05,.69), vec2(.10,.13));
	vec2 flow = vec2(-elapsed * .040, elapsed * .009);
	float curl = noise(air * vec2(11.0, 16.0) + flow * .40);
	float broad = noise(air * vec2(8.0, 28.0) + flow + vec2(curl * .8, curl * .5));
	float wisp = noise(air * vec2(19.0, 64.0) + flow * 1.65 + vec2(curl, broad));
	float vapor = smoothstep(.27,.78,broad * .65 + wisp * .35);
	float mist = min(mask, 1.0) * vapor * mix(.29,.34,night_mix) * atmosphere_strength;
	col = mix(col, mix(vec3(.79,.84,.77),vec3(.43,.57,.64),night_mix), mist);
	// Soft diagonal light in the upper woodland; open camp remains crisp.
	float shaft = pow(.5 + .5 * sin(UV.x * 38. + UV.y * 19. + .15 * sin(elapsed * .12)), 10.);
	float canopy = (1.0 - smoothstep(.10,.48,UV.y)) * (1.0 - smoothstep(.30,.70,UV.x));
	col += vec3(1.,.82,.44) * shaft * canopy * .045 * (1.0-night_mix) * atmosphere_strength;
	// Breathe only the warm pixels already painted inside the night tents.
	float warm = smoothstep(.08,.24,night.r-night.b) * smoothstep(.18,.45,night.r);
	float pulse = sin(elapsed * 1.7 + UV.x * 29.) * .012 + sin(elapsed * 3.1) * .005;
	col += vec3(1.,.55,.18) * warm * night_mix * pulse * atmosphere_strength;
	COLOR = vec4(col,1.0);
	}
}
