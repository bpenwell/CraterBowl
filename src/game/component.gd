extends Node
## Base for a piece of main-scene behavior that lives in its own file instead of in main.gd.
## main.gd's switchboards (_render, _process, configure, the world/match event handlers) loop
## over registered components, so a new feature adds a component and one add_component()
## line in main._ready instead of more lines in those functions. Precedent and worked example:
## src/game/components/route_art.gd.
##
## Read game state only through `ctx` (src/game/game_context.gd), never through `main`.
## Override only the hooks you need; the defaults do nothing.

var ctx   # GameContext, set by main.add_component() before _ready

## Per physics tick, after the sim stepped and the views synced (main._render).
func on_render() -> void:
	pass

## Per rendered frame (main._process).
func on_frame(_delta: float) -> void:
	pass

## A new match was built (main.configure): world, field and views are new.
func on_configure() -> void:
	pass

func on_world_event(_name: String, _data: Dictionary) -> void:
	pass

func on_match_event(_name: String, _data: Dictionary) -> void:
	pass
