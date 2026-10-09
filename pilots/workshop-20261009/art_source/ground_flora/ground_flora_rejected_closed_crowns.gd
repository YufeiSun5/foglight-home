extends RefCounted
## Original, editable workshop-pilot landscape. Godot coordinates: Y up, Z = -Blender Y.
## Entry: preload("res://src/ground_flora.gd").apply(parent) -> Node3D.
## No camera, environment, building, or gameplay changes. No external dependencies.

const SEED := 20261009
const ASSET_ROOT := "res://assets/ground_flora/"

static func apply(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "GroundFlora_OriginalPilot"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var mats := _materials()
	_add_terrain(root, mats)
	_add_rocks(root, mats, rng)
	_add_grass(root, mats, rng)
	_add_broadleaf(root, mats, rng)
	_add_flowers(root, mats, rng)
	_add_tree_canopies(root, mats, rng)
	_add_fences(root, mats, rng)
	_add_backdrop(root, mats)
	_mask_repositioned_building(root)
	root.set_meta("source", "Original independent workshop pilot; not restoration of an earlier map.")
	root.set_meta("seed", SEED)
	return root

static func _plain(color: Color, roughness: float = 0.91) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	return mat

static func _materials() -> Dictionary:
	var soil := ShaderMaterial.new()
	soil.shader = Shader.new()
	soil.shader.code = """
shader_type spatial;
render_mode diffuse_burley;
varying vec3 world_pos;
varying vec3 vcolor;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123); }
float n(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y); }
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; vcolor=COLOR.rgb; }
void fragment() {
 vec2 p=world_pos.xz;
 float grain=n(p*78.0); float gravel=n(p*19.0); float broad=n(p*1.2);
 vec3 sand=mix(vec3(0.39,0.30,0.18),vec3(0.68,0.56,0.34),broad*0.65+gravel*0.35);
 sand*=0.90+grain*0.18;
 float pebble=smoothstep(0.69,0.84,gravel);
 sand=mix(sand,vec3(0.63,0.59,0.45),pebble*0.65);
 ALBEDO=sand*vcolor; ROUGHNESS=0.96;
 NORMAL_MAP=vec3(0.5+(n(p*42.0)-0.5)*0.16,0.5+(n(p*42.0+13.0)-0.5)*0.16,1.0);
 NORMAL_MAP_DEPTH=0.75;
}
"""
	var grass := _plain(Color(0.32,0.385,0.16))
	grass.backlight_enabled = true
	grass.backlight = Color(0.035,0.055,0.018)
	var leaf := _plain(Color(0.28,0.36,0.155))
	leaf.backlight_enabled = true
	leaf.backlight = Color(0.040,0.060,0.022)
	var canopy := _plain(Color(0.285,0.37,0.19))
	canopy.backlight_enabled = true
	canopy.backlight = Color(0.027,0.040,0.018)
	var rock := _plain(Color(0.55,0.56,0.47))
	var bark := _plain(Color(0.23,0.20,0.13))
	var fence := _plain(Color(0.30,0.255,0.175))
	return {"soil":soil,"grass":grass,"leaf":leaf,"canopy":canopy,"rock":rock,"bark":bark,"fence":fence,"flower":_plain(Color(1,1,1)),"stem":_plain(Color(0.24,0.35,0.07))}

static func _noise(x: float, z: float) -> float:
	return sin(x*0.63+sin(z*0.31))*0.44+sin(z*0.83-x*0.27)*0.31+sin(x*1.97+z*1.31)*0.13

static func _height(x: float, z: float) -> float:
	var rear := clampf((-z-4.3)/9.0,0.0,1.0)
	var side := clampf((absf(x)-9.0)/8.0,0.0,1.0)
	var h := -0.10 + _noise(x,z)*0.045
	h += rear*rear*(1.8+0.85*sin(x*0.19+1.7))
	h += side*side*(0.6+0.4*sin(z*0.37))
	return h

static func _base_road_dist(x: float, z: float) -> float:
	# Wide quiet foreground and a fork curving past the right side of the workshop.
	var center := -0.45+sin(z*0.24)*0.78
	var d := absf(x-center) - (2.55 + 0.16*maxf(0.0,z-5.0))
	if z < 6.0:
		var right_x := 6.9 + 2.2*clampf((5.0-z)/8.0,0.0,1.0)
		d = minf(d if z>2.8 else 100.0, absf(x-right_x)-1.65)
	return d

static func _base_blocked(x: float, z: float) -> bool:
	if x > -8.25 and x < 4.5 and z > -3.05 and z < 3.70:
		return true
	if Vector2(x,z).distance_to(Vector2(0.0,5.0)) < 1.3:
		return true
	return false

static func _add_terrain(root: Node3D, mats: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Existing near grid is unchanged; only coarse continuous rings extend rear and sides.
	var xs:Array[float]=[-65.0,-52.0,-42.0,-34.0,-28.0,-24.0]
	for i in range(83): xs.append(-20.5+float(i)*0.5)
	xs.append_array([24.0,28.0,34.0,42.0,52.0,65.0])
	var zs:Array[float]=[-90.0,-74.0,-60.0,-49.0,-40.0,-33.0,-27.0,-23.0,-20.0]
	for j in range(79): zs.append(-18.0+float(j)*0.5)
	for j in range(zs.size()-1):
		for i in range(xs.size()-1):
			var x := xs[i]
			var z := zs[j]
			var corners := [Vector2(x,z),Vector2(xs[i+1],z),Vector2(xs[i+1],zs[j+1]),Vector2(x,zs[j+1])]
			for idx in [0,1,2,0,2,3]:
				var p: Vector2 = corners[idx]
				var green := clampf(_road_dist(p.x,p.y)*0.27,0.0,1.0)
				if _blocked(p.x,p.y): green=0.0
				st.set_color(Color(1,1,1).lerp(Color(0.67,0.78,0.48),green*0.65))
				st.set_uv(p*0.3)
				st.add_vertex(Vector3(p.x,_landscape_height(p.x,p.y),p.y))
	st.generate_normals()
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.name = "SoftStoneEarth_PathAndBanks"
	node.mesh=mesh
	node.material_override=mats.soil
	root.add_child(node)

static func _multimesh(root: Node3D, name_text: String, mesh: Mesh, material: Material, transforms: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i,transforms[i])
		multi.set_instance_color(i,colors[i] if i<colors.size() else Color.WHITE)
	var node := MultiMeshInstance3D.new()
	node.name=name_text
	node.multimesh=multi
	node.set_meta("_placement_transforms", transforms)
	node.set_meta("_placement_colors", colors)
	node.material_override=material
	root.add_child(node)
	return node

static func _transform(pos: Vector3, scale3: Vector3, angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,angle).scaled(scale3),pos)

static func _blade_mesh() -> ArrayMesh:
	# Seven cross-sections with a central crease, tapered tip and genuine swept curve.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sections := 7
	for s in range(sections):
		var a := float(s)/sections
		var b := float(s+1)/sections
		for side in [-1.0,1.0]:
			var p0 := _blade_point(a,0.0)
			var p1 := _blade_point(a,side)
			var p2 := _blade_point(b,side)
			var p3 := _blade_point(b,0.0)
			for k in ([0,1,2,0,2,3] if side > 0.0 else [0,2,1,0,3,2]):
				var arr := [p0,p1,p2,p3]
				var p: Vector3 = arr[k]
				st.set_color(Color(0.70,0.79,0.47).lerp(Color(1.0,1.0,0.74),p.y))
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()

static func _blade_point(t: float, side: float) -> Vector3:
	var width := (0.024+sin(t*PI)*0.045)*pow(1.0-t,0.65)
	return Vector3(side*width,t*0.84,0.48*t*t + absf(side)*width*0.28)

static func _leaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(6):
		var t0 := float(j)/6.0
		var t1 := float(j+1)/6.0
		for s in [-1.0,1.0]:
			var pts := [_leaf_point(t0,0.0),_leaf_point(t0,s),_leaf_point(t1,s),_leaf_point(t1,0.0)]
			for id in ([0,1,2,0,2,3] if s > 0.0 else [0,2,1,0,3,2]):
				var p: Vector3=pts[id]
				st.set_color(Color(0.70,0.83,0.59).lerp(Color(1.0,1.0,0.83),p.z))
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()

static func _leaf_point(t: float, side: float) -> Vector3:
	var width := pow(sin(t*PI),0.85)*0.25
	return Vector3(side*width,sin(t*PI)*0.085-0.17*t*t + absf(side)*width*0.15,t)

static func _add_grass(root: Node3D, mats: Dictionary, rng: RandomNumberGenerator) -> void:
	var transforms: Array[Transform3D]=[]
	var colors: Array[Color]=[]
	var dead_trans: Array[Transform3D]=[]
	var dead_colors: Array[Color]=[]
	var accepted := 0
	for i in range(16500):
		var x := rng.randf_range(-17.0,17.0)
		var z := rng.randf_range(-10.0,17.7)
		if _base_blocked(x,z): continue
		var d := _base_road_dist(x,z)
		var patch := (_noise(x*1.6,z*1.6)+1.0)*0.5
		var chance := smoothstep(-0.18,1.5,d)*0.90*(0.38+patch*0.64)
		# Small discontinuities expose soil rather than a uniform lawn.
		if rng.randf()>chance or (patch<0.28 and d>1.2): continue
		if z<0.0 and x>-7.6 and x<5.0: continue
		accepted += 1
		var cluster_scale := rng.randf_range(0.43,0.82)*(0.72+patch*0.50)
		if d<0.5: cluster_scale*=0.57
		var count := rng.randi_range(4,8)
		for blade in range(count):
			var px := x+rng.randf_range(-0.13,0.13)
			var pz := z+rng.randf_range(-0.13,0.13)
			var h := cluster_scale*rng.randf_range(0.66,1.25)
			transforms.append(_transform(Vector3(px,_height(px,pz)+0.008,pz),Vector3(rng.randf_range(0.60,1.2),h,h),rng.randf()*TAU))
			colors.append(Color(rng.randf_range(0.84,1.02),rng.randf_range(0.86,1.0),rng.randf_range(0.85,1.05)))
		if rng.randf()<0.08:
			dead_trans.append(_transform(Vector3(x,_height(x,z)+0.01,z),Vector3(0.46,cluster_scale*1.22,cluster_scale*0.74),rng.randf()*TAU))
			dead_colors.append(Color(0.96,0.92,0.68))
	_multimesh(root,"CurvedGrass_ClumpedRoadVerges",_blade_mesh(),mats.grass,transforms,colors)
	_multimesh(root,"DryLongGrass_SparseAccent",_blade_mesh(),_plain(Color(0.45,0.405,0.25)),dead_trans,dead_colors)
	root.set_meta("grass_clumps",accepted)
	root.set_meta("grass_blades",transforms.size())

static func _add_broadleaf(root: Node3D, mats: Dictionary, rng: RandomNumberGenerator) -> void:
	var transforms: Array[Transform3D]=[]
	var colors: Array[Color]=[]
	var patches := [Vector3(-8.8,0,4.9),Vector3(-7.6,0,8.4),Vector3(-6.6,0,11.9),Vector3(-10.5,0,1.0),Vector3(4.2,0,6.9),Vector3(6.0,0,9.9),Vector3(10.7,0,3.6),Vector3(12.3,0,-1.5),Vector3(-11.0,0,-4.0),Vector3(5.2,0,-5.0)]
	for patch in patches:
		for plant in range(38):
			var x:float=patch.x+rng.randfn(0.0,0.70)
			var z:float=patch.z+rng.randfn(0.0,0.62)
			if _base_blocked(x,z) or _base_road_dist(x,z)<0.1: continue
			var plant_h := rng.randf_range(0.42,0.93)
			for leaf in range(rng.randi_range(8,15)):
				var angle := rng.randf()*TAU
				var length := rng.randf_range(0.23,0.56)
				var origin := Vector3(x,_height(x,z)+rng.randf_range(0.04,plant_h),z)
				var basis := Basis(Vector3.UP,angle)*Basis(Vector3.RIGHT,rng.randf_range(-0.82,0.32))
				transforms.append(Transform3D(basis.scaled(Vector3(length*0.75,length,length)),origin))
				colors.append(Color(rng.randf_range(0.68,1.12),rng.randf_range(0.78,1.08),rng.randf_range(0.70,1.10)))
	_multimesh(root,"BroadCurvedLeaves_RoadsideHerbClumps",_leaf_mesh(),mats.leaf,transforms,colors)

static func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for petal in range(7):
		var a:=float(petal)*TAU/7.0
		for ring in range(4):
			var t0:=float(ring)/4.0
			var t1:=float(ring+1)/4.0
			for side in [-1.0,1.0]:
				var points: Array[Vector3]=[]
				for p in [Vector2(t0,0.0),Vector2(t0,side),Vector2(t1,side),Vector2(t1,0.0)]:
					var radius:float=0.025+p.x*0.09
					var w:float=sin(p.x*PI)*0.031*p.y
					var height:float=0.022*pow(p.x,1.8)+absf(p.y)*sin(p.x*PI)*0.005
					points.append(Vector3(cos(a)*radius-sin(a)*w,height,sin(a)*radius+cos(a)*w))
				for id in ([0,2,1,0,3,2] if side > 0.0 else [0,1,2,0,2,3]):
					st.set_color(Color(0.88+float(ring)*0.035,0.885+float(ring)*0.033,0.79+float(ring)*0.06))
					st.add_vertex(points[id])
	for j in range(12):
		var a:=float(j)*TAU/12.0
		var b:=float(j+1)*TAU/12.0
		for p in [Vector3(0,0.014,0),Vector3(cos(a)*0.027,0.006,sin(a)*0.027),Vector3(cos(b)*0.027,0.006,sin(b)*0.027)]:
			st.set_color(Color(0.78,0.55,0.085))
			st.add_vertex(p)
	st.generate_normals()
	return st.commit()

static func _add_flowers(root: Node3D, mats: Dictionary, rng: RandomNumberGenerator) -> void:
	var flower_trans: Array[Transform3D]=[]
	var stem_trans: Array[Transform3D]=[]
	var flower_colors: Array[Color]=[]
	var stem_colors: Array[Color]=[]
	var patches := [Vector2(-6.1,12.8),Vector2(-7.0,8.3),Vector2(-8.3,5.6),Vector2(-10.5,0.9),Vector2(4.4,7.2),Vector2(5.2,10.0),Vector2(7.1,14.0),Vector2(11.3,4.4),Vector2(11.9,-1.0)]
	for patch in patches:
		for i in range(rng.randi_range(24,43)):
			var x:float=patch.x+rng.randfn(0.0,0.63)
			var z:float=patch.y+rng.randfn(0.0,0.48)
			if _base_blocked(x,z) or _base_road_dist(x,z)<0.1:continue
			var h:=rng.randf_range(0.26,0.72)
			var lean:=rng.randf_range(-0.20,0.20)
			var origin:=Vector3(x,_height(x,z),z)
			var stem_basis:=Basis(Vector3.FORWARD,lean)
			stem_trans.append(Transform3D(stem_basis.scaled(Vector3(1,h,1)),origin+stem_basis.y*h*0.5))
			stem_colors.append(Color.WHITE)
			var blossom:=Basis(Vector3.UP,rng.randf()*TAU)*Basis(Vector3.RIGHT,rng.randf_range(0.28,1.18))
			var scale:=rng.randf_range(0.70,1.05)
			flower_trans.append(Transform3D(blossom.scaled(Vector3.ONE*scale),origin+stem_basis.y*h))
			flower_colors.append(Color(1.0,1.0,rng.randf_range(0.93,1.0)))
	var stem:=CylinderMesh.new()
	stem.top_radius=0.005
	stem.bottom_radius=0.008
	stem.height=1.0
	stem.radial_segments=5
	_multimesh(root,"SlenderFlowerStems",stem,mats.stem,stem_trans,stem_colors)
	_multimesh(root,"IvoryCupFlowers_SevenCurvedPetals",_flower_mesh(),mats.flower,flower_trans,flower_colors)

static func _rock_mesh(seed_value: int) -> ArrayMesh:
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n:=7
	var lower:Array[Vector3]=[]
	var upper:Array[Vector3]=[]
	for i in range(n):
		var a:=float(i)*TAU/n+rng.randf_range(-0.13,0.13)
		var r:=rng.randf_range(0.78,1.10)
		lower.append(Vector3(cos(a)*r,-0.12+rng.randf_range(-0.07,0.07),sin(a)*r))
		upper.append(Vector3(cos(a)*r*rng.randf_range(0.65,0.92),rng.randf_range(0.45,0.69),sin(a)*r*rng.randf_range(0.72,0.97)))
	var peak:=Vector3(rng.randf_range(-0.2,0.2),0.64,rng.randf_range(-0.2,0.2))
	for i in range(n):
		var j: int=(i+1)%n
		var tint:=rng.randf_range(0.76,1.13)
		var triangles: Array[Vector3]=[lower[i],lower[j],upper[j],lower[i],upper[j],upper[i],upper[i],upper[j],peak]
		for k in range(triangles.size()):
			st.set_color(Color(tint,tint*1.01,tint*0.95) if k<6 else Color(tint*1.12,tint*1.10,tint))
			st.add_vertex(triangles[k])
	st.generate_normals()
	return st.commit()

static func _add_rocks(root: Node3D, mats: Dictionary, rng: RandomNumberGenerator) -> void:
	var positions:Array[Vector3]=[]
	# Uneven broken banks: selected groups, with gaps and overlapping plates.
	for cl in [Vector3(-8.7,0,7.7),Vector3(-6.8,0,12.5),Vector3(-10.1,0,1.1),Vector3(-11.7,0,-3.5),Vector3(5.4,0,8.1),Vector3(10.8,0,3.3),Vector3(12.4,0,-1.5),Vector3(9.5,0,-8.0)]:
		for j in range(rng.randi_range(7,12)):
			positions.append(Vector3(cl.x+rng.randfn(0.0,1.2),0,cl.z+rng.randfn(0.0,0.63)))
	for v in range(7):
		var transforms:Array[Transform3D]=[]
		var colors:Array[Color]=[]
		for i in range(positions.size()):
			if i%7!=v: continue
			var p:Vector3=positions[i]
			if _base_blocked(p.x,p.z) or _base_road_dist(p.x,p.z)<0.7: continue
			var sz:=rng.randf_range(0.36,0.85)
			p.y=_height(p.x,p.z)-0.07
			var bas:=Basis(Vector3.UP,rng.randf()*TAU)*Basis(Vector3.FORWARD,rng.randf_range(-0.24,0.24))
			transforms.append(Transform3D(bas.scaled(Vector3(sz*rng.randf_range(1.0,1.55),sz*rng.randf_range(0.65,1.05),sz)),p))
			colors.append(Color(rng.randf_range(0.83,1.08),rng.randf_range(0.87,1.03),rng.randf_range(0.87,1.08)))
		_multimesh(root,"BrokenStonePlate_Variant%d"%v,_rock_mesh(710+v),mats.rock,transforms,colors)
	# Sparse small sunken angular stones on the bare road, never a cobble carpet.
	var gravel_t:Array[Transform3D]=[]
	var gravel_c:Array[Color]=[]
	for i in range(380):
		var x:=rng.randf_range(-13.0,13.0)
		var z:=rng.randf_range(3.8,18.0)
		if _base_road_dist(x,z)>0.55:continue
		var size:=rng.randf_range(0.045,0.14)
		gravel_t.append(_transform(Vector3(x,_height(x,z)-0.01,z),Vector3(size*1.5,size*0.48,size),rng.randf()*TAU))
		gravel_c.append(Color(rng.randf_range(0.91,1.15),rng.randf_range(0.94,1.11),0.92))
	_multimesh(root,"SparsePathStoneChips",_rock_mesh(997),mats.rock,gravel_t,gravel_c)

static func _add_tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, col: Color, sides: int=7) -> void:
	var axis:Vector3=(b-a).normalized()
	var tangent:Vector3=axis.cross(Vector3.FORWARD).normalized()
	if tangent.length_squared()<0.1:tangent=axis.cross(Vector3.RIGHT).normalized()
	var bitangent:Vector3=axis.cross(tangent).normalized()
	for i in range(sides):
		var p:=float(i)*TAU/sides
		var q:=float(i+1)*TAU/sides
		var u:=tangent*cos(p)+bitangent*sin(p)
		var v:=tangent*cos(q)+bitangent*sin(q)
		for point in [a+u*ra,b+v*rb,a+v*ra,a+u*ra,b+u*rb,b+v*rb]:
			st.set_color(col)
			st.add_vertex(point)

