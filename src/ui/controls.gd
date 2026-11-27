extends RefCounted
## Controls: action table, rebinding and gamepad support as a translation layer.
## The match code reads fixed default keys (main.gd); the Launch autoload turns the
## player's bound key / gamepad input into those default key events. Pure + testable.

## [action id, label, default key]. Gridiron layout (#138): WASD, Q/E spin, F dive,
## R dash, T timeout, C taunt; next play moved off R to Enter.
const ACTIONS := [
	["move_up", "Move up", KEY_W], ["move_down", "Move down", KEY_S],
	["move_left", "Move left", KEY_A], ["move_right", "Move right", KEY_D],
	["sprint", "Sprint", KEY_SHIFT], ["snap", "Snap / break stance (defense: double-tap) / fair catch", KEY_SPACE],
	["throw", "Throw (QB: hold to charge)", KEY_J], ["lob", "Lob modifier", KEY_CTRL],
	["tackle", "Dive / tackle (pre-snap: cycle route)", KEY_F],
	["spin_left", "Spin left (pre-snap: play picker)", KEY_Q], ["spin_right", "Spin right", KEY_E],
	["dash", "Dash (when charged)", KEY_R], ["handoff", "Handoff", KEY_G], ["timeout", "Team timeout", KEY_T],
	["taunt", "Taunt wheel (hold, drag, release)", KEY_C],
	["scoreboard", "Show scoreboard (hold)", KEY_TAB],
	["next", "Next play", KEY_ENTER], ["replay", "Instant replay", KEY_V],
	["try1", "Extra point / toss: receive", KEY_1], ["try2", "Two-point try / toss: kick", KEY_2],
]
## Pause -> Controls page (#134): a few short sections per tab, each row [label, keys, tooltip].
## A key is an action id (shown as the player's bound key, or its pad input on the Gamepad tab),
## "@Text" (a fixed input: mouse buttons, sticks, the K kick call) or "+text" (plain text after
## the chips). Context that used to sit in parentheses lives in the tooltip.
const PAGE_KEYBOARD := [
	["Move", [
		["Move", ["move_up", "move_left", "move_down", "move_right"], "Relative to the camera; for the passer, to the aim"],
		["Sprint", ["sprint"], "Hold to run faster"],
		["Spin", ["spin_left", "spin_right"], "Live play: spin left / right, sheds a block"],
		["Dash", ["dash"], "Burst forward when a move charge is full"],
		["Dive / tackle", ["tackle"], "Tackle on defense; with the ball, dive for yards"],
	]],
	["Ball", [
		["Aim / look", ["@Mouse"], "Passer: look higher to throw higher"],
		["Snap", ["snap"], "Starts the play (offense)"],
		["Throw", ["@L-Click", "throw"], "Passer: hold to charge distance, release to throw"],
		["Handoff", ["handoff"], ""],
		["Block", ["@R-Click"], "Hold to block"],
	]],
	["Game", [
		["Timeout", ["timeout"], "Team timeout, outside live play"],
		["Taunt", ["taunt"], "Hold, drag to a taunt, release. Tap repeats your last one"],
		["Scoreboard", ["scoreboard"], "Hold to show"],
		["Replay", ["replay"], "Instant replay; its controls show on screen"],
		["Next play", ["next"], "After the whistle: skip the wait"],
	]],
]
const PAGE_MORE := [
	["Before the snap", [
		["Play picker", ["spin_left"], "Open / close the play picker"],
		["Cycle route", ["tackle"], "Pick your next route"],
		["Look around", ["@Middle drag"], "Orbit the camera before the snap"],
		["Break stance", ["snap", "+x2"], "Defense: double-tap to leave your stance early"],
	]],
	["Kicks and tries", [
		["Fair catch", ["snap"], "Returner: signal before the ball lands"],
		["Kick call", ["@K"], "Kicking team: cycle the kick play"],
		["Extra point", ["try1"], "After a touchdown. Coin toss: receive"],
		["Two-point try", ["try2"], "After a touchdown. Coin toss: kick"],
	]],
	["Passing", [
		["Lob", ["lob"], "Hold while releasing a pass for a high arc"],
	]],
]
const PAGE_GAMEPAD := [
	["Move", [
		["Move", ["@L-Stick"], ""], ["Sprint", ["sprint"], ""], ["Spin", ["spin_left", "spin_right"], ""],
		["Dash", ["dash"], ""], ["Dive / tackle", ["tackle"], ""],
	]],
	["Ball", [
		["Aim", ["@R-Stick"], "Passer aim"], ["Snap", ["snap"], ""], ["Throw", ["throw"], ""],
		["Lob", ["lob"], ""], ["Handoff", ["handoff"], ""],
	]],
	["Game", [
		["Scoreboard", ["scoreboard"], ""], ["Replay", ["replay"], ""], ["Next play", ["next"], ""],
		["Extra point", ["try1"], "Coin toss: receive"], ["Two-point try", ["try2"], "Coin toss: kick"],
		["Menu", ["@Start"], ""],
	]],
]
## Short pad names for the Gamepad tab (SDL/Xbox layout).
const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_BACK: "Back", JOY_BUTTON_DPAD_UP: "D-Up",
	JOY_BUTTON_DPAD_DOWN: "D-Down", JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
}
const PAD_TRIGGER_NAMES := {JOY_AXIS_TRIGGER_RIGHT: "RT", JOY_AXIS_TRIGGER_LEFT: "LT"}
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

