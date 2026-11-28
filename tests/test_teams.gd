extends "res://tests/test_case.gd"
## #233 (part of #132): the original team roster, its logo art, and the overlay showing it.

const Teams := preload("res://src/sim/teams.gd")
const TeamLogos := preload("res://src/game/art/team_logos.gd")
const Overlay := preload("res://src/game/overlay.gd")
const Potg := preload("res://src/sim/potg.gd")
const FieldArt := preload("res://src/game/art/field_art.gd")

## Real pro/college nicknames a lunar/space theme could stumble into. Ours must not match.
const REAL_NAMES := ["ROCKETS", "ASTROS", "COMETS", "GALAXY", "SUNS", "SUN", "STARS", "JETS",
	"TITANS", "METEORS", "LIGHTNING", "THUNDER", "SKY", "SOLAR", "ORBIT", "MOONS", "SATELLITES"]

func test_roster_has_eight_unique_original_teams() -> void:
	assert_true(Teams.ROSTER.size() >= 8, "at least 8 teams (%d)" % Teams.ROSTER.size())
	var ids := {}
	var names := {}
	var codes := {}
	var re := RegEx.create_from_string("^[A-Z]{3}$")
	for t in Teams.ROSTER:
		for key in ["id", "name", "code", "primary", "secondary", "logo"]:
			assert_true(t.has(key), "%s has %s" % [t.get("id", "?"), key])
		ids[t["id"]] = true
		names[t["name"]] = true
		codes[t["code"]] = true
		assert_true(re.search(t["code"]) != null, "%s code is 3 capital letters (%s)" % [t["id"], t["code"]])
		assert_true(t["primary"] is Color and t["secondary"] is Color, "%s colors are Colors" % t["id"])
		assert_true(not REAL_NAMES.has(t["name"]), "%s is not a real team nickname" % t["name"])
		assert_eq(Teams.team(t["id"]), t, "lookup by id")
	assert_eq(ids.size(), Teams.ROSTER.size(), "ids unique")
	assert_eq(names.size(), Teams.ROSTER.size(), "names unique")
	assert_eq(codes.size(), Teams.ROSTER.size(), "codes unique")
	assert_eq(Teams.ids().size(), Teams.ROSTER.size(), "ids() lists every team")
	assert_eq(Teams.team("no-such-team"), {}, "unknown id → {}")

func test_every_logo_loads_as_a_square_transparent_png() -> void:
	for t in Teams.ROSTER:
		var tex := TeamLogos.logo(t["id"])
		assert_true(tex != null, "%s logo texture loads (%s)" % [t["id"], t["logo"]])
		assert_true(TeamLogos.logo(t["id"]) == tex, "%s logo is cached (one texture shared by every view)" % t["id"])
		# The source PNG: 512 px square with a transparent background (corners clear).
		var img := Image.load_from_file(ProjectSettings.globalize_path(t["logo"]))
		assert_true(img != null and not img.is_empty(), "%s PNG decodes" % t["id"])
		if img == null or img.is_empty():
			continue
		assert_eq(img.get_size(), Vector2i(512, 512), "%s logo is 512 px" % t["id"])
		for c in [Vector2i(2, 2), Vector2i(509, 2), Vector2i(2, 509), Vector2i(509, 509)]:
			assert_true(img.get_pixelv(c).a < 0.05, "%s corner %s is transparent" % [t["id"], c])
		# ...and the emblem actually fills the middle.
		assert_true(img.get_pixel(256, 256).a > 0.9, "%s has an opaque emblem in the center" % t["id"])
	assert_eq(TeamLogos.logo("no-such-team"), null, "unknown id → no texture")

func test_logos_import_with_mipmaps() -> void:
	# Drawn at 34 px on the scorebug from 512 px: without mipmaps it shimmers.
	for t in Teams.ROSTER:
		var cfg := ConfigFile.new()
		assert_eq(cfg.load(t["logo"] + ".import"), OK, "%s .import is committed" % t["id"])
		assert_eq(cfg.get_value("params", "mipmaps/generate", false), true, "%s imports with mipmaps" % t["id"])

func test_defaults_are_unchanged() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	for side in 2:
		var t := Teams.default_team(side)
		assert_eq(t["name"], ["HELIOS", "NEBULA"][side], "team %d is still %s" % [side, t["name"]])
		assert_eq(t["code"], ["HEL", "NEB"][side], "team %d code" % side)
		assert_eq(t["primary"], main.TEAM_COLORS[side], "team %d primary is the uniform/HUD color" % side)
		# Places that still hard-code the names (#234 moves them to Teams) agree with the roster.
		assert_eq(Potg.TEAM_NAMES[side], t["name"], "potg names agree")
		assert_eq(FieldArt.TEAM_NAMES[side], t["name"], "end-zone names agree")
	main.free()

func test_overlay_shows_team_logos_on_scorebug_and_board() -> void:
	var o = Overlay.new()
	o._ready()
	for side in 2:
		var id: String = Teams.DEFAULT_IDS[side]
		assert_eq(o.TEAM_NAMES[side], Teams.default_team(side)["name"], "overlay name from Teams")
		assert_eq(o.TEAM_ABBR[side], Teams.default_team(side)["code"], "overlay code from Teams")
		assert_true(o.team_logo[side].texture != null and o.team_logo[side].texture == TeamLogos.logo(id), "scorebug logo %d is %s" % [side, id])
		assert_true(o.board_logo[side].texture == TeamLogos.logo(id), "Tab board logo %d is %s" % [side, id])
		assert_true(o.bug.is_ancestor_of(o.team_logo[side]), "logo %d sits in the scorebug" % side)
		assert_true(o.scoreboard.is_ancestor_of(o.board_logo[side]), "logo %d sits on the Tab board" % side)
	# The picker (#234) can swap teams; an unknown id leaves that side alone.
	o.set_teams(["eclipse", "bogus"])
	assert_true(o.team_logo[0].texture == TeamLogos.logo("eclipse") and o.board_logo[0].texture == TeamLogos.logo("eclipse"), "set_teams swaps team 0's logos")
	assert_eq([o.TEAM_NAMES[0], o.TEAM_ABBR[0], o._abbr_l[0].text], ["ECLIPSE", "ECL", "ECL"], "set_teams swaps team 0's name and code")
	assert_eq([o.team_ids[1], o.TEAM_ABBR[1]], ["nebula", "NEB"], "unknown id keeps NEBULA")
	o.free()
