extends Object

## Canonical runtime identity, confined to the simulation owner. Object (not
## RefCounted) retains the positive, full ObjectID used by ActorRef v1. The
## registry owns manual retirement; this object never owns a second HP value.
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")

var _owner_thread: int
var _world: Dictionary
var _model: Object
var _life: int
var _kind: StringName
var _slot: int
var _scope_ref: WeakRef
var _registered := true
var _retiring := false
var _inside_world_before_scope := true
var _inside_world: bool:
	get: return _scope_ref.get_ref().inside_world if _scope_ref != null and _scope_ref.get_ref() != null else _inside_world_before_scope
	set(value):
		if _scope_ref != null and _scope_ref.get_ref() != null: _scope_ref.get_ref().inside_world = value
		else: _inside_world_before_scope = value
var _queued_for_retirement_before_scope := false
var _queued_for_retirement: bool:
	get: return _scope_ref.get_ref().queued_for_retirement if _scope_ref != null and _scope_ref.get_ref() != null else _queued_for_retirement_before_scope
	set(value):
		if _scope_ref != null and _scope_ref.get_ref() != null: _scope_ref.get_ref().queued_for_retirement = value
		else: _queued_for_retirement_before_scope = value
var _parent_scope_id_before_scope := 0
var _parent_scope_id: int:
	get: return _scope_ref.get_ref().parent_scope_id if _scope_ref != null and _scope_ref.get_ref() != null else _parent_scope_id_before_scope
	set(value):
		if _scope_ref != null and _scope_ref.get_ref() != null: _scope_ref.get_ref().parent_scope_id = value
		else: _parent_scope_id_before_scope = value
var _can_process_before_scope := true
var _can_process: bool:
	get: return _scope_ref.get_ref().can_process() if _scope_ref != null and _scope_ref.get_ref() != null else _can_process_before_scope
	set(value):
		if _scope_ref != null and _scope_ref.get_ref() != null: _scope_ref.get_ref().can_process_value = value
		else: _can_process_before_scope = value
var _process_processing_enabled_before_scope := true
var _process_processing_enabled: bool:
	get: return _scope_ref.get_ref().process_processing_enabled if _scope_ref != null and _scope_ref.get_ref() != null else _process_processing_enabled_before_scope
	set(value):
		if _scope_ref != null and _scope_ref.get_ref() != null: _scope_ref.get_ref().process_processing_enabled = value
		else: _process_processing_enabled_before_scope = value
var _physics_processing_enabled_before_scope := true
var _physics_processing_enabled: bool:
	get: return _scope_ref.get_ref().physics_processing_enabled if _scope_ref != null and _scope_ref.get_ref() != null else _physics_processing_enabled_before_scope
	set(value):
		if _scope_ref != null and _scope_ref.get_ref() != null: _scope_ref.get_ref().physics_processing_enabled = value
		else: _physics_processing_enabled_before_scope = value
var _leases := 0
var _position_screen_px := Vector2.ZERO
var _position_ground_gu := Vector2.ZERO
var _radius_gu := 0.0
var _pose_revision := 0

func _init(world: Dictionary, model: Object, life: int, kind: StringName, slot: int) -> void:
	_owner_thread = OS.get_thread_caller_id()
	_world = Graph.capture(world).value
	_parent_scope_id = int(world.world_runtime_id)
	_model = model
	_life = life
	_kind = kind
	_slot = slot

func _owned() -> bool:
	var valid := OS.get_thread_caller_id() == _owner_thread
	assert(valid, "actor handle accessed outside its simulation owner")
	return valid

func identity() -> Dictionary:
	if not _owned():
		return {}
	var life: Variant = _model.call("current_life") if is_instance_valid(_model) and _model.has_method("current_life") else _life
	if not life is int or life <= 0:
		return {}
	return Graph.capture({"world":_world,"runtime_id":get_instance_id(),"life_generation":life}).value

func model() -> Object:
	return _model if _owned() else null

