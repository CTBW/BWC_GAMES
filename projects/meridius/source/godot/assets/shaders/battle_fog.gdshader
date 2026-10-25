shader_type canvas_item;
render_mode unshaded;
uniform sampler2D sight_map : filter_linear, repeat_disable;
uniform sampler2D old_sight_map : filter_linear, repeat_disable;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform vec2 map_size;
uniform vec2 camera;
uniform vec2 view_size;
uniform float zoom = 1.0;
uniform float clock = 0.0;
uniform float blend = 1.0;
uniform sampler2D fog_grain : source_color, filter_nearest, repeat_enable;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
vec2 mask_at(vec2 uv) {
    if (any(lessThan(uv,vec2(0))) || any(greaterThan(uv,vec2(1)))) return vec2(0);
    return mix(texture(old_sight_map,uv).rg,texture(sight_map,uv).rg,blend);
}
vec3 grain_patch(vec2 pixel, vec2 id) {
    float angle=hash(id+17.3)*6.2831853;
    mat2 rotation=mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)));
    vec2 offset=vec2(hash(id+41.7),hash(id-12.8))*vec2(905.0,563.0);
    return texture(fog_grain,(rotation*pixel+offset)/vec2(905.0,563.0)).rgb;
}
vec3 irregular_grain(vec2 pixel) {
    // Overlapping, independently rotated source patches: no repeated wallpaper tiles.
    vec2 patch=pixel/370.0;
    vec2 id=floor(patch), f=fract(patch);
    f=f*f*(3.0-2.0*f);
    return mix(mix(grain_patch(pixel,id),grain_patch(pixel,id+vec2(1,0)),f.x),
        mix(grain_patch(pixel,id+vec2(0,1)),grain_patch(pixel,id+vec2(1,1)),f.x),f.y);
}
void fragment() {
    vec2 world = (UV*view_size-view_size*0.5)/zoom+camera;
    float diff=world.x/64.0;
    float sum=world.y/32.0;
    // Height-aware inverse projection; visual edge softness hides plateau discontinuities.
    for(int i=0;i<6;i++) {
        vec2 cell=vec2(sum+diff,sum-diff)*0.5;
        float h=texture(height_map,(cell+0.5)/map_size).r;
        sum=mix(sum,(world.y+h*26.0)/32.0,0.65);
    }
    vec2 cell=vec2(sum+diff,sum-diff)*0.5;
    vec2 uv=(cell+0.5)/map_size;
    vec2 d=vec2(0.42)/map_size;
    vec2 m=mask_at(uv)*0.4;
    m+=(mask_at(uv+vec2(d.x,0))+mask_at(uv-vec2(d.x,0))+mask_at(uv+vec2(0,d.y))+mask_at(uv-vec2(0,d.y)))*0.15;
    float clear=smoothstep(0.08,0.84,m.r);
    float known=smoothstep(0.04,0.85,m.g);
    float cloud=noise(world/260.0+vec2(clock*0.014,-clock*0.009));
    cloud=cloud*0.7+noise(world/110.0-vec2(clock*0.018))*0.3;
    vec3 tint=irregular_grain(world)*1.35;
    tint+=vec3(0.002,0.003,0.007)*known;
    float alpha=(1.0-clear)*mix(1.0,0.64,known);
    alpha+= (1.0-clear)*known*(cloud-0.5)*0.025;
    COLOR=vec4(tint,alpha);
}
