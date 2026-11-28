extends RefCounted
## Loads the CC0 Quaternius rigged character + animation libraries once and
## dresses instances as football players. A region id per vertex (jersey,
## pants, sock, cleat, skin, glove) is baked from each vertex's dominant bone,
## so one shared shader colors every athlete via per-instance uniforms.

const BASE := "res://assets/characters/UAL1_Standard.glb"
const EXTRA := "res://assets/characters/UAL2_Standard.glb"
const SHADER := "res://src/game/art/athlete.gdshader"
## Bone-name prefix -> region id (matches athlete.gdshader).
const REGIONS := [["hand_", 5], ["thumb_", 5], ["index_", 5], ["middle_", 5], ["ring_", 5], ["pinky_", 5],
	["lowerarm_", 4], ["neck", 4], ["Head", 4], ["foot_", 3], ["ball_", 3], ["calf_", 2],
	["thigh_", 1], ["pelvis", 1], ["root", 1]]

static var _scene: PackedScene
static var _extra_lib: AnimationLibrary
static var _mesh: Mesh
static var _mat: ShaderMaterial

static func instance() -> Node3D:
	if _scene == null:
		_scene = load(BASE)
		# Keep the PackedScene referenced until ex.free(): the dummy renderer (headless)
		# errors when a freed mesh node held the last ref to its mesh (#92).
		var ex_scene := load(EXTRA) as PackedScene
		var ex: Node = ex_scene.instantiate()
		var ap := find_anim(ex)
		if ap:
			_extra_lib = ap.get_animation_library("")
		ex.free()
	var n: Node3D = _scene.instantiate()
	var ap := find_anim(n)
	if ap and _extra_lib and not ap.has_animation_library("u2"):
		ap.add_animation_library("u2", _extra_lib)
	return n

static func find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := find_mesh(c)
		if m:
			return m
	return null

static func find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := find_anim(c)
		if a:
			return a
	return null

## Swap in the region-baked mesh (once, shared) and the athlete shader.
static func dress_mesh(mi: MeshInstance3D) -> void:
	if mi == null:
		return
	# Hit_Knockback moves the rig beyond its imported rest-pose bounds.
	mi.extra_cull_margin = 1.5
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load(SHADER)
	if _mesh == null:
		_mesh = _bake(mi)
	if _mesh:
		mi.mesh = _mesh
	mi.material_override = _mat.duplicate()   # per-athlete colors (no instance uniforms on GL compat)

static func _region_of(bone_name: String) -> int:
	for r in REGIONS:
		if bone_name.begins_with(r[0]):
			return r[1]
	return 0   # spine/clavicle/upper arm: jersey

static func _bake(mi: MeshInstance3D) -> Mesh:
	var src: Mesh = mi.mesh
	var skel := mi.get_parent() as Skeleton3D
	var skin: Skin = mi.skin
	if src == null or skel == null:
		return null
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(s)
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null or arr[Mesh.ARRAY_BONES] == null:
			return null   # headless/dummy renderer keeps no mesh data
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(verts.size(), 1)
		var region_of_bind := {}
		var cols := PackedColorArray()
		cols.resize(verts.size())
		for v in verts.size():
			var best := 0
			var bw := -1.0
			for k in per:
				if weights[v * per + k] > bw:
					bw = weights[v * per + k]
					best = bones[v * per + k]
			if not region_of_bind.has(best):
				var bname := ""
				if skin and best < skin.get_bind_count():
					bname = str(skin.get_bind_name(best))
					if bname == "" and skin.get_bind_bone(best) >= 0:
						bname = skel.get_bone_name(skin.get_bind_bone(best))
				else:
					bname = skel.get_bone_name(best)
				region_of_bind[best] = _region_of(bname)
			cols[v] = Color(float(region_of_bind[best]) / 8.0, 0, 0)
		arr[Mesh.ARRAY_COLOR] = cols
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return out
