"""Read-only GLB validation: UV existence alone is not validity; TBN must be orthogonal."""
import struct,json,hashlib,sys,numpy as np
p=sys.argv[1];b=open(p,'rb').read();n,_=struct.unpack_from('<II',b,12);j=json.loads(b[20:20+n]);blob=b[28+n:]
DT={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'};SZ={'VEC3':3,'VEC4':4,'VEC2':2,'SCALAR':1}
def a(i):
 z=j['accessors'][i];v=j['bufferViews'][z['bufferView']];dt=np.dtype(DT[z['componentType']]);off=v.get('byteOffset',0)+z.get('byteOffset',0);ct=SZ[z['type']]
 return np.ndarray((z['count'],ct),dtype=dt,buffer=blob,offset=off,strides=(v.get('byteStride',ct*dt.itemsize),dt.itemsize))
r={'path':p,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'meshes':len(j['meshes']),'materials':len(j['materials']),'embedded_images':sum('bufferView' in x for x in j.get('images',[])),'surfaces':[]}
for mesh in j['meshes']:
 for pr in mesh['primitives']:
  at=pr['attributes'];q={'material':j['materials'][pr['material']]['name'],'uv_present':'TEXCOORD_0'in at,'tangent_present':'TANGENT'in at};idx=a(pr['indices']).reshape(-1,3);q['triangles']=len(idx)
  if q['uv_present']:
   uv=a(at['TEXCOORD_0']);v=uv[idx];ed1=v[:,1]-v[:,0];ed2=v[:,2]-v[:,0];area2=ed1[:,0]*ed2[:,1]-ed1[:,1]*ed2[:,0];q['zero_area_uv_triangles']=int((abs(area2)<1e-10).sum())
  if q['tangent_present']:
   nm=a(at['NORMAL']);ta=a(at['TANGENT']);dot=(nm*ta[:,:3]).sum(-1);q.update({'vertices':len(nm),'nonfinite_components':int((~np.isfinite(nm)).sum()+(~np.isfinite(ta)).sum()),'max_abs_N_dot_T':float(abs(dot).max()),'tangents_dot_over_0_001':int((abs(dot)>.001).sum()),'parallel_N_T_count':int((abs(dot)>.99).sum())})
  r['surfaces'].append(q)
r['tbn_orthogonality_pass']=all(s.get('tangents_dot_over_0_001',1)==0 for s in r['surfaces']);r['nondegenerate_uv_pass']=all(s.get('zero_area_uv_triangles',1)==0 for s in r['surfaces'])
print(json.dumps(r,indent=2))
