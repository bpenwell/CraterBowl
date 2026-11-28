extends SceneTree
## Scene-wide render budget for the real main scene (headless, GPU-independent).
## Counts what the renderer WOULD be asked to draw: visible geometry instances,
## triangles, shadow casters and distinct materials. Fails (exit 1) over budget.
##   godot --headless --path . -s res://tests/render_budget.gd [-- --size=7]
## Budgets + rationale: docs/optimization/README.md. Raise a budget only with a
## written reason in docs/optimization/LOG.md.

const RC := preload("res://src/game/render_cache.gd")

# Ratchet: current cost + ~25% headroom (measured 2026-11-25 on the CC0 rigged-athlete art,
# gfx=high crowd density). Lower these when you make things cheaper; raise only with a
# written reason in docs/optimization/LOG.md.
const MAX_TRIANGLES := 312000       # measured ~255k (14 Mannequins = 192k of it); -8k for the #159 ball
const MAX_GEOMETRY_INSTANCES := 297 # measured ~248 visible MeshInstance3D/MultiMesh/Label3D; -3 for the #159 ball
const MAX_SHADOW_CASTERS := 103     # measured 85 (2026-11-25), 82 after #159; each one is redrawn per shadow split
const MAX_MATERIALS := 169          # measured ~137 (per-athlete shader materials for team colors); -1 for the #159 ball
const MAX_SKINNED := 14             # skinned meshes = the expensive part (~8 ms each on WSL d3d12)

var _main: Node
var _frame := 0

func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	# Pin the opening coin toss: the two outcomes put different props on the field
	# (226 vs 227 instances), and a count must be the same every run (#180).
	_main.toss_seed = 1
	_main.toss_cutscene = false   # #129: budget the opening kickoff, not the cutscene (3 skinned meshes)
	root.add_child(_main)
	process_frame.connect(_tick)

func _tick() -> void:
	_frame += 1
	if _frame == 4:
		# #129: the bots pick after the coin lands now; take their pick so the kick still goes at 5.
		_main.series.choose_toss(_main.series.toss_winner, "receive")
	if _frame == 5:
		_main.world.snap()
	if _frame < 40:
		return
	var tris := 0
	var inst := 0
	var casters := 0
	var mats := {}
	var skinned := 0
	var worst := []
	for n in _walk(_main):
		if not (n is GeometryInstance3D) or not n.is_visible_in_tree():
			continue
		inst += 1
		if n is MeshInstance3D and n.skin != null or (n is MeshInstance3D and n.get_parent() is Skeleton3D):
			skinned += 1
		var t := 0
		if n is MeshInstance3D and n.mesh:
			t = int(n.mesh.get_meta("tris")) if n.mesh.has_meta("tris") else _tris(n.mesh)
			for s in n.mesh.get_surface_count() if not (n.mesh is PrimitiveMesh) else 1:
				var m = n.get_active_material(s)
				if m:
					mats[m.get_instance_id()] = true
		elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
			t = _tris(n.multimesh.mesh) * maxi(0, n.multimesh.visible_instance_count)
		if n.material_override:
			mats[n.material_override.get_instance_id()] = true
		if n.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and not (n is Label3D):
			casters += 1
		tris += t
		worst.append([t, str(n.get_path()).get_file()])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("BUDGET triangles=%d/%d instances=%d/%d shadow_casters=%d/%d materials=%d/%d skinned=%d/%d" % [
		tris, MAX_TRIANGLES, inst, MAX_GEOMETRY_INSTANCES, casters, MAX_SHADOW_CASTERS, mats.size(), MAX_MATERIALS, skinned, MAX_SKINNED])
	print("BUDGET heaviest: %s" % str(worst.slice(0, 5)))
	var ok := tris <= MAX_TRIANGLES and inst <= MAX_GEOMETRY_INSTANCES and casters <= MAX_SHADOW_CASTERS and mats.size() <= MAX_MATERIALS and skinned <= MAX_SKINNED
	print("RENDER BUDGET %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

func _tris(mesh: Mesh) -> int:
	if mesh is ImmediateMesh:
		return 0   # route lines: a few dozen line segments
	return RC.triangles(mesh)

func _walk(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
