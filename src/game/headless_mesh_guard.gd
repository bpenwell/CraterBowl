extends Node
## Headless-only (#92): keeps a MeshInstance3D's mesh alive until a frame after the node
## is freed.
##
## Godot 4.3's dummy renderer (--headless) has no dependency tracking. When a
## MeshInstance3D holds the last reference to its mesh, freeing the node frees the mesh
## RID first, then the render instance asks the dummy storage for that dead mesh's
## surface count. That prints `Parameter "m" is null` (mesh_storage.h:120) once per node,
## about 419 times in tests/menu_flow.gd. Holding the mesh until the instance is gone avoids
## it. Real renderers track dependencies and never hit this, so Launch adds this node only
## when the display server is headless. Rendering is untouched either way.

var _held: Array = []   # [WeakRef(node), mesh]: removed nodes whose mesh we keep alive

static func needed() -> bool:
	return DisplayServer.get_name() == "headless"

## Frees `n` and its subtree without the dummy renderer's mesh-null error (#179).
## Headless never draws, so a render instance's pending update (any instance_set_* since
## its last flush) waits until some instance is freed. Label3D frees its own mesh before
## its render instance, and freeing that instance flushes its pending update against the
## dead mesh. Freeing a throwaway instance first flushes every pending update while the
## meshes are alive. Use it for trees freed outside the scene tree (tests).
static func free_node(n: Node) -> void:
	if needed():
		RenderingServer.free_rid(RenderingServer.instance_create())
	n.free()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_removed.connect(_on_node_removed)
	set_process(false)

func _on_node_removed(n: Node) -> void:
	# The node is still intact here, even when it's leaving because it's being freed.
	if n is MeshInstance3D and n.mesh != null:
		_held.append([weakref(n), n.mesh])
		set_process(true)

func _process(_dt: float) -> void:
	# Freed (render instance gone, so dropping the mesh is safe) or back in the tree
	# (it re-registers when it leaves again): stop holding it.
	var keep: Array = []
	for e in _held:
		var n = e[0].get_ref()
		if n != null and not n.is_inside_tree():
			keep.append(e)
	_held = keep
	set_process(not _held.is_empty())
