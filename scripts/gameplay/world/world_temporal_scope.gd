extends RefCounted

## The single former Node qualification record. A queued object is still
## present/inside until its original exit checkpoint; these are independent.
var _owner := OS.get_thread_caller_id()
var runtime_present := true
var life_generation := 1
var inside_world := false
var queued_for_retirement := false
var parent_scope_id := 0
var can_process_value := false
var process_processing_enabled := false
var physics_processing_enabled := false
var ordinary_p_enabled := false
var raw_h_enabled := false
var physics_priority := 0
var process_priority := 0
var process_mode := 0
var exit_callbacks_complete := false
var final_free_checkpoint := false
var initialized := false
var _world_ref: WeakRef
var effective_process_mode := -1
var _original_implicit_ready_applied := false

func owner_thread_id() -> int:
	return _owner

func apply_original_implicit_ready(callbacks: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or not initialized or not runtime_present or not inside_world or _original_implicit_ready_applied: return false
	# Pinned Node::NOTIFICATION_READY enables only overridden script methods
	# before the script's original _ready body. Later explicit setters remain
	# authoritative; this is never applied a second time after that body.
	if callbacks.has("_process"):
		process_processing_enabled = true; ordinary_p_enabled = true
	if callbacks.has("_physics_process"):
		physics_processing_enabled = true; raw_h_enabled = true
	_original_implicit_ready_applied = true
	return true

func configure_source(publication: Dictionary, world: RefCounted = null) -> bool:
	if OS.get_thread_caller_id() != _owner or initialized: return false
	var required := {"runtime_present": TYPE_BOOL, "life_generation": TYPE_INT,
		"inside_world": TYPE_BOOL, "queued_for_retirement": TYPE_BOOL,
		"parent_scope_id": TYPE_INT, "can_process": TYPE_BOOL,
		"process_processing_enabled": TYPE_BOOL, "physics_processing_enabled": TYPE_BOOL,
		"ordinary_p_enabled": TYPE_BOOL, "raw_h_enabled": TYPE_BOOL,
		"physics_priority": TYPE_INT, "process_priority": TYPE_INT, "process_mode": TYPE_INT}
	for key: String in required:
		if typeof(publication.get(key)) != required[key]: return false
	if publication.life_generation <= 0 or publication.parent_scope_id < 0: return false
	for key: String in required:
		if key == "can_process": can_process_value = publication[key]
		else: set(key, publication[key])
	initialized = true
	if world != null:
		if not publication.get("effective_process_mode") is int or publication.effective_process_mode not in [1, 2, 3, 4]: return false
		effective_process_mode = publication.effective_process_mode
		_world_ref = weakref(world)
	return true

func snapshot() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner and initialized)
	return {"runtime_present": runtime_present, "life_generation": life_generation,
		"inside_world": inside_world, "queued_for_retirement": queued_for_retirement,
		"parent_scope_id": parent_scope_id, "can_process": can_process(),
		"process_processing_enabled": process_processing_enabled,
		"physics_processing_enabled": physics_processing_enabled,
		"ordinary_p_enabled": ordinary_p_enabled, "raw_h_enabled": raw_h_enabled,
		"physics_priority": physics_priority}

func runtime_object_is_present() -> bool: return runtime_present
func is_inside_world() -> bool: return inside_world
func is_queued_for_retirement() -> bool: return queued_for_retirement
func can_process() -> bool:
	if _world_ref != null: return _world_ref.get_ref().original_scope_can_process(self)
	return can_process_value
func process_enabled() -> bool: return process_processing_enabled
func physics_enabled() -> bool: return physics_processing_enabled
func set_process_processing_enabled(value: bool) -> bool:
	if OS.get_thread_caller_id() != _owner or not runtime_present: return false
	process_processing_enabled = value
	return true

func queue_retirement() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	if not runtime_present: return false
	queued_for_retirement = true
	return true

func exit_at_original_checkpoint() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	if not runtime_present: return false
	inside_world = false
	parent_scope_id = 0
	exit_callbacks_complete = true
	return true

func free_at_original_checkpoint() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	if not exit_callbacks_complete or inside_world: return false
	final_free_checkpoint = true
	runtime_present = false
	return true
