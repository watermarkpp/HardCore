extends RefCounted
## The Main input boundary publishes actual Godot action/button facts in source
## sequence. This object owns input state only; it never decides skill readiness.
var _world: WeakRef
var _owner := OS.get_thread_caller_id()
var _last_sequence := -1
var _last_main_process_frame := -1
var _process_edge_frame := -1
var _pending_edges: Dictionary = {}
var _active_edges: Dictionary = {}
var _last_edge_main_frames: Dictionary = {}
var _packet: Dictionary
func _init(world: RefCounted) -> void: _world = weakref(world)
func owner_thread_id() -> int: return _owner
func actual_main_frame_observation() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	if not _packet.has("actual_main_frame_interval_ms"): return {}
	return {"main_process_frame":_packet.main_process_frame,"interval_ms":_packet.actual_main_frame_interval_ms}
func accept(packet: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or packet.get("contract_id") != "world.input.publication.v1": return false
	if packet.get("world_context") != _world.get_ref().current_world_identity(): return false
	if not packet.get("main_process_frame") is int or packet.main_process_frame < _last_main_process_frame or not packet.get("main_physics_frame") is int or packet.main_physics_frame < 0: return false
	for field: String in ["actions", "buttons"]:
		if not packet.get(field) is Dictionary: return false
	if not packet.get("button_owner_present") is bool: return false
	if packet.has("actual_main_frame_interval_ms"):
		var interval: Variant = packet.actual_main_frame_interval_ms
		if not (interval is float or interval is int) or not is_finite(interval) or (interval != -1.0 and interval < 0.0): return false
	if not packet.get("sequence") is int or packet.sequence <= _last_sequence or not packet.get("keyboard_movement") is Vector2 or not packet.keyboard_movement.is_finite(): return false
	for action: String in packet.actions:
		var row: Variant = packet.actions[action]
		if not row is Dictionary or not row.get("pressed") is bool or not row.get("just_pressed") is bool: return false
	for token: Variant in packet.buttons:
		var row: Variant = packet.buttons[token]
		if not packet.button_owner_present or not token is int or token <= 0 or not row is Dictionary or not row.get("pointer_index") is int or not (row.get("source") is String or row.get("source") is StringName): return false
	if packet.has("attack_button_snapshot") and not packet.attack_button_snapshot is Dictionary: return false
	# Main can publish several HUD/viewport callbacks in the same frame. Its
	# just_pressed bit is one edge, not one new edge per packet or Source frame.
	for action: String in packet.actions:
		if packet.actions[action].just_pressed and packet.main_process_frame > int(_last_edge_main_frames.get(action,-1)):
			_pending_edges[action] = true
			_last_edge_main_frames[action] = packet.main_process_frame
	_last_sequence = packet.sequence
	_last_main_process_frame = packet.main_process_frame
	_packet = packet
	return true
func _action(action: StringName) -> Dictionary:
	if not _packet.actions.has(String(action)):
		_world.get_ref().fault("input_action_not_published", {"action": action})
		assert(false, "input publication omitted a consumed original action")
	return _packet.actions[String(action)]
func is_action_pressed(action: StringName) -> bool: return _action(action).pressed
func is_action_just_pressed(action: StringName) -> bool:
	_action(action) # Omitted consumed actions remain a hard source error.
	return _process_edge_frame == _world.get_ref().current_clock_frame().get("source_process_frame") and bool(_active_edges.get(String(action),false))
func begin_original_process_boundary(frame: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner: return false
	var actual: Dictionary = _world.get_ref().current_clock_frame()
	# Native callback's frame omits phase; the actual getter supplies it.
	if actual.get("phase") != "P_INPUT" or not frame.get("source_process_frame") is int or frame.source_process_frame <= _process_edge_frame or actual.get("source_process_frame") != frame.source_process_frame or actual.get("epoch") != frame.get("epoch"): return false
	_process_edge_frame = frame.source_process_frame
	_active_edges = _pending_edges
	_pending_edges = {}
	return true
func keyboard_movement_vector() -> Vector2: return _packet.keyboard_movement
func gameplay_input_is_enabled() -> bool: return _world.get_ref().gameplay_input_is_enabled()
func has_button_lifecycle_snapshot() -> bool: return _packet.has("attack_button_snapshot")
func button_lifecycle_snapshot() -> Dictionary:
	assert(has_button_lifecycle_snapshot())
	return _packet.attack_button_snapshot
func has_button_lifecycle_owner() -> bool: return _packet.button_owner_present
func button_owns_lifecycle_input(token: int, pointer_index: int, source: StringName) -> bool:
	if not _packet.buttons.has(token): return false
	var row: Dictionary = _packet.buttons[token]
	return row.pointer_index == pointer_index and row.source == source

var _pick_presses: Array[Dictionary] = []
func retain_original_pick_press(fact: Dictionary, packet: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=_owner or not preload("res://scripts/gameplay/presentation/main_original_pick_input.gd").validate(fact,_world.get_ref().current_world_identity()) or packet.get("sequence")!=_last_sequence: return false
	# Sorting needs physical Main canvas order and is deliberately unsupported.
	if fact.sort: return false
	_pick_presses.append(fact.duplicate(true))
	return true
func process_original_viewport_picking() -> bool:
	if OS.get_thread_caller_id()!=_owner: return false
	var core: RefCounted=_world.get_ref()
	if core.current_clock_frame().get("phase")!="H_PREPARE": return false
	var pending: Array[Dictionary]=_pick_presses;_pick_presses=[]
	for fact: Dictionary in pending:
		var result: Dictionary=core.native_world.intersect_original_pick_point(fact.canvas_position,fact.canvas_instance_id)
		if result.get("ok")!=true or result.get("limit")!=64 or not result.get("hits") is Array:
			core.fault("original_viewport_pick_query_failed",result);return false
		for hit: Variant in result.hits:
			if not hit is Dictionary or not hit.get("collider_id") is int or not hit.get("rid") is RID or not hit.get("shape") is int: core.fault("original_viewport_pick_hit_schema",{});return false
			var handle: Object=core.registry.resolve_runtime_actor(hit.collider_id)
			if handle==null or not handle.can_process(): continue
			# Original Viewport dispatches EACH raw shape hit, in backend order.
			if handle.kind()==&"enemy":
				var instance: RefCounted=core._actor_instances.get(hit.collider_id)
				if instance==null or instance.motion.actual_body_rid()!=hit.rid or not instance.ports.input_pickable(): core.fault("original_pickable_body_fact_mismatch",{});return false
				handle.model()._input_event(null,preload("res://scripts/gameplay/presentation/main_original_pick_input.gd").source_event(fact),hit.shape)
			# first_only is the first processable real collision object, not a
			# visual-radius or first-enemy guess. Default Viewport value is false.
			if fact.first_only: break
	return not core.is_faulted()