static func _add_tree_canopies(root: Node3D, mats: Dictionary, rng: RandomNumberGenerator) -> void:
	var leaves:Array[Transform3D]=[]
	var colors:Array[Color]=[]
	var branch_st:=SurfaceTool.new()
	branch_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Complete overlapping crowns close the view; no broad unexplored map behind them.
	var trees := [Vector3(-13.2,6.8,-5.0),Vector3(-9.8,6.0,-7.2),Vector3(-6.8,5.4,-9.2),Vector3(-2.0,5.8,-11.8),Vector3(2.8,5.5,-10.0),Vector3(7.0,6.2,-8.8),Vector3(11.8,5.8,-5.8),Vector3(15.1,6.6,-3.1),Vector3(-15.2,5.3,0.0)]
	for ti in range(trees.size()):
		var tree:Vector3=trees[ti]
		var base:=Vector3(tree.x,_height(tree.x,tree.z),tree.z)
		var h:float=tree.y
		var sway:=Vector3(rng.randf_range(-0.35,0.35),0,rng.randf_range(-0.3,0.3))
		var trunk_top:=base+Vector3(0,h*0.72,0)+sway
		_add_tube(branch_st,base,trunk_top,0.15+0.025*h,0.08,Color(0.85,0.88,0.75),9)
		for cluster in range(14):
			var angle:=float(cluster)*2.39996+ti
			var radius:=sqrt(float(cluster)/14.0)*h*0.29
			var center:=base+Vector3(cos(angle)*radius,h*0.60+rng.randf_range(-0.02,h*0.31),sin(angle)*radius)
			var branch_start:=base+Vector3(0,h*rng.randf_range(0.38,0.58),0)
			_add_tube(branch_st,branch_start,center,0.055,0.018,Color(0.93,0.94,0.83),6)
			var cluster_radius:=rng.randf_range(0.83,1.32)
			for li in range(260):
				var azimuth:=rng.randf()*TAU
				var vertical:=rng.randf_range(-1.0,1.0)
				var radial:=pow(rng.randf(),0.30)*cluster_radius
				var flat:=sqrt(maxf(0.0,1.0-vertical*vertical))
				var offset:=Vector3(cos(azimuth)*flat*radial,vertical*radial*0.77,sin(azimuth)*flat*radial)
				var pos:=center+offset
				var scale:=rng.randf_range(0.26,0.48)
				var bas:=Basis(Vector3.UP,rng.randf()*TAU)*Basis(Vector3.RIGHT,rng.randf_range(-0.85,0.90))*Basis(Vector3.FORWARD,rng.randf_range(-0.45,0.45))
				leaves.append(Transform3D(bas.scaled(Vector3(scale*0.92,scale,scale)),pos))
				var light:=rng.randf_range(0.67,1.13)
				colors.append(Color(light*rng.randf_range(0.89,1.10),light,light*rng.randf_range(0.82,1.15)))
	branch_st.generate_normals()
	var branches:=MeshInstance3D.new()
	branches.name="JoinedTreeTrunksAndBranches"
	branches.mesh=branch_st.commit()
	branches.material_override=mats.bark
	root.add_child(branches)
	_multimesh(root,"DenseBroadleafCanopies_SharedCurvedLeafMesh",_leaf_mesh(),mats.canopy,leaves,colors)
	root.set_meta("tree_leaf_count",leaves.size())

