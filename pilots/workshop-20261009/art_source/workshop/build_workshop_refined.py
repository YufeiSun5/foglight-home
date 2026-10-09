import bpy, bmesh, math, os, json, random
from mathutils import Vector
from math import sin,cos,pi
ROOT='/workspace/shared/foglight-town-pilot-20261009'
D=ROOT+'/art_source/workshop'; A=ROOT+'/assets/workshop'; T=D+'/textures'
random.seed(60219)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for d in list(bpy.data.materials): bpy.data.materials.remove(d)
C=bpy.data.collections.new('Workshop • editable architectural components');bpy.context.scene.collection.children.link(C)

def coll(o):
 for c in list(o.users_collection): c.objects.unlink(o)
 C.objects.link(o)
 return o

def material(name,col,rough=.7,metal=0,tex=None,tint=None):
 m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);m.use_nodes=True
 nt=m.node_tree; p=nt.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
 if tex:
  nodes={}
  for kind in ['basecolor','roughness','normal']:
   im=bpy.data.images.load(f'{T}/{tex}_{kind}.png',check_existing=True)
   if kind!='basecolor': im.colorspace_settings.name='Non-Color'
   n=nt.nodes.new('ShaderNodeTexImage');n.image=im;n.label=tex+' '+kind;n.location=(-600,{'basecolor':180,'roughness':-50,'normal':-280}[kind]);nodes[kind]=n
  nt.links.new(nodes['basecolor'].outputs['Color'],p.inputs['Base Color'])
  nt.links.new(nodes['roughness'].outputs['Color'],p.inputs['Roughness'])
  n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.38;n.location=(-220,-180);nt.links.new(nodes['normal'].outputs['Color'],n.inputs['Color']);nt.links.new(n.outputs['Normal'],p.inputs['Normal'])
 return m
wood=material('Workshop | weathered structural oak',(.29,.18,.09),tex='aged_oak')
woodlight=material('Workshop | cut oak edges',(.42,.285,.135),.78)
wooddark=material('Workshop | aged recessed timber',(.135,.09,.045),.88)
teal=material('Workshop | muted weathered blue-green roof',(.19,.30,.29),.72,.09,tex='teal_refined')
teal_dark=material('Workshop | low flat patinated folds',(.036,.076,.068),.75,.09)
plaster=material('Workshop | weathered lime plaster',(.62,.57,.44),tex='lime_plaster')
stone=material('Workshop | grey limestone',(.49,.49,.42),tex='limestone')
stone_dark=material('Workshop | recessed lime mortar',(.27,.29,.25),.98)
cloth=material('Workshop | unbleached woven canopy',(.78,.69,.51),tex='linen');cloth.use_backface_culling=False
iron=material('Workshop | hand forged iron',(.072,.09,.085),.56,.72)
rust=material('Workshop | oxidised iron edge',(.18,.12,.065),.9,.32)
glass=material('Workshop | deep cold grey glass',(.023,.042,.050),.24,.10)
warmglass=material('Workshop | deep cold dormer glass',(.018,.035,.045),.22,.12)
p=warmglass.node_tree.nodes.get('Principled BSDF');p.inputs['Emission Color'].default_value=(.7,.4,.12,1);p.inputs['Emission Strength'].default_value=0.0
inside=material('Workshop | deep unlit interior',(.075,.069,.045),.95)

def mesh(name,verts,faces,mat,uvs=None):
 me=bpy.data.meshes.new(name+' mesh');me.from_pydata(verts,[],faces);me.materials.append(mat);me.update()
 ob=bpy.data.objects.new(name,me);C.objects.link(ob)
 uv=me.uv_layers.new(name='Metre-scaled UV')
 if uvs:
  for p in me.polygons:
   for li in p.loop_indices:uv.data[li].uv=uvs[me.loops[li].vertex_index]
 else:
  for p in me.polygons:
   n=p.normal; axes=sorted(range(3),key=lambda a:abs(n[a]))[:2]
   for li in p.loop_indices:
    co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]]*.5,co[axes[1]]*.5)
 return ob

def bevel(o,a=.025,seg=2):
 if a>0:
  mod=o.modifiers.new('Soft worn arris','BEVEL');mod.width=a;mod.segments=seg
  mod=o.modifiers.new('Weighted face normals','WEIGHTED_NORMAL');mod.keep_sharp=True
 return o

