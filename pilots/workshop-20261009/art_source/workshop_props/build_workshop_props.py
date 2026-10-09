"""Build original editable medieval workshop props. Blender 4.3; metres; Z up; front -Y."""
import bpy, math, json, os, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path('/workspace/shared/foglight-town-pilot-20261009')
SRC=ROOT/'art_source/workshop_props'; OUT=ROOT/'assets/workshop_props'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for d in list(bpy.data.materials):bpy.data.materials.remove(d)
GROUPS={}; active=''
def group(name):
 global active
 active=name
 col=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(col);GROUPS[name]=col
 return col

def register(o,name,mat):
 o.name=name
 for col in list(o.users_collection):col.objects.unlink(o)
 GROUPS[active].objects.link(o)
 if mat:o.data.materials.append(mat)
 return o

def material(name,color,kind,metallic=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF')
 p.inputs['Metallic'].default_value=metallic;p.inputs['Roughness'].default_value=.55
 for slot,file,typ in [('Base Color',color,'COLOR'),('Roughness',kind+'_roughness','DATA')]:
  t=n.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(SRC/'textures'/f'{file}.png'),check_existing=True)
  if typ=='DATA':t.image.colorspace_settings.name='Non-Color'
  l.new(t.outputs['Color'],p.inputs[slot])
 t=n.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(SRC/'textures'/f'{kind}_normal.png'),check_existing=True);t.image.colorspace_settings.name='Non-Color'
 nm=n.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.28;l.new(t.outputs['Color'],nm.inputs['Color']);l.new(nm.outputs['Normal'],p.inputs['Normal'])
 return m
WOOD=material('Oak | oiled structural timber','wood_oak_color','wood')
OLD=material('Oak | old inner endgrain','wood_old_color','wood')
GREEN=material('Oak | faded olive work chest','wood_olive_color','wood')
IRON=material('Forged blue iron | satin scale','metal_iron_color','metal',.72)
EDGE=material('Machined iron | burnished collars','metal_edge_color','metal',.85)
BRASS=material('Warm brass | bearing bushings','metal_brass_color','metal',.78)

def bevel(o,width=.012,segments=2):
 mod=o.modifiers.new('Soft machined or handled edges','BEVEL');mod.width=width;mod.segments=segments
 mod.affect='EDGES'
 mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=40
 return o

def uv_box(o,dims):
 mesh=o.data;uv=mesh.uv_layers.new(name='Metric_grain_UV');long=max(range(3),key=lambda k:dims[k])
 for f in mesh.polygons:
  na=max(range(3),key=lambda k:abs(f.normal[k]));axes=[i for i in range(3) if i!=na]
  if long in axes:axes.remove(long);axes=[long]+axes
  for li in f.loop_indices:
   c=mesh.vertices[mesh.loops[li].vertex_index].co
   uv.data[li].uv=(c[axes[0]]/1.5+.37,c[axes[1]]/.35+.27)

def cube(name,loc,dims,mat=WOOD,bev=.01):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=register(bpy.context.object,name,mat)
 o.dimensions=dims;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);uv_box(o,dims)
 if bev:bevel(o,bev)
 return o

def beam(name,a,b,w,d=None,mat=WOOD,bev=.012):
 a=Vector(a);b=Vector(b);o=cube(name,(a+b)/2,(w,d or w,(b-a).length),mat,bev);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def cylinder(name,loc,r,depth,mat=IRON,axis=(0,1,0),verts=24,bev=.008):
 bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,end_fill_type='NGON',location=loc)
 o=register(bpy.context.object,name,mat);o.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler()
 for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
 if bev:bevel(o,bev)
 return o

def rod(name,a,b,r,mat=IRON,verts=16):
 a=Vector(a);b=Vector(b);return cylinder(name,(a+b)/2,r,(b-a).length,mat,b-a,verts,.004)