static func _add_fences(root: Node3D, mats: Dictionary, rng: RandomNumberGenerator) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var runs := [[Vector2(8.5,11.0),Vector2(10.2,11.5),Vector2(12.2,11.7),Vector2(14.3,12.3)], [Vector2(-13.6,-1.2),Vector2(-11.8,-1.7),Vector2(-10.1,-2.0)]]
	for run in runs:
		var posts:Array[Vector3]=[]
		for p in run:
			var base:=Vector3(p.x,_height(p.x,p.y),p.y)
			var top:=base+Vector3(rng.randf_range(-0.07,0.07),rng.randf_range(1.12,1.34),rng.randf_range(-0.09,0.09))
			_add_tube(st,base-Vector3(0,0.10,0),top,0.135,0.115,Color(rng.randf_range(0.83,1.15),1.0,0.94),4)
			posts.append(base)
		for i in range(posts.size()-1):
			for h in [0.37,0.94]:
				var a:=posts[i]+Vector3(0,h,0)
				var b:=posts[i+1]+Vector3(0,h+rng.randf_range(-0.08,0.07),0)
				_add_tube(st,a,b,0.095,0.105,Color(0.88,0.89,0.82),4)
	st.generate_normals()
	var node:=MeshInstance3D.new()
	node.name="WeatheredBrokenRailFence"
	node.mesh=st.commit()
	node.material_override=mats.fence
	root.add_child(node)

