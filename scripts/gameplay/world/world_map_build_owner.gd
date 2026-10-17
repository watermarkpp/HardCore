extends RefCounted

## Background's staged-build facade. Every collision and query is delegated to
## the SAME configured environment; no second bodies/index/map/RNG is created.
var _owner := OS.get_thread_caller_id()
var _world_ref: WeakRef
var _world: RefCounted:
	get: return _world_ref.get_ref() if _world_ref != null else null
	set(value): _world_ref = weakref(value) if value != null else null
var _factory: RefCounted
var _environment: RefCounted
var _transport: RefCounted
var _coordinator: RefCounted
var _map_id := -1
var _generation := -1
var _complete := false
var _map_descriptors: Array = []
var _collision_descriptors: Array = []
var _visual_facts: Dictionary = {}
var zone_name := ""
var zone_data: Dictionary = {}

func owner_thread_id() -> int: return _owner
func configure_owner(world: RefCounted, factory: RefCounted, transport: RefCounted) -> bool:
	if _world != null or world.owner_thread_id() != _owner or factory.owner_thread_id() != _owner or transport.owner_thread_id() != _owner: return false
	if not factory.has_method("adopt_original_loading_publication") or not factory.environment.has_method("clear_original_map_environment") or not factory.environment.has_method("finish_original_map_build"): return false
	_world = world; _factory = factory; _environment = factory.environment; _transport = transport
	return true
func _trace_rejected_current(reason: String, details: Dictionary = {}) -> void:
	if not bool(_world.clock_ports.get_setting("hardcore/diagnostics/main_boot_trace",false)): return
	print("HC_SOURCE_MAP_BUILD_REJECT ",JSON.stringify({"reason":reason,"usec":Time.get_ticks_usec(),"generation":_generation,"world":_world.current_world_identity(),"descriptor_world":_transport.get("_descriptor").get("world_context"),"scope":_transport.get("_scope"),"details":details}))
func _current() -> bool:
	if _coordinator == null: return false
	if not _coordinator.is_generation_current(_generation):
		_trace_rejected_current("coordinator_generation",{"current_generation":_coordinator.generation,"current_stage":_coordinator.stage})
		return false
	var current: bool = _transport.scope_is_current()
	if not current: _trace_rejected_current("native_map_scope")
	return current
func prepare_map_build(map_id: int, coordinator: RefCounted, data: Dictionary) -> Dictionary:
	if coordinator.owner_thread_id() != _owner or not _transport.scope_is_current(): return {"ok":false}
	_coordinator = coordinator; _generation = coordinator.generation; _map_id = map_id; _complete = false
	zone_name = str(data.get("name", "")); zone_data = data.duplicate(true)
	# Original COLLECT_REQUIREMENTS clears old authority before resource requests.
	if not _environment.clear_original_map_environment(_generation, map_id, data): return {"ok":false}
	var prepared: Dictionary = await _transport.exchange_original_map_leaf("prepare",[map_id,_generation,data])
	if not _current() or prepared.get("ok") != true: return {"ok":false}
	coordinator.resource_manifest = prepared.resource_manifest.duplicate(true)
	return prepared
func set_pending_arrival_position(position_px: Vector2) -> void:
	_environment.set_original_pending_arrival_position(position_px)
func submit_staged_build() -> bool:
	if not _current(): return false
	var selected: Dictionary = await _transport.exchange_original_map_leaf("select_descriptors",[])
	if not _current() or selected.get("ok") != true: return false
	# Required resources are actually acquired before masks and pin-backed values.
	var captured: Dictionary = await _transport.exchange_original_map_leaf("capture_environment",[])
	if not _current() or captured.get("ok") != true or not _factory.adopt_original_loading_publication(captured.publication,captured.actual_loading_receipt,_transport): return false
	_map_descriptors = selected.descriptors.duplicate(true)
	_collision_descriptors = _environment.build_collision_descriptors(zone_data)
	if _environment.get("_editor_runtime_collision_invalid") == true: return false
	_coordinator.submit_map_descriptors(_map_descriptors)
	_coordinator.submit_collision_descriptors(_collision_descriptors)
	return true
func build_one_map_item(descriptor: Dictionary) -> Dictionary:
	if not _current(): return {"ok":false,"cancelled":true}
	var built: Dictionary = await _transport.exchange_original_map_leaf("build_item",[descriptor])
	if not _current(): return {"ok":false,"cancelled":true}
	if built.get("ok") == true:
		_visual_facts = built.visual_facts
		if not _environment.install_original_gothic_build_entries(_visual_facts.gothic_collision_entries):
			_trace_rejected_current("environment_install",{"entries":_visual_facts.gothic_collision_entries.size()})
			return {"ok":false}
	return built
func build_one_collision(descriptor: Dictionary) -> Variant:
	if not _current(): return null
	var built: Dictionary = _environment.build_one_collision(descriptor)
	return built if built.get("ok") == true and not built.get("cancelled",false) else null
func finish_map_build() -> bool:
	if not _current(): return false
	var visual: Dictionary = await _transport.exchange_original_map_leaf("finish_visual",[])
	if not _current() or visual.get("ok") != true: return false
	if not _environment.finish_original_map_build(_generation,_map_id): return false
	_complete = true; _visual_facts = visual.visual_facts
	return true
func set_zone_data(value: String, data: Dictionary) -> void:
	if not _complete or int(data.get("mapId",-1)) != _map_id:
		_world.fault("arrival_before_actual_map_build",{})
		return
	zone_name = value; zone_data = data.duplicate(true)
	_environment.zone_name = value; _environment.zone_data = data.duplicate(true)
	# Only an actual accepted Main visual command may update the display later.
	_world.emit_original_main_event(&"source_map_visual_zone",[value,data,_generation])
func set_focus_position(position: Vector2) -> void:
	_environment.set_original_focus_position(position)
	_world.emit_original_main_event(&"source_map_visual_focus",[position,_generation])
func environment_node_count() -> int: return int(_visual_facts.get("environment_node_count",0))
func editor_runtime_chunk_texture_count() -> int: return int(_visual_facts.get("chunk_texture_count",0))
func environment_collision_revision() -> int: return _environment.environment_collision_revision()
func is_environment_point_blocked(position: Vector2) -> bool: return _environment.is_environment_point_blocked(position)
func is_environment_actor_blocked(position: Vector2, radius: float) -> bool: return _environment.is_environment_actor_blocked(position,radius)
func profile_for_map(map_id: int) -> Dictionary: return _factory.catalog.get_map_profile(_environment._presentation_map_id(map_id))
func owner_environment() -> RefCounted: return _environment