## Saved bindings are stored as overrides of the default keys, so a default change
## needs a migration. Version 1 = before #138 (C dash, U timeout, T taunt, R next).
const BINDINGS_VERSION := 2
const V1_DEFAULTS := {"dash": KEY_C, "timeout": KEY_U, "taunt": KEY_T, "next": KEY_R}

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

## Bring bindings saved under an older default layout up to BINDINGS_VERSION.
## Actions the player never rebound take the new defaults; rebound actions keep their key.
## If a rebound key sits on one of the new defaults (e.g. the player moved dash to R,
## which swapped next play onto C), the moved actions keep their old keys instead, so
## the player's layout stays exactly as it was and no two actions share a key.
static func migrate_bindings(bindings: Dictionary, from_version: int) -> Dictionary:
	if from_version >= BINDINGS_VERSION:
		return bindings
	var out := {}
	for a in bindings:
		out[a] = int(bindings[a])
	var taken := {}
	for a in out:
		taken[out[a]] = true
	var clash := false
	for a in V1_DEFAULTS:
		if not out.has(a) and taken.has(default_key(a)):
			clash = true
	if clash:
		for a in V1_DEFAULTS:
			if not out.has(a):
				out[a] = V1_DEFAULTS[a]
	for a in out.keys():
		if out[a] == default_key(a):
			out.erase(a)
	return out

## Movement keys the left stick holds down for a given stick vector.
static func stick_keys(v: Vector2) -> Dictionary:
	return {KEY_W: v.y < -STICK_DEADZONE, KEY_S: v.y > STICK_DEADZONE,
		KEY_A: v.x < -STICK_DEADZONE, KEY_D: v.x > STICK_DEADZONE}

static func key_name(k: int) -> String:
	return "None" if k == KEY_NONE else OS.get_keycode_string(k)

## Gamepad inputs that act as an action (triggers first: RT throw reads better than nothing).
static func pad_inputs(action: String) -> Array:
	var out := []
	for axis in PAD_TRIGGERS:
		if PAD_TRIGGERS[axis] == action:
			out.append(PAD_TRIGGER_NAMES[axis])
	for button in PAD_BUTTONS:
		if PAD_BUTTONS[button] == action:
			out.append(PAD_NAMES[button])
	return out

## A Controls page resolved for display: [[heading, [{label, keys, note, tip}, ...]], ...].
## keys are chip texts: bound keys (keyboard pages, so rebinds show) or pad inputs (gamepad).
static func page(which: String, bindings: Dictionary) -> Array:
	var src: Array = {"keyboard": PAGE_KEYBOARD, "more": PAGE_MORE, "gamepad": PAGE_GAMEPAD}[which]
	var out := []
	for section in src:
		var rows := []
		for r in section[1]:
			var keys := []
			var note := ""
			for k in r[1]:
				if k.begins_with("@"):
					keys.append(k.substr(1))
				elif k.begins_with("+"):
					note = k.substr(1)
				elif which == "gamepad":
					keys.append_array(pad_inputs(k))
				else:
					keys.append(key_name(key_for(k, bindings)))
			rows.append({"label": r[0], "keys": keys, "note": note, "tip": r[2]})
		out.append([section[0], rows])
	return out

## Plain-text form of the Keyboard and More pages (bound keys).
static func help_text(bindings: Dictionary) -> String:
	var lines := []
	for which in ["keyboard", "more"]:
		for section in page(which, bindings):
			lines.append(str(section[0]).to_upper())
			for r in section[1]:
				lines.append("  %-14s %s%s" % [r["label"], " / ".join(r["keys"]), (" " + r["note"]) if r["note"] != "" else ""])
	return "\n".join(lines)