func kind() -> StringName:
	return _kind if _owned() else &""

func stable_combat_order() -> int:
	return _slot if _owned() else -1

func is_registered() -> bool:
	return _owned() and _registered and not _retiring

func runtime_object_is_present() -> bool:
	return _owned() and not _retiring and is_instance_valid(_model)

func is_inside_world() -> bool:
	return runtime_object_is_present() and _inside_world

func is_queued_for_retirement() -> bool:
	return _owned() and (_queued_for_retirement or _retiring)

func set_world_membership(present: bool) -> bool:
	if not runtime_object_is_present() or (present and _queued_for_retirement):
		return false
	_inside_world = present
	if not present: _parent_scope_id = 0
	return true

func parent_scope_id() -> int:
	return _parent_scope_id if runtime_object_is_present() and _inside_world else 0

func can_process() -> bool:
	return runtime_object_is_present() and _inside_world and _can_process

func is_physics_processing_enabled() -> bool:
	return runtime_object_is_present() and _physics_processing_enabled

func is_processing() -> bool:
	return runtime_object_is_present() and _process_processing_enabled

func set_process_processing_enabled(value: bool) -> bool:
	if not runtime_object_is_present(): return false
	_process_processing_enabled = value
	return true

func set_parent_scope_id(value: int) -> bool:
	if not runtime_object_is_present() or value < 0: return false
	_parent_scope_id = value
	return true

func set_processing_qualification(process_allowed: bool, physics_enabled: bool) -> bool:
	if not runtime_object_is_present(): return false
	_can_process = process_allowed
	_physics_processing_enabled = physics_enabled
	return true

func set_runtime_qualification(parent_id: int, process_allowed: bool, physics_enabled: bool) -> bool:
	if not runtime_object_is_present() or parent_id < 0: return false
	_parent_scope_id = parent_id
	_can_process = process_allowed
	_physics_processing_enabled = physics_enabled
	return true

func rebind_world_while_detached(world: Dictionary) -> bool:
	if not runtime_object_is_present() or _inside_world or _queued_for_retirement \
		or world.size() != 5 or world.get("contract_id") != _world.get("contract_id") \
		or world.get("world_runtime_id") != _world.get("world_runtime_id") \
		or world.get("profile_id") != _world.get("profile_id") \
		or not world.get("world_epoch") is int or world.world_epoch <= int(_world.world_epoch) \
		or not world.get("runtime_map_id") is int or world.runtime_map_id < 0:
		return false
	var captured := Graph.capture(world)
	if not captured.success: return false
	_world = captured.value
	_parent_scope_id = 0
	return true

func queue_retirement() -> bool:
	if not runtime_object_is_present():
		return false
	_queued_for_retirement = true
	return true

# Only the canonical attached Player crosses the actual Root arrival boundary.
# Scope, physics lease, combat life and model state remain owned in place.
func can_rebind_attached_player_at_map_arrival(before: Dictionary, after: Dictionary) -> bool:
	return _owned() and _kind == &"player" and is_registered() and is_inside_world() \
		and not is_queued_for_retirement() and _world == before and after.size() == 5 \
		and after.get("contract_id") == before.get("contract_id") \
		and after.get("world_runtime_id") == before.get("world_runtime_id") \
		and after.get("profile_id") == before.get("profile_id") \
		and int(before.world_epoch) != 9223372036854775807 \
		and after.get("world_epoch") is int and after.world_epoch == int(before.world_epoch) + 1 \
		and after.get("runtime_map_id") is int and after.runtime_map_id >= 0

func capture_attached_player_map_arrival_identity(before: Dictionary, after: Dictionary) -> Dictionary:
	if not can_rebind_attached_player_at_map_arrival(before,after): return {}
	var source: Script = _model.get_script()
	if source == null or source.resource_path != "res://scripts/gameplay/actors/player_actor_model.gd" or _model.get("_runtime_actor_id") != get_instance_id(): return {}
	# The actual original combat_epoch is read through the model authority.
	# A pre-map display descriptor cannot manufacture a positive combat life.
	var actual: Dictionary = identity()
	if actual.size() != 3 or actual.get("world") != before or actual.get("runtime_id") != get_instance_id(): return {}
	return Graph.capture({"world":after,"runtime_id":get_instance_id(),"life_generation":actual.life_generation}).value

