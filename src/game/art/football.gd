extends RefCounted
## The football (#159): a pointed prolate spheroid built in code, long axis along local Z,
## laces on top (+Y). Seams, laces and stripes are drawn by football.gdshader, so the ball is
## one mesh and one draw call. The mesh is built at size: the view never needs a non-uniform
## scale (the old SphereMesh was stretched 1.75x in Z, and every pose that reset the scale to
## ONE drew a 0.3 m sphere).

## Half-length and widest radius, m. 0.44 x 0.26: ~1.6x a real ball (0.28 x 0.17), the same
## length/width ratio, kept large so the ball reads from the broadcast camera.
const HALF_LENGTH := 0.22
const RADIUS := 0.13
## Profile r(t) = RADIUS * (1 - t^2)^TIP, t = z / HALF_LENGTH. 0.5 is an ellipsoid; nearer 1
## the ends come to a point like a real ball's.
const TIP := 0.8
const SEGMENTS := 20   # around the long axis
const RINGS := 14      # tip to tip

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial

static func radius_at(z: float) -> float:
	return RADIUS * pow(maxf(0.0, 1.0 - pow(z / HALF_LENGTH, 2.0)), TIP)

static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RINGS + 1:
		var z := lerpf(-HALF_LENGTH, HALF_LENGTH, float(i) / RINGS)
		var r := radius_at(z)
		# Profile slope for the normal: dr/dz.
		var dz := 0.001
		var slope := (radius_at(clampf(z + dz, -HALF_LENGTH, HALF_LENGTH)) - radius_at(clampf(z - dz, -HALF_LENGTH, HALF_LENGTH))) / (2.0 * dz)
		for j in SEGMENTS + 1:
			var a := TAU * j / SEGMENTS
			var radial := Vector3(cos(a), sin(a), 0.0)
			var n := (radial - Vector3(0, 0, slope)).normalized() if r > 0.0 else Vector3(0, 0, signf(z))
			st.set_normal(n)
			st.set_uv(Vector2(float(j) / SEGMENTS, float(i) / RINGS))
			st.add_vertex(radial * r + Vector3(0, 0, z))
	var row := SEGMENTS + 1
	for i in RINGS:
		for j in SEGMENTS:
			var k := i * row + j
			st.add_index(k)
			st.add_index(k + row)
			st.add_index(k + 1)
			st.add_index(k + 1)
			st.add_index(k + row)
			st.add_index(k + row + 1)
	_mesh = st.commit()
	return _mesh

static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://src/game/art/football.gdshader")
		_mat.set_shader_parameter("half_length", HALF_LENGTH)
	return _mat