# Integration revision: building/props translated by (3.2,0,-1.2).
# Keep the baseline random placement sequence and original leaf/rock/tree shapes.
# New building occupancy and the outward right-path corridor are subtractive masks.
static func _blocked(x: float, z: float) -> bool:
	if x > -5.05 and x < 7.70 and z > -4.25 and z < 2.50:
		return true
	return Vector2(x,z).distance_to(Vector2(0.0,5.0)) < 1.3

static func _road_dist(x: float, z: float) -> float:
	var center := -0.45+sin(z*0.24)*0.78
	var d := absf(x-center) - (2.55 + 0.16*maxf(0.0,z-5.0))
	if z < 6.0:
		var right_x := 10.1 + 2.2*clampf((5.0-z)/8.0,0.0,1.0)
		d = minf(d if z>2.8 else 100.0, absf(x-right_x)-1.65)
	return d

static func _mask_repositioned_building(root: Node3D) -> void:
	var names := ["CurvedGrass_ClumpedRoadVerges", "DryLongGrass_SparseAccent", "BroadCurvedLeaves_RoadsideHerbClumps", "SlenderFlowerStems", "IvoryCupFlowers_SevenCurvedPetals"]
	var removed := 0
	for child in root.get_children():
		if not (child is MultiMeshInstance3D) or not names.has(String(child.name)): continue
		var original:MultiMesh=child.multimesh
		var transforms:Array[Transform3D]=child.get_meta("_placement_transforms")
		var colors:Array[Color]=child.get_meta("_placement_colors")
		var kept:Array[int]=[]
		for i in range(original.instance_count):
			var p:Vector3=transforms[i].origin
			if _blocked(p.x,p.z) or _road_dist(p.x,p.z)<-0.05:
				removed+=1
			else: kept.append(i)
		var filtered:=MultiMesh.new()
		filtered.transform_format=MultiMesh.TRANSFORM_3D
		filtered.use_colors=true
		filtered.mesh=original.mesh
		filtered.instance_count=kept.size()
		for j in range(kept.size()):
			filtered.set_instance_transform(j,transforms[kept[j]])
			filtered.set_instance_color(j,colors[kept[j]])
		child.multimesh=filtered
		if child.name=="CurvedGrass_ClumpedRoadVerges": root.set_meta("grass_blades",kept.size())
	for child in root.get_children():
		if child.has_meta("_placement_transforms"): child.remove_meta("_placement_transforms")
		if child.has_meta("_placement_colors"): child.remove_meta("_placement_colors")
	root.set_meta("building_offset",Vector3(3.2,0,-1.2))
	root.set_meta("flora_removed_for_repositioned_building",removed)

