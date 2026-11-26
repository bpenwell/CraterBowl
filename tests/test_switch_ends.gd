extends "res://tests/test_case.gd"
## C04c / #89: teams switch the goal they attack every period; field position carries
## over and the on-field end-zone cues follow the period and the offense.

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Protocol := preload("res://src/net/protocol.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const FieldArt := preload("res://src/game/art/field_art.gd")
const HeadlessMeshGuard := preload("res://src/game/headless_mesh_guard.gd")
const DT := 1.0 / 60.0
const R := Athlete.Role
const COLORS := [Color(0.95, 0.75, 0.15), Color(0.3, 0.8, 0.95)]

func _match(los: float = 25.0, quarter_length: float = 120.0) -> Match:
	var w := World.new()
	var cx := w.field.width / 2.0
	var pairs := [[R.C, 0.0, R.DL, -1.5], [R.QB, 0.0, R.LB, 0.0], [R.WR, -18.0, R.CB, -18.0], [R.WR, 18.0, R.CB, 18.0], [R.RB, 4.0, R.S, -8.0], [R.OL, -2.5, R.DL, 1.5], [R.OL, 2.5, R.S, 8.0]]
	for t in 2:
		for p in pairs:
			w.add_two_way(t, p[0], cx + p[1], p[2], cx + p[3])
	var m := Match.new(w)
	m.clock.quarter_length = quarter_length
	m.start(0, los)
	return m

func _tick(m: Match, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		m.tick(DT)
		m.world.step({}, DT)

## Run one short play that ends in a tackle at `spot` with the period clock out.
func _expire_with_tackle(m: Match, spot: float) -> Dictionary:
	m.world.snap()
	_tick(m, 0.5)
	m.clock.remaining = 0.0
	var c := m.world.carrier()
	c.position.y = spot
	m.world._whistle("tackle", {"carrier": c.id, "team": m.world.offense_team})
	return m.next_play()

func test_each_team_attacks_the_other_goal_every_quarter() -> void:
	var m := _match()
	assert_eq([m.defended_end(0), m.defended_end(1)], [0, 1], "Q1: HELIOS defends its painted end")
	var out := _expire_with_tackle(m, 28.0)
	assert_eq(out["outcome"], "quarter")
	assert_true(out.get("switch_ends", false), "Q1 -> Q2 announces the switch")
	assert_eq(m.clock.quarter, 2)
	assert_eq([m.defended_end(0), m.defended_end(1)], [1, 0], "Q2: ends switched")
	out = _expire_with_tackle(m, 31.0)
	assert_eq(out["outcome"], "halftime")
	assert_true(out.get("switch_ends", false), "Q2 -> Q3 announces the switch")
	assert_eq(m.clock.quarter, 3)
	assert_eq([m.defended_end(0), m.defended_end(1)], [0, 1], "Q3: back to the opening ends")
	m.clock.remaining = 0.1
	m.clock.play_clock = 0.1
	m.clock.running_between_plays = true
	m.tick(0.2)
	assert_eq(m.last_outcome["outcome"], "quarter")
	assert_true(m.last_outcome.get("switch_ends", false), "Q3 -> Q4 between snaps announces it")
	assert_eq(m.clock.quarter, 4)
	assert_eq([m.defended_end(0), m.defended_end(1)], [1, 0], "Q4: ends switched again")

## #130: a zero quarter length was the old halves format; it now plays default quarters.
func test_legacy_halves_length_still_switches_every_quarter() -> void:
	var m := _match(25.0, 0.0)
	assert_eq(m.clock.label(), "Q1 2:30")
	assert_true(not m.ends_switched(), "Q1 opening ends")
	var out := _expire_with_tackle(m, 28.0)
	assert_eq(out["outcome"], "quarter", "the first period ends at Q1, not at halftime")
	assert_true(out.get("switch_ends", false))
	assert_eq(m.clock.half, 1)
	assert_true(m.ends_switched(), "Q2 ends switched")
	assert_eq(m.defended_end(0), 1)

func test_switch_preserves_field_position_down_and_possession() -> void:
	var m := _match(40.0)
	m.world.snap()
	_tick(m, 0.5)
	var c := m.world.carrier()
	c.position.y = 44.0
	m.world._whistle("tackle", {"carrier": c.id, "team": 0})
	m.next_play()   # 2nd & 6 at the 44
	var out := _expire_with_tackle(m, 47.0)
	assert_eq(out["outcome"], "quarter")
	assert_eq(m.downs.offense_team, 0, "same offense")
	assert_eq(m.world.offense_team, 0)
	assert_eq(m.downs.down, 3, "down carries over")
	assert_near(m.downs.los, 47.0, 0.001, "spot carries over (offense-relative yards)")
	assert_near(m.world.los_y, 47.0, 0.001, "lined up at the same spot")
	assert_near(m.downs.first_down_y, 50.0, 0.001, "line to gain carries over")
	assert_eq(m.defended_end(0), 1, "but HELIOS now defends the other end")

func test_client_derives_the_same_ends_from_the_snapshot() -> void:
	var host := _match()
	_expire_with_tackle(host, 28.0)
	var client := _match()
	assert_true(not client.ends_switched())
	Protocol.apply_snapshot(client, Protocol.encode_snapshot(host, 10))
	assert_eq(client.defended_end(0), host.defended_end(0))
	assert_true(client.ends_switched(), "client sees Q2 switched ends")

## The nodes FieldArt.build names (Turf + EndZoneName0/1), without the meshes the
## headless dummy renderer complains about. The Label3Ds still own a mesh: free the tree
## with HeadlessMeshGuard.free_node (#179).
func _field_nodes() -> Node3D:
	var root := Node3D.new()
	var turf := GeometryInstance3D.new()   # stands in for the turf MeshInstance3D
	turf.name = "Turf"
	var tm := ShaderMaterial.new()
	tm.shader = load("res://src/game/art/turf.gdshader")
	tm.set_shader_parameter("home_color", COLORS[0])
	tm.set_shader_parameter("away_color", COLORS[1])
	turf.material_override = tm
	root.add_child(turf)
	for i in 2:
		var l := Label3D.new()
		l.name = "EndZoneName%d" % i
		l.text = ["HELIOS", "NEBULA"][i]
		root.add_child(l)
	return root

func test_end_zone_cues_follow_offense_and_period() -> void:
	var m := _match()
	var root := _field_nodes()
	var near := root.get_node("EndZoneName0") as Label3D
	var far := root.get_node("EndZoneName1") as Label3D
	var tm := (root.get_node("Turf") as GeometryInstance3D).material_override as ShaderMaterial
	assert_eq(near.text, "HELIOS", "built: HELIOS behind the offense")
	# Q2, HELIOS on offense: it now defends the NEBULA-painted end.
	_expire_with_tackle(m, 28.0)
	FieldArt.orient_ends(root, m.defended_end(m.world.offense_team), COLORS)
	assert_eq([near.text, far.text], ["NEBULA", "HELIOS"], "Q2 cues switched")
	assert_eq(tm.get_shader_parameter("home_color"), COLORS[1], "near end zone tinted NEBULA")
	assert_eq(tm.get_shader_parameter("away_color"), COLORS[0])
	# Same period, NEBULA on offense: the end behind it is the HELIOS end.
	FieldArt.orient_ends(root, m.defended_end(1), COLORS)
	assert_eq([near.text, far.text], ["HELIOS", "NEBULA"], "cues follow possession too (#93)")
	HeadlessMeshGuard.free_node(root)   # plain free() logs mesh_storage.h "m" is null (#179)
