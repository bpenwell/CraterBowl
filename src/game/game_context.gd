extends RefCounted
## What a main-scene component (src/game/component.gd) may read and call. It forwards to main
## because configure() swaps world/field/views/series on every new match, so a component
## must never cache them. Add a getter here when a component needs more; don't hand
## components `main` itself (that's how coin_toss.gd ended up touching 40+ of main's fields).

var _main

func _init(main) -> void:
	_main = main

var world:
	get: return _main.world
var series:
	get: return _main.series
var field:
	get: return _main.field
var views:
	get: return _main.views
var my_id: int:
	get: return _main.my_id
var controlled_id: int:
	get: return _main.controlled_id
var camera:
	get: return _main.camera
var replay_active: bool:
	get: return _main.replay_active

func in_lobby() -> bool:
	return _main.in_lobby()

func pov_active() -> bool:
	return _main.pov_active()
