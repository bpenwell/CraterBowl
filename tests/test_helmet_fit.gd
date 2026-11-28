extends "res://tests/test_case.gd"
## #158: the local team's helmet sits snug on the head in every clip the view plays.
## Geometry comes from the GLBs on the CPU (GLTFDocument), because the headless dummy
## renderer keeps no mesh arrays. Poses are sampled from the real animation library and
## the cranium is skinned by hand into Head-bone space, where the helmet is rigid.

const PlayerNode := preload("res://src/game/player.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Emotes := preload("res://src/sim/emotes.gd")
const BODY_GLB := "res://assets/characters/UAL1_Standard.glb"
const HELMET_GLB := "res://assets/characters/InnersceneHelmet.glb"
## Every clip player.gd plays (run, dive, down, hit, throw, line play, celebrations), plus taunts.
const CLIPS := ["Idle", "Jog_Fwd", "Sprint", "Crouch_Idle", "Push", "u2/Idle_Shield",
	"u2/Slide_Start", "u2/Slide", "u2/LayToIdle", "u2/Hit_Knockback", "u2/OverhandThrow",
	"Dance", "Jump", "Roll", "Jump_Start", "Jump_Land"]
const SAMPLES := [0.0, 0.33, 0.67]   # fraction of each clip's length
## Helmet inside to the top of the skull: resting on the head, not perched above it.
const MAX_CROWN_GAP := 0.012
## Typical helmet-to-skull clearance over the covered cranium (padding, not a bucket).
const MAX_MEDIAN_GAP := 0.025
## Helmet-local point inside the shell's cavity; rays start here.
const SHELL_CENTER := Vector3(0.0, 0.33, -0.02)
const DIR_CELLS := 12.0

static var _cranium: Array = []   # [rest vertex, bones, weights, required, top]
static var _shell: PackedVector3Array
static var _binds: Array[Transform3D] = []   # skin bind index -> bind pose
static var _bind_bones: PackedInt32Array      # skin bind index -> skeleton bone

func test_helmet_follows_the_head_bone() -> void:
	var v = _view(false)
	var ba := _bone_attachment(v._open_helmet)
	assert_true(ba != null, "helmet hangs under a BoneAttachment3D")
	if ba:
		assert_eq(ba.bone_name, "Head", "helmet bone")
		assert_true(ba.get_parent() == v.mesh_i.get_parent(), "attached to the body's own skeleton")
	assert_true(v._open_helmet.visible, "local team wears the open helmet")
	v.set_opponent(true)
	assert_true(not v._open_helmet.visible, "opponents hide it (their uniform has its own helmet)")
	v.free()

func test_helmet_sits_snug_in_every_clip() -> void:
	var v = _view(false)
	_load_geometry(v.mesh_i.skin)
	assert_true(_cranium.size() > 150 and _shell.size() > 1000, "cranium %d verts, shell %d tris" % [_cranium.size(), _shell.size() / 3])
	var skel: Skeleton3D = v.mesh_i.get_parent()
	var head := skel.find_bone("Head")
	var to_head := _helmet_to_bone(v._open_helmet)
	var center: Vector3 = to_head * SHELL_CENTER
	var grid := _direction_grid(to_head, center)
	var clips: Array = CLIPS.duplicate()
	for e in Emotes.LIST:
		clips.append(e[2])
	var poses := 0
	for clip in clips:
		assert_true(v.anim.has_animation(clip), "clip %s exists" % clip)
		if not v.anim.has_animation(clip):
			continue
		var a: Animation = v.anim.get_animation(clip)
		for f in SAMPLES:
			var t: float = a.length * f
			_pose(skel, a, t)
			var from_skel := skel.get_bone_global_pose(head).affine_inverse()
			var binds := {}
			var pokes := 0
			var uncovered := 0
			var crown_gap := -1.0
			var gaps: Array[float] = []
			for cv in _cranium:
				var q: Vector3 = from_skel * _skin(skel, cv, binds)
				var hit := _cast(grid, center, q)
				if hit[0]:
					pokes += 1
				elif hit[1] < 0.0:
					if cv[3]:
						uncovered += 1
				elif cv[3]:
					gaps.append(hit[1])
				if cv[4]:
					crown_gap = hit[1]
			gaps.sort()
			var where := "%s @%.2fs" % [clip, t]
			assert_eq(pokes, 0, "%s: cranium vertices through the shell" % where)
			assert_eq(uncovered, 0, "%s: skull left outside the helmet" % where)
			assert_true(crown_gap >= 0.0 and crown_gap <= MAX_CROWN_GAP, "%s: crown gap %.3f (max %.3f)" % [where, crown_gap, MAX_CROWN_GAP])
			var median: float = gaps[gaps.size() / 2] if not gaps.is_empty() else 1.0
			assert_true(median <= MAX_MEDIAN_GAP, "%s: median gap %.3f (max %.3f)" % [where, median, MAX_MEDIAN_GAP])
			poses += 1
	assert_true(poses >= 60, "sampled %d poses" % poses)
	v.free()

# --- helpers ----------------------------------------------------------------

func _view(opponent: bool):
	var a = Athlete.new()
	a.role = 2
	var v = PlayerNode.new()
	v.setup(a, Color(0.8, 0.2, 0.2), null, opponent)
	v._ready()   # unit tests run before the tree processes; build the rig directly
	return v

func _bone_attachment(n: Node) -> BoneAttachment3D:
	while n != null and not n is BoneAttachment3D:
		n = n.get_parent()
	return n

## Helmet mesh space -> Head-bone space (the BoneAttachment's frame).
func _helmet_to_bone(mesh: Node3D) -> Transform3D:
	var xf := Transform3D()
	var n: Node = mesh
	while n != null and not n is BoneAttachment3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

## Set the skeleton to `anim` at time t from the clip's own tracks (no mixer, no tree).
func _pose(skel: Skeleton3D, anim: Animation, t: float) -> void:
	skel.reset_bone_poses()
	for tr in anim.get_track_count():
		var bone := skel.find_bone(anim.track_get_path(tr).get_concatenated_subnames())
		if bone < 0:
			continue
		match anim.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				skel.set_bone_pose_position(bone, anim.position_track_interpolate(tr, t))
			Animation.TYPE_ROTATION_3D:
				skel.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(tr, t))
			Animation.TYPE_SCALE_3D:
				skel.set_bone_pose_scale(bone, anim.scale_track_interpolate(tr, t))

