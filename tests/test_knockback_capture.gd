extends "res://tests/test_case.gd"
## #428: the root capture can have more pixels than the logical canvas has units.

const KnockbackCapture := preload("res://tests/visual/knockback_cull_test.gd")
const LOGICAL_SIZE := Vector2(1280, 720)
const BOTTOM_RIGHT_CELL := Rect2(960, 360, 320, 360)

func test_capture_cells_at_native_and_double_resolution() -> void:
	assert_eq(KnockbackCapture.image_rect(BOTTOM_RIGHT_CELL, LOGICAL_SIZE, Vector2i(1280, 720)),
		Rect2i(960, 360, 320, 360), "native resolution retains the logical region")
	assert_eq(KnockbackCapture.image_rect(BOTTOM_RIGHT_CELL, LOGICAL_SIZE, Vector2i(2560, 1440)),
		Rect2i(1920, 720, 640, 720), "2x sampling reaches the last cell")

func test_capture_cells_round_and_clip_fractional_pixels() -> void:
	assert_eq(KnockbackCapture.image_rect(BOTTOM_RIGHT_CELL, LOGICAL_SIZE, Vector2i(2558, 1438)),
		Rect2i(1918, 719, 640, 719), "the fractional left edge rounds down at 2558x1438")
	assert_eq(KnockbackCapture.image_rect(Rect2(960, 360, 330, 370), LOGICAL_SIZE, Vector2i(2558, 1438)),
		Rect2i(1918, 719, 640, 719), "a partially visible cell is clipped to the image")
