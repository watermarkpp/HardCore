extends RefCounted

## Only actual Main canvas/viewport values cross this boundary. No second
## camera, actor position or visibility authority is constructed on S.
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _publication: Dictionary
# The immutable sample remains exactly what Main measured. Only its permitted
# consumption-world binding moves across a verified arrival of the SAME Root.
var _bound_world: Dictionary

static func _capture(value: Dictionary) -> Dictionary:
	if not ClassDB.class_exists("HardCoreContentValueGraph"): return {"success":false}
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	return graph.capture(value, true, false)

static func capture_original_main(root: Node2D, world_identity: Dictionary, sequence: int) -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if root == null or not root.is_inside_tree() or root.is_queued_for_deletion() or sequence < 0:
		return {}
	if world_identity.get("contract_id") != "hardcore.execution.world_context.v1" or world_identity.get("world_runtime_id") != root.get_instance_id():
		return {}
	var viewport := root.get_viewport()
	var captured := _capture({"contract_id":"world.visual.actual_viewport.v1", "world_identity":world_identity,
		"sequence":sequence,"main_process_frame":Engine.get_process_frames(),
		"viewport_available":viewport != null,"canvas_transform":root.get_canvas_transform(),
		"visible_rect":viewport.get_visible_rect() if viewport != null else Rect2()})
	return captured.value if captured.success else {}

func configure_owner(core: RefCounted, publication: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _owner == OS.get_main_thread_id() or _core != null or core == null:
		return false
	if not core.has_method("current_world_identity") or not core.has_method("owner_thread_id") or core.owner_thread_id() != _owner:
		return false
	_core = weakref(core)
	if not accept_original_main(publication):
		_core = null
		return false
	return true

func owner_thread_id() -> int: return _owner

func accept_original_main(publication: Dictionary) -> bool:
	assert(OS.get_thread_caller_id() == _owner and _core != null)
	if publication.get("contract_id") != "world.visual.actual_viewport.v1" or not publication.get("world_identity") is Dictionary or not can_accept_original_main_world(publication.world_identity): return false
	if not publication.get("sequence") is int or publication.sequence < 0 or not publication.get("main_process_frame") is int or publication.main_process_frame < 0: return false
	if not publication.get("viewport_available") is bool or not publication.get("canvas_transform") is Transform2D or not publication.get("visible_rect") is Rect2: return false
	if not publication.canvas_transform.is_finite() or not publication.visible_rect.position.is_finite() or not publication.visible_rect.size.is_finite(): return false
	if not _publication.is_empty() and publication.sequence <= _publication.sequence: return publication == _publication
	var captured := _capture(publication)
	if not captured.success: return false
	_publication = captured.value
	if _publication.world_identity == _core.get_ref().current_world_identity(): _bound_world = _publication.world_identity
	return true

func viewport_snapshot(service_id: int) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner and service_id > 0 and not _publication.is_empty())
	var core: RefCounted = _core.get_ref()
	if core == null or core.service_registry.resolve_service(service_id) == null or _bound_world != core.current_world_identity():
		if core != null: core.fault("actual_viewport_source_scope_missing", {"service_id":service_id})
		return {}
	return {"viewport_available":_publication.viewport_available,"canvas_transform":_publication.canvas_transform,"visible_rect":_publication.visible_rect}

func root_viewport_snapshot() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner and _core != null)
	var core: RefCounted = _core.get_ref()
	var scope: RefCounted = core.original_source_scope("game_root") if core != null else null
	if scope == null or not scope.is_inside_world() or _publication.is_empty() or _bound_world != core.current_world_identity():
		if core != null: core.fault("actual_viewport_Root_scope_missing",{})
		return {}
	return {"viewport_available":_publication.viewport_available,"canvas_transform":_publication.canvas_transform,"visible_rect":_publication.visible_rect}

static func _arrival_preserves_viewport_binding(transaction: Dictionary, bound_world: Dictionary, scope: RefCounted) -> bool:
	# Schema/lifetime precondition only, never a substitute for Native commit.
	if not preload("res://scripts/gameplay/world/world_original_map_arrival_contract.gd").accepts(transaction) or transaction.before_world != bound_world or scope == null:
		return false
	return scope.runtime_object_is_present() and scope.is_inside_world() and not scope.is_queued_for_retirement() and not scope.exit_callbacks_complete and not scope.final_free_checkpoint

func _arrival_core(transaction: Dictionary, committed: bool, prior_world: Dictionary = {}) -> RefCounted:
	if OS.get_thread_caller_id() != _owner or _owner == OS.get_main_thread_id() or _core == null or _publication.is_empty(): return null
	var core: RefCounted = _core.get_ref()
	if core == null or core.get_script() == null or core.get_script().resource_path != "res://scripts/gameplay/world/world_simulation_core.gd": return null
	if core.is_faulted() or core.get("_closing") or core.is_original_world_closed(): return null
	var scope: RefCounted = core.original_source_scope("game_root")
	if not _arrival_preserves_viewport_binding(transaction,_bound_world if prior_world.is_empty() else prior_world,scope): return null
	var expected: Dictionary = transaction.after_world if committed else transaction.before_world
	if core.current_world_identity() != expected or core.registry == null or core.registry.capture_world() != expected: return null
	var root: RefCounted = core.original_root_owner()
	var session: RefCounted = core.original_source_session()
	if root == null or session == null or transaction.world_core_id != core.get_instance_id() or transaction.source_root_id != root.get_instance_id() or transaction.registry_id != core.registry.get_instance_id() or transaction.owner_session_id != session.original_budget_session_id(): return null
	# A binding chain can never substitute a new physical Main Root or Profile.
	if _publication.world_identity.world_runtime_id != expected.world_runtime_id or _publication.world_identity.profile_id != expected.profile_id: return null
	return core

func can_commit_original_map_arrival_transaction(transaction: Dictionary) -> bool:
	return _arrival_core(transaction,false) != null

func commit_original_map_arrival_transaction(transaction: Dictionary) -> bool:
	var core: RefCounted = _arrival_core(transaction,true)
	if core == null: return false
	var host: Object = core.original_native_host()
	if host == null or not host.is_class("HardCoreSimulationHost") or not host.verify_committed_original_map_arrival(transaction): return false
	var captured := _capture(transaction.after_world)
	if not captured.success: return false
	# Do not rewrite the Main sample's identity, sequence, timestamp, transform
	# or visible rectangle. The next genuine Main publication replaces it.
	_bound_world = captured.value
	return true

func can_accept_original_main_world(world: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _owner == OS.get_main_thread_id() or _core == null: return false
	var core: RefCounted = _core.get_ref()
	if core == null: return false
	var current: Dictionary = core.current_world_identity()
	if world == current: return true
	# Only an in-flight sample from the existing physical viewport can cross
	# the exact committed before->after seam. A current sample closes it.
	if _publication.is_empty() or _publication.world_identity != world or _publication.world_identity == current or _bound_world != current: return false
	if core.get_script() == null or core.get_script().resource_path != "res://scripts/gameplay/world/world_simulation_core.gd": return false
	var transaction: Variant = core.get("_last_original_map_arrival")
	if not transaction is Dictionary or transaction.get("before_world") != world or transaction.get("after_world") != current: return false
	if _arrival_core(transaction,true,world) == null: return false
	var host: Object = core.original_native_host()
	return host != null and host.is_class("HardCoreSimulationHost") and host.verify_committed_original_map_arrival(transaction)