## Linear-blend skinning of one vertex into skeleton space.
func _skin(skel: Skeleton3D, cv: Array, cache: Dictionary) -> Vector3:
	var out := Vector3.ZERO
	var bones: PackedInt32Array = cv[1]
	var weights: PackedFloat32Array = cv[2]
	for k in bones.size():
		if weights[k] <= 0.0:
			continue
		var b := bones[k]
		if not cache.has(b):
			cache[b] = skel.get_bone_global_pose(_bind_bones[b]) * _binds[b]
		out += weights[k] * ((cache[b] as Transform3D) * (cv[0] as Vector3))
	return out

## Cranium = vertices mostly skinned to Head. `required` marks the skull the helmet must
## cover (above the brow, back of the head down to the skull base), in Head-bone rest space.
func _load_geometry(skin: Skin) -> void:
	if not _cranium.is_empty():
		return
	var body := _importer_mesh(BODY_GLB)
	var skel := (load(BODY_GLB) as PackedScene).instantiate()
	var sk := skel.find_child("Skeleton3D", true, false) as Skeleton3D
	_binds.clear()
	_bind_bones.clear()
	var head_bind := -1
	for i in skin.get_bind_count():
		_binds.append(skin.get_bind_pose(i))
		_bind_bones.append(sk.find_bone(skin.get_bind_name(i)))
		if skin.get_bind_name(i) == &"Head":
			head_bind = i
	skel.free()
	var top := -1
	var top_y := -INF
	for s in body.get_surface_count():
		var arr := body.get_surface_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		for i in verts.size():
			var hw := 0.0
			for k in per:
				if bones[i * per + k] == head_bind:
					hw += weights[i * per + k]
			if hw < 0.5:
				continue
			var p: Vector3 = _binds[head_bind] * verts[i]
			var req := (p.y > 0.12 and not (p.z > 0.05 and p.y < 0.20)) or (p.y > 0.09 and p.z < -0.03)
			_cranium.append([verts[i], bones.slice(i * per, i * per + per), weights.slice(i * per, i * per + per), req, false])
			if p.y > top_y:
				top_y = p.y
				top = _cranium.size() - 1
	if top >= 0:
		_cranium[top][4] = true
	var helmet := _importer_mesh(HELMET_GLB)
	for s in helmet.get_surface_count():
		if helmet.get_surface_material(s) == null or helmet.get_surface_material(s).resource_name != "Shell":
			continue
		var arr := helmet.get_surface_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx:
			_shell.append(verts[i])

func _importer_mesh(path: String) -> ImporterMesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert_eq(doc.append_from_file(path, state), OK, "parse " + path)
	return (state.get_meshes()[0] as GLTFMesh).mesh

## Shell triangles (Head-bone space) bucketed by direction from the cavity center.
func _direction_grid(to_head: Transform3D, center: Vector3) -> Dictionary:
	var grid := {}
	for i in range(0, _shell.size(), 3):
		var tri := [to_head * _shell[i], to_head * _shell[i + 1], to_head * _shell[i + 2]]
		var keys := {}
		for p in [tri[0], tri[1], tri[2], (tri[0] + tri[1] + tri[2]) / 3.0]:
			var c := _cell(p - center)
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						keys[c + Vector3i(dx, dy, dz)] = true
		for k in keys:
			if not grid.has(k):
				grid[k] = []
			grid[k].append(tri)
	return grid

func _cell(d: Vector3) -> Vector3i:
	var u := d.normalized() * DIR_CELLS
	return Vector3i(floori(u.x), floori(u.y), floori(u.z))

## [segment center->q crosses the shell (pokes through), distance from q out to the
## shell along the same ray (-1 when the ray leaves through an opening)].
func _cast(grid: Dictionary, center: Vector3, q: Vector3) -> Array:
	var poke := false
	var gap := -1.0
	var far := center + (q - center).normalized() * 0.6
	for tri in grid.get(_cell(q - center), []):
		if Geometry3D.segment_intersects_triangle(center, q, tri[0], tri[1], tri[2]) != null:
			poke = true
		var hit = Geometry3D.segment_intersects_triangle(q, far, tri[0], tri[1], tri[2])
		if hit != null:
			var d := q.distance_to(hit)
			if gap < 0.0 or d < gap:
				gap = d
	return [poke, gap]
