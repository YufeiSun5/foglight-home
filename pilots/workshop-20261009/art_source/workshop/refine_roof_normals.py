import bpy,math,json
D='/workspace/shared/foglight-town-pilot-20261009/art_source/workshop'
bpy.ops.wm.open_mainfile(filepath=D+'/foglight_workshop_refined.blend')
changed=[]
for o in bpy.context.scene.objects:
 if o.type=='MESH' and any(s in o.name for s in ['Teal standing seam curved panel','Annex curved teal roof panel','Low flat roof folded joint','Annex low flat folded joint']):
  # Smooth along the curved slope. Sharp boundaries prevent the sheet's vertical
  # thickness faces from pulling roof-top corner normals sideways into fake ribs.
  o.data.set_sharp_from_angle(angle=math.radians(20))
  o.data.update();changed.append(o.name)
bpy.ops.wm.save_as_mainfile(filepath=D+'/foglight_workshop_refined2.blend')
json.dump({'roof_meshes_with_explicit_sharp_perimeter':len(changed),'angle_threshold_degrees':20,'vertex_positions_changed':False,'materials_changed':False},open(D+'/refined2_normals_report.json','w'),indent=2)
print('SHARP_ROOF_MESHES',len(changed))