def box(name,loc,dim,mat,bev=.025):
 x,y,z=[v/2 for v in dim]
 vs=[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
 fs=[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]
 o=mesh(name,vs,fs,mat);o.location=loc
 # Local length UV for real beams. Geometry has unit object scale before UV.
 uv=o.data.uv_layers.active; off=random.random()*3
 for p in o.data.polygons:
  for li in p.loop_indices:
   c=o.data.vertices[o.data.loops[li].vertex_index].co
   if abs(p.normal.z)>.9: u,v=c.x/.6,c.y/.6
   elif abs(p.normal.y)>.9:u,v=c.x/.6,c.z/2.5
   else:u,v=c.y/.6,c.z/2.5
   uv.data[li].uv=(u+off,v+off)
 return bevel(o,min(bev,min(dim)*.18))

def beam(name,a,b,width=.2,depth=None,mat=wood,bev=.025):
 a,b=Vector(a),Vector(b);d=b-a;o=box(name,(a+b)/2,(width,depth or width,d.length),mat,bev);o.rotation_mode='QUATERNION';o.rotation_quaternion=d.to_track_quat('Z','Y');return o

def curve(name,points,r,mat):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=1;cu.bevel_depth=r;cu.bevel_resolution=2
 sp=cu.splines.new('POLY');sp.points.add(len(points)-1)
 for p,co in zip(sp.points,points):p.co=(*co,1)
 o=bpy.data.objects.new(name,cu);C.objects.link(o);o.data.materials.append(mat);return o

def cylinder(name,loc,r,depth,mat,axis=(0,0,1),vertices=16):
 bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,location=loc);o=coll(bpy.context.object);o.name=name;o.data.materials.append(mat);o.rotation_mode='QUATERNION';o.rotation_quaternion=Vector(axis).to_track_quat('Z','Y');return bevel(o,.007,1)

# Foundation. Individual stones reveal mortar and irregular dressed edges.
box('Lime mortar plinth', (0,-.05,.14),(7.64,4.88,.28),stone_dark,.04)
for y,tag in [(-2.51,'front'),(2.40,'rear')]:
 for i in range(12):
  x=-3.52+i*.64
  box(f'Dressed foundation {tag} {i:02}',(x,y,.15),(.61,.36,.30+random.uniform(-.025,.03)),stone,.045)
for x in [-3.7,3.7]:
 for i in range(8):box('Foundation end block',(x,-2.15+i*.59,.15),(.35,.57,.30),stone,.038)
# Porch floor broad irregular flagstones only under building.
for ix in range(10):
 for iy in range(4):
  box('Porch flagstone',( -3.35+ix*.745,-2.13+iy*.56,.295),(.72,.54,.10+random.random()*.025),stone,.025)

# True closed side walls and rear wall. Main street-facing wall recessed by two metres.
box('Left wall lime infill',(-3.59,-.1,1.94),(.20,4.67,3.25),plaster,.025)
box('Right wall lime infill',(3.59,-.1,1.94),(.20,4.67,3.25),plaster,.025)
box('Rear wall lime infill',(0,2.31,1.94),(7.12,.20,3.25),plaster,.025)
for x in [-3.68,3.68]:
 for y in [-2.4,0,2.31]:
  beam('Oak side post',(x,y,.28),(x,y,3.78),.24,.24)
 for z in [.53,2.90,3.63]:beam('Side wall horizontal rail',(x,-2.48,z),(x,2.40,z),.20,.19)
 # Diagonal lower wattle bay bracing, broad legible geometry.
 for ya,yb in [(-2.3,-.1),(.1,2.2)]:beam('Side wall diagonal brace',(x,ya,.64),(x,yb,2.8),.17,.16)
for x in [-3.65,-1.4,1.25,3.65]:beam('Back timber post',(x,2.45,.3),(x,2.45,3.70),.22)
beam('Rear crown beam',(-3.75,2.40,3.70),(3.75,2.40,3.70),.26)
# Recessed front wall: sheltered plank work area, with real open door at left.
for xa,xb in [(-3.55,-2.96),(-1.74,3.52)]:
 n=round((xb-xa)/.23)
 for i in range(n):
  xx=xa+(i+.5)*(xb-xa)/n
  if .87 < xx < 2.53:
   box('Work window lower boarding',(xx,-.28,1.00),((xb-xa)/n-.014,.14,1.32),wood,.009)
   box('Work window upper boarding',(xx,-.28,3.13),((xb-xa)/n-.014,.14,.92),wood,.009)
  else:
   box('Sheltered vertical oak boarding',(xx,-.28,1.95),((xb-xa)/n-.014,.14,3.28),wood,.009)
