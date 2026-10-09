shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
void fragment(){
 vec4 tex=texture(atlas,UV*vec2(0.5,0.25));
 if(tex.a<0.5) discard;
 ALBEDO=tex.rgb;
 ROUGHNESS=0.96;
 SPECULAR=0.08;
}
