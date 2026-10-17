extends RefCounted

## S display token; no HP, attack, collision, lifetime clock or resource.
var _owner := OS.get_thread_caller_id()
var _presentation: RefCounted
var visual_id := 0
var profile: Dictionary
var setup_payload: Dictionary
var is_cell := false
var _entered := false
var duration := 0.0

func configure(presentation: RefCounted, id: int, source_profile: Dictionary, cell := false) -> bool:
	if _presentation != null or presentation == null or id <= 0 or OS.get_thread_caller_id() != _owner: return false
	_presentation = presentation
	visual_id = id
	profile = source_profile.duplicate(true)
	is_cell = cell
	return true

func setup(position: Vector2, skill: String, radius: float, lifetime: float, direction: Vector2,
	target: Object = null, phase := "", geometry: Dictionary = {}) -> void:
	assert(OS.get_thread_caller_id() == _owner and not is_cell and not _entered)
	setup_payload = _presentation.capture_visual_setup(self, position, skill, radius, lifetime, direction, target, phase, geometry)

func refresh_lifetime(value: float) -> void:
	assert(OS.get_thread_caller_id() == _owner and is_cell)
	duration = maxf(0.1, value)
	_presentation.refresh_fire_wall_cell(self, duration)

func owner_thread_id() -> int: return _owner
