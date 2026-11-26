extends RefCounted
## Controls: action table, rebinding and gamepad support as a translation layer.
## The match code reads fixed default keys (main.gd); the Launch autoload turns the
## player's bound key / gamepad input into those default key events. Pure + testable.

## [action id, label, default key]
const ACTIONS := [
	["move_up", "Move up", KEY_W], ["move_down", "Move down", KEY_S],
	["move_left", "Move left", KEY_A], ["move_right", "Move right", KEY_D],
	["sprint", "Sprint", KEY_SHIFT], ["snap", "Snap / break stance", KEY_SPACE],
	["throw", "Throw (QB: hold to charge)", KEY_J], ["lob", "Lob modifier", KEY_CTRL],
	["tackle", "Dive / tackle (pre-snap: cycle route)", KEY_F],
	["spin_left", "Spin left (pre-snap: play picker)", KEY_Q], ["spin_right", "Spin right", KEY_E],
	["dash", "Dash", KEY_C], ["handoff", "Handoff", KEY_G], ["timeout", "Team timeout", KEY_U],
	["taunt", "Taunt (wheel picks)", KEY_T],
	["scoreboard", "Show scoreboard (hold)", KEY_TAB],
	["next", "Next play", KEY_R], ["replay", "Instant replay", KEY_V],
	["try1", "Extra point", KEY_1], ["try2", "Two-point try", KEY_2],
]
const OTHER_CONTROLS := [
	"Mouse: look live · middle drag: look pre-snap · wheel: pick taunt (T performs)",
	"QB / passer: mouse aims your view (look up = loft) · hold left click to charge distance, release to throw",
	"Hold right click: block",
	"Gamepad: left stick move · right stick QB aim · A snap · B dive · X / Y spin · R3 handoff · RT pass · LT sprint",
	"Replays: Space pause · , . step · ← → previous / next play · H highlights · [ ] speed · C camera",
]
const SYNTH_DEVICE := -42     # marks events we injected (never re-translated)
const STICK_DEADZONE := 0.4
const TRIGGER_ON := 0.5
## Gamepad (SDL/Xbox layout) button -> action
const PAD_BUTTONS := {
	JOY_BUTTON_A: "snap", JOY_BUTTON_B: "tackle", JOY_BUTTON_X: "spin_left", JOY_BUTTON_Y: "spin_right",
	JOY_BUTTON_LEFT_SHOULDER: "scoreboard", JOY_BUTTON_RIGHT_SHOULDER: "lob",
	JOY_BUTTON_LEFT_STICK: "sprint", JOY_BUTTON_RIGHT_STICK: "handoff", JOY_BUTTON_BACK: "replay", JOY_BUTTON_DPAD_UP: "next",
	JOY_BUTTON_DPAD_LEFT: "try1", JOY_BUTTON_DPAD_RIGHT: "try2", JOY_BUTTON_DPAD_DOWN: "dash",
}
## Gamepad trigger axis -> action (held while past TRIGGER_ON)
const PAD_TRIGGERS := {JOY_AXIS_TRIGGER_RIGHT: "throw", JOY_AXIS_TRIGGER_LEFT: "sprint"}

static func default_key(action: String) -> int:
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return KEY_NONE

static func label(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action

static func key_for(action: String, bindings: Dictionary) -> int:
	return int(bindings.get(action, default_key(action)))

## Map of pressed key -> default key it should act as. Only rebound actions appear.
## A default key that was rebound away from its action and not reused maps to KEY_NONE
## (disabled), so rebinding moves an action instead of duplicating it.
static func translation(bindings: Dictionary) -> Dictionary:
	var out := {}
	for a in ACTIONS:
		var k := key_for(a[0], bindings)
		if k != a[2]:
			out[k] = a[2]
	for a in ACTIONS:
		var k := key_for(a[0], bindings)
		if k != a[2] and not out.has(a[2]):
			out[a[2]] = KEY_NONE
	return out

## Which action (if any) a key is bound to.
static func action_for_key(key: int, bindings: Dictionary) -> String:
	for a in ACTIONS:
		if key_for(a[0], bindings) == key:
			return a[0]
	return ""

## Rebind; if another action already uses the key, the two swap keys.
static func rebind(bindings: Dictionary, action: String, key: int) -> Dictionary:
	var b := bindings.duplicate()
	var other := action_for_key(key, b)
	if other != "" and other != action:
		var mine := key_for(action, b)
		if mine == default_key(other):
			b.erase(other)
		else:
			b[other] = mine
	if key == default_key(action):
		b.erase(action)
	else:
		b[action] = key
	return b

## Movement keys the left stick holds down for a given stick vector.
static func stick_keys(v: Vector2) -> Dictionary:
	return {KEY_W: v.y < -STICK_DEADZONE, KEY_S: v.y > STICK_DEADZONE,
		KEY_A: v.x < -STICK_DEADZONE, KEY_D: v.x > STICK_DEADZONE}

static func key_name(k: int) -> String:
	return "None" if k == KEY_NONE else OS.get_keycode_string(k)

static func help_text(bindings: Dictionary) -> String:
	var lines := []
	for a in ACTIONS:
		lines.append("%-24s %s" % [a[1], key_name(key_for(a[0], bindings))])
	lines.append_array(OTHER_CONTROLS)
	return "\n".join(lines)
