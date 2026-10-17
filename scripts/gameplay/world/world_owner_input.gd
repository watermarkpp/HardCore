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
var _last_received_world: Dictionary
func _init(world: RefCounted) -> void: _world = weakref(world)
func owner_thread_id() -> int: return _owner
func actual_main_frame_observation() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	if not _packet.has("actual_main_frame_interval_ms"): return {}
	return {"main_process_frame":_packet.main_process_frame,"interval_ms":_packet.actual_main_frame_interval_ms}
func accept(packet: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or packet.get("contract_id") != "world.input.publication.v1": return false
	if not _publication_world_matches_current(packet): return false
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
	_last_received_world = packet.world_context
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

static func _is_original_viewport_observation(packet: Dictionary) -> bool:
	# Value-schema discrimination only: this never authorizes a Native arrival.
	if packet.get("contract_id") != "world.input.publication.v1" or not packet.get("world_context") is Dictionary or not packet.get("main_process_frame") is int: return false
	var events: Variant = packet.get("original_events")
	if not events is Array or events.size() != 1 or not events[0] is Dictionary: return false
	var event: Dictionary = events[0]
	if event.get("kind") != "world_viewport_publication" or not event.get("arguments") is Array or event.arguments.size() != 1 or not event.arguments[0] is Dictionary: return false
	var publication: Dictionary = event.arguments[0]
	var context: Variant = event.get("view_context")
	if not context is Dictionary or context.get("actual_Main_capture") != true or context.get("world_context") != packet.world_context or not context.get("actual_hud_observation") is Dictionary: return false
	if not context.get("main_process_frame") is int or context.main_process_frame < 0 or context.main_process_frame > packet.main_process_frame: return false
	return publication.get("contract_id") == "world.visual.actual_viewport.v1" and publication.get("world_identity") == packet.world_context and publication.get("main_process_frame") == context.main_process_frame

func _publication_world_matches_current(packet: Dictionary) -> bool:
	if _world == null or not packet.get("world_context") is Dictionary: return false
	var core: RefCounted = _world.get_ref()
	if core == null: return false
	var current: Dictionary = core.current_world_identity()
	if packet.world_context == current: return true
	# Preserve the actual InputMap/button sample and its original edge/serial
	# semantics, not a rewritten current-world packet or a dropped command.
	if _last_received_world == current or not _is_original_viewport_observation(packet): return false
	if core.get_script() == null or core.get_script().resource_path != "res://scripts/gameplay/world/world_simulation_core.gd": return false
	var viewport: RefCounted = core.required_owner_service(&"VisualViewport",["can_accept_original_main_world"])
	return viewport != null and viewport.can_accept_original_main_world(packet.world_context)
