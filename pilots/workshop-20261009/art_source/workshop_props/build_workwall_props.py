"""Add a restrained, functional workshop wall display; preserves the original props GLB."""
from pathlib import Path
helpers=(Path('/workspace/shared/foglight-town-pilot-20261009/art_source/workshop_props/build_workshop_props.py').read_text().split('# Left shed.')[0])
exec(compile(helpers,'build_workshop_props_helpers','exec'))
# Coordinate contract with hero: back wall Y=-.28; window X=.82..2.58, Z=1.67..2.68.
# Keep warm-plaster left bay legible; tall rack fits entirely to the right of the main post.
group('01_Three_tier_tool_shelf')
for xx in [-.48,.68]:
 cube('Rack vertical mortised oak upright',(xx,-.475,1.68),(.072,.085,1.88),OLD,.009)
 for zz in [.82,2.53]:bolt('Rack wall anchor',(xx,-.531,zz),.031,IRON)
for level,z in enumerate([1.00,1.53,2.08]):
 cube('Shelf %d solid board'%level,(.10,-.585,z),(1.32,.37,.065),WOOD,.009)
 # Real triangular corbels rather than free-floating shelf boards.
 for xx in [-.39,.59]:
  beam('Shelf %d diagonal bracket'%level,(xx,-.47,z-.27),(xx,-.735,z-.048),.048,.048,OLD,.006)
 cube('Shelf %d shallow rear stop'%level,(.10,-.445,z+.092),(1.30,.036,.13),OLD,.005)
# Lowest shelf: one open-topped carpenter's tote, with clear carry handle and contents.
x,y,z=.13,-.605,1.05
cube('Open tote base',(x,y,z+.025),(.66,.27,.042),OLD,.007)
for yy in [y-.126,y+.126]:cube('Open tote raised side',(x,yy,z+.122),(.65,.035,.19),WOOD,.006)
for xx in [x-.316,x+.316]:
 cube('Open tote end',(xx,y,z+.12),(.038,.27,.19),WOOD,.006)
 cube('Open tote handle cheek',(xx,y,z+.25),(.045,.055,.29),OLD,.008)
rod('Open tote worn carry grip',(x-.30,y,z+.385),(x+.30,y,z+.385),.027,WOOD,16)
# Two purposeful pieces in the tote, large enough to read as tools.
beam('Tote hammer handle',(x-.15,y,z+.075),(x-.10,y,z+.31),.027,.034,WOOD,.005)
cube('Tote hammer head',(x-.10,y,z+.33),(.12,.05,.05),EDGE,.007)
beam('Tote chisel',(x+.17,y,z+.04),(x+.22,y,z+.29),.026,.028,EDGE,.003)
# Middle shelf: two different oil cans, not a repetition wall of tiny jars.
def oilcan(name,x,y,z,r=.10,h=.22,brass=False):
 mat=BRASS if brass else IRON
 cylinder(name+' reservoir',(x,y,z+h/2),r,h,mat,(0,0,1),24,.008)
 cylinder(name+' shoulder',(x,y,z+h),r*.75,.048,mat,(0,0,1),24,.008)
 cylinder(name+' lid',(x,y,z+h+.035),r*.34,.024,EDGE,(0,0,1),16,.005)
 # slender bent delivery spout plus an open back handle
 rod(name+' long spout',(x+r*.68,y,z+h*.72),(x+r*2.05,y,z+h*1.72),.017,EDGE,12)
 rod(name+' nozzle',(x+r*2.05,y,z+h*1.72),(x+r*2.25,y-.018,z+h*1.81),.012,EDGE,10)
 for a,b in [((x-r*.8,y,z+h*.80),(x-r*1.65,y,z+h*.78)),((x-r*1.65,y,z+h*.78),(x-r*1.65,y,z+h*.16)),((x-r*1.65,y,z+h*.16),(x-r*.8,y,z+h*.22))]:rod(name+' handle',a,b,.014,mat,12)
