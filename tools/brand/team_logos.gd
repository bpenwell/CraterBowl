extends SceneTree
## Team logos (#233): raw image-generation PNGs -> assets/teams/<id>.png (512 px, transparent).
## The prompt that made the raw images is tools/brand/team_logos_prompt.md; ASSETS.md logs it.
##
##   godot --headless --path . -s res://tools/brand/team_logos.gd -- --src=/tmp/raw [--ids=helios,nebula]
##
## Per image: key out the flat background by flood fill from the borders (the badge's thick
## dark outline stops the fill), crop to the emblem, pad to a square with a small margin and
## resize to 512 px (Lanczos). Then run `godot --headless --path . --import`; the committed
## .import files keep `mipmaps/generate=true` (team_logos.gd in src/game draws them small).

const Teams := preload("res://src/sim/teams.gd")
const TOLERANCE := 0.16   # max per-channel distance from the corner color that counts as background
const MARGIN := 1.06      # square side = emblem size * MARGIN

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var src: String = args.get("src", "")
	var ids: Array = Array(str(args["ids"]).split(",")) if args.has("ids") else Teams.ids()
	for id in ids:
		var img := Image.load_from_file(src.path_join(id + ".png"))
		if img == null or img.is_empty():
			print("TEAM LOGO MISSING %s" % id)
			continue
		var out := process(img)
		var dest := ProjectSettings.globalize_path(Teams.team(id)["logo"])
		print("TEAM LOGO %s -> %s: %s" % [id, dest, error_string(out.save_png(dest))])
	quit()

static func process(img: Image) -> Image:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var bg := img.get_pixel(1, 1)
	if bg.a > 0.5:
		var seen := PackedByteArray()
		seen.resize(w * h)
		var stack := PackedInt32Array()
		for x in w:
			stack.append(x)
			stack.append((h - 1) * w + x)
		for y in h:
			stack.append(y * w)
			stack.append(y * w + w - 1)
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			if seen[i]:
				continue
			seen[i] = 1
			var px := i % w
			var py := i / w
			var c := img.get_pixel(px, py)
			var d := maxf(maxf(absf(c.r - bg.r), absf(c.g - bg.g)), absf(c.b - bg.b))
			if d > TOLERANCE:
				continue
			img.set_pixel(px, py, Color(c.r, c.g, c.b, 0.0))
			if px > 0:
				stack.append(i - 1)
			if px < w - 1:
				stack.append(i + 1)
			if py > 0:
				stack.append(i - w)
			if py < h - 1:
				stack.append(i + w)
		_unblend_fringe(img, bg)
	var used := img.get_used_rect()
	var side := int(maxf(used.size.x, used.size.y) * MARGIN)
	var sq := Image.create(side, side, false, Image.FORMAT_RGBA8)
	sq.fill(Color(0, 0, 0, 0))
	sq.blit_rect(img, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
	sq.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	return sq

## The anti-aliased ring between the background and the outline was blended with the
## background color. Without this it leaves a light halo on the dark HUD. For opaque pixels
## touching a cleared one: alpha from the distance to bg, color un-blended from bg.
static func _unblend_fringe(img: Image, bg: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate() as Image
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := src.get_pixel(x, y)
			if c.a == 0.0:
				continue
			if src.get_pixel(x - 1, y).a > 0.0 and src.get_pixel(x + 1, y).a > 0.0 and src.get_pixel(x, y - 1).a > 0.0 and src.get_pixel(x, y + 1).a > 0.0:
				continue
			var d := maxf(maxf(absf(c.r - bg.r), absf(c.g - bg.g)), absf(c.b - bg.b))
			var a := clampf(d / 0.7, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
				continue
			img.set_pixel(x, y, Color(
				clampf((c.r - bg.r * (1.0 - a)) / a, 0.0, 1.0),
				clampf((c.g - bg.g * (1.0 - a)) / a, 0.0, 1.0),
				clampf((c.b - bg.b * (1.0 - a)) / a, 0.0, 1.0), a))