def ring(name,c,ro,ri,depth,mat=IRON,n=64):
 # Mesh annulus in XZ; two smooth radial surfaces and two flat front/rear faces.
 x,y,z=c;v=[]
 for yy in [-depth/2,depth/2]:
  for rr in [ro,ri]:
   for i in range(n):
    a=2*math.pi*i/n;v.append((x+rr*math.cos(a),y+yy,z+rr*math.sin(a)))
 fs=[]
 for i in range(n):
  j=(i+1)%n
  fs.extend([(i,j,n+j,n+i),(2*n+j,2*n+i,3*n+i,3*n+j),(j,i,2*n+i,2*n+j),(n+i,n+j,3*n+j,3*n+i)])
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(v,[],fs);mesh.update();o=bpy.data.objects.new(name,mesh);GROUPS[active].objects.link(o);o.data.materials.append(mat)
 uv=mesh.uv_layers.new(name='Metric_ring_UV')
 for p in mesh.polygons:
  p.use_smooth=p.index%4>=2
  for li in p.loop_indices:
   co=mesh.vertices[mesh.loops[li].vertex_index].co;uv.data[li].uv=((co.x-x)/1.5,(co.z-z)/.35)
 bevel(o,.009,2);return o

def bolt(name,loc,r=.045,mat=EDGE):return cylinder(name,loc,r,.033,mat,verts=6,bev=.003)

def spoke(name,c,r1,r2,angle,width,depth,mat=IRON):
 x,y,z=c
 return beam(name,(x+r1*math.cos(angle),y,z+r1*math.sin(angle)),(x+r2*math.cos(angle),y,z+r2*math.sin(angle)),width,depth,mat,.012)

def wood_wheel(name,c,r,depth=.1):
 ring(name+' oak felloe',c,r,r-.075,depth,WOOD,48)
 ring(name+' fitted iron tyre',c,r+.014,r-.008,depth+.018,IRON,48)
 cylinder(name+' hub',c,r*.21,depth+.18,OLD,verts=16)
 cylinder(name+' hub collar',(c[0],c[1]-depth/2-.105,c[2]),r*.15,.045,IRON,verts=16)
 for i in range(10):spoke(name+' tapered spoke '+str(i),c,r*.14,r-.045,2*math.pi*i/10,.043,.06,WOOD)
 bolt(name+' axle pin',(c[0],c[1]-depth/2-.14,c[2]),.041,EDGE)

# Left shed. Principal open flywheel, separate gear and two load-bearing bearing pedestals.
group('01_Flywheel_drive')
C=(-5.55,-1.25,1.38)
for x in [-6.45,-4.65]:cube('Machine oak sleeper',(x,-1.14,.18),(.3,2.6,.3),OLD,.025)
for y in [-2.15,-.2]:cube('Machine cast bed cross-member',(-5.55,y,.38),(2.25,.22,.18),IRON,.025)
ring('Flywheel outer cast rim',C,1.19,1.015,.21,IRON,80)
ring('Flywheel polished rolling edge',(C[0],C[1]-.115,C[2]),1.198,1.165,.035,EDGE,80)
for i in range(8):
 a=2*math.pi*i/8
 spoke('Flywheel web spoke %02d'%i,C,.2,1.05,a,.115,.13,IRON)
 bolt('Flywheel rim joint %02d'%i,(C[0]+1.10*math.cos(a),C[1]-.133,C[2]+1.10*math.sin(a)),.035)
cylinder('Main forged shaft',(-5.55,-1.10,1.38),.105,2.78,EDGE)
cylinder('Flywheel central hub',C,.245,.34,IRON)
cylinder('Flywheel hub bronze ring',(-5.55,-1.46,1.38),.155,.075,BRASS)
for y in [-2.10,-.10]:
 cube('Bearing pedestal upright',(-5.55,y,.79),(.44,.44,.75),IRON,.025)
 cube('Bearing foot flange',(-5.55,y,.45),(.7,.52,.11),IRON,.022)
 cylinder('Bearing pillow housing',(-5.55,y,1.34),.255,.30,IRON)
 ring('Bearing bronze bush',(-5.55,y-.165,1.38),.165,.11,.035,BRASS,32)
 for dx in [-.22,.22]:
  bolt('Bearing flange bolt',(-5.55+dx,y-.27,.5),.041)
