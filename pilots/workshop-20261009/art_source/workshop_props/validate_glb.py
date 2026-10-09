"""Inspect the exported glTF directly without altering it or invoking engine QA."""
import json, struct, pathlib, hashlib, numpy as np
ROOT=pathlib.Path('/workspace/shared/foglight-town-pilot-20261009')
p=ROOT/'assets/workshop_props/workshop_props.glb';raw=p.read_bytes();magic,version,total=struct.unpack_from('<4sII',raw);assert magic==b'glTF' and version==2 and total==len(raw)
n,kind=struct.unpack_from('<II',raw,12);g=json.loads(raw[20:20+n]);bn,bk=struct.unpack_from('<II',raw,20+n);data=raw[28+n:28+n+bn]
dtypes={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'};size={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def accessor(i):
 a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];off=v.get('byteOffset',0)+a.get('byteOffset',0);dt=np.dtype(dtypes[a['componentType']]);stride=v.get('byteStride',size[a['type']]*dt.itemsize)
 return np.ndarray((a['count'],size[a['type']]),dtype=dt,buffer=data,offset=off,strides=(stride,dt.itemsize)).copy()
triangles=0;warnings=[];bounds=[]
for node in g['nodes']:
 m=g['meshes'][node['mesh']];coords=[]
 for pr in m['primitives']:
  assert pr.get('mode',4)==4
  attrs=pr['attributes'];assert all(k in attrs for k in ('POSITION','NORMAL','TANGENT','TEXCOORD_0'))
  for key,idx in attrs.items():assert np.isfinite(accessor(idx)).all(),f'{node["name"]}: {key}'
  points=accessor(attrs['POSITION']);coords.append(points)
  normals=accessor(attrs['NORMAL']);lens=np.linalg.norm(normals,axis=1)
  if np.any(abs(lens-1)>.02):warnings.append(node['name']+' non-unit normals')
  indices=accessor(pr['indices']).reshape(-1);assert len(indices)%3==0 and indices.max()<len(points);triangles+=len(indices)//3
 loc=np.array(node.get('translation',[0,0,0]));pts=np.concatenate(coords)+loc
 bounds.append({'assembly':node['name'],'glTF_min':pts.min(axis=0).round(4).tolist(),'glTF_max':pts.max(axis=0).round(4).tolist()})
assert all('bufferView' in im for im in g['images'])
report={'file':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(raw).hexdigest(),'glb_version':version,'bytes':len(raw),'mesh_count':len(g['meshes']),'material_count':len(g['materials']),'embedded_images':len(g['images']),'triangle_count':triangles,'all_finite':True,'every_primitive_has_normal_tangent_uv':True,'all_textures_embedded':True,'warnings':warnings,'assembly_world_bounds':bounds,'scope':'Format and geometry checks only; parent owns Godot native visual QA.'}
(ROOT/'art_source/workshop_props/glb_validation.json').write_text(json.dumps(report,indent=2))
files=[p]+list((ROOT/'art_source/workshop_props/textures').glob('*.png'))+list((ROOT/'art_source/workshop_props').glob('*.py'))+[ROOT/'art_source/workshop_props/workshop_props.blend']
(ROOT/'art_source/workshop_props/dependency_hashes.json').write_text(json.dumps({str(x.relative_to(ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in files},indent=2))
print(json.dumps(report,indent=2))