box('Door lintel infill',(-2.35,-.28,3.18),(1.20,.16,.82),plaster,.012)
box('Shadow inside doorway',(-2.34,1.82,1.38),(1.08,.07,2.15),inside,.0)
for x in [-3.00,-1.72]:beam('Door oak jamb',(x,-.47,.34),(x,-.47,2.82),.17,.24)
beam('Door oak lintel',(-3.12,-.46,2.87),(-1.59,-.46,2.87),.20,.24)
box('Worn doorway sill',(-2.35,-.44,.35),(1.51,.62,.18),stone,.025)
# Half-open plank door leaf with a visible thickness and iron straps.
door=bpy.data.objects.new('Half-open door assembly',None);C.objects.link(door);door.location=(-2.96,-.36,.37);door.rotation_euler[2]=math.radians(-63)
for i in range(5):
 o=box('Door board',((i+.5)*.23,0,1.16),(.224,.085,2.30),wood,.01);o.parent=door
for z in [.25,1.88]:
 o=box('Door cross rail',(.575,-.06,z),(1.12,.105,.13),woodlight,.017);o.parent=door
 o=box('Forged strap hinge',(.44,-.125,z),(.82,.023,.072),iron,.009);o.parent=door
ob=beam('Door diagonal cleat',(.08,-.07,.36),(1.03,-.07,1.79),.11,.09);ob.parent=door
# Small dark framed workshop window with deep sill, mounted on the wooden wall.
box('Recessed counter window darkness',(1.70,.38,2.17),(1.54,.028,.88),inside,.009)
for x in [.87,2.53]:beam('Small opening frame',(x,-.44,1.67),(x,-.44,2.68),.10,.13)
for z in [1.67,2.68]:beam('Small opening rail',(.82,-.44,z),(2.58,-.44,z),.10,.13)
box('Deep projecting window sill',(1.70,-.53,1.66),(1.90,.44,.11),woodlight,.017)
for x in [1.28,1.70,2.12]:beam('Counter window bars',(x,-.48,1.74),(x,-.48,2.61),.022,.025,iron,.004)
# Exposed ground-floor frontage. Spliced, chamfered load-bearing posts and knee braces.
for x in [-3.67,-.66,3.65]:
 box('Front post stone shoe',(x,-2.43,.36),(.49,.47,.30),stone,.045)
 beam('Street frontage oak post',(x,-2.43,.40),(x,-2.43,3.78),.27,.28)
 for z in [.59,3.43]:box('Wrought post collar',(x,-2.43,z),(.286,.295,.085),iron,.009)
beam('Primary front lintel',(-3.9,-2.46,3.69),(3.91,-2.46,3.69),.29,.31)
beam('Porch back lintel',(-3.67,-.35,3.60),(3.67,-.35,3.60),.24,.26)
for x in [-3.65,-.66,3.65]:
 beam('Porch transverse ceiling tie',(x,-2.53,3.61),(x,.15,3.61),.19,.22)
 for direction in [-1,1]:
  if -3.8 < x+direction*.72 <3.8:
   beam('Front porch knee brace',(x,-2.43,2.91),(x+direction*.72,-2.43,3.59),.18,.19)
 beam('Porch depth knee brace',(x,-2.39,2.96),(x,-1.66,3.53),.16,.17)
# Ceiling joists visible above the working recess.
for x in [-3.1,-2.45,-1.8,-1.15,-.5,.15,.8,1.45,2.1,2.75,3.4]:
 beam('Exposed porch ceiling joist',(x,-2.52,3.62),(x,2.4,3.62),.11,.16)

# Smooth convex roof cross-section, continuous along the ridge. Not an A-frame.
def prof(y,half=2.90,peak=6.20,drop=2.34):
 u=abs(y)/half
 return peak-drop*(.30*u+.70*u**1.80)

