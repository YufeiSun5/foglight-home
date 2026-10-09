"""Immutable geometry-only multiview control. Run in background Blender, never the game scene."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'control_renders'; OUT.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for db in bpy.data.materials: bpy.data.materials.remove(db)
COLORS={'plaster':(.73,.65,.48,1),'roof':(.08,.38,.41,1),'wood':(.23,.12,.065,1),'stone':(.39,.41,.42,1),'glass':(.14,.42,.56,1),'iron':(.075,.085,.095,1)}
M={}
for n,c in COLORS.items():
 m=bpy.data.materials.new(n); m.diffuse_color=c; M[n]=m

def finish(obj,n,mat):
 obj.name=n; obj.data.materials.append(M[mat]); obj['purpose']='Editable geometric control, not Tripo result or game asset'; return obj

def box(n,loc,dims,mat):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.dimensions=dims; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); return finish(o,n,mat)

def mesh(n,verts,faces,mat):
 d=bpy.data.meshes.new(n);d.from_pydata(verts,[],faces);d.update();o=bpy.data.objects.new(n,d);bpy.context.collection.objects.link(o);return finish(o,n,mat)

def roofz(y):return 3.55+2.0*(1-(abs(y)/2.45)**1.7)

def profile_prism(n,profile,xlo,xhi,mat):
 N=len(profile); vs=[(x,y,z) for x in [xlo,xhi] for y,z in profile];fs=[tuple(range(N-1,-1,-1)),tuple(range(N,N*2))];fs += [(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)];return mesh(n,vs,fs,mat)
ys=[-2.1+i*4.2/84 for i in range(85)]
body=profile_prism('MAIN_WALL_ENVELOPE', [(-2.1,.45),(2.1,.45)]+[(y,roofz(y)-.12) for y in ys[::-1]],-3,3,'plaster')
foundation=box('FOUNDATION',(0,0,.225),(6.2,4.4,.45),'stone')
ysr=[-2.45+i*4.9/98 for i in range(99)]
roof=profile_prism('MAIN_CURVED_ROOF',[(y,roofz(y)) for y in ysr]+[(y,roofz(y)-.12) for y in ysr[::-1]],-3.35,3.35,'roof')
roof['cross_section']='z=3.55+2*(1-(abs(y)/2.45)^1.7)';roof['ridge_axis']='X';roof['ridge_z']=5.55
# Very sparse structure: its job is to show mass, not imitate concept textures.
for x in [-3,-1.6,.4,3]:
 for y in [-2.105,2.105]:
  if x==.4 and y>0:
   box('BACK_POST_BELOW_W2',(x,y,.83),(.16,.16,.76),'wood')
   box('BACK_POST_ABOVE_W2',(x,y,2.995),(.16,.16,1.11),'wood')
  else:box(f'POST_{x}_{y}',(x,y,2.0),(.16,.16,3.10),'wood')
for y in [-2.105,2.105]:
 for z in [.53,3.46]:box(f'LONG_BEAM_{y}_{z}',(0,y,z),(6.1,.18,.17),'wood')
for x in [-3.01,3.01]:
 for y in [0]:box(f'GABLE_CENTER_{x}',(x,y,2.97),(.17,.17,5.04),'wood')
 box(f'GABLE_TIE_{x}',(x,0,3.46),(.18,4.22,.17),'wood')
# Opening cutters followed by distinct editable door/glass panels. Exact design opening extents retained.
def cut(n,loc,dims):
 cutter=box(n+'_CUTTER',loc,dims,'iron'); mod=body.modifiers.new(n+'_OPENING','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
 bpy.context.view_layer.objects.active=body;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)
cut('D1',(-.9,-2.06,1.65),(1.15,.5,2.4))
door=box('D1_DOOR',(-.9,-2.03,1.65),(1.15,.10,2.4),'wood');door['opening']='FRONT only, x=-0.9, width1.15, z.45..2.85'
for x in [-1.535,-.265]:box('D1_JAMB', (x,-2.13,1.65),(.12,.13,2.52),'wood')
box('D1_LINTEL',(-.9,-2.13,2.91),(1.39,.13,.12),'wood')
for z in [1.0,2.35]:box('D1_HINGE',(-1.00,-2.10,z),(.8,.035,.065),'iron')

def window(n,x,y,z,w=.85,h=1.05,cutwall=True):
 if cutwall:cut(n,(x,y,z),(w,.5,h))
 box(n+'_GLASS',(x,y,z),(w,.045,h),'glass')
 for xx in [x-w/2-.045,x+w/2+.045]:box(n+'_JAMB',(xx,y-.01 if y<0 else y+.01,z),(.09,.10,h+.18),'wood')
 for zz in [z-h/2-.045,z+h/2+.045]:box(n+'_RAIL',(x,y,zz),(w+.18,.10,.09),'wood')
 box(n+'_MULLION',(x,y-.035 if y<0 else y+.035,z),(.045,.055,h),'wood')
 box(n+'_TRANSOM',(x,y-.035 if y<0 else y+.035,z),(w,.055,.045),'wood')
window('W1_FRONT',1.65,-2.08,1.825)
window('W2_BACK_INFERRED',0,2.08,1.825)
# Dormer front plane, pentagonal extruded volume. Roof below intersects naturally; no independent side shed.
xs=[.125,.65,1.175]; p=[(.125,4.20),(1.175,4.20),(1.175,4.99),(.65,5.34),(.125,4.99)]
vs=[(x,y,z) for y in [-1.95,-.8] for x,z in p]; N=len(p)
dorm=mesh('DW1_DORMER_BODY',vs,[tuple(range(4,-1,-1)),tuple(range(5,10))]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)],'plaster')
# Distinct small double-pitch roof, stopping at same prescribed ridge maximum5.40.
for side,xa,xb,za,zb in [('L',.055,.65,5.00,5.40),('R',.65,1.245,5.40,5.00)]:
 vs=[(xa,-2.02,za),(xb,-2.02,zb),(xb,-.76,zb),(xa,-.76,za)]
 o=mesh('DW1_ROOF_'+side,vs,[(0,1,2,3)],'roof');mod=o.modifiers.new('Roof thickness','SOLIDIFY');mod.thickness=.07;mod.offset=-1
window('DW1',.65,-1.977,4.65,.60,.65,False)
# Chimney exactly one, on rear roof slope.
box('C1_FLASHING',(-1.65,.45,5.38),(.78,.78,.27),'stone')
shaft=box('C1_STONE_SHAFT',(-1.65,.45,(5.10+6.70)/2),(.60,.60,1.60),'stone')
box('C1_CAP_BASE',(-1.65,.45,6.72),(.76,.76,.10),'iron')
for dx in [-.27,.27]:
 for dy in [-.27,.27]:box('C1_OPEN_CAP_POST',(-1.65+dx,.45+dy,6.90),(.07,.07,.32),'iron')
box('C1_CAP_TOP',(-1.65,.45,7.105),(.80,.80,.09),'iron')
box('D1_STEP_LOWER',(-.9,-2.55,.1125),(1.55,.70,.225),'stone')
box('D1_STEP_UPPER',(-.9,-2.375,.3375),(1.55,.35,.225),'stone')
# Five cameras, one shared immutable model, identical scale and orthographic projection.
scene=bpy.context.scene
scene.render.engine='BLENDER_WORKBENCH'
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.display.shading.light='STUDIO';scene.display.shading.studiolight_rotate_z=.5
scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True
scene.display.shading.show_cavity=True;scene.display.shading.cavity_type='BOTH'
scene.display.shading.show_specular_highlight=False;scene.display.shading.show_object_outline=True
scene.display.shading.background_type='WORLD';scene.world.color=(.82,.82,.82)
scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast'
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
cams={}
for name,pos,target in [('FRONT',(0,-20,3.575),(0,0,3.575)),('BACK',(0,20,3.575),(0,0,3.575)),('LEFT',(-20,0,3.575),(0,0,3.575)),('RIGHT',(20,0,3.575),(0,0,3.575)),('TOP',(0,0,20),(0,0,0))]:
 d=bpy.data.cameras.new('ORTHO_'+name);o=bpy.data.objects.new('ORTHO_'+name,d);scene.collection.objects.link(o);o.location=pos
 if name=='TOP':o.rotation_euler=(0,0,0)
 else:o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
 d.type='ORTHO';d.ortho_scale=8.20;d.lens=50;cams[name]=o
scene.camera=cams['FRONT']
# Measured bounds and numeric assertions, before rendering.
def bounds(o):
 pts=[o.matrix_world@Vector(v) for v in o.bound_box];return {'min':[round(min(p[i] for p in pts),6) for i in range(3)],'max':[round(max(p[i] for p in pts),6) for i in range(3)]}
bpy.context.view_layer.update()
measured={n:bounds(o) for n,o in [('main_wall',body),('foundation',foundation),('main_roof',roof),('door',door),('chimney_shaft',shaft),('chimney_cap',bpy.data.objects['C1_CAP_TOP']),('front_window',bpy.data.objects['W1_FRONT_GLASS']),('back_window',bpy.data.objects['W2_BACK_INFERRED_GLASS']),('dormer_window',bpy.data.objects['DW1_GLASS'])]}
assert measured['main_roof']['min']==[-3.35,-2.45,3.43],measured
assert measured['main_roof']['max']==[3.35,2.45,5.55],measured
assert measured['door']['min']==[-1.475,-2.08,.45]
assert measured['door']['max']==[-.325,-1.98,2.85]
assert measured['chimney_cap']['max'][2]==7.15
assert len([o for o in bpy.data.objects if o.name.endswith('_GLASS')])==3
report={'label':'Geometry control only; not Tripo output, not game render','units':'meters','source':'build_control.py / multiview-design.md v1.1 frozen','measurement':measured,'camera_scale':8.2,'resolution':[1000,1000],'pixels_per_meter':1000/8.2,'camera_type':'ORTHO','same_model_all_views':True,'manual_inferred_design':['BACK window and timber arrangement','RIGHT wall'],'checks':{'main_roof_dimensions':'PASS 6.70 x 4.90, z3.43..5.55 including thickness','door_position_size':'PASS x=-.90 width1.15 z.45..2.85','chimney_center':'PASS x=-1.65 y+.45','cap_top':'PASS z7.15','straight_ridge':'PASS constant y0 z5.55 for all x','opening_counts':'PASS 1 door, 2 ground-wall windows, 1 front dormer','excluded_geometry':'PASS no lean-to, canopy, machinery, people or landscape'},'limitations':['Control mesh only: flat colors, simplified structure, intersecting dormer/roof solids retained as separately editable objects.','No production topology, UV, PBR texture or game import approval.','Windows are recess panels with wall openings; dormer window is a surface control panel.','Back and right remain proposed design, not observed reconstruction.']}
(ROOT/'dimension-check.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'workshop_multiview_control.blend'))
for name,o in cams.items():
 scene.camera=o;scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
scene.camera=cams['FRONT'];bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'workshop_multiview_control.blend'))
print('MULTIVIEW_CONTROL_DONE',json.dumps(report['checks']))
