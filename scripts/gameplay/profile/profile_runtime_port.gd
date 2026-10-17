extends RefCounted

## The original process_frame continuation is serviced once at logic P,
## including paused P. No H dispatch and no timer may emit this signal.
signal service_frame
const ResourceWaiter := preload("res://scripts/gameplay/profile/profile_resource_service_waiter.gd")
var _resource_service_waiters: Array[RefCounted] = []
const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const REQUIRED_OWNER_METHODS := ["profile_runtime_owner_view", "profile_runtime_registry", "feature_publication_scope", "gameplay_input_is_enabled", "profile_global_randi", "profile_global_randi_range"]
var _thread := OS.get_thread_caller_id()
var _service_owner: WeakRef
var _last_service_sequence := -1
var world_owners: Dictionary = {}

func _init(service_owner: RefCounted) -> void:
	assert(OS.get_thread_caller_id() != OS.get_main_thread_id())
	assert(service_owner != null and not service_owner is Resource)
	assert(service_owner.has_method("profile_world_paused") and service_owner.has_method("fault"))
	_service_owner = weakref(service_owner)

func _assert_owner() -> void:
	assert(OS.get_thread_caller_id() == _thread)
	assert(_service_owner.get_ref() != null, "profile service owner must outlive profile continuations")

func global_randi() -> int:
	_assert_owner()
	return _service_owner.get_ref().profile_global_randi()

func global_randi_range(low: int, high: int) -> int:
	_assert_owner()
	return _service_owner.get_ref().profile_global_randi_range(low, high)

func service_process_frame(sequence: int) -> bool:
	_assert_owner()
	if sequence < 0 or (_last_service_sequence >= 0 and sequence != _last_service_sequence+1):
		_service_owner.get_ref().fault("profile_service_phase_sequence", {"previous":_last_service_sequence,"received":sequence})
		return false
	_last_service_sequence = sequence
	var waiting: Array[RefCounted] = _resource_service_waiters
	_resource_service_waiters = []
	for waiter: RefCounted in waiting: waiter.complete_at_original_service()
	service_frame.emit()
	return true

func next_service() -> void:
	_assert_owner()
	# This exact port has only the nine original Profile resource/transaction
	# await sites listed in PROFILE_WAITER_SOURCE_MAP.json. Registration uses
	# Native's already-published Main SIGNAL watermark even during backlog.
	var actual_highwater: int = _service_owner.get_ref().original_close_process_signal_highwater()
	if actual_highwater<0:
		_service_owner.get_ref().fault("actual_close_signal_registration_missing",{})
		return
	var waiter: RefCounted = ResourceWaiter.new(actual_highwater)
	_resource_service_waiters.append(waiter)
	await waiter.released

func register_world(owner: Object) -> void:
	_assert_owner()
	assert(owner is RefCounted and not owner is Resource)
	for method: String in REQUIRED_OWNER_METHODS:
		assert(owner.has_method(method), "missing profile world service:" + method)
	var view: Dictionary = owner.profile_runtime_owner_view()
	assert(view.get("inside_world") is bool and view.get("queued_for_retirement") is bool and view.get("player_runtime_id") is int)
	assert(owner.profile_runtime_registry() is Registry)
	if bool(view.inside_world):
		world_owners[owner.get_instance_id()] = weakref(owner)

func unregister_world(owner: Object) -> void:
	_assert_owner()
	if is_instance_valid(owner): world_owners.erase(owner.get_instance_id())

func feature_publication_context(active_profile_id: String) -> Dictionary:
	_assert_owner()
	var active := false
	var ready := not bool(_service_owner.get_ref().profile_world_paused())
	var scopes := {}
	var scope_ready := true
	for runtime_id: int in world_owners.keys():
		var owner: RefCounted = (world_owners[runtime_id] as WeakRef).get_ref()
		if owner == null:
			world_owners.erase(runtime_id)
			continue
		var view: Dictionary = owner.profile_runtime_owner_view()
		if not bool(view.inside_world):
			world_owners.erase(runtime_id)
			continue
		active = true
		var scope: Dictionary = owner.feature_publication_scope()
		if scope.is_empty(): scope_ready = false
		else: scopes[runtime_id] = scope
		if bool(view.queued_for_retirement) or not bool(owner.gameplay_input_is_enabled()):
			ready = false
			continue
		var registry: Registry = owner.profile_runtime_registry()
		var player_id: int = int(view.player_runtime_id)
		var handle: Object = registry.resolve_runtime_actor(player_id)
		var actor: Variant = handle.model() if handle != null else null
		if actor == null or not actor.has_method("combat_action_snapshot") or not actor.has_method("has_pending_combat_release") \
			or bool(actor.has_pending_combat_release()) or bool(actor.combat_action_snapshot().get("active", true)):
			ready = false
	return {"world_active":active,"world_ready":ready,"scope_ready":scope_ready,"scope":{"profile_id":active_profile_id,"owners":scopes}}

func profile_is_owned_by_gameplay() -> bool:
	_assert_owner()
	for runtime_id: int in world_owners.keys():
		var owner: RefCounted = (world_owners[runtime_id] as WeakRef).get_ref()
		if owner != null and bool(owner.profile_runtime_owner_view().inside_world): return true
		world_owners.erase(runtime_id)
	return false

func owner_thread_id() -> int: return _thread

func original_resource_service_waiter_count() -> int:
	_assert_owner()
	return _resource_service_waiters.size()
func service_original_close_process_signal(sequence: int, actual_main_frame: int, published_signal_highwater: int) -> bool:
	_assert_owner()
	if sequence<0 or (_last_service_sequence>=0 and sequence!=_last_service_sequence+1) or actual_main_frame<0 or published_signal_highwater<actual_main_frame:
		_service_owner.get_ref().fault("actual_resource_close_signal_invalid",{})
		return false
	_last_service_sequence=sequence
	var eligible: Array[RefCounted] = []
	var retained: Array[RefCounted] = []
	for waiter: RefCounted in _resource_service_waiters:
		if actual_main_frame>waiter.signal_highwater: eligible.append(waiter)
		else: retained.append(waiter)
	_resource_service_waiters=retained
	# Remove before emission: reentrant next_service records the current Native
	# highwater and cannot be released by this consumed old signal a second time.
	for waiter: RefCounted in eligible: waiter.complete_at_original_service()
	return true
