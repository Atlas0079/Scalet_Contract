shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D enamel_texture : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 paint_position;
varying vec3 paint_normal;
void vertex() {
    paint_position = VERTEX * 1.15;
    paint_normal = NORMAL;
}
void fragment() {
    vec3 weights = pow(abs(normalize(paint_normal)),vec3(6.0));
    weights /= max(weights.x+weights.y+weights.z,.0001);
    vec3 grain = texture(enamel_texture,paint_position.yz).rgb*weights.x;
    grain += texture(enamel_texture,paint_position.xz).rgb*weights.y;
    grain += texture(enamel_texture,paint_position.xy).rgb*weights.z;
    float variation = (dot(grain,vec3(.2126,.7152,.0722))-.55)*.075;
    ALBEDO = vec3(.17,.19,.195)+vec3(variation);
    METALLIC = .16;
    ROUGHNESS = clamp(.60+variation*.4,.55,.65);
    CLEARCOAT = .12;
    CLEARCOAT_ROUGHNESS = .4;
}
