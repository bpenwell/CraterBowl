extends "res://tests/test_case.gd"
## View-layer perf contracts that can be checked without a GPU.
## Scene-wide budgets (triangles, draw objects, shadow casters) live in tests/render_budget.gd.

const RC := preload("res://src/game/render_cache.gd")
const PlayerNode := preload("res://src/game/player.gd")
const CharacterArt := preload("res://src/game/art/character_art.gd")
const Uniforms := preload("res://src/game/art/football_uniforms.gd")

func test_cache_shares_meshes_and_materials() -> void:
	assert_true(RC.sphere(0.3) == RC.sphere(0.3), "same sphere key -> same mesh")
	assert_true(RC.capsule(0.4, 1.9) == RC.capsule(0.4, 1.9), "same capsule key -> same mesh")
	assert_true(RC.mat(Color.RED) == RC.mat(Color.RED), "same color -> same material")
	assert_true(RC.mat(Color.RED) != RC.mat(Color.RED, true), "unshaded is a different material")

func test_cached_primitives_are_low_poly() -> void:
	# Godot defaults: SphereMesh ~4k tris, CapsuleMesh ~2.3k. Low-poly art keeps these tiny.
	assert_true(RC.triangles(RC.sphere(0.28, 0.5)) <= 200, "sphere tris %d" % RC.triangles(RC.sphere(0.28, 0.5)))
	assert_true(RC.triangles(RC.capsule(0.4, 1.9)) <= 250, "capsule tris %d" % RC.triangles(RC.capsule(0.4, 1.9)))
	assert_true(RC.triangles(RC.torus(0.6, 0.8)) <= 300, "torus tris %d" % RC.triangles(RC.torus(0.6, 0.8)))

func test_skinned_uniforms_share_animation_cull_margin() -> void:
	var model := CharacterArt.instance()
	var local_mesh := CharacterArt.find_mesh(model)
	CharacterArt.dress_mesh(local_mesh)
	var opponent_mesh := Uniforms.opponent_mesh(local_mesh)
	assert_true(local_mesh.extra_cull_margin > 0.0, "animated home body expands its rest bounds")
	assert_eq(opponent_mesh.extra_cull_margin, local_mesh.extra_cull_margin,
		"both uniforms on the shared rig use the animation margin")
	model.free()

func test_view_interpolates_between_ticks() -> void:
	var v := PlayerNode.new()
	v.place(Vector3(10, 0, -20), 0.0)
	v.place(Vector3(10.2, 0, -20), 0.0)
	v.interpolate(0.5)
	assert_near(v.position.x, 10.1, 0.0001, "halfway between ticks")
	v.interpolate(1.0)
	assert_near(v.position.x, 10.2, 0.0001, "f=1 -> latest tick")
	assert_eq(v.target_position(), Vector3(10.2, 0, -20), "target is the latest sim pose")
	v.free()

func test_view_snaps_on_teleport() -> void:
	var v := PlayerNode.new()
	v.place(Vector3(10, 0, -20), 0.0)
	v.place(Vector3(30, 0, -60), 0.0)   # new formation: must not glide across the field
	v.interpolate(0.0)
	assert_near(v.position.x, 30.0, 0.0001, "teleport snaps")
	v.free()

func test_yaw_interpolates_the_short_way() -> void:
	var v := PlayerNode.new()
	v.place(Vector3.ZERO, PI - 0.1)
	v.place(Vector3(0.1, 0, 0), -PI + 0.1)
	v.interpolate(0.5)
	assert_true(absf(absf(v.rotation.y) - PI) < 0.01, "wraps through PI, not through 0 (%.2f)" % v.rotation.y)
	v.free()