oilcan('Tall iron oil can',-.22,-.59,1.566,.083,.21)
oilcan('Small brass oil can',.34,-.58,1.566,.075,.15,True)
# Upper shelf: one timber hand plane, and a coil whose empty centre stays readable.
cube('Shelf hand plane stock',(-.22,-.59,2.16),(.43,.16,.095),WOOD,.011)
o=cube('Shelf hand plane set iron',(-.17,-.59,2.245),(.062,.095,.105),IRON,.005);o.rotation_euler[1]=-.38
ring('Spare brass bearing ring',(.38,-.535,2.255),.13,.085,.085,BRASS,32)
cube('Ring resting wedge',(.38,-.61,2.134),(.20,.16,.055),OLD,.006)
# Slim left tool hangers preserve most of the new warm gray plaster surface.
group('02_Left_wall_hung_tools')
cube('Left tool peg rail',(-1.25,-.425,2.57),(.77,.09,.075),OLD,.008)
for xx in [-1.47,-1.08]:
 rod('Left tool hook shank',(xx,-.46,2.57),(xx,-.585,2.57),.019,IRON,12)
 rod('Left tool hook tip',(xx,-.585,2.57),(xx,-.585,2.62),.019,IRON,12)
# A long-handled wooden mallet hangs from its head, with a collared handle.
cube('Hung joiner mallet head',(-1.47,-.56,2.48),(.245,.135,.105),WOOD,.016)
beam('Hung joiner mallet handle',(-1.47,-.56,2.465),(-1.43,-.575,1.81),.036,.049,OLD,.007)
# Blacksmith tongs: long handles, visible hinge, opposing curved jaws.
for sign in [-1,1]:
 rod('Hung tongs long grip',(-1.08+sign*.08,-.55,1.77),(-1.08+sign*.018,-.55,2.26),.016,IRON,12)
 rod('Hung tongs jaw',(-1.08+sign*.018,-.55,2.26),(-1.08+sign*.076,-.55,2.44),.018,IRON,12)
 rod('Hung tongs bent tip',(-1.08+sign*.076,-.55,2.44),(-1.08+sign*.029,-.55,2.49),.018,IRON,12)
bolt('Hung tongs hinge',(-1.08,-.575,2.26),.03,EDGE)
# One substantial frame saw on the narrow wooden strip right of the existing window.
group('03_Right_wall_frame_saw')
x,y=3.01,-.51
for xx in [x-.17,x+.17]:cube('Frame saw upright',(xx,y,2.05),(.045,.058,.83),WOOD,.007)
cube('Frame saw top stretcher',(x,y,2.40),(.43,.055,.045),OLD,.007)
cube('Frame saw middle stretcher',(x,y,2.05),(.35,.047,.048),OLD,.007)
blade=cube('Frame saw tensioned blade',(x,y,1.69),(.41,.012,.045),EDGE,.003)
for i in range(14):
 # Broad real teeth, not an alpha texture.
 xx=x-.19+i*.027
 me=bpy.data.meshes.new('Saw tooth');me.from_pydata([(xx,y-.006,1.672),(xx+.022,y-.006,1.672),(xx+.006,y-.006,1.651),(xx,y+.006,1.672),(xx+.022,y+.006,1.672),(xx+.006,y+.006,1.651)],[],[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)]);me.update()
 ob=bpy.data.objects.new('Frame saw tooth',me);GROUPS[active].objects.link(ob);me.materials.append(EDGE);uv_box(ob,(.022,.012,.021))
rod('Frame saw tension cord',(x-.17,y,2.465),(x+.17,y,2.465),.008,OLD,8)
rod('Frame saw wall hook',(x,-.36,2.46),(x,-.59,2.46),.018,IRON,12)

scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
for im in bpy.data.images:
 if im.source=='FILE':im.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'workwall_props.blend'))
