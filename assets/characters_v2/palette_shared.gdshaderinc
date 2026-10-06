// Shared sprite-only color contract. sRGB ramps measured on v2 blue-cloth masks.
// 0 original blue, 1 deep indigo, 2 verdigris, 3 warm ivory.
vec3 source_ramp(float t){
 vec3 a=vec3(28.,37.,70.)/255.;
 vec3 b=vec3(92.,109.,156.)/255.;
 vec3 c=vec3(128.,148.,192.)/255.;
 return t<.5 ? mix(a,b,t*2.) : mix(b,c,(t-.5)*2.);
}
vec3 target_ramp(float t,int id){
 if(id==0){return source_ramp(t);}
 vec3 a=vec3(32.,38.,51.)/255.;
 vec3 b=vec3(86.,100.,125.)/255.;
 vec3 c=vec3(165.,177.,186.)/255.;
 if(id==2){a=vec3(38.,59.,54.)/255.;b=vec3(120.,151.,131.)/255.;c=vec3(206.,211.,179.)/255.;}
 if(id==3){a=vec3(104.,94.,85.)/255.;b=vec3(208.,195.,166.)/255.;c=vec3(255.,245.,223.)/255.;}
 return t<.5 ? mix(a,b,t*2.) : mix(b,c,(t-.5)*2.);
}
vec3 recolor_sprite_srgb(vec3 s,int id){
 float l=dot(s,vec3(.2126,.7152,.0722));
 float t=l<.426 ? .5*(l-.143)/(.426-.143) : .5+.5*(l-.426)/(.576-.426);
 t=clamp(t,0.,1.);
 return clamp(s*target_ramp(t,id)/max(source_ramp(t),vec3(.015)),vec3(0.),vec3(1.));
}
vec3 sprite_to_linear(vec3 s){return mix(s/12.92,pow((s+.055)/1.055,vec3(2.4)),step(vec3(.04045),s));}
vec3 sprite_to_srgb(vec3 c){return mix(c*12.92,1.055*pow(max(c,vec3(0.)),vec3(1./2.4))-.055,step(vec3(.0031308),c));}
