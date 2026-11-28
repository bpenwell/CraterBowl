extends RefCounted
## The team roster (#233, part of #132): original fictional clubs of the lunar league.
## Pure data, no engine calls: views load the logo PNG through
## `src/game/art/team_logos.gd`. Names, codes and marks are made up for Crater Bowl and
## must never copy a real pro or college team (ASSETS.md logs where the logo art came from).
##
## Usage: `Teams.team("helios")` → {id, name, code, primary, secondary, logo}.
## `Teams.default_team(0)` is the team a seat plays as until a team picker (#234) exists.

const HELIOS := {
	"id": "helios", "name": "HELIOS", "code": "HEL",
	"primary": Color(0.95, 0.75, 0.15), "secondary": Color(0.10, 0.13, 0.28),
	"logo": "res://assets/teams/helios.png",
}
const NEBULA := {
	"id": "nebula", "name": "NEBULA", "code": "NEB",
	"primary": Color(0.3, 0.8, 0.95), "secondary": Color(0.42, 0.24, 0.70),
	"logo": "res://assets/teams/nebula.png",
}

## Every team in the league, HELIOS and NEBULA first (the default matchup).
const ROSTER := [
	HELIOS,
	NEBULA,
	{"id": "eclipse", "name": "ECLIPSE", "code": "ECL",
		"primary": Color(0.86, 0.16, 0.24), "secondary": Color(0.08, 0.08, 0.10),
		"logo": "res://assets/teams/eclipse.png"},
	{"id": "regolith", "name": "REGOLITH", "code": "REG",
		"primary": Color(0.90, 0.42, 0.16), "secondary": Color(0.30, 0.32, 0.36),
		"logo": "res://assets/teams/regolith.png"},
	{"id": "selene", "name": "SELENE", "code": "SEL",
		"primary": Color(0.80, 0.84, 0.90), "secondary": Color(0.16, 0.30, 0.75),
		"logo": "res://assets/teams/selene.png"},
	{"id": "apogee", "name": "APOGEE", "code": "APG",
		"primary": Color(0.55, 0.88, 0.25), "secondary": Color(0.05, 0.28, 0.30),
		"logo": "res://assets/teams/apogee.png"},
	{"id": "quasar", "name": "QUASAR", "code": "QSR",
		"primary": Color(0.92, 0.25, 0.75), "secondary": Color(0.12, 0.10, 0.30),
		"logo": "res://assets/teams/quasar.png"},
	{"id": "tycho", "name": "TYCHO", "code": "TYC",
		"primary": Color(0.50, 0.30, 0.85), "secondary": Color(0.55, 0.95, 0.80),
		"logo": "res://assets/teams/tycho.png"},
]

## The matchup every match uses today: team 0 = HELIOS, team 1 = NEBULA.
const DEFAULT_IDS := ["helios", "nebula"]

static func ids() -> Array:
	var out := []
	for t in ROSTER:
		out.append(t["id"])
	return out

## The team with this id, or {} if there is none.
static func team(id: String) -> Dictionary:
	for t in ROSTER:
		if t["id"] == id:
			return t
	return {}

## The team a side (0 or 1) plays as by default.
static func default_team(side: int) -> Dictionary:
	return team(DEFAULT_IDS[clampi(side, 0, 1)])
