import bpy, bmesh, json, os
R='/workspace/shared/foglight-town-pilot-20261009';D=R+'/art_source/workshop';A=R+'/assets/workshop'
bpy.ops.wm.open_mainfile(filepath=D+'/foglight_workshop_refined2.blend')
C=bpy.data.collections.get('Workshop • editable architectural components');dg=bpy.context.evaluated_depsgraph_get()
# Validate signed volumes of roof decks and skins before enabling backface culling.
volumes={}
for o in C.objects:
 if o.type=='MESH' and ('roof deck' in o.name or 'curved panel' in o.name or 'curved teal roof panel' in o.name or 'Low flat roof folded joint' in o.name or 'low flat folded joint' in o.name):
  bm=bmesh.new();bm.from_mesh(o.data);volumes[o.name]=bm.calc_volume(signed=True);bm.free()
assert all(v>0 for v in volumes.values()),volumes
for m in bpy.data.materials:m.use_backface_culling='canopy' not in m.name.lower()
# Source file remains untouched. Combine evaluated meshes with world transforms and their UVs.
bpy.ops.object.select_all(action='DESELECT')
for o in list(C.objects):
 if o.type in ['MESH','CURVE']:o.select_set(True);bpy.context.view_layer.objects.active=o
bpy.ops.object.convert(target='MESH')
for o in bpy.context.selected_objects:
 if o.type=='MESH':bpy.context.view_layer.objects.active=o;break
bpy.ops.object.join();o=bpy.context.object;o.name='Workshop runtime mesh • 13 material surfaces'
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
tri=o.modifiers.new('Runtime explicit triangulation','TRIANGULATE')
if hasattr(tri,'keep_custom_normals'):tri.keep_custom_normals=True
bpy.ops.object.modifier_apply(modifier=tri.name)
bpy.ops.export_scene.gltf(filepath=A+'/foglight_workshop_refined2_runtime.glb',export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_materials='EXPORT',export_texcoords=True,export_normals=True,export_tangents=True,export_cameras=False,export_lights=False)
json.dump({'roof_positive_volume_count':len(volumes),'roof_positive_volume_min':min(volumes.values()),'mesh_objects':1,'material_slots':len(o.data.materials),'runtime_bytes':os.path.getsize(A+'/foglight_workshop_refined2_runtime.glb'),'editable_source':'art_source/workshop/foglight_workshop_refined2.blend'},open(A+'/refined2_runtime_validation.json','w'),indent=2)
print('RUNTIME_READY',len(o.data.vertices))
