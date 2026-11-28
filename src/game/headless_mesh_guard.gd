extends Node
## Headless-only (#92, #217): stops the dummy renderer's `Parameter "m" is null`
## (mesh_storage.h:120) when an in-tree mesh node is freed.
##
## Two things combine in Godot 4.3's dummy renderer (--headless):
## 1. No dependency tracking: freeing a mesh RID doesn't tell the instances using it.
## 2. Pending instance updates (any instance_set_* since the last flush) are flushed when
##    some instance is freed, and the flush asks storage for each instance's mesh.
## A node that frees its mesh before its render instance therefore errors once per flush
## that reaches a dead mesh: a MeshInstance3D holding the last reference to its mesh (about
## 419 times in tests/menu_flow.gd), or a Label3D, which always frees its own mesh first.
## When such a node leaves the tree (before its destructor runs), this guard holds a
## MeshInstance3D's mesh until a frame after the node is gone, and for a Label3D (whose
## mesh it can't hold) flushes the pending updates right away, while the mesh is alive.
## Real renderers track dependencies and never hit this, so Launch adds this node only
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
	elif n is Label3D:
		# It has left the world, so its last pending update (the scenario change) is queued.
		# Flush it now, while the Label3D's own mesh is still alive (#217).
		RenderingServer.free_rid(RenderingServer.instance_create())

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