static func _landscape_height(x:float,z:float) -> float:
	var original:=_height(x,z)
	var extension:=smoothstep(0.0,15.0,maxf(-z-18.0,absf(x)-20.5))
	var ridge:=0.35+1.05*pow(sin(x*0.095+z*0.023+0.6),2.0)+0.40*sin(x*0.18-z*0.06)
	return original+extension*ridge

static func _crown_point(latitude:float,longitude:float,seed_phase:float) -> Vector3:
	var latitude_scale:=sin(latitude)
	var ripple:=1.0+0.105*sin(longitude*3.0+seed_phase)*sin(latitude*2.0)+0.075*cos(longitude*7.0-latitude*3.0+seed_phase)
	return Vector3(cos(longitude)*latitude_scale*ripple,cos(latitude)*(0.92+0.06*sin(longitude*4.0+seed_phase)),sin(longitude)*latitude_scale*ripple)

static func _crown_volume_mesh(variant:int) -> ArrayMesh:
	# Closed, editable irregular crown mass. Its low-frequency silhouette carries distant volume.
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(9):
		for i in range(18):
			var a:=float(j)*PI/9.0
			var b:=float(j+1)*PI/9.0
			var c:=float(i)*TAU/18.0
			var d:=float(i+1)*TAU/18.0
			var phase:=float(variant)*1.73
			var p:=[_crown_point(a,c,phase),_crown_point(b,c,phase),_crown_point(b,d,phase),_crown_point(a,d,phase)]
			for k in [0,1,2,0,2,3]:
				var point:Vector3=p[k]
				var shade:=0.78+0.19*(point.y+1.0)*0.5+0.08*sin(c*3.0+phase)
				st.set_color(Color(shade,shade,shade*0.98))
				st.add_vertex(point)
	st.index()
	st.generate_normals()
	return st.commit()