# Separate smaller back gear; clean discrete teeth communicate mechanical purpose.
gc=(-5.55,-.74,1.38)
ring('Driven gear open ring',gc,.88,.725,.14,IRON,72)
for i in range(6):spoke('Driven gear spoke '+str(i),gc,.15,.74,math.tau*i/6,.08,.12,IRON)
for i in range(36):
 a=math.tau*i/36
 o=cube('Gear tooth %02d'%i,(gc[0]+.915*math.cos(a),gc[1],gc[2]+.915*math.sin(a)),(.102,.145,.11),EDGE,.008)
 o.rotation_euler[1]=-a
# Smaller meshing pinion beside wheel, with a connecting crank and articulated rod.
pc=(-4.30,-.74,1.1)
ring('Side pinion wheel',pc,.265,.155,.17,IRON,36)
for i in range(12):
 a=math.tau*i/12;o=cube('Pinion tooth '+str(i),(pc[0]+.29*math.cos(a),pc[1],pc[2]+.29*math.sin(a)),(.072,.17,.075),EDGE,.006);o.rotation_euler[1]=-a
cylinder('Side transmission shaft',(-4.30,-1.09,1.1),.075,.95,EDGE)
cube('Side shaft pillow block',(-4.30,-1.0,.78),(.31,.39,.53),IRON,.02)
cylinder('Hand crank offset boss',(-5.55,-2.56,1.38),.21,.09,IRON)
rod('Crank arm',(-5.55,-2.64,1.38),(-5.33,-2.64,1.12),.054,IRON)
cylinder('Crank swivel wrist',(-5.33,-2.66,1.12),.076,.12,BRASS)
rod('Connecting rod',(-5.33,-2.72,1.12),(-4.45,-2.72,.75),.033,EDGE)
cylinder('Connecting rod far eye',(-4.45,-2.72,.75),.075,.07,IRON)
rod('Lower linkage pivot brace',(-4.45,-2.55,.75),(-4.45,-1.05,.75),.065,IRON)
# A small functional oil cup on the forward bearing.
cylinder('Oil cup brass',(-5.55,-2.08,1.64),.064,.105,BRASS,(0,0,1),16)

# Two-wheeled timber handcart. Open plank body, separate rails, spokes and tyre.
group('02_Timber_handcart')
cx,cy=-4.55,-4.58
for i in range(5):cube('Cart bed floor board %02d'%i,(cx,cy+(i-2)*.18,.62),(1.54,.169,.072),WOOD,.014)
for yy in [cy-.49,cy+.49]:
 for z in [.80,1.00]:cube('Cart sideboard',(cx,yy,z),(1.62,.065,.17),WOOD,.01)
 for x in [cx-.73,cx+.73]:cube('Cart upright corner',(x,yy,.86),(.09,.09,.66),OLD,.014)
for x in [cx-.78,cx+.78]:
 for z in [.80,1.0]:cube('Cart end board',(x,cy,z),(.065,.91,.17),WOOD,.01)
for y in [cy-.36,cy+.36]:
 beam('Cart underframe',(cx-.85,y,.50),(cx+1.80,y,.69),.092,.10,OLD,.015)
 cylinder('Smooth cart handle grip',(cx+1.68,y,.68),.065,.27,WOOD,(1,0,.07),16)
rod('Cart iron axle',(cx-.23,cy-.68,.46),(cx-.23,cy+.68,.46),.06,IRON)
for y in [cy-.64,cy+.64]:wood_wheel('Cart wheel '+str(y),(cx-.23,y,.46),.45)
for y in [cy-.35,cy+.35]:beam('Cart resting leg',(cx+.62,y,.08),(cx+.55,y,.54),.09,.09,OLD)
for y in [cy-.525,cy+.525]:
 for x in [cx-.68,cx+.68]:
  cube('Cart vertical iron strap',(x,y,.85),(.055,.016,.51),IRON,.005)
  for z in [.66,1.04]:bolt('Cart strap rivet',(x,y-.012,z),.022)
