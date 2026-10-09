import struct,json,numpy as np,pathlib,hashlib
ROOT=pathlib.Path('/workspace/shared/foglight-town-pilot-20261009');p=ROOT/'assets/workshop_props/workwall_props.glb';b=p.read_bytes();n,k=struct.unpack_from('<II',b,12);g=json.loads(b[20:20+n]);bn,bk=struct.unpack_from('<II',b,20+n);d=b[28+n:]
def a(i):
 q=g['accessors'][i];v=g['bufferViews'][q['bufferView']];cols={'VEC2':2,'VEC3':3,'VEC4':4,'SCALAR':1}[q['type']];dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[q['componentType']];dd=np.dtype(dtype);return np.ndarray((q['count'],cols),dtype=dd,buffer=d,offset=v.get('byteOffset',0)+q.get('byteOffset',0),strides=(v.get('byteStride',cols*dd.itemsize),dd.itemsize)).copy()
rows=[]
for m in g['meshes']:
 for pr in m['primitives']:
  at=pr['attributes'];nn=a(at['NORMAL']);tt=a(at['TANGENT'])[:,:3];uv=a(at['TEXCOORD_0']);ii=a(pr['indices']).reshape((-1,3));tris=uv[ii];uvarea=np.abs((tris[:,1,0]-tris[:,0,0])*(tris[:,2,1]-tris[:,0,1])-(tris[:,1,1]-tris[:,0,1])*(tris[:,2,0]-tris[:,0,0]))
  dot=np.abs((nn*tt).sum(1));rows.append({'mesh':m['name'],'material':g['materials'][pr['material']]['name'],'vertices':len(nn),'max_abs_dot_N_T':float(dot.max()),'invalid_tangent_count':int(sum(dot>.01)),'degenerate_uv_triangles':int(sum(uvarea<1e-12))})
res={'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b),'max_abs_dot_N_T':max(x['max_abs_dot_N_T'] for x in rows),'invalid_tangent_count':sum(x['invalid_tangent_count'] for x in rows),'degenerate_uv_triangles':sum(x['degenerate_uv_triangles'] for x in rows),'primitives':rows}
(ROOT/'art_source/workshop_props/workwall_validation.json').write_text(json.dumps(res,indent=2));print(json.dumps(res,indent=2));assert res['invalid_tangent_count']==0,'TBN orthogonality failed';assert res['degenerate_uv_triangles']==0,'UV degeneracy failed'
