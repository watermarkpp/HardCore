extends RefCounted

## Pinned Godot 4.7 scene/main/timer.cpp numerical Node Timer. The world
## callback scheduler supplies the original INTERNAL H/P slot and delta.
## This is independent of the Host-owned SceneTreeTimer list checkpoints.
signal timeout
const TIMER_PROCESS_PHYSICS := 0
const TIMER_PROCESS_IDLE := 1
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _scope: RefCounted
var _service_id := 0
var _wait_time := 1.0
var wait_time: float:
	get: return _wait_time
	set(value): set_wait_time(value)
var one_shot := false
var autostart := false
var _processing := false
var _paused := false
var paused: bool:
	get: return _paused
	set(value): set_paused(value)
var ignore_time_scale := false
var _time_left := -1.0
var _process_callback := TIMER_PROCESS_IDLE
var process_callback: int:
	get: return _process_callback
	set(value): set_timer_process_callback(value)

func configure_owner(world: RefCounted, service_id: int, scope: RefCounted) -> bool:
	if _world != null or _owner == OS.get_main_thread_id() or service_id <= 0 or scope.owner_thread_id() != _owner: return false
	_world = weakref(world)
	_service_id = service_id
	_scope = scope
	return true
func owner_thread_id() -> int: return _owner
func runtime_service_id() -> int: return _service_id
func is_inside_world() -> bool: return _scope.is_inside_world()
func is_queued_for_retirement() -> bool: return _scope.is_queued_for_retirement()
func set_wait_time(value: float) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if value <= 0.0:
		_world.get_ref().fault("original_timer_wait_time_rejected", {"time": value})
		return
	_wait_time = value
func get_wait_time() -> float: return _wait_time
func start(value := -1.0) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if not is_inside_world():
		_world.get_ref().fault("original_node_timer_start_outside_tree", {"service_id": _service_id})
		return
	if value > 0.0: set_wait_time(value)
	_time_left = _wait_time
	_set_process(true)
func stop() -> void:
	_time_left = -1.0
	_set_process(false)
	autostart = false
func set_paused(value: bool) -> void:
	if _paused == value: return
	_paused = value
	_set_process(_processing)
func get_time_left() -> float: return _time_left if _time_left > 0.0 else 0.0
func is_stopped() -> bool: return get_time_left() <= 0.0
func set_timer_process_callback(value: int) -> void:
	if _process_callback == value: return
	assert(value in [TIMER_PROCESS_PHYSICS, TIMER_PROCESS_IDLE])
	# Exact original internal-notification enable transition, including pause.
	if _process_callback == TIMER_PROCESS_PHYSICS and _scope.physics_processing_enabled:
		_scope.physics_processing_enabled = false
		_scope.process_processing_enabled = true
	elif _process_callback == TIMER_PROCESS_IDLE and _scope.process_processing_enabled:
		_scope.process_processing_enabled = false
		_scope.physics_processing_enabled = true
	_process_callback = value
func _set_process(value: bool) -> void:
	if _process_callback == TIMER_PROCESS_PHYSICS: _scope.physics_processing_enabled = value and not _paused
	else: _scope.process_processing_enabled = value and not _paused
	_processing = value
func original_ready() -> void:
	if autostart:
		start()
		autostart = false
func original_internal_physics(delta: float) -> void:
	if not _processing or _process_callback == TIMER_PROCESS_IDLE or not _scope.physics_processing_enabled: return
	_original_timeout_update(delta)
func original_internal_process(delta: float) -> void:
	if not _processing or _process_callback == TIMER_PROCESS_PHYSICS or not _scope.process_processing_enabled: return
	_original_timeout_update(delta)
func _original_timeout_update(delta: float) -> void:
	if ignore_time_scale:
		var frame: Dictionary = _world.get_ref().current_clock_frame()
		assert(frame.has("unscaled_timer_delta"), "actual Engine process step is required")
		_time_left -= float(frame.unscaled_timer_delta)
	else: _time_left -= delta
	if _time_left < 0.0:
		if not one_shot: _time_left += _wait_time
		else: stop()
		timeout.emit()
func retire() -> void: stop()
