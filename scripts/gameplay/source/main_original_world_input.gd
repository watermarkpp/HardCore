extends RefCounted
## Main owns Input/InputMap and the actual physical touch button. This producer
## captures their values only; Source retains movement/skill readiness authority.
const TouchButton := preload("res://scripts/circular_touch_button.gd")
var _root: WeakRef
var _world: Dictionary
var _button: WeakRef
var _last_sequence := -1
var _last_measured_main_frame := -1
var _actual_main_interval_ms := -1.0
func owner_thread_id() -> int: return OS.get_main_thread_id()
func can_commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	return _main() and transaction.get("before_world") == _world and transaction.get("after_world") is Dictionary and transaction.after_world.get("world_runtime_id") == _root.get_ref().get_instance_id() and transaction.after_world.get("profile_id") == _world.profile_id and transaction.after_world.get("world_epoch") == _world.world_epoch + 1
func commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not can_commit_actual_original_map_arrival(transaction): return false
	# Keep the real InputMap/button and monotonically increasing input serial.
	_world = transaction.after_world.duplicate(true)
	return true
func configure_main(root: Node2D,world: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _root != null or not is_instance_valid(root) or root.is_queued_for_deletion() or root.get_script() != preload("res://scripts/game_root.gd"): return false
	if world.size() != 5 or world.get("contract_id") != "hardcore.execution.world_context.v1" or world.get("world_runtime_id") != root.get_instance_id() or not world.get("profile_id") is String or world.profile_id.is_empty(): return false
	if not world.get("world_epoch") is int or world.world_epoch < 0 or not world.get("runtime_map_id") is int or (world.runtime_map_id < 0 and (world.runtime_map_id != -1 or world.world_epoch != 0)): return false
	# InputMap is Main-owned. Guarded GameRoot does not execute legacy _ready,
	# so execute this real original setup body here, exactly once per publisher.
	root._register_input_actions()
	_root = weakref(root); _world = world.duplicate(true)
	return true
func bind_original_attack_button(button: Control) -> bool:
	if not _main() or _button != null or not is_instance_valid(button) or button.get_script() != TouchButton or button.is_queued_for_deletion() or not _root.get_ref().is_ancestor_of(button): return false
	_button = weakref(button)
	return true
func _main() -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and _root != null and is_instance_valid(_root.get_ref()) and not _root.get_ref().is_queued_for_deletion()
func capture_original_main_input(sequence: int,name: StringName = &"",arguments: Array = [],view_context: Dictionary = {}) -> Dictionary:
	if not _main() or sequence <= _last_sequence: return _invalid("actual_Main_input_sequence_and_Root_required")
	if name.is_empty() and (not arguments.is_empty() or not view_context.is_empty()): return _invalid("input_snapshot_has_no_synthetic_callback")
	if not name.is_empty() and (view_context.get("actual_Main_capture") != true or view_context.get("world_context") != _world or not view_context.get("main_process_frame") is int or view_context.main_process_frame > Engine.get_process_frames()): return _invalid("actual_same_Main_event_context_required")
	var actions: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		actions[String(action)] = {"pressed":Input.is_action_pressed(action),"just_pressed":Input.is_action_just_pressed(action)}
	# Same original player.gd InputMap guard and Input.get_vector deadzone.
	var keyboard := Vector2.ZERO
	var movement_actions_present := true
	for action: StringName in [&"move_left",&"move_right",&"move_up",&"move_down"]:
		if not InputMap.has_action(action): movement_actions_present = false
	if movement_actions_present: keyboard = Input.get_vector("move_left","move_right","move_up","move_down")
	var events: Array[Dictionary] = []
	if not name.is_empty(): events.append({"kind":String(name),"arguments":arguments,"view_context":view_context})
	var actual_frame: int = Engine.get_process_frames()
	if actual_frame != _last_measured_main_frame:
		_actual_main_interval_ms = RuntimeDiagnostics.wall_frame_interval_ms() if OS.is_debug_build() else -1.0
		_last_measured_main_frame = actual_frame
	var packet := {"contract_id":"world.input.publication.v1","world_context":_world,"sequence":sequence,
		"main_process_frame":Engine.get_process_frames(),"main_physics_frame":Engine.get_physics_frames(),
		"actual_main_frame_interval_ms":_actual_main_interval_ms,
		"actions":actions,"keyboard_movement":keyboard,"buttons":{},"button_owner_present":false,"original_events":events}
	if _button != null:
		var button: Control = _button.get_ref()
		if not is_instance_valid(button) or button.is_queued_for_deletion() or not _root.get_ref().is_ancestor_of(button): return _invalid("actual_original_button_retired_before_input_close")
		var snapshot: Dictionary = button.input_lifecycle_snapshot()
		packet.attack_button_snapshot = snapshot
		packet.button_owner_present = button.has_method("owns_lifecycle_input")
		for pointer: Variant in snapshot.active_inputs:
			var entry: Variant = snapshot.active_inputs[pointer]
			if not pointer is int or not entry is Dictionary or not entry.get("press_token") is int or not (entry.get("source") is String or entry.get("source") is StringName): return _invalid("actual_original_button_lifecycle_schema")
			var token: int = entry.press_token
			var source := StringName(entry.source)
			if not button.owns_lifecycle_input(token,pointer,source): continue
			if token <= 0 or packet.buttons.has(token): return _invalid("original_button_token_identity_conflict")
			packet.buttons[token] = {"pointer_index":pointer,"source":source}
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var copied: Dictionary = graph.capture(packet,true,false)
	if copied.get("success") != true: return _invalid("Main_input_contains_nonvalue_data")
	_last_sequence = sequence
	return {"success":true,"publication":copied.value}
static func _invalid(reason: String) -> Dictionary: return {"success":false,"status":"INVALID","error":reason}