# Original cargo: one short rolled timber and two spare iron hoops, kept low.
for y in [cy-.17,cy+.05]:cube('Cart spare short timber',(cx-.05,y,.77),(.89,.15,.12),OLD,.008)

# Under-awning carpenter's / fitter's bench and separate low stool.
group('03_Right_workbench')
x,y=1.95,-3.26
for i in range(4):cube('Workbench thick top plank',(x,y+(i-1.5)*.20,1.04),(2.2,.187,.095),WOOD,.015)
for xx in [x-.84,x+.84]:
 for yy in [y-.28,y+.28]:beam('Workbench splayed leg',(xx,yy,.10),(xx*.99+.0195,yy,1.01),.12,.12,OLD,.015)
 cube('Workbench side stretcher',(xx,y,.30),(.11,.70,.11),OLD,.012)
for yy in [y-.28,y+.28]:cube('Workbench long stretcher',(x,yy,.34),(1.8,.075,.10),OLD,.012)
for i in range(3):cube('Workbench lower shelf',(x,y+(i-1)*.17,.41),(1.68,.158,.052),OLD,.009)
# Bench vice with stationary jaw, sliding jaw, screw and handle.
cube('Bench vice mounting base',(x-.65,y-.22,1.13),(.31,.34,.075),IRON,.015)
cube('Bench vice fixed jaw',(x-.65,y-.16,1.24),(.26,.065,.21),IRON,.015)
cube('Bench vice sliding jaw',(x-.65,y-.39,1.24),(.26,.065,.21),IRON,.015)
cylinder('Bench vice lead screw',(x-.65,y-.43,1.18),.042,.44,EDGE,verts=20)
cylinder('Bench vice handle boss',(x-.65,y-.64,1.18),.059,.075,IRON)
rod('Bench vice sliding handle',(x-.80,y-.69,1.18),(x-.50,y-.69,1.18),.017,EDGE,12)
# Hammer lies across a working plank, no random clutter.
beam('Joiner hammer ash handle',(x+.04,y-.21,1.13),(x+.64,y-.05,1.13),.039,.048,WOOD,.008)
cube('Joiner hammer forged head',(x+.06,y-.21,1.16),(.10,.22,.095),EDGE,.015)
# Two chisels, a plane, short task board.
cube('Work in progress board',(x+.63,y+.10,1.13),(.49,.29,.065),OLD,.009)
for i in range(2):
 cylinder('Chisel wood grip',(x+.18+i*.11,y+.12,1.14),.027,.15,WOOD,(0,1,0),12)
 cube('Chisel flat blade',(x+.18+i*.11,y-.015,1.14),(.024,.16,.008),EDGE,.003)
cube('Smoothing plane oak stock',(x+.76,y-.20,1.145),(.30,.10,.065),WOOD,.012)
o=cube('Smoothing plane iron',(x+.78,y-.20,1.21),(.047,.075,.06),IRON,.005);o.rotation_euler[1]=-.4
# Coiled/loop tong as two hooked rods.
for dx in [-.018,.018]:rod('Blacksmith tong',(x-.16+dx,y+.20,1.12),(x-.05+dx,y+.41,1.12),.012,IRON,10)

group('04_Low_joiner_stool')
sx,sy=2.12,-4.04
for i in range(2):cube('Stool seat',(sx+(i-.5)*.24,sy,.56),(.226,.38,.071),WOOD,.018)
for xx in [-.17,.17]:
 for yy in [-.12,.12]:beam('Stool splayed leg',(sx+xx*1.25,sy+yy*1.25,.045),(sx+xx,sy+yy,.53),.054,.06,OLD,.007)
for yy in [-.13,.13]:rod('Stool foot rung',(sx-.18,sy+yy,.23),(sx+.18,sy+yy,.23),.021,WOOD,12)