def arch_solid(name,x1,x2,half,peak,drop,thick,mat,steps=72):
 ys=[-half+2*half*i/steps for i in range(steps+1)];vs=[];uv=[]
 arc=[0]
 for a,b in zip(ys,ys[1:]):arc.append(arc[-1]+math.hypot(b-a,prof(b,half,peak,drop)-prof(a,half,peak,drop)))
 for x in [x1,x2]:
  for dz in [0,-thick]:
   for i,y in enumerate(ys):vs.append((x,y,prof(y,half,peak,drop)+dz));uv.append((x/.75,arc[i]/2.7))
 n=steps+1;fs=[]
 for i in range(steps):
  fs += [(i,i+1,2*n+i+1,2*n+i),(n+i,3*n+i,3*n+i+1,n+i+1),(i,n+i,n+i+1,i+1),(2*n+i,2*n+i+1,3*n+i+1,3*n+i)]
 fs.extend([(0,2*n,3*n,n),(n-1,2*n-1,4*n-1,3*n-1)])
 o=mesh(name,vs,fs,mat,uv)
 for p in o.data.polygons:p.use_smooth=True
 return o
# Broad wooden structural deck with thick end fascia; metal skin is finely folded sheet.
arch_solid('Main curved timber roof deck',-4.03,4.03,2.90,6.17,2.34,.145,wooddark)
for x in [-4.035,3.90]:
 arch_solid('Thick arched oak verge board',x,x+.14,2.94,6.23,2.40,.24,wood,72)
# Vertical seam pattern follows the full curve, with a fine lifted return hem.
num=18
for i in range(num):
 x1=-3.965+7.93*i/num; x2=-3.965+7.93*(i+1)/num
 arch_solid(f'Teal standing seam curved panel {i:02}',x1+.003,x2-.006,2.955,6.235,2.375,.026,teal,64)
 xx=x1+.005
 pts=[(xx,-2.957+5.914*j/64,prof(-2.957+5.914*j/64,2.955,6.263,2.375)) for j in range(65)]
 arch_solid('Low flat roof folded joint',xx-.009,xx+.009,2.955,6.243,2.375,.012,teal_dark,64)
# Crown cap and continuous eave hem.
beam('Subtle ridge crown cap',(-4.06,0,6.277),(4.06,0,6.277),.09,.105,teal_dark,.022)
for y in [-2.947,2.947]:
 beam('Folded teal eave drip edge',(-4.06,y,3.86),(4.06,y,3.86),.055,.082,teal_dark,.014)
 beam('Main exposed eave oak',(-4.02,y*.875,3.68),(4.02,y*.875,3.68),.17,.23,wood,.023)
# Rafter tails below the eaves carry real shadows and a readable rhythm.
for i in range(18):
 x=-3.91+i*.46
 for s in [-1,1]:beam('Exposed rafter end',(x,s*2.46,3.81),(x,s*2.95,3.67),.075,.12,wood,.012)
# Gable panels are extruded curved polygons; timber framework sits proud of the lime face.
def gable(x):
 ys=[-2.53+5.06*j/48 for j in range(49)]
 poly=[(-2.53,3.69),(2.53,3.69)]+[(y,prof(y)-.22) for y in reversed(ys)]
 vs=[(x+dx,y,z) for dx in [-.075,.075] for y,z in poly]; n=len(poly)
 fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 return mesh('Curved gable lime infill',vs,fs,plaster)
