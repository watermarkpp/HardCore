extends RefCounted
## Loading-only capture of the actual detached original Root constructor.
## Consumer field names are derived from the installed same-source adapters;
## values come from the original object, never a hand-authored default table.
const Values := preload("res://scripts/gameplay/source/source_constructor_value_codec.gd")
const RootCode := preload("res://scripts/game_root.gd")
const SourceRoot := preload("res://scripts/gameplay/world/world_root_interactable_loading.gd")
const OWNER_OBJECT_TYPES := {
	"_world_context":"res://scripts/layers/runtime/execution/world_context.gd",
	"_world_bootstrap_coordinator":"res://scripts/world_bootstrap_coordinator.gd",
	"_feature_target_bound":"res://scripts/features/adapters/world_target_bound.gd"}
const EXTRA_OWNER_SLOTS: Array[String] = ["player","background","_rng","_world_skill_domain","_feature_target_bound","_ground_effect_manager","locked_target","magic_locked_target","_skill_cast_target"]
static func capture_original_constructor_fields(root: Node2D) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not is_instance_valid(root) or root.get_script() != RootCode or root.is_inside_tree() or root.is_queued_for_deletion() or root.get("current_map_id") != -1 or root.get("_zone_generation") != 0:
		return {"success":false,"errors":["original_detached_initial_Root_required"]}
	var wanted: Dictionary = {}
	var source_hashes: Dictionary = {}
	var code: Script = SourceRoot
	var expression := RegEx.create_from_string("(?:read_source_field|write_source_field|bind_owner_field)\\s*\\(\\s*&?\"([^\"]+)\"")
	while code != null:
		var text: String = code.get_source_code()
		source_hashes[code.resource_path] = text.sha256_text()
		for found: RegExMatch in expression.search_all(text): wanted[found.get_string(1)] = true
		code = code.get_base_script()
	for field: String in EXTRA_OWNER_SLOTS: wanted[field] = true
	var available: Dictionary = {}
	for property: Dictionary in root.get_property_list(): available[String(property.name)] = true
	var fields: Dictionary = {}
	var errors: Array[String] = []
	var late: Array[String] = []
	var random: Dictionary = {}
	for field: String in wanted:
		if field == "map_combat_transition_token":
			# Original finish paths use get_meta with exactly this empty fallback.
			fields[field] = root.get_meta(field, "")
			continue
		if field == "home_resolution_failure_diagnostic":
			# Original source creates this metadata only on the failure branch.
			fields[field] = root.get_meta(field) if root.has_meta(field) else null
			continue
		if not available.has(field): errors.append("original_Root_field_missing:"+field); continue
		var value: Variant = root.get(field)
		if OWNER_OBJECT_TYPES.has(field):
			if not value is RefCounted or value is Resource or value.get_script() != load(OWNER_OBJECT_TYPES[field]):
				errors.append("original_Root_owner_object_type:"+field); continue
			if field == "_world_context" and not value.capture_world().is_empty():
				errors.append("original_Root_context_already_entered"); continue
			if field == "_feature_target_bound" and (not value.get("_world").is_empty() or not value.get("_slots").is_empty() or not value.get("_closures").is_empty() or not value.get("_inputs").is_empty() or value.get("_sealed")):
				errors.append("original_Root_target_bound_already_used"); continue
			if field == "_world_bootstrap_coordinator":
				if value.get("stage") != 0 or value.get("generation") != 0 or value.get("map_id") != -1:
					errors.append("original_Root_bootstrap_already_started"); continue
				var busy := false
				for key: String in ["_map_build_queue","_collision_build_queue","_actor_spawn_queue","resource_manifest","_prefetched_resources","_consumed_paths"]:
					if not value.get(key).is_empty(): busy = true
				if busy: errors.append("original_Root_bootstrap_has_obligations"); continue
			fields[field] = null; late.append(field)
			continue
		if field == "_rng":
			if not value is RandomNumberGenerator: errors.append("actual_original_Root_RNG_required"); continue
			random = {"seed":value.seed,"state":value.state}
			# Explicit storage binding is fulfilled by the existing S ready RNG
			# owner. This null is not a claimed runtime value of the Main object.
			fields[field] = null; late.append(field)
		elif value is Object or value is Callable or value is Signal:
			errors.append("original_Root_object_requires_explicit_owner_binding:"+field)
		else: fields[field] = value
	if not errors.is_empty(): return {"success":false,"errors":errors}
	late.sort()
	var encoded: Dictionary = Values.encode(fields,root.get_script().get_source_code().sha256_text())
	if encoded.get("ok") != true: return {"success":false,"errors":["original_constructor_encoding_rejected"],"details":encoded}
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary = graph.capture({"source_fields":{"contract_id":"world.source_fields.handoff.v1", "fields":encoded.value.fields,"unbound_owner_fields":late,"constructor_values":encoded.value.constructor_values}, "world_random":random,
		"original_root_id":root.get_instance_id(),"original_source_sha256":root.get_script().get_source_code().sha256_text(),"consumer_source_sha256":source_hashes},true,false)
	if captured.get("success") != true: return {"success":false,"errors":["original_Root_fields_not_plain"],"details":captured}
	var result: Dictionary = captured.value.duplicate(false)
	result.success = true
	return result
