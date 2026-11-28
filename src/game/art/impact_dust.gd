extends Node3D
## Impact dust belongs to the live field view.
const Mats := preload("res://src/game/art/materials.gd")

func follow_replay(replaying: bool) -> void:
	if visible == replaying:
		visible = not replaying

func spawn(at: Vector3, amount: int, replaying: bool) -> void:
	if replaying:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -2.5, 0)   # low lunar gravity: dust hangs
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var m := Mats.flat(Color(0.75, 0.72, 0.68, 0.55))
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	var g := Gradient.new()
	g.set_color(0, Color(0.8, 0.78, 0.74, 0.6))
	g.set_color(1, Color(0.8, 0.78, 0.74, 0.0))
	p.color_ramp = g
	p.position = at + Vector3(0, 0.3, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
