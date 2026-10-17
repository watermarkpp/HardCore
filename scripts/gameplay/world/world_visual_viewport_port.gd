extends RefCounted

## Only actual Main canvas/viewport values cross this boundary. No second
## camera, actor position or visibility authority is constructed on S.
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _publication: Dictionary

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
	if publication.get("contract_id") != "world.visual.actual_viewport.v1" or publication.get("world_identity") != _core.get_ref().current_world_identity(): return false
	if not publication.get("sequence") is int or publication.sequence < 0 or not publication.get("main_process_frame") is int or publication.main_process_frame < 0: return false
	if not publication.get("viewport_available") is bool or not publication.get("canvas_transform") is Transform2D or not publication.get("visible_rect") is Rect2: return false
	if not publication.canvas_transform.is_finite() or not publication.visible_rect.position.is_finite() or not publication.visible_rect.size.is_finite(): return false
	if not _publication.is_empty() and publication.sequence <= _publication.sequence: return publication == _publication
	var captured := _capture(publication)
	if not captured.success: return false
	_publication = captured.value
	return true

func viewport_snapshot(service_id: int) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner and service_id > 0 and not _publication.is_empty())
	var core: RefCounted = _core.get_ref()
	if core == null or core.service_registry.resolve_service(service_id) == null or _publication.world_identity != core.current_world_identity():
		if core != null: core.fault("actual_viewport_source_scope_missing", {"service_id":service_id})
		return {}
	return {"viewport_available":_publication.viewport_available,"canvas_transform":_publication.canvas_transform,"visible_rect":_publication.visible_rect}

func root_viewport_snapshot() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner and _core != null)
	var core: RefCounted = _core.get_ref()
	var scope: RefCounted = core.original_source_scope("game_root") if core != null else null
	if scope == null or not scope.is_inside_world() or _publication.is_empty() or _publication.world_identity != core.current_world_identity():
		if core != null: core.fault("actual_viewport_Root_scope_missing",{})
		return {}
	return {"viewport_available":_publication.viewport_available,"canvas_transform":_publication.canvas_transform,"visible_rect":_publication.visible_rect}
