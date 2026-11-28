extends SceneTree
## Pair before/after screenshots by file name and build one side-by-side PNG per pair.
## Run headless (no renderer needed, it only uses Image):
##   godot --headless --path . -s res://tools/compare.gd -- --before=DIR --after=DIR --out=DIR
## Each compare PNG is [BEFORE | AFTER] with a grey bar over the before half and a green bar
## over the after half. Prints one line per pair:
##   PAIR <name> changed=<percent of pixels that differ> <compare path>
##   ONLY_BEFORE <name> / ONLY_AFTER <name>  (screens that exist on one side only)
## UNCHANGED means no sampled pixel differed beyond tolerance.
const GAP := 12
const BAR := 10
const BEFORE_BAR := Color(0.55, 0.58, 0.62)
const AFTER_BAR := Color(0.3, 0.85, 0.45)
const PIXEL_TOLERANCE := 0.04   # ignore llvmpipe dithering / tiny AA differences

func _initialize() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else ""
	var before := str(opts.get("before", ""))
	var after := str(opts.get("after", ""))
	var out := str(opts.get("out", ""))
	if before == "" or after == "" or out == "":
		printerr("usage: -- --before=DIR --after=DIR --out=DIR")
		quit(2)
		return
	if not DirAccess.dir_exists_absolute(out):
		var err := DirAccess.make_dir_recursive_absolute(out)
		if not DirAccess.dir_exists_absolute(out):
			var reason := err if err != OK else ERR_CANT_CREATE
			printerr("Could not create comparison directory: %s (%s)" % [out, error_string(reason)])
			quit(1)
			return
	var names := {}
	for n in _pngs(before):
		names[n] = true
	for n in _pngs(after):
		names[n] = true
	var keys := names.keys()
	keys.sort()
	for n in keys:
		var b := _load(before.path_join(n))
		var a := _load(after.path_join(n))
		if b == null:
			print("ONLY_AFTER %s" % n)
			continue
		if a == null:
			print("ONLY_BEFORE %s" % n)
			continue
		var path := out.path_join(n)
		var pct := _changed(b, a)
		var err := _side_by_side(b, a).save_png(path)
		if err != OK:
			printerr("Could not save comparison PNG: %s (%s)" % [path, error_string(err)])
			quit(1)
			return
		var status := "  UNCHANGED" if pct == 0.0 else ""
		print("PAIR %s changed=%s %s%s" % [n.get_basename(), _format_percent(pct), path, status])
	quit(0)

static func _format_percent(pct: float) -> String:
	var rounded := "%.1f%%" % pct
	return "<0.1%" if pct > 0.0 and rounded == "0.0%" else rounded

func _pngs(dir: String) -> PackedStringArray:
	var res := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			res.append(f)
	return res

func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img:
		img.convert(Image.FORMAT_RGBA8)
	return img

## Percent of pixels whose color moved more than PIXEL_TOLERANCE (sizes must match, else 100).
func _changed(b: Image, a: Image) -> float:
	if b.get_size() != a.get_size():
		return 100.0
	var diff := 0
	var step := 2   # sample every other pixel each way: same answer within 0.1%, 4x faster
	var total := 0
	for y in range(0, b.get_height(), step):
		for x in range(0, b.get_width(), step):
			total += 1
			var cb := b.get_pixel(x, y)
			var ca := a.get_pixel(x, y)
			if absf(cb.r - ca.r) > PIXEL_TOLERANCE or absf(cb.g - ca.g) > PIXEL_TOLERANCE or absf(cb.b - ca.b) > PIXEL_TOLERANCE:
				diff += 1
	return 100.0 * diff / maxi(total, 1)

func _side_by_side(b: Image, a: Image) -> Image:
	var w := b.get_width() + GAP + a.get_width()
	var h := maxi(b.get_height(), a.get_height()) + BAR
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.05, 0.07))
	img.fill_rect(Rect2i(0, 0, b.get_width(), BAR), BEFORE_BAR)
	img.fill_rect(Rect2i(b.get_width() + GAP, 0, a.get_width(), BAR), AFTER_BAR)
	img.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(0, BAR))
	img.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i(b.get_width() + GAP, BAR))
	return img
