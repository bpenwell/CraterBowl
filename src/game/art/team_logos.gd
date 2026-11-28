extends RefCounted
## Team logo textures (#233), loaded once and shared by every view that shows a team:
## the scorebug, the hold-Tab board and, next, the jumbotron (#135) and lobby/overview (#235).
## Data (names, codes, colors, logo path) lives in `src/sim/teams.gd`.
##
## The PNGs are 512 px and imported with mipmaps, so draw them with
## `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` (see `rect()`): a 34 px scorebug logo sampled from
## 512 px without mipmaps shimmers.

const Teams := preload("res://src/sim/teams.gd")

static var _cache := {}

## The logo texture of team `id`, or null for an unknown id.
static func logo(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var t := Teams.team(id)
	var tex: Texture2D = load(t["logo"]) if not t.is_empty() else null
	_cache[id] = tex
	return tex

## A square TextureRect showing team `id`'s logo at `px` pixels.
static func rect(id: String, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture = logo(id)
	return r
