shader_type spatial;
render_mode cull_disabled;
uniform sampler2D paint_color: source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D steel_color: source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D steel_arm: filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D steel_normal: hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 work_position;
void vertex() { work_position=VERTEX; }
float hash21(vec2 p) { p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y); }
float noise2(vec2 p) {
 vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
float corrosion(vec3 color) {
 return smoothstep(.010,.045,color.r-color.g)*smoothstep(.003,.025,color.g-color.b);
}
float paint_height(vec3 color) {
 float rusty=corrosion(color);
 float primer=smoothstep(.18,.34,dot(color,vec3(.2126,.7152,.0722)));
 return mix(1.0,.32,rusty)-primer*.14;
}
void fragment() {
 vec2 position=work_position.xz;
 // One detailed image sample preserves flaked contours. Continuous warping
 // and physical-space aging vary the material without a focus-state switch.
 vec2 warp=.040*vec2(noise2(UV*2.3+vec2(1.2,7.4)),noise2(UV*2.7+vec2(8.9,2.1)));
 vec2 paint_uv=(UV+warp)/.22;
 vec3 paint=texture(paint_color,paint_uv).rgb;
 float painted_rust=corrosion(paint);
 float large=noise2(position*3.7+vec2(7.1,12.4));
 float broken=noise2(position*22.0);
 float distance_edge=min(1.05-abs(position.x),.6595-abs(position.y));
 float rim=1.0-smoothstep(.005,.085,distance_edge);
 float local_patch=smoothstep(.60,.83,large+broken*.16);
 float edge_patch=rim*smoothstep(.27,.60,large+broken*.22);
 vec2 phone_zone=(position-vec2(-.32,.46))/vec2(.12,.16);
 float wiped=exp(-dot(phone_zone,phone_zone))*.40;
 float extra_rust=max(local_patch*.65,edge_patch*.85)*(1.0-wiped);
 vec2 rust_uv=UV/.55;
 vec3 rust=texture(steel_color,rust_uv).rgb*.90;
 vec3 arm=texture(steel_arm,rust_uv).rgb;
 float primer=smoothstep(.18,.34,dot(paint,vec3(.2126,.7152,.0722)))*(1.0-painted_rust);
 float grey=1.0-smoothstep(.012,.05,max(paint.r,max(paint.g,paint.b))-min(paint.r,min(paint.g,paint.b)));
 float bare=grey*(1.0-primer)*(1.0-painted_rust);
 // Original 4K photographic grain keeps close-ups detailed beneath paint.
 vec3 micro=texture(steel_normal,UV/.16).rgb*2.0-1.0;
 vec3 color=paint*(.86+.10*large);
 color*=1.0-.12*noise2(position*10.0);
 ALBEDO=mix(color,rust,extra_rust);
 ROUGHNESS=mix(mix(.78,.55,bare),.91,painted_rust);
 ROUGHNESS=mix(ROUGHNESS,max(.87,arm.g),extra_rust);
 METALLIC=mix(mix(.08,.65,bare),.015,painted_rust);
 METALLIC=mix(METALLIC,arm.b*.20,extra_rust);
 AO=mix(1.0,arm.r,extra_rust*.45);
 // Approximate peeling relief from material classes, not baked lighting.
 float texel=1.0/float(textureSize(paint_color,0).x);
 float height=paint_height(paint);
 vec2 gradient=vec2(paint_height(texture(paint_color,paint_uv+vec2(texel,0)).rgb)-height,
                    paint_height(texture(paint_color,paint_uv+vec2(0,texel)).rgb)-height);
 vec2 relief=-gradient*.65+micro.xy*.06;
 vec3 rust_normal=texture(steel_normal,rust_uv).rgb*2.0-1.0;
 relief=mix(relief,rust_normal.xy*.26,extra_rust);
 NORMAL_MAP=normalize(vec3(relief,1.0))*.5+.5;
 NORMAL_MAP_DEPTH=1.0;
}
