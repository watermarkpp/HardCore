extends RefCounted
## Source already changes the original visual scope's process qualification.
## Main records delivery against the actual claimed event and physical renderer;
## it never starts a second animation/process clock on that renderer.
const Prefix := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd")
const Vault := preload("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd")
const Renderer := preload("res://scripts/gameplay/presentation/enemy_main_visual_projection.gd")
var _root: WeakRef
var _world: Dictionary
var _host: Object
var _prefix: RefCounted
var _vault: RefCounted
var _generation := 0
var _qualifications: Dictionary = {}

func configure_main(root: Node2D, world: Dictionary, host: Object, prefix: RefCounted, vault: RefCounted, generation: int) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _root != null or not is_instance_valid(root) or not root.is_inside_tree() or root.is_queued_for_deletion() or generation <= 0: return false
	if world.get("contract_id") != "hardcore.execution.world_context.v1" or world.get("world_runtime_id") != root.get_instance_id() or world.size() != 5: return false
	if host == null or not host.is_class("HardCoreSimulationHost") or prefix == null or prefix.get_script() != Prefix or prefix.get("_host") != host: return false
	if vault == null or vault.get_script() != Vault or vault.get("_configured") != true or vault.get("_bridge_generation") != generation: return false
	var validator: Callable = vault.get("_validate_ticket")
	if not validator.is_valid() or validator.get_object() != host or validator.get_method() != &"validate_original_primitive_ticket": return false
	_root = weakref(root); _world = world.duplicate(true); _host = host; _prefix = prefix; _vault = vault; _generation = generation
	return true

func publish_visual_process_qualification(service_id: int, enabled: bool) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _root == null or not is_instance_valid(_root.get_ref()) or service_id <= 0: return false
	var event: Dictionary = _prefix.actual_current_original_event()
	var prefix: Dictionary = _prefix.actual_current_original_prefix()
	if event.get("kind") != "enemy_visual" or not event.get("event") is Dictionary or not event.get("source_site") is Dictionary or event.source_site.get("world_context") != _world: return false
	var visual: Dictionary = event.event
	if visual.get("service_id") != service_id or visual.get("operation") != &"visual_process_enabled" or not visual.get("arguments") is Array or visual.arguments != [enabled] or not visual.get("sequence") is int or visual.sequence <= 0: return false
	if prefix.get("bridge_generation") != _generation or not event.get("ordinal") is int or event.ordinal <= 0 or int(prefix.get("through_ordinal",-1)) < event.ordinal: return false
	var renderer: Object = _vault._renderer(service_id)
	var root: Node2D = _root.get_ref()
	if not is_instance_valid(renderer) or renderer.get_script() != Renderer or renderer.canonical_service_id != service_id or not renderer.is_inside_tree() or renderer.is_queued_for_deletion() or not root.is_ancestor_of(renderer) or renderer.is_processing() or renderer.is_physics_processing(): return false
	if _qualifications.has(service_id):
		var previous: Dictionary = _qualifications[service_id]
		if previous.event.ordinal == event.ordinal: return previous.event == event and previous.renderer_id == renderer.get_instance_id() and renderer.get_meta(&"original_source_process_enabled",null) == enabled
		if previous.event.ordinal > event.ordinal or previous.visual_sequence >= visual.sequence or previous.renderer_id != renderer.get_instance_id(): return false
	else:
		renderer.tree_exited.connect(_actual_renderer_left_tree.bind(service_id,renderer.get_instance_id()),CONNECT_ONE_SHOT)
	renderer.set_meta(&"original_source_process_enabled",enabled)
	if renderer.get_meta(&"original_source_process_enabled",null) != enabled: return false
	_qualifications[service_id] = {"event":event.duplicate(true),"visual_sequence":visual.sequence,"renderer":weakref(renderer),"renderer_id":renderer.get_instance_id(),"enabled":enabled,"actual_Main_process_frame":Engine.get_process_frames()}
	return true

func inspect_actual_original_visual_qualification(service_id: int) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not _qualifications.has(service_id): return {"status":"MISSING"}
	var row: Dictionary = _qualifications[service_id]
	var renderer: Object = row.renderer.get_ref()
	if not is_instance_valid(renderer) or not renderer.is_inside_tree() or renderer.is_processing() or renderer.is_physics_processing() or renderer.get_meta(&"original_source_process_enabled",null) != row.enabled: return {"status":"INVALID"}
	return {"status":"READY","service_id":service_id,"actual_renderer_id":row.renderer_id,"world_context":_world,"source_process_enabled":row.enabled,"visual_sequence":row.visual_sequence,"original_journal_ordinal":row.event.ordinal,"actual_Main_process_frame":row.actual_Main_process_frame,"physical_Main_process_enabled":false,"physical_Main_physics_enabled":false}

func _actual_renderer_left_tree(service_id: int, actual_renderer_id: int) -> void:
	if OS.get_thread_caller_id() == OS.get_main_thread_id() and _qualifications.has(service_id) and _qualifications[service_id].renderer_id == actual_renderer_id: _qualifications.erase(service_id)

func can_commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _root == null or not is_instance_valid(_root.get_ref()) or transaction.get("before_world") != _world: return false
	var event: Dictionary = _prefix.actual_current_original_event()
	return event.get("operation") == &"source_map_arrival" and event.get("arguments") == [transaction] and _host.verify_committed_original_map_arrival(transaction)
func commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not can_commit_actual_original_map_arrival(transaction): return false
	_world = transaction.after_world.duplicate(true)
	return true
