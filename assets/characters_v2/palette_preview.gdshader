shader_type canvas_item;
#include "res://assets/characters_v2/palette_shared.gdshaderinc"
uniform int coat_color : hint_range(0,3)=0;
uniform sampler2D top_mask : filter_nearest;
uniform bool recolor_enabled=true;
uniform bool use_top_mask=true;
varying vec4 vertex_tint;
void vertex(){vertex_tint=COLOR;}
void fragment(){
 vec4 c=texture(TEXTURE,UV);
 if(recolor_enabled && use_top_mask && coat_color>0 && texture(top_mask,UV).a>.5){
  c.rgb=recolor_sprite_srgb(c.rgb,coat_color);
 }
 COLOR=c*vertex_tint;
}
