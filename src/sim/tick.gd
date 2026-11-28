extends RefCounted
## The fixed simulation tick rate: the one source for it (#61). Pure, Node-free.
## project.godot sets `physics/common/physics_ticks_per_second` to RATE explicitly, and everything
## that converts ticks to seconds (interpolator, replay, snapshots, world) derives from here.
## tests/test_tick.gd fails if project.godot, the engine or a derived site disagrees.

const RATE := 60              # sim ticks per second
const HZ := float(RATE)       # same, as a float, for tick <-> seconds conversions
const DT := 1.0 / HZ          # seconds per tick
