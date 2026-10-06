shader_type canvas_item;
// Shared coat_color contract: 0 blue, 1 indigo, 2 verdigris, 3 warm ivory.
// Source-blue range only; skin, hair, leather and gold stay unchanged.
uniform int coat_color : hint_range(0, 3) = 0;
uniform bool recolor_enabled = true;
// Optional exact mask for pixel-avatar wardrobe preview. Use same full atlas as TEXTURE.
uniform sampler2D top_mask : filter_nearest;
uniform bool use_top_mask = false;
varying vec4 vertex_tint;
void vertex(){vertex_tint=COLOR;}
vec3 ramp(float t, int id) {
 vec3 dark = vec3(0.161,0.216,0.278);
 vec3 mid = vec3(0.380,0.533,0.616);
 vec3 light = vec3(0.694,0.776,0.788);
 if(id==1){dark=vec3(.125,.149,.2);mid=vec3(.337,.392,.490);light=vec3(.647,.694,.729);}
 if(id==2){dark=vec3(.149,.231,.212);mid=vec3(.471,.592,.514);light=vec3(.808,.827,.702);}
 if(id==3){dark=vec3(.408,.369,.333);mid=vec3(.816,.765,.651);light=vec3(1.,.961,.875);}
 return t<.5 ? mix(dark,mid,t*2.) : mix(mid,light,(t-.5)*2.);
}
void fragment(){
 vec4 c=texture(TEXTURE,UV);
 if(recolor_enabled && coat_color>0){
  // Hue range approximately 185–230 degrees; saturation ≥0.075.
  float d=max(c.b,c.g)-c.r;
  float blue=smoothstep(.018,.055,d) * smoothstep(-.02,.016,c.b-c.g);
  float chroma=max(max(c.r,c.g),c.b)-min(min(c.r,c.g),c.b);
  blue*=smoothstep(.025,.075,chroma);
  if(use_top_mask){blue=step(.5,texture(top_mask,UV).a);}
  // Luminance-indexed ramp preserves fabric shading without a source-hue ratio
  // turning warm ivory cloth orange. Gold/skin remain outside the blue mask.
  float l=dot(c.rgb,vec3(.2126,.7152,.0722));
  float t=clamp((l-.21)/.56,0.,1.);
  c.rgb=mix(c.rgb,ramp(t,coat_color),blue);
 }
 COLOR=c*vertex_tint;
}
