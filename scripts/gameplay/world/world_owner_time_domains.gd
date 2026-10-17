extends RefCounted

## New extension simulation uses the existing world's physics delta. Existing
## fire-wall, poison, buffs and persistence deadlines retain their own clocks.
const SIMULATION := "simulation"
const MONOTONIC_WALL := "monotonic_wall"
const PERSISTENT_UNIX := "persistent_unix"
var _owner := WeakRef.new()
var _simulation_seconds := 0.0

var _owner_thread := OS.get_thread_caller_id()
func owner_thread_id() -> int: return _owner_thread
func configure_owner(owner: RefCounted, source_seconds: float) -> bool:
	if _owner_thread == OS.get_main_thread_id() or not is_finite(source_seconds) or source_seconds < 0.0: return false
	_owner = weakref(owner)
	_simulation_seconds = source_seconds
	return true

func configure(owner: RefCounted) -> void:
	_owner = weakref(owner)

func advance_simulation(delta_seconds: float) -> bool:
	assert(OS.get_thread_caller_id() == _owner_thread)
	var owner: RefCounted = _owner.get_ref()
	if not is_instance_valid(owner) or owner.is_queued_for_retirement() or not owner.is_inside_world():
		return false
	if owner.profile_world_paused() or not is_finite(delta_seconds) or delta_seconds < 0.0:
		return false
	_simulation_seconds += delta_seconds
	return true

func simulation_usec() -> int:
	# Round the accumulated time, not every small delta: 240 x 1/60 is 4s.
	return roundi(_simulation_seconds * 1000000.0)

static func monotonic_usec() -> int:
	return Time.get_ticks_usec()

static func persistent_unix_seconds() -> float:
	return Time.get_unix_time_from_system()
