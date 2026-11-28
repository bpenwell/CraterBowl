extends RefCounted
## Both uniforms use the Quaternius animation rig in PlayerView.

const CharacterArt := preload("res://src/game/art/character_art.gd")
const Mats := preload("res://src/game/art/materials.gd")
const OPEN_HELMET := preload("res://assets/characters/InnersceneHelmet.glb")
const OPPONENT := preload("res://assets/characters/OpponentUniform.glb")

## Fit of InnersceneHelmet.glb on the Quaternius head, in Head-bone space (#158).
## The GLB as built rides about 0.2 high and is ~1.8x the skull's width, so it
## perched on the crown. This scale/offset clears the crown by about 7 mm, covers
## the back of the head down to the skull base and keeps every cranium vertex
## inside the shell in every clip (tests/test_helmet_fit.gd).
const OPEN_HELMET_SCALE := 0.75
const OPEN_HELMET_OFFSET := Vector3(0.0, -0.106, -0.003)

static var _opponent_mesh: Mesh
static var _opponent_skin: Skin

## `parent` is the Head BoneAttachment3D itself (PlayerView._bone), so the fit is in
## bone-space units and moves with the head in every clip.
static func open_helmet(parent: Node3D) -> MeshInstance3D:
	var gear := OPEN_HELMET.instantiate() as Node3D
	gear.name = "OpenHelmet"
	gear.transform = Transform3D(Basis.from_scale(Vector3.ONE * OPEN_HELMET_SCALE), OPEN_HELMET_OFFSET)
	parent.add_child(gear)
	return CharacterArt.find_mesh(gear)

static func opponent_mesh(reference: MeshInstance3D) -> MeshInstance3D:
	if _opponent_mesh == null:
		var source := OPPONENT.instantiate()
		var imported := CharacterArt.find_mesh(source)
		_opponent_mesh = imported.mesh
		# Use the live rig's inverse rest transforms. Blender can round-trip the
		# joint axes differently even though the vertex positions match.
		_opponent_skin = Skin.new()
		var live_binds := {}
		for i in reference.skin.get_bind_count():
			live_binds[reference.skin.get_bind_name(i)] = reference.skin.get_bind_pose(i)
		for i in imported.skin.get_bind_count():
			var bone := imported.skin.get_bind_name(i)
			_opponent_skin.add_named_bind(bone, live_binds[bone])
		source.free()
	var mesh := MeshInstance3D.new()
	mesh.name = "OpponentUniform"
	mesh.mesh = _opponent_mesh
	mesh.skin = _opponent_skin
	mesh.skeleton = NodePath("..")
	mesh.extra_cull_margin = reference.extra_cull_margin
	reference.get_parent().add_child(mesh)
	return mesh

static func recolor(mesh: MeshInstance3D, jersey: Color, skin: Color,
		trim: Material, helmet_stripe: Material) -> void:
	for i in mesh.mesh.get_surface_count():
		var material := mesh.mesh.surface_get_material(i)
		if material == null:
			continue
		match material.resource_name:
			"Jersey":
				mesh.set_surface_override_material(i, Mats.cloth(jersey.darkened(0.13)))
			"Shell":
				mesh.set_surface_override_material(i, Mats.glossy(jersey.darkened(0.23)))
			"Trim":
				mesh.set_surface_override_material(i, trim)
			"HelmetStripe":
				mesh.set_surface_override_material(i, helmet_stripe)
			"Face":
				mesh.set_surface_override_material(i, Mats.cloth(skin))