# Six distinct storage pieces, restrained deliberate placement.
def crate(name,loc,dims=(.78,.67,.74),mat=WOOD):
 group(name);x,y,z=loc;w,d,h=dims
 for yy in [y-d/2+.032,y+d/2-.032]:
  for i in range(4):cube(name+' face plank',(x-w/2+(i+.5)*w/4,yy,z+h/2),(w/4-.01,.058,h-.06),mat,.008)
 for xx in [x-w/2+.032,x+w/2-.032]:
  for i in range(3):cube(name+' side plank',(xx,y-d/2+(i+.5)*d/3,z+h/2),(.058,d/3-.01,h-.06),mat,.008)
 for i in range(4):cube(name+' lid',(x-w/2+(i+.5)*w/4,y,z+h),(w/4-.009,d,.049),mat,.008)
 for yy in [y-d/2-.007,y+d/2+.007]:
  for zz in [z+.07,z+h-.07]:cube(name+' frame horizontal',(x,yy,zz),(w+.03,.054,.08),OLD,.009)
  for xx in [x-w/2+.055,x+w/2-.055]:cube(name+' frame upright',(xx,yy,z+h/2),(.082,.061,h+.035),WOOD,.009)
  beam(name+' diagonal brace',(x-w/2+.08,yy-.018,z+.12),(x+w/2-.08,yy-.018,z+h-.12),.066,.051,WOOD,.006)
 for xx in [x-w/2+.08,x+w/2-.08]:
  for zz in [z+.08,z+h-.08]:bolt(name+' peg',(xx,y-d/2-.044,zz),.018,IRON)

def barrel(name,loc,r=.36,h=.86):
 group(name);x,y,z=loc;n=16
 # Each stave is an editable bent solid prism, with real profile and small joints.
 levels=[0,.07,.23,.5,.77,.93,1];profile=[.86,.90,.97,1,.97,.90,.86]
 for i in range(n):
  a0=math.tau*(i+.016)/n;a1=math.tau*(i+.984)/n;verts=[]
  for zz,rr in zip(levels,profile):
   for rad,aa in [(r*rr,a0),(r*rr,a1),(r*rr-.045,a1),(r*rr-.045,a0)]:verts.append((x+rad*math.cos(aa),y+rad*math.sin(aa),z+zz*h))
  faces=[(3,2,1,0),(24,25,26,27)]
  for k in range(6):
   for j in range(4):faces.append((k*4+j,k*4+(j+1)%4,(k+1)*4+(j+1)%4,(k+1)*4+j))
  me=bpy.data.meshes.new(name+' stave');me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name+' oak stave %02d'%i,me);GROUPS[active].objects.link(o);me.materials.append(WOOD if i%3 else OLD)
  uv=me.uv_layers.new(name='Stave_metric_UV')
  for p in me.polygons:
   for li in p.loop_indices:
    co=me.vertices[me.loops[li].vertex_index].co;ang=math.atan2(co.y-y,co.x-x);uv.data[li].uv=((co.z-z)/1.5,ang*r/.35)
  bevel(o,.006,1)
 # Horizontal hoops use the same annulus function rotated from XZ into XY.
 for fr in [.115,.30,.70,.885]:
  rr=r*(.9+.10*math.sin(math.pi*fr))+.011
  o=ring(name+' riveted iron hoop',(0,0,0),rr+.015,rr-.015,.048,IRON,48);o.rotation_euler[0]=math.pi/2;o.location=(x,y,z+h*fr)
  bolt(name+' hoop rivet',(x,y-rr-.016,z+h*fr),.018)
 cylinder(name+' recessed lid',(x,y,z+h-.012),r*.846,.035,OLD,(0,0,1),32,.006)
 for i in [-1,1]:cube(name+' lid cross batten',(x,y+i*r*.30,z+h+.013),(r*1.46,.056,.022),WOOD,.004)
crate('05_Olive_work_chest',(-3.25,-3.52,.06),(.92,.68,.78),GREEN)
barrel('06_Door_barrel',(-1.78,-3.07,.05),.33,.86)
crate('07_Outer_supply_crate',(4.20,-3.09,.04),(.85,.73,.76))
crate('08_Tall_side_crate',(4.73,-2.25,.04),(.67,.63,.97),OLD)
barrel('09_Side_barrel',(4.28,-1.62,.045),.31,.83)
barrel('10_Small_work_keg',(-2.76,-2.98,.05),.23,.57)

