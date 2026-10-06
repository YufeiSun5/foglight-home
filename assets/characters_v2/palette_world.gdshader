shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_disabled;
#include "res://assets/characters_v2/palette_shared.gdshaderinc"
uniform sampler2D character_texture : source_color, filter_nearest;
uniform sampler2D top_mask : filter_nearest;
uniform int coat_color : hint_range(0,3)=0;
uniform bool recolor_enabled=true;
uniform bool billboard_enabled=true;
// API retained. Default0 prevents additive light washing the painted sprite out.
uniform float minimum_light : hint_range(0.,1.)=0.;
void vertex(){
 if(billboard_enabled){
  vec3 scale=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
  vec3 up=vec3(0.,1.,0.);
  vec3 face=vec3(INV_VIEW_MATRIX[2].x,0.,INV_VIEW_MATRIX[2].z);
  face=length(face)>.0001?normalize(face):vec3(0.,0.,1.);
  vec3 right=normalize(cross(up,face));
  MODELVIEW_MATRIX=VIEW_MATRIX*mat4(vec4(right*scale.x,0.),vec4(up*scale.y,0.),vec4(face*scale.z,0.),MODEL_MATRIX[3]);
  MODELVIEW_NORMAL_MATRIX=mat3(MODELVIEW_MATRIX);
 }
}
void fragment(){
 vec4 c=texture(character_texture,UV);
 if(recolor_enabled && coat_color>0 && texture(top_mask,UV).a>.5){
  c.rgb=sprite_to_linear(recolor_sprite_srgb(sprite_to_srgb(c.rgb),coat_color));
 }
 ALBEDO=c.rgb;
 EMISSION=c.rgb*minimum_light;
 ALPHA=c.a;
 ALPHA_SCISSOR_THRESHOLD=.5;
}
