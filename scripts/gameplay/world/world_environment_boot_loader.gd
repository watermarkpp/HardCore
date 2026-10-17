extends RefCounted

const Codec := preload("res://scripts/gameplay/world/world_environment_transport_codec.gd")
const WorldClock := preload("res://scripts/world_monster_clock_ledger.gd")
const CONTRACT_ID := "world.environment.formal_boot.v1"
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var _world_ref: WeakRef
var _factory_ref: WeakRef
var publication: Dictionary
var boot: Dictionary

func owner_thread_id() -> int:
	return _owner_thread

func _fault(code: String, details: Dictionary) -> void:
	var world: Object = _world_ref.get_ref() if _world_ref != null else null
	if world != null:
		world.fault(code, details)

func configure_owner(native_boot: Dictionary, world: Object) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread or world == null or world is Node or world is Resource or not world.has_method("owner_thread_id") or world.owner_thread_id() != _owner_thread or not world.has_method("fault"):
		return false
	_world_ref = weakref(world)
	if not ClassDB.class_exists("HardCoreContentValueGraph"):
		_fault("native_math_value_graph_missing", {})
		return false
	var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph") as RefCounted
	var validated: Dictionary = native.call("validate", native_boot, false)
	if not validated.get("success", false):
		_fault("native_boot_graph_invalid", {"errors": validated.get("errors", [])})
		return false
	if native_boot.get("contract_id") != CONTRACT_ID or not native_boot.get("world_identity") is Dictionary or not native_boot.get("runtime_map_id") is int or not native_boot.get("world_clock_generation") is String or not WorldClock.valid_generation(native_boot.world_clock_generation):
		_fault("environment_boot_identity_invalid", {})
		return false
	var identity: Dictionary = native_boot.world_identity
	if identity.size() != 5 or identity.get("contract_id") != "hardcore.execution.world_context.v1" or identity.get("runtime_map_id") != native_boot.runtime_map_id or not identity.get("world_runtime_id") is int or identity.world_runtime_id <= 0 or not identity.get("world_epoch") is int or identity.world_epoch < 0 or not identity.get("profile_id") is String or identity.profile_id.is_empty():
		_fault("environment_boot_world_schema_invalid", {})
		return false
	for field: String in ["runtime_source_documents", "default_area", "project_settings", "body_templates", "engine_clock", "background_clock_eligibility", "host_config"]:
		if not native_boot.get(field) is Dictionary:
			_fault("environment_boot_field_missing", {"field": field})
			return false
	var area: Dictionary = native_boot.default_area
	for field: String in ["gravity", "linear_damp", "angular_damp"]:
		if not (area.get(field) is int or area.get(field) is float) or not is_finite(float(area[field])):
			_fault("environment_boot_area_invalid", {"field": field})
			return false
	if not area.get("gravity_vector") is Vector2 or not area.gravity_vector.is_finite():
		_fault("environment_boot_gravity_vector_invalid", {})
		return false
	var clock: Dictionary = native_boot.engine_clock
	for field: String in ["physics_ticks_per_second", "max_physics_steps_per_frame", "process_frames", "physics_frames", "wall_msec", "wall_usec"]:
		if not clock.get(field) is int or clock[field] < 0:
			_fault("environment_boot_clock_invalid", {"field": field})
			return false
	for field: String in ["time_scale", "physics_jitter_fix"]:
		if not (clock.get(field) is int or clock.get(field) is float) or not is_finite(float(clock[field])) or clock[field] < 0.0:
			_fault("environment_boot_clock_invalid", {"field": field})
			return false
	if not clock.get("paused") is bool or clock.physics_ticks_per_second <= 0 or native_boot.host_config.get("physics_hz") != clock.physics_ticks_per_second:
		_fault("environment_boot_clock_host_mismatch", {})
		return false
	for field: String in ["max_epochs_per_turn", "timer_capacity", "input_capacity", "event_capacity"]:
		if not native_boot.host_config.get(field) is int or native_boot.host_config[field] <= 0:
			_fault("environment_boot_host_config_invalid", {"field": field})
			return false
	var eligibility: Dictionary = native_boot.background_clock_eligibility
	for field: String in ["can_process", "process_processing", "physics_processing", "inside_world", "queued_for_retirement"]:
		if not eligibility.get(field) is bool:
			_fault("environment_boot_clock_eligibility_missing", {"field": field})
			return false
	if not eligibility.get("process_mode") is int:
		_fault("environment_boot_clock_eligibility_missing", {"field": "process_mode"})
		return false
	var decoded: Dictionary = Codec.decode(native_boot.get("environment_wire"))
	if not decoded.ok or not decoded.value is Dictionary:
		_fault("environment_boot_wire_invalid", {"errors": decoded.get("errors", [])})
		return false
	publication = decoded.value
	var map_id: int = native_boot.runtime_map_id
	if map_id < 0:
		if not _valid_original_pre_map_context(native_boot, publication, world):
			_fault("environment_pre_map_context_invalid", {})
			return false
		map_id = native_boot.pre_map_context.background_reference_map_id
	if not publication.get("runtime_maps") is Dictionary or not publication.runtime_maps.has(map_id) or not native_boot.runtime_source_documents.has(map_id):
		_fault("environment_boot_active_runtime_missing", {"map_id": map_id})
		return false
	var entry: Dictionary = publication.runtime_maps[map_id]
	if not entry.get("formal_playable", false) or not entry.get("runtime") is Dictionary or entry.runtime.is_empty():
		_fault("environment_boot_active_runtime_unready", {"map_id": map_id})
		return false
	for id: int in native_boot.runtime_source_documents:
		var document: Dictionary = native_boot.runtime_source_documents[id]
		if not document.get("raw_utf8") is PackedByteArray or not document.get("raw_json") is String or not document.get("raw_file_sha256") is String or not document.get("original_json") is Dictionary or not publication.runtime_maps.has(id):
			_fault("environment_boot_runtime_document_invalid", {"map_id": id})
			return false
		var bytes: PackedByteArray = document.raw_utf8
		var hash_context := HashingContext.new()
		if hash_context.start(HashingContext.HASH_SHA256) != OK or hash_context.update(bytes) != OK or hash_context.finish().hex_encode() != document.raw_file_sha256 or bytes.get_string_from_utf8() != document.raw_json or str(publication.runtime_maps[id].runtime.get("build_sha256", "")) != document.get("build_sha256"):
			_fault("environment_boot_runtime_source_fingerprint_mismatch", {"map_id": id})
			return false
	var body: Dictionary = native_boot.body_templates
	if not body.get("motion") is Dictionary or not body.get("footprints") is Dictionary or not body.get("filters") is Dictionary or not body.get("policy") is Dictionary:
		_fault("environment_boot_body_templates_invalid", {})
		return false
	if not body.motion.get("motion_mode") is int or body.motion.motion_mode != 1 or not body.motion.get("max_slides") is int or body.motion.max_slides <= 0:
		_fault("environment_boot_motion_settings_invalid", {})
		return false
	for field: String in ["safe_margin", "wall_min_slide_angle", "collision_priority"]:
		if not (body.motion.get(field) is float or body.motion.get(field) is int) or not is_finite(float(body.motion[field])):
			_fault("environment_boot_motion_settings_invalid", {"field": field})
			return false
	for tier: String in ["player", "small", "large"]:
		if not body.footprints.get(tier) is Dictionary or not body.footprints[tier].get("footprint_points") is PackedVector2Array or body.footprints[tier].footprint_points.size() != 16:
			_fault("environment_boot_footprint_invalid", {"tier": tier})
			return false
		for point: Vector2 in body.footprints[tier].footprint_points:
			if not point.is_finite():
				_fault("environment_boot_footprint_nonfinite", {"tier": tier})
				return false
	for filter_kind: String in ["player", "enemy_ground", "enemy_flying", "summon"]:
		if not body.filters.get(filter_kind) is Dictionary or not body.filters[filter_kind].get("collision_layer") is int or not body.filters[filter_kind].get("collision_mask") is int:
			_fault("environment_boot_collision_filters_missing", {"kind": filter_kind})
			return false
	boot = native_boot
	_configured = true
	return true