# Source is fully editable, with named component collections.
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene.world.color=(.22,.26,.31)
for image in bpy.data.images:
 if image.source=='FILE':image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'workshop_props.blend'))
# Export copies merged by assembly, so engine scene remains inexpensive and independently placeable.
all_originals=[o for col in GROUPS.values() for o in col.objects]
exports=[];counts={}
for name,col in GROUPS.items():
 copies=[]
 for original in list(col.objects):
  if original.type!='MESH':continue
  ob=original.copy();ob.data=original.data.copy();scene.collection.objects.link(ob)
  bpy.context.view_layer.objects.active=ob;ob.select_set(True)
  for mod in list(ob.modifiers):
   try:bpy.ops.object.modifier_apply(modifier=mod.name)
   except Exception:pass
  copies.append(ob);ob.select_set(False)
 bpy.ops.object.select_all(action='DESELECT')
 for o in copies:o.select_set(True)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();ob=bpy.context.object;ob.name=name
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 tri=ob.modifiers.new('Export triangulation for exact normal tangents','TRIANGULATE');tri.keep_custom_normals=True;bpy.ops.object.modifier_apply(modifier=tri.name)
 ob.data.calc_loop_triangles();counts[name]={'source_components':len(col.objects),'vertices':len(ob.data.vertices),'triangles':len(ob.data.loop_triangles)};exports.append(ob)
bpy.ops.object.select_all(action='DESELECT')
for ob in exports:ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'workshop_props.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_materials='EXPORT',export_texcoords=True,export_normals=True,export_tangents=True)
# Asset-only preview. This is not claimed as final engine QA.
for ob in all_originals:ob.hide_render=True
for ob in exports:ob.select_set(False)
# Move lighting/camera into temporary non-export preview group.
group('QA_preview_only')
floor=cube('preview ground',(-1,-1.5,-.07),(16,11,.1),OLD,.0)
# floor neutral shader
fm=bpy.data.materials.new('Preview neutral sand');fm.diffuse_color=(.26,.235,.18,1);floor.data.materials.clear();floor.data.materials.append(fm)
bpy.ops.object.light_add(type='AREA',location=(-3,-5,10));light=bpy.context.object;light.data.energy=1700;light.data.shape='DISK';light.data.size=7
bpy.ops.object.light_add(type='AREA',location=(3,4,7));light=bpy.context.object;light.data.energy=1200;light.data.size=8
bpy.ops.object.camera_add(location=(8,-17,11));cam=bpy.context.object;cam.rotation_euler=(Vector((-1.25,-2,1))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=15.2;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=False
scene.render.resolution_x=1400;scene.render.resolution_y=850;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(SRC/'props_overview.png')
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
bpy.ops.render.render(write_still=True)
cam.location=(-1.8,-9.4,5.5);cam.rotation_euler=(Vector((-5.4,-1.1,1.2))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=4.6
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.filepath=str(SRC/'flywheel_detail.png');bpy.ops.render.render(write_still=True)
summary={'asset':'workshop_props.glb','units':'metres','source_coordinate_system':'Blender Z up; facade -Y','engine_glb':'glTF Y up; exported automatic Blender conversion','material_contract':'Original wood and forged metal maps, metric grain UVs; no baked AO or external textures','materials':6,'assemblies':counts,'total_triangles':sum(c['triangles'] for c in counts.values()),'source_component_count':len(all_originals),'preview_warning':'Blender preview only. Parent performs Godot native-frame validation.','license':'Original authored procedural geometry and textures for this project; no third-party assets.'}
summary['sha256_glb']=hashlib.sha256((OUT/'workshop_props.glb').read_bytes()).hexdigest()
(SRC/'asset_stats.json').write_text(json.dumps(summary,indent=2))
print('PROP_ASSET_READY '+json.dumps(summary))