static func _add_backdrop(root:Node3D,mats:Dictionary) -> void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=SEED+803
	var volumes:Array[Transform3D]=[]
	var volume_colors:Array[Color]=[]
	var foliage:Array[Transform3D]=[]
	var foliage_colors:Array[Color]=[]
	var mass_material:=_plain(Color(0.27,0.35,0.19))
	var far_positions := [Vector3(-30.0,4.2,-20.0),Vector3(-23.0,4.9,-24.0),Vector3(-16.0,4.0,-21.0),Vector3(-9.5,4.7,-26.0),Vector3(-2.0,3.7,-23.5),Vector3(5.5,4.2,-25.0),Vector3(13.0,4.6,-22.0),Vector3(20.5,4.0,-24.0),Vector3(28.0,4.7,-20.0),Vector3(35.0,4.2,-26.0)]
	for tree in far_positions:
		var base:=Vector3(tree.x,_landscape_height(tree.x,tree.z),tree.z)
		for lobe in range(6):
			var angle:=float(lobe)*2.39996
			var center:=base+Vector3(cos(angle)*rng.randf_range(0.8,1.6),tree.y*0.57+rng.randf_range(-0.15,0.45),sin(angle)*rng.randf_range(0.6,1.5))
			var scale:=Vector3(rng.randf_range(1.4,1.9),rng.randf_range(1.3,1.8),rng.randf_range(1.3,1.8))
			volumes.append(_transform(center,scale,rng.randf()*TAU))
			volume_colors.append(Color(rng.randf_range(0.83,1.04),rng.randf_range(0.87,1.03),rng.randf_range(0.92,1.08)))
			for leaf in range(45):
				var az:=rng.randf()*TAU
				var el:=rng.randf_range(0.12,PI*0.88)
				var off:=Vector3(cos(az)*sin(el)*scale.x,cos(el)*scale.y,sin(az)*sin(el)*scale.z)*rng.randf_range(0.99,1.10)
				var size:=rng.randf_range(0.30,0.46)
				var basis:=Basis(Vector3.UP,rng.randf()*TAU)*Basis(Vector3.RIGHT,rng.randf_range(-0.8,0.7))
				foliage.append(Transform3D(basis.scaled(Vector3.ONE*size),center+off))
				foliage_colors.append(Color(rng.randf_range(0.88,1.06),rng.randf_range(0.90,1.04),1.0))
	# Low understory hides exposed stems and the old flat bank beneath the nearest row.
	for shrub in [Vector2(-17.0,-3.5),Vector2(-13.0,-6.8),Vector2(-8.5,-7.2),Vector2(-4.0,-9.4),Vector2(2.5,-10.2),Vector2(7.7,-8.5),Vector2(13.0,-6.0),Vector2(17.2,-3.7)]:
		for lobe in range(3):
			var x:float=shrub.x+rng.randf_range(-1.1,1.1)
			var z:float=shrub.y+rng.randf_range(-0.9,0.9)
			var center:=Vector3(x,_height(x,z)+rng.randf_range(0.52,0.83),z)
			var scale:=Vector3(rng.randf_range(1.1,1.6),rng.randf_range(0.85,1.2),rng.randf_range(1.0,1.4))
			volumes.append(_transform(center,scale,rng.randf()*TAU))
			volume_colors.append(Color(0.86,0.94,0.90))
			for leaf in range(40):
				var az:=rng.randf()*TAU
				var el:=rng.randf_range(0.18,PI*0.77)
				var off:=Vector3(cos(az)*sin(el)*scale.x,cos(el)*scale.y,sin(az)*sin(el)*scale.z)*1.02
				var size:=rng.randf_range(0.25,0.40)
				var basis:=Basis(Vector3.UP,rng.randf()*TAU)*Basis(Vector3.RIGHT,rng.randf_range(-0.8,0.7))
				foliage.append(Transform3D(basis.scaled(Vector3.ONE*size),center+off))
				foliage_colors.append(Color(0.93,0.99,0.95))
	for variant in range(3):
		var transforms:Array[Transform3D]=[]
		var colors:Array[Color]=[]
		for i in range(volumes.size()):
			if i%3==variant:
				transforms.append(volumes[i])
				colors.append(volume_colors[i])
		_multimesh(root,"LayeredBackdropCrownVolumes_%d"%variant,_crown_volume_mesh(variant),mass_material,transforms,colors)
	_multimesh(root,"BackdropLimitedSurfaceLeaves",_leaf_mesh(),mats.canopy,foliage,foliage_colors)
	root.set_meta("backdrop_added_leaves",foliage.size())
	root.set_meta("backdrop_crown_volumes",volumes.size())