originals=[o for col in GROUPS.values() for o in col.objects];exports=[];counts={}
for name,col in GROUPS.items():
 copies=[]
 for original in list(col.objects):
  if original.type!='MESH':continue
  ob=original.copy();ob.data=original.data.copy();scene.collection.objects.link(ob);bpy.context.view_layer.objects.active=ob;ob.select_set(True)
  for mod in list(ob.modifiers):
   try:bpy.ops.object.modifier_apply(modifier=mod.name)
   except Exception:pass
  copies.append(ob);ob.select_set(False)
 bpy.ops.object.select_all(action='DESELECT')
 for ob in copies:ob.select_set(True)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();ob=bpy.context.object;ob.name=name
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 tri=ob.modifiers.new('Export triangulation','TRIANGULATE');tri.keep_custom_normals=True;bpy.ops.object.modifier_apply(modifier=tri.name)
 # Bevels on radial caps can create zero-area interpolated UV slivers. Repair
 # only those triangles from their actual local geometric face plane.
 import bmesh
 bm=bmesh.new();bm.from_mesh(ob.data)
 tiny=[f for f in bm.faces if f.calc_area()<1e-8]
 if tiny:bmesh.ops.delete(bm,geom=tiny,context='FACES_ONLY')
 bm.to_mesh(ob.data);bm.free();ob.data.update()
 uv=ob.data.uv_layers.active.data;fixed=0
 for face in ob.data.polygons:
  loops=list(face.loop_indices);a,b,c=[uv[i].uv.copy() for i in loops]
  area=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
  if abs(area)<1e-8:
   coords=[ob.data.vertices[ob.data.loops[li].vertex_index].co.copy() for li in loops]
   origin=coords[0];edge=(coords[1]-origin).normalized();perp=face.normal.cross(edge).normalized()
   for li,co in zip(loops,coords):
    delta=co-origin;uv[li].uv=(delta.dot(edge)*4,delta.dot(perp)*4)
   fixed+=1
 ob.data.update();ob.data.calc_loop_triangles();counts[name]={'source_components':len(col.objects),'triangles':len(ob.data.loop_triangles),'uv_degenerate_triangles_repaired':fixed};exports.append(ob)
bpy.ops.object.select_all(action='DESELECT')
for ob in exports:ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'workwall_props.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_materials='EXPORT',export_texcoords=True,export_normals=True,export_tangents=True)
summary={'asset':'workwall_props.glb','assemblies':counts,'triangles':sum(c['triangles'] for c in counts.values()),'units':'metres','coordinates':'Source Blender Z up/front -Y; use unchanged scene origin and same parent offset as house.','sha256':hashlib.sha256((OUT/'workwall_props.glb').read_bytes()).hexdigest(),'materials':'Same restrained procedural oak/iron/brass as original prop source. No diagnostic changes to normals or roughness.','scope':'Additional wall props only; workshop_props.glb remains unchanged.'}
(SRC/'workwall_stats.json').write_text(json.dumps(summary,indent=2));print('WORKWALL_READY '+json.dumps(summary))
# Standalone preview for positioning and silhouette review.
for ob in originals:ob.hide_render=True;ob.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'workwall_props_export_verified.blend'))
world=scene.world;world.color=(.35,.35,.35)
group('Preview_only')
wall=cube('Preview neutral backing',(1,-.25,1.6),(6,.1,3.2),OLD,0)
fm=bpy.data.materials.new('Preview clay');fm.diffuse_color=(.3,.28,.24,1);wall.data.materials.clear();wall.data.materials.append(fm)
bpy.ops.object.light_add(type='AREA',location=(-2,-4,6));bpy.context.object.data.energy=750;bpy.context.object.data.size=5
bpy.ops.object.camera_add(location=(3,-8,4));cam=bpy.context.object;cam.rotation_euler=(Vector((.8,-.45,1.75))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=5.6;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=False;scene.render.resolution_x=1200;scene.render.resolution_y=700;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(SRC/'workwall_preview.png');scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';bpy.ops.render.render(write_still=True)