func rebind_attached_player_at_map_arrival(before: Dictionary, after: Dictionary, player_identity: Dictionary) -> bool:
	var actual: Dictionary = capture_attached_player_map_arrival_identity(before,after)
	if actual.is_empty() or actual != player_identity: return false
	var captured := Graph.capture(after)
	if not captured.success: return false
	_world = captured.value
	return true

func original_world_context() -> Dictionary: return _world if _owned() else {}

func can_receive_damage() -> bool:
	if not is_registered() or not is_instance_valid(_model):
		return false
	if _model.has_method("can_receive_damage") and not bool(_model.call("can_receive_damage")):
		return false
	var hp: Variant = _model.get("current_hp")
	return hp is int and hp > 0

func set_pose(screen_px: Vector2, ground_gu: Vector2, radius_gu: float) -> bool:
	if not _owned() or not is_registered() or not screen_px.is_finite() or not ground_gu.is_finite() \
		or not is_finite(radius_gu) or radius_gu < 0.0:
		return false
	if screen_px != _position_screen_px or ground_gu != _position_ground_gu or radius_gu != _radius_gu:
		_pose_revision += 1
	_position_screen_px = screen_px
	_position_ground_gu = ground_gu
	_radius_gu = radius_gu
	return true

func actor_view() -> Dictionary:
	if not is_registered():
		return {}
	return _pose_view()

func runtime_actor_view() -> Dictionary:
	return _pose_view() if runtime_object_is_present() else {}

func _pose_view() -> Dictionary:
	var result := {"runtime_id":get_instance_id(),"identity":identity(),
		"position_screen_px":_position_screen_px,"position_ground_gu":_position_ground_gu,
		"combat_radius_gu":_radius_gu,"pose_revision":_pose_revision,
		"stable_combat_order":_slot,"kind":_kind,"parent_scope_id":parent_scope_id(),
		"can_process":can_process(),"physics_processing_enabled":is_physics_processing_enabled(),
		"inside_world":is_inside_world(),"queued_for_retirement":is_queued_for_retirement()}
	result.make_read_only()
	return result

func retain_lease() -> bool:
	if not _owned() or _retiring:
		return false
	_leases += 1
	return true

func release_lease() -> bool:
	if not _owned() or _leases <= 0:
		return false
	_leases -= 1
	return true

func begin_retirement() -> bool:
	if not _owned() or _retiring:
		return false
	_registered = false
	_retiring = true
	_inside_world = false
	_queued_for_retirement = true
	return true

func can_destroy() -> bool:
	return _owned() and _retiring and _leases == 0

func replace_life(life: int) -> bool:
	if not _owned() or not is_registered() or life <= _life \
		or (is_instance_valid(_model) and _model.has_method("current_life")):
		return false
	_life = life
	return true

func mark_original_birth_unconfigured() -> bool:
	if not _owned() or _life != 0 or _leases != 0 or _retiring or not _model.has_method("current_life") or _model.current_life() != 0: return false
	_registered = false
	_inside_world = false
	_parent_scope_id = 0
	return true
func commit_original_birth_life() -> bool:
	if not _owned() or _registered or _life != 0 or _leases != 0 or _retiring or not _model.has_method("current_life"): return false
	var life: Variant = _model.current_life()
	if not life is int or life <= 0: return false
	_life = life
	_registered = true
	return true

func bind_original_temporal_scope(scope: RefCounted) -> bool:
	if not _owned() or _scope_ref != null or scope == null or scope.owner_thread_id() != _owner_thread: return false
	_scope_ref = weakref(scope)
	return true
