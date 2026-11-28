extends Control
## Timeout indicator for one team on the scorebug (#133): one rounded bar per timeout the
## match allows. Available = lit in the team color with a bright top edge; used = a hollow,
## dim outline. Replaces the 11 px "●○" text pips that read as periods at HUD scale.
## Change-driven: redraws only when the count, limit or color changes, and runs `_process`
## only while the short pulse on a just-spent timeout plays.

## Bar size and gap in canvas px (1280×720 base). Three bars span 56 px, but the meter only
## *reserves* FOOTPRINT (38 px, the narrowest team code in Teko 22, ECL/SEL) and draws the rest
## past its right edge, into the empty space under the score. So the team cell never widens and
## the scorebug keeps its fixed BUG_W (#116/#233). A 56 px footprint pushed the bug to 751 px; 10 px
## bars that fit inside 38 px read as the same dots as before (see presentation.md, #133).
const BAR := Vector2(16, 7)
const GAP := 4.0
const FOOTPRINT := 38.0
## The old 11 px pip label's line height: the bug stays exactly as tall as before. Bars sit at
## the bottom, clear of the score digits' baseline.
const HEIGHT := 14.0
const MAX_SHOWN := 3
const PULSE := 0.6   # seconds the just-used bar flashes white and shrinks back to hollow
const USED_FILL := Color(1, 1, 1, 0.07)
const USED_EDGE := Color(1, 1, 1, 0.38)

var left := -1        # timeouts remaining; -1 = not set yet (the first set never pulses)
var limit := 0
var color := Color.WHITE
var _pulse_t := 0.0
var _pulse_i := -1
var _lit := StyleBoxFlat.new()
var _used := StyleBoxFlat.new()
var _flash := StyleBoxFlat.new()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(FOOTPRINT, HEIGHT)
	for sb in [_lit, _used, _flash]:
		sb.set_corner_radius_all(int(BAR.y * 0.5))
		sb.anti_aliasing = true
	_lit.border_width_top = 2   # a bright top edge: the bar reads as lit, not flat paint
	_used.bg_color = USED_FILL
	_used.border_color = USED_EDGE
	_used.set_border_width_all(1)
	set_process(false)

## Show `remaining` of `total` timeouts in team color `c`. Cheap to call every HUD tick.
func set_state(remaining: int, total: int, c: Color) -> void:
	if remaining == left and total == limit and c == color:
		return
	if left >= 0 and total == limit and remaining < left:
		_pulse_i = remaining          # the bar that just went out (bars fill left to right)
		_pulse_t = PULSE
		set_process(true)
	left = remaining
	limit = total
	color = c
	_lit.bg_color = c
	_lit.border_color = c.lightened(0.55)
	queue_redraw()

func pulsing() -> bool:
	return _pulse_t > 0.0

## Bar `i`'s rect in local coordinates (tests use it to sample pixels).
func bar_rect(i: int) -> Rect2:
	return Rect2(Vector2(i * (BAR.x + GAP), size.y - BAR.y - 1.0), BAR)

func is_available(i: int) -> bool:
	return i < left

func _process(delta: float) -> void:
	_pulse_t = maxf(0.0, _pulse_t - delta)
	if _pulse_t == 0.0:
		_pulse_i = -1
		set_process(false)
	queue_redraw()

func _draw() -> void:
	for i in limit:
		var r := bar_rect(i)
		if i < left:
			draw_style_box(_lit, r)
		else:
			draw_style_box(_used, r)
		if i == _pulse_i and _pulse_t > 0.0:
			var k := _pulse_t / PULSE   # 1 → 0
			_flash.bg_color = Color(1, 1, 1, 0.85 * k)
			draw_style_box(_flash, r.grow(2.0 * k))