for x in [-3.76,3.76]:
 g=gable(x)
 if x < 0:
  # A real through-cut in the 15cm gable wall, with glazing recessed behind its lip.
  bm=bmesh.new();bm.from_mesh(g.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(g.data);bm.free()
  cut=box('Temporary upper window aperture',(x,-.65,5.30),(.55,.57,.78),inside,0)
  mod=g.modifiers.new('True gable window opening','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cut
  bpy.context.view_layer.objects.active=g;bpy.ops.object.modifier_apply(modifier=mod.name)
  bpy.data.objects.remove(cut,do_unlink=True)
 front=x+(-.10 if x<0 else .10)
 beam('Gable tie beam',(front,-2.62,3.76),(front,2.62,3.76),.21,.25)
 beam('High gable king post',(front,0,3.77),(front,0,6.02),.23,.24)
 for y in [-1.56,1.56]:beam('Gable upright',(front,y,3.82),(front,y,prof(y)-.15),.16,.18)
 for s in [-1,1]:beam('Gable diagonal brace',(front,s*1.51,3.88),(front,s*.16,5.37),.17,.17)
 pts=[(front,-2.63+5.26*j/50,prof(-2.63+5.26*j/50)-.18) for j in range(51)]
 # True curved rim, wide enough to read from hero camera.
 curve('Bent timber gable arch',pts,.085,wood)
# High gable upper window on left end: raised casing and dark blue-green glazing.
x=-3.89
box('Upper gable recessed glazing',(x+.18,-.65,5.30),(.035,.50,.73),glass,.008)
for y in [-.96,-.34]:beam('Upper gable window jamb',(x-.09,y,4.86),(x-.09,y,5.73),.085,.09)
for z in [4.87,5.73]:beam('Upper gable window rail',(x-.09,-1.0,z),(x-.09,-.30,z),.085,.09)
beam('Upper gable window mullion',(x-.11,-.65,4.94),(x-.11,-.65,5.65),.035,.04,woodlight,.006)
beam('Upper gable window transom',(x-.11,-.91,5.28),(x-.11,-.39,5.28),.035,.04,woodlight,.006)
box('Upper gable deep sill',(x-.15,-.65,4.87),(.36,.77,.11),wood,.01)
# Main front dormer. Side cheeks are real geometry meeting the curved roof.
cx=.32; fy=-1.97
box('Dormer dark inset',(cx,fy,5.53),(.64,.10,.82),wooddark,.012)
for s in [-1,1]:
 x=cx+s*.40
 o=mesh('Dormer triangular plaster cheek',[(x,fy,prof(fy)-.025),(x,fy,5.98),(x,-.82,5.98),(x,-.82,prof(-.82)-.045)],[(0,1,2,3)],plaster)
 sol=o.modifiers.new('Dormer lime cheek thickness','SOLIDIFY');sol.thickness=.075
 beam('Dormer front upright',(x,fy-.065,5.06),(x,fy-.065,5.97),.14,.18)
for z in [5.10,5.94]:beam('Dormer window horizontal',(cx-.4,fy-.09,z),(cx+.4,fy-.09,z),.13,.18)
box('Dormer lower oak apron',(cx,fy,5.025),(.81,.16,.18),wooddark,.012)
box('Dormer glass',(cx,fy-.045,5.51),(.62,.035,.68),warmglass,.008)
beam('Dormer central mullion',(cx,fy-.14,5.18),(cx,fy-.14,5.85),.045,.055,woodlight,.008)
beam('Dormer cross light',(cx-.30,fy-.14,5.5),(cx+.30,fy-.14,5.5),.04,.055,woodlight,.008)
box('Dormer window sill',(cx,fy-.20,5.1),(.98,.34,.11),woodlight,.016)
for s in [-1,1]:
 vs=[(cx,fy-.20,6.31),(cx+s*.59,fy-.20,5.96),(cx+s*.59,-.72,5.96),(cx,-.72,6.31)]
 o=mesh('Dormer turquoise roof slope',vs,[(0,1,2,3)],teal);sol=o.modifiers.new('Folded roof thickness','SOLIDIFY');sol.thickness=.042
 beam('Dormer oak verge',(cx,fy-.23,6.28),(cx+s*.57,fy-.23,5.93),.10,.12)
 for t in [.3,.6,.9]:
  xx=cx+s*.59*t; zz=6.31-.35*t
  beam('Dormer fine seam',(xx,fy-.22,zz+.02),(xx,-.74,zz+.02),.017,.020,teal_dark,.003)

# Masonry chimney in the rear-left roof, layered ashlar with a stone cap and metal hood.
cc=(-2.1,.84); basez=5.80
box('Chimney recessed mortar core',(cc[0],cc[1],6.97),(.64,.69,2.52),stone_dark,.018)
for row in range(9):
 z=basez+.135+row*.273
 for side in range(4):
  for k in range(2):
   offset=(-.165 if k==0 else .165)
   if side<2:loc=(cc[0]+offset,cc[1]+(-.34 if side==0 else .34),z);dim=(.318,.14,.258)
   else:loc=(cc[0]+(-.34 if side==2 else .34),cc[1]+offset,z);dim=(.14,.318,.258)
   o=box('Hand cut chimney ashlar',loc,dim,stone,.022);o.rotation_euler[2]=random.uniform(-.016,.016)
box('Chimney stepped crown stone',(cc[0],cc[1],8.32),(.83,.83,.15),stone,.024)
box('Chimney dark flue mouth',(cc[0],cc[1],8.405),(.48,.48,.03),inside,.009)
for dx in [-.32,.32]:
 for dy in [-.32,.32]:beam('Chimney hood support',(cc[0]+dx,cc[1]+dy,8.38),(cc[0]+dx,cc[1]+dy,8.79),.055,.055,iron,.007)
box('Iron rain hood',(cc[0],cc[1],8.81),(.91,.91,.105),iron,.025)
# The original reference has a tall chimney; it remains the vertical secondary silhouette.

# Left mechanical annex: lower, open-ended shallow curved roof and no blocking infill.
sh_center=-.875; sh_half=2.67
# Annex curve along Y is offset to align front eave -3.545 / rear +1.795.
def shedprof(y):return 3.68-1.02*(abs((y-sh_center)/sh_half))**1.68

def shed_strip(name,x1,x2,mat,thick=.08):
 steps=56;ys=[sh_center-sh_half+2*sh_half*i/steps for i in range(steps+1)];n=len(ys)
 vs=[(x,y,shedprof(y)+dz) for x in [x1,x2] for dz in [0,-thick] for y in ys];uv=[(x/.7,(y+3.55)/2.5) for x in [x1,x2] for dz in [0,-thick] for y in ys]
 fs=[]
 for i in range(steps):fs.extend([(i,i+1,2*n+i+1,2*n+i),(n+i,3*n+i,3*n+i+1,n+i+1),(i,n+i,n+i+1,i+1),(2*n+i,2*n+i+1,3*n+i+1,3*n+i)])
 fs.extend([(0,2*n,3*n,n),(n-1,2*n-1,4*n-1,3*n-1)])
 o=mesh(name,vs,fs,mat,uv)
 for p in o.data.polygons:p.use_smooth=True
 return o
shed_strip('Annex continuous timber deck',-7.43,-3.53,wooddark,.14)
for i in range(10):
 x1=-7.44+i*3.92/10;x2=-7.44+(i+1)*3.92/10
 o=shed_strip('Annex curved teal roof panel',x1+.007,x2-.004,teal,.022);o.location.z=.023
 pts=[(x1,-3.55+5.35*j/56,shedprof(-3.55+5.35*j/56)+.049) for j in range(57)]
 o=shed_strip('Annex low flat folded joint',x1-.009,x1+.009,teal_dark,.012);o.location.z=.031
for x in [-7.47,-3.59]:shed_strip('Annex thick bent oak end fascia',x,x+.14,wood,.20)
for y in [-3.43,1.65]:
 beam('Annex longitudinal eave timber',(-7.37,y,2.53),(-3.6,y,2.53),.22,.24)
 for x in [-7.07,-3.88]:
  box('Annex stone post shoe',(x,y+.23 if y<0 else y,.18),(.46,.48,.36),stone,.035)
  yy=y+.23 if y<0 else y
  beam('Annex open shed post',(x,yy,.27),(x,yy,2.68),.25,.26)
  dd=1 if x< -5 else -1
  beam('Annex corner knee brace',(x,yy,1.94),(x+dd*.69,yy,2.51),.18,.20)
# Visible open arch in left end: continuous bent wood and a cross tie, truss struts.
xx=-7.27
beam('Annex open truss tie',(xx,-3.24,2.57),(xx,1.51,2.57),.18,.22)
pts=[(xx,-3.4+5.03*j/40,shedprof(-3.4+5.03*j/40)-.15) for j in range(41)];curve('Annex open bent roof frame',pts,.085,wood)
for y in [-2.76,1.00]:beam('Annex open truss diagonal',(xx,y,2.62),(xx,-.875,3.49),.13,.15)
beam('Annex open king post',(xx,-.875,2.60),(xx,-.875,3.51),.13,.17)
for i in range(9):
 x=-7.30+i*.45
 for s in [-1,1]:
  y=sh_center+s*sh_half
  beam('Annex rafter end',(x,y-s*.39,2.77),(x,y,2.57),.075,.13,wood,.012)
# Low rear half wall gives framing depth without obstructing the wheel.
for i in range(14):
 box('Annex low rear vertical board',(-7.02+i*.24,1.62,.71),(.228,.115,.91),wood,.012)
beam('Annex low rear top rail',(-7.2,1.60,1.22),(-3.66,1.60,1.22),.12,.18)

# Suspended cream linen canopy. Explicit fine quad drape, stitched raised hems, not a flat triangle.
x0=-.14;x1=3.65;y0=-2.52;y1=-4.14;nx=30;ny=22
verts=[];uv=[]
def canopy(u,v):
 x=x0+(x1-x0)*u; y=y0+(y1-y0)*v
 z=3.38-.46*v-.22*sin(pi*v)-.115*sin(pi*u)*(0.4+.6*v)+.025*sin(u*pi*8)*sin(v*pi)
 return (x,y,z)
for j in range(ny+1):
 v=j/ny
 for i in range(nx+1):u=i/nx;verts.append(canopy(u,v));uv.append((u*2.2,v*1.35))
faces=[]
for j in range(ny):
 for i in range(nx):k=j*(nx+1)+i;faces.append((k,k+1,k+nx+2,k+nx+1))
o=mesh('Woven linen awning • draped editable grid',verts,faces,cloth,uv)
for p in o.data.polygons:p.use_smooth=True
sol=o.modifiers.new('Real linen hem thickness','SOLIDIFY');sol.thickness=.012
for side in ['left','right','front','back']:
 points=[]
 for i in range(41):
  t=i/40;u,v=(0,t) if side=='left' else (1,t) if side=='right' else (t,1) if side=='front' else (t,0)
  points.append(canopy(u,v))
 curve('Thick stitched linen perimeter',points,.021,cloth)
# Softly scalloped valance rather than a straight rectangle.
vs=[];uv=[];n=60
for i in range(n+1):
 u=i/n;px,py,pz=canopy(u,1);drop=.12+.055*(.5-.5*cos(u*14*pi))
 vs.extend([(px,py,pz),(px,py+.02,pz-drop)]);uv.extend([(u*2.2,0),(u*2.2,.12)])
fs=[(i*2,i*2+1,i*2+3,i*2+2) for i in range(n)]
o=mesh('Canopy soft scalloped front valance',vs,fs,cloth,uv);m=o.modifiers.new('Hem fabric thickness','SOLIDIFY');m.thickness=.012
for x in [x0-.1,x1+.06]:
 beam('Awning slender support pole',(x,y1,.22),(x,y1,3.02),.067,.08,wood,.011)
 cylinder('Awning iron pole finial',(x,y1,3.045),.064,.08,iron)
for u in [0,1]:
 p=Vector(canopy(u,1));p1=(p.x+(-.11 if u==0 else .07),y1,3.03)
 curve('Awning taut corner rope',[tuple(p),p1],.014,woodlight)
# A small iron bracket for the shop sign. Sign board itself has no text or copied insignia.
beam('Sign wall cantilever',(3.74,-2.43,3.35),(4.36,-2.43,3.35),.065,.065,iron,.008)
beam('Sign wall brace',(3.78,-2.43,3.03),(4.28,-2.43,3.35),.043,.043,iron,.006)
for x in [4.04,4.28]:curve('Sign suspension iron link',[(x,-2.43,3.34),(x,-2.43,3.10)],.015,iron)
box('Hanging artisan sign',(4.16,-2.43,2.83),(.59,.095,.50),wooddark,.025)
# Original simple brass ring-and-hammer emblem, modeled so no image is substituted.
curve('Shop sign brass ring',[(4.16+.135*cos(i*2*pi/32),-2.489,2.84+.135*sin(i*2*pi/32)) for i in range(33)],.013,woodlight)
beam('Shop sign hammer haft',(4.10,-2.495,2.72),(4.22,-2.495,2.98),.023,.025,woodlight,.004)
beam('Shop sign hammer head',(4.13,-2.498,2.98),(4.29,-2.498,2.91),.055,.038,woodlight,.005)
# Useful selected connection pegs and iron plates, not surface noise everywhere.
for x in [-3.65,-.66,3.65]:
 for z in [3.48,3.73]:cylinder('Structural iron tie bolt',(x,-2.623,z),.036,.028,iron,(0,-1,0),12)
for y in [-1.55,0,1.55]:cylinder('Gable wooden trunnel',(-4.003,y,3.76),.035,.042,woodlight,(-1,0,0),12)

# Recalculate closed mesh orientation after custom arch sweeps. Skin surfaces face outward.
for o in C.objects:
 if o.type == 'MESH':
  bm=bmesh.new();bm.from_mesh(o.data)
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
  if ('draped editable' in o.name or 'valance' in o.name):
   bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
  bm.to_mesh(o.data);bm.free();o.data.update()
# Geometry audit and portable export. Source objects remain separate and editable.
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.render.threads_mode='FIXED';scene.render.threads=4
for im in bpy.data.images:
 if im.filepath: im.pack()
bpy.ops.wm.save_as_mainfile(filepath=D+'/foglight_workshop_refined.blend')
print('REFINED_SOURCE_READY')
