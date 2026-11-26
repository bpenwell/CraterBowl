extends Node
## Menu soundtrack: plays the licensed tracks listed in assets/music/tracks.json
## (see assets/music/CREDITS.md) in order, looping the playlist, and builds the
## footer "now playing" widget (prev / pause / next, title, progress).
## With no playlist (or no audio device) it stays silent and the widget hides.

const C := preload("res://src/ui/ui_theme.gd")
const PLAYLIST := "res://assets/music/tracks.json"
const BASE_DB := -7.0     # sits under UI sounds; scaled by the music-volume setting

static var resume_index := 0   # carry the playlist position across menu visits

var tracks: Array = []    # [{file, title, artist, license}]
var index := 0
var player: AudioStreamPlayer
var volume := 0.7         # 0..1 linear
var widget: Control
var _title: Label
var _time: Label
var _bar: ProgressBar
var _pause: Button
var _shown := true        # the menu hides the chip while a side panel is open (#125)

static func load_playlist(path: String = PLAYLIST) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out := []
	if d is Array:
		for t in d:
			if t is Dictionary and str(t.get("file", "")) != "":
				out.append(t)
	return out

func _ready() -> void:
	tracks = load_playlist()
	player = AudioStreamPlayer.new()
	player.finished.connect(next)
	add_child(player)
	if tracks.is_empty():
		if widget:
			widget.visible = false
		return
	index = resume_index % tracks.size()
	set_volume(volume)
	_start(index)

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	if player:
		player.volume_db = BASE_DB + linear_to_db(maxf(volume, 0.0001))
		if volume <= 0.001:
			player.volume_db = -80.0

func next() -> void:
	if not tracks.is_empty():
		_start((index + 1) % tracks.size())

func prev() -> void:
	if tracks.is_empty():
		return
	if player.get_playback_position() > 3.0:
		_start(index)   # first press restarts the song, like every music app
	else:
		_start((index - 1 + tracks.size()) % tracks.size())

func toggle_pause() -> void:
	if player.stream == null:
		return
	player.stream_paused = not player.stream_paused
	_refresh()

func current() -> Dictionary:
	return tracks[index] if index < tracks.size() else {}

func _start(i: int) -> void:
	index = i
	resume_index = i
	var t: Dictionary = tracks[i]
	var st := _load_stream(str(t["file"]))
	player.stream = st
	if st:
		player.play()
	_refresh()

static func _load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is AudioStream:
			if "loop" in r:
				r.loop = false   # playlist advances on finished
			return r
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(path)
	if path.ends_with(".mp3") and FileAccess.file_exists(path):
		var m := AudioStreamMP3.new()
		m.data = FileAccess.get_file_as_bytes(path)
		return m
	return null

func _process(_dt: float) -> void:
	if widget == null or player == null or player.stream == null:
		return
	var len := player.stream.get_length()
	var pos := player.get_playback_position()
	_time.text = "%s / %s" % [_fmt(pos), _fmt(len)]
	_bar.value = pos / len if len > 0.0 else 0.0

static func _fmt(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]

func _refresh() -> void:
	if widget == null:
		return
	var t := current()
	widget.visible = _shown and not t.is_empty()
	_title.text = "%s - %s" % [t.get("artist", ""), t.get("title", "")]
	_title.tooltip_text = "%s · %s" % [_title.text, t.get("license", "")]
	_pause.set_meta("icon", "play" if player and player.stream_paused else "pause")
	_pause.queue_redraw()

## Footer widget: [⏮] (❚❚) [⏭]  Artist - Title / progress / time
func set_widget_shown(v: bool) -> void:
	_shown = v
	if widget:
		widget.visible = _shown and not tracks.is_empty()

## True when there is a playlist to show controls for.
func widget_wanted() -> bool:
	return not tracks.is_empty()

## Compact now-playing chip: play/pause, title + progress, next (#125). Full controls are in
## Settings > Audio. Buttons keep a fixed square size (SHRINK_CENTER): stretched by the row they
## used to render as a tall capsule with a seam through it.
func build_widget() -> Control:
	var chip := PanelContainer.new()
	chip.name = "NowPlaying"
	var bg := C.box(Color(C.SPACE, 0.8), Color(C.CREAM, 0.14), 1, 22)
	bg.content_margin_left = 6
	bg.content_margin_right = 10
	bg.content_margin_top = 4
	bg.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", bg)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	chip.add_child(h)
	var mk := func(icon: String, cb: Callable, round_btn: bool) -> Button:
		var b := Button.new()
		b.name = icon.capitalize()
		b.set_meta("icon", icon)
		b.focus_mode = Control.FOCUS_NONE
		b.draw.connect(func(): _draw_icon(b))
		var d := 32 if round_btn else 26
		b.custom_minimum_size = Vector2(d, d)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = {"pause": "Pause / play", "next": "Next track", "prev": "Previous track"}.get(icon, "")
		var r := d / 2
		var mkbox := func(fill: Color, edge: Color) -> StyleBoxFlat:
			var sb := C.box(fill, edge, 1, r)
			sb.set_content_margin_all(0)
			return sb
		b.add_theme_stylebox_override("normal", mkbox.call(Color(C.CREAM, 0.1) if round_btn else Color(0, 0, 0, 0), Color(C.CREAM, 0.3) if round_btn else Color(0, 0, 0, 0)))
		b.add_theme_stylebox_override("hover", mkbox.call(Color(C.CYAN, 0.2), C.CYAN))
		b.add_theme_stylebox_override("pressed", mkbox.call(Color(C.CYAN, 0.35), C.CYAN))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(cb)
		h.add_child(b)
		return b
	_pause = mk.call("pause", toggle_pause, true)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var top := HBoxContainer.new()
	info.add_child(top)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	_title.add_theme_font_size_override("font_size", 15)
	top.add_child(_title)
	_time = Label.new()
	_time.add_theme_font_override("font", C.font(400))
	_time.add_theme_font_size_override("font_size", 13)
	_time.add_theme_color_override("font_color", Color(C.REGOLITH, 1.0))
	top.add_child(_time)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(0, 3)
	_bar.add_theme_stylebox_override("background", C.box(Color(C.CREAM, 0.15), Color(0, 0, 0, 0), 0, 2))
	var fill := C.box(C.CYAN, C.CYAN, 0, 2)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	_bar.add_theme_stylebox_override("fill", fill)
	info.add_child(_bar)
	mk.call("next", next, false)
	widget = chip
	widget.visible = _shown and not tracks.is_empty()
	_refresh()
	return chip

## Transport icons drawn as shapes (no glyph-font dependency).
static func _draw_icon(b: Button) -> void:
	var c := b.size / 2.0
	var col := C.CYAN if b.is_hovered() else C.CREAM
	var u := 5.0
	match str(b.get_meta("icon", "")):
		"play":
			b.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.8, -u * 1.2), c + Vector2(u * 1.3, 0), c + Vector2(-u * 0.8, u * 1.2)]), col)
		"pause":
			b.draw_rect(Rect2(c + Vector2(-u * 1.0, -u * 1.1), Vector2(u * 0.7, u * 2.2)), col)
			b.draw_rect(Rect2(c + Vector2(u * 0.3, -u * 1.1), Vector2(u * 0.7, u * 2.2)), col)
		"next", "prev":
			var d := 1.0 if b.get_meta("icon") == "next" else -1.0
			b.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * d, -u), c + Vector2(u * 0.6 * d, 0), c + Vector2(-u * d, u)]), col)
			b.draw_rect(Rect2(c + Vector2(u * 0.6 * d - (1.6 if d < 0 else 0.0), -u), Vector2(1.6, u * 2)), col)