func _valid_original_pre_map_context(value: Dictionary, environment: Dictionary, world: Object) -> bool:
	# Only the actual first Source constructor can admit the original -1 map.
	# No negative entry is added to the map table and geometry queries remain
	# strict. Later map arrival commits through the original source transaction.
	if value.runtime_map_id != -1 or value.world_identity.get("world_epoch") != 0 or not world.has_method("current_clock_frame"):
		return false
	var frame: Dictionary = world.current_clock_frame()
	if frame.get("epoch") != 0 or not value.get("pre_map_context") is Dictionary:
		return false
	var initial: Dictionary = value.pre_map_context
	var source: Script = preload("res://scripts/world_background.gd")
	if initial.size() != 6 or initial.get("contract_id") != "world.environment.pre_map_context.v1" or initial.get("world_identity") != value.world_identity or initial.get("source_path") != source.resource_path or initial.get("source_sha256") != source.get_source_code().sha256_text():
		return false
	if not initial.get("background_reference_map_id") is int or initial.background_reference_map_id < 0 or not initial.get("prepared_map_ids") is Array or initial.prepared_map_ids.is_empty() or initial.prepared_map_ids != environment.get("map_load_order"):
		return false
	if not environment.get("runtime_maps") is Dictionary or environment.runtime_maps.has(-1) or not initial.prepared_map_ids.has(initial.background_reference_map_id):
		return false
	var state: Variant = environment.get("background")
	if not state is Dictionary or not state.get("zone_data") is Dictionary or not state.zone_data.is_empty() or state.get("source_collision_shape_count") != 0 or state.get("source_mask_present") != false or state.get("editor_runtime_size") != Vector2i.ZERO:
		return false
	for id: Variant in initial.prepared_map_ids:
		if not id is int or id < 0 or not environment.runtime_maps.has(id) or not value.runtime_source_documents.has(id): return false
		var entry: Variant = environment.runtime_maps[id]
		if not entry is Dictionary or entry.get("formal_playable") != true or not entry.get("runtime") is Dictionary or entry.runtime.is_empty(): return false
	return true

