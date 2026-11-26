extends VBoxContainer
## Server browser widget: lists public lobbies from the matchmaker, refreshes every
## few seconds, Join buttons launch with the lobby's invite code.

const MMClient := preload("res://src/net/mm_client.gd")
const MMServer := preload("res://src/net/mm_server.gd")
const Settings := preload("res://src/ui/settings_store.gd")
const REFRESH := 3.0
const CONNECT_TIMEOUT := 4.0

var menu                      # main_menu (calls launch.start_game)
var address := ""
var client: MMClient
var rows: VBoxContainer
var info: Label
var state := "connecting"     # connecting | online | offline
var last_list: Array = []
var _t := 0.0
var _since := 0.0

func setup(m, addr: String) -> void:
	menu = m
	address = addr

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	info = Label.new()
	info.name = "BrowserInfo"
	info.text = "Looking for open matches…"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	add_child(rows)
	client = MMClient.new()
	client.name = "BrowserClient"
	add_child(client)
	var hp := Settings.split_address(address, MMServer.DEFAULT_PORT)
	client.lobbies.connect(show_list)
	client.connected.connect(func(): state = "online"; client.request_list())
	client.failed.connect(_offline)
	if client.open(hp[0], hp[1]) != OK:
		_offline()

func _offline() -> void:
	state = "offline"
	info.text = "Matchmaking is offline right now, so Quick match, Ranked and this list are unavailable. You can still host a match or join one with an invite code."

func _process(dt: float) -> void:
	_since += dt
	if state == "connecting" and _since > CONNECT_TIMEOUT:
		_offline()
	if state != "online":
		return
	_t += dt
	if _t >= REFRESH:
		_t = 0.0
		client.request_list()

func show_list(list: Array) -> void:
	last_list = list
	for c in rows.get_children():
		c.queue_free()
	info.text = "%d open match%s" % [list.size(), "" if list.size() == 1 else "es"] if not list.is_empty() \
		else "No public matches right now. Host one and tick “List publicly”."
	for e in list:
		if not (e is Dictionary):
			continue
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s   ·   %dv%d %s   ·   %d/%d%s" % [e.get("name", "Match"), e.get("size", 7), e.get("size", 7),
			"CHAOSBALL" if e.get("mode") == "chaosball" else "CLASSIC", e.get("players", 0), e.get("max", 14),
			"   ·   IN PROGRESS" if e.get("in_game", false) else ""]
		h.add_child(l)
		var b := Button.new()
		b.text = "JOIN"
		b.disabled = int(e.get("players", 0)) >= int(e.get("max", 14))
		var code := str(e.get("code", ""))
		b.pressed.connect(func(): menu.launch.start_game({"join": code}))
		h.add_child(b)
		rows.add_child(h)
