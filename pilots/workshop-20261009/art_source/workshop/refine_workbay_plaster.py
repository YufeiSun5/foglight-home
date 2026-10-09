import bpy, random, math,json
D='/workspace/shared/foglight-town-pilot-20261009/art_source/workshop';bpy.ops.wm.open_mainfile(filepath=D+'/foglight_workshop_refined2.blend')
C=bpy.data.collections.get('Workshop • editable architectural components');wood=bpy.data.materials['Workshop | weathered structural oak'];plaster=bpy.data.materials['Workshop | weathered lime plaster']
removed=[]
for o in list(C.objects):
 if o.type=='MESH' and o.name.startswith('Sheltered vertical oak boarding') and o.location.x < -.77:
  removed.append(o.name);bpy.data.objects.remove(o,do_unlink=True)

def box(name,loc,dims,mat):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=dims;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for c in list(o.users_collection):c.objects.unlink(o)
 C.objects.link(o);o.data.materials.append(mat);uv=o.data.uv_layers.active
 for p in o.data.polygons:
  for li in p.loop_indices:
   v=o.data.vertices[o.data.loops[li].vertex_index].co
   uv.data[li].uv=(v.x/1.5,v.z/2.5) if abs(p.normal.y)>.5 else (v.y/1.5,v.z/2.5)
 m=o.modifiers.new('Worn edge','BEVEL');m.width=.014;m.segments=2;m=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');m.keep_sharp=True
 return o
# Real full-thickness infill on each side of the preserved open doorway.
for a,b in [(-3.56,-3.01),(-1.70,-.76)]:
 box('Left work bay warm lime inset',((a+b)/2,-.28,1.92),(b-a,.14,3.10),plaster)
 for z in [.45,3.44]:box('Left work bay oak panel rail',((a+b)/2,-.39,z),(b-a+.045,.115,.09),wood)
for x in [-3.55,-.76]:box('Left work bay oak panel stile',(x,-.39,1.95),(.105,.115,3.13),wood)
bpy.ops.wm.save_as_mainfile(filepath=D+'/foglight_workshop_refined3.blend')
json.dump({'removed_full_height_wood_planks':len(removed),'plaster_ranges_X':[[-3.56,-3.01],[-1.70,-.76]],'back_wall_Y':-.28,'door_opening_preserved':[-2.96,-1.74],'new_side_infill_thickness':.14,'post_and_wall_depth_unchanged':True},open(D+'/refined3_workbay_report.json','w'),indent=2)