func attach_environment_factory(factory: Object) -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or factory == null or factory is Node or factory is Resource or not factory.has_method("owner_thread_id") or factory.owner_thread_id() != _owner_thread or factory.get("_configured") != true:
		return false
	_factory_ref = weakref(factory)
	return true

func runtime_map(map_id: int) -> Dictionary:
	var factory: Object = _factory_ref.get_ref() if _factory_ref != null else null
	if not _configured or OS.get_thread_caller_id() != _owner_thread or factory == null:
		_fault("environment_boot_shared_factory_unavailable", {"map_id": map_id})
		return {}
	if not factory.runtime_maps.require_map(map_id):
		return {}
	return factory.runtime_maps.load_map(map_id)

func projection_profile(map_id: int) -> Dictionary:
	var factory: Object = _factory_ref.get_ref() if _factory_ref != null else null
	if not _configured or OS.get_thread_caller_id() != _owner_thread or factory == null:
		_fault("environment_boot_shared_factory_unavailable", {"map_id": map_id})
		return {"success": false, "reason": "environment_boot_shared_factory_unavailable"}
	return factory.coordinate_mapper.resolve_formal_runtime_projection_profile(map_id)

func actor_motion_configuration(tier: String, filter_kind: String, position_screen_px: Vector2) -> Dictionary:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or not position_screen_px.is_finite() or not boot.body_templates.footprints.has(tier) or not boot.body_templates.filters.has(filter_kind):
		_fault("environment_boot_body_selection_invalid", {"tier": tier, "filter_kind": filter_kind})
		return {}
	var configuration: Dictionary = boot.body_templates.motion.duplicate(false)
	configuration["position_screen_px"] = position_screen_px
	configuration["footprint_points"] = boot.body_templates.footprints[tier].footprint_points
	configuration.merge(boot.body_templates.filters[filter_kind])
	return configuration
