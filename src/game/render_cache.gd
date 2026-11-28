extends RefCounted
## Shared, low-poly meshes and materials for every view node.
##
## Why: Godot's PrimitiveMesh defaults are high-poly (SphereMesh = 64x32 ~4k tris,
## CapsuleMesh ~2.3k) and every `StandardMaterial3D.new()` is a separate material
## (more pipeline/state changes, no sharing). With shadows each mesh is drawn again
## per shadow split. Before this cache the 7v7 scene pushed ~568k triangles per frame.
##
## Rules (see docs/optimization/README.md):
##   - Never `XxxMesh.new()` / `StandardMaterial3D.new()` in per-entity view code; ask here.
##   - Same key -> same Resource instance, so identical colors share one material.
##   - Keep segment counts low: the art direction is low-poly / flat colors.

static var _meshes := {}
static var _mats := {}

## Budget used by tests/test_render_budget.gd (triangles per primitive kind).
const SEGMENTS := 12
const RINGS := 4

static func capsule(radius: float, height: float) -> CapsuleMesh:
	var k := "capsule:%.3f:%.3f" % [radius, height]
	if not _meshes.has(k):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = SEGMENTS
		m.rings = 2
		_meshes[k] = m
	return _meshes[k]

## segments/rings: raise only for big, glossy, close-up shapes (helmets); default is plenty
## for pads, dots and anything that is scaled small.
static func sphere(radius: float, height: float = -1.0, segments: int = SEGMENTS, rings: int = RINGS + 2) -> SphereMesh:
	var h := radius * 2.0 if height < 0.0 else height
	var k := "sphere:%.3f:%.3f:%d:%d" % [radius, h, segments, rings]
	if not _meshes.has(k):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = h
		m.radial_segments = segments
		m.rings = rings
		_meshes[k] = m
	return _meshes[k]

static func cylinder(radius: float, height: float) -> CylinderMesh:
	var k := "cyl:%.3f:%.3f" % [radius, height]
	if not _meshes.has(k):
		var m := CylinderMesh.new()
		m.top_radius = radius
		m.bottom_radius = radius
		m.height = height
		m.radial_segments = SEGMENTS
		m.rings = 1
		_meshes[k] = m
	return _meshes[k]

## Tapered cylinder (top and bottom radius differ): the kickoff tee (#68).
static func cone(top: float, bottom: float, height: float) -> CylinderMesh:
	var k := "cone:%.3f:%.3f:%.3f" % [top, bottom, height]
	if not _meshes.has(k):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = SEGMENTS
		m.rings = 1
		_meshes[k] = m
	return _meshes[k]

static func box(size: Vector3) -> BoxMesh:
	var k := "box:%s" % size
	if not _meshes.has(k):
		var m := BoxMesh.new()
		m.size = size
		_meshes[k] = m
	return _meshes[k]

static func torus(inner: float, outer: float) -> TorusMesh:
	var k := "torus:%.3f:%.3f" % [inner, outer]
	if not _meshes.has(k):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 24
		m.ring_segments = 4
		_meshes[k] = m
	return _meshes[k]

## Flat quad lying on the ground (blob shadows, rings, decals).
static func ground_quad(size: Vector2) -> QuadMesh:
	var k := "gquad:%s" % size
	if not _meshes.has(k):
		var m := QuadMesh.new()
		m.size = size
		m.orientation = PlaneMesh.FACE_Y
		_meshes[k] = m
	return _meshes[k]

## One shared material per (color, unshaded, vertex-color) combination.
static func mat(c: Color, unshaded: bool = false, vertex_color: bool = false) -> StandardMaterial3D:
	var k := "%s:%s:%s" % [c.to_html(true), unshaded, vertex_color]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if vertex_color:
			m.vertex_color_use_as_albedo = true
		_mats[k] = m
	return _mats[k]

static func material_count() -> int:
	return _mats.size()

## Triangle count of a mesh (CPU-side arrays; works headless). Used by budget tests.
static func triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	if mesh.has_meta("tris"):
		return int(mesh.get_meta("tris"))
	if mesh is PrimitiveMesh:
		var pa: Array = mesh.get_mesh_arrays()
		var pi = pa[Mesh.ARRAY_INDEX]
		return pi.size() / 3 if pi != null and pi.size() > 0 else pa[Mesh.ARRAY_VERTEX].size() / 3
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			n += idx.size() / 3
		else:
			n += arr[Mesh.ARRAY_VERTEX].size() / 3
	return n
