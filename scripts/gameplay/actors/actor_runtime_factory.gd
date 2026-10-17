extends RefCounted

## Call ONLY in the factory/on_phase of production HardCoreSimulationHost.start.
## Relative paths are intentional: staging itself can be parsed before promotion.
const PlayerModel := preload("player_actor_model.gd")
const SummonModel := preload("summon_actor_model.gd")
const Ports := preload("actor_runtime_ports.gd")
const Motion := preload("actor_native_motion_port.gd")
const Runtime := preload("actor_runtime_instance.gd")
const ProfileModel := preload("res://scripts/gameplay/profile/profile_model.gd")
const ContentPort := preload("res://scripts/gameplay/profile/profile_content_port.gd")
const ActionTiming := preload("res://scripts/gameplay/world/world_skill_action_timing.gd")
const ValueGraph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Warrior := preload("res://scripts/warrior_combat_math.gd")
const Combat := preload("res://scripts/combat_resolution_rules.gd")
const Art := preload("res://scripts/art_spec.gd")
const Skills := preload("res://scripts/skills/skill_data_loader.gd")
const Resources := preload("res://scripts/skills/skill_resource_service.gd")
const Visibility := preload("res://scripts/skills/skill_visibility_policy.gd")
const InputPortScript := preload("res://scripts/skill_input_policy.gd")
const SummonRules := preload("res://scripts/taoist_combat_math.gd")
const Ranks := preload("res://scripts/skills/skill_rank_resolver.gd")
const REQUIRED_WORLD_METHODS := [
	"fault", "actor_runtime_is_faulted", "actor_native_birth_registered", "environment_blocks_actor_screen_px", "query_aabb_candidates",
	"unregister_combat_target", "queue_actor_retirement", "canonical_summon_follow_landing_plan",
	"capture_follow_landing_authority", "register_pending_main_pet_arrival", "emit_actor_fact",
	"update_actor_spatial", "actor_spatial_available", "player_keyboard_movement_vector",
	"on_player_stats_changed", "on_player_resources_changed", "on_actor_passive_wakeup_changed",
	"on_player_attack_requested", "on_player_skill_requested", "on_player_death_requested",
	"on_player_movement_performed", "on_player_skill_cast_started", "on_player_warrior_skill_state_changed",
	"on_summon_state_changed",
]
const REQUIRED_CONTEXT := ["world_core", "registry", "host", "native_world", "profile", "content", "action_timing",
	"screen_to_ground", "ground_to_screen", "motion_configuration", "life_generation", "stable_combat_order",
	"parent_scope_id", "can_process", "physics_processing_enabled", "combat_radius_gu", "visual_available", "damage_recording_enabled", "combat_contract_sha256"]

static func validate_required(context: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if OS.get_thread_caller_id() == OS.get_main_thread_id(): errors.append("simulation_owner_required")
	for name: String in REQUIRED_CONTEXT:
		if not context.has(name): errors.append("missing_context:" + name)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	for name: String in ["world_core", "registry", "host", "native_world", "profile", "content", "action_timing"]:
		var object: Variant = context[name]
		if not object is Object or object is Node or object is Resource or not is_instance_valid(object):
			errors.append("invalid_owner_object:" + name)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	if not context.registry is Registry: errors.append("canonical_registry_required")
	if not context.profile is ProfileModel: errors.append("canonical_profile_model_required")
	if not context.content is ContentPort: errors.append("canonical_profile_content_port_required")
	if not context.action_timing is ActionTiming: errors.append("canonical_numeric_action_timing_required")
	if not ClassDB.class_exists("HardCoreContentValueGraph"): errors.append("native_value_capture_required")
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	if context.profile._owner_thread_id != OS.get_thread_caller_id() or not context.profile._configured:
		errors.append("configured_s_profile_required")
	for name: String in ["_mode_port", "_runtime_port", "_diagnostics_port"]:
		var profile_port: Variant = context.profile.get(name)
		if not profile_port is RefCounted or profile_port is Node:
			errors.append("missing_s_profile_port:" + name)
		elif profile_port.get_script() != null and "legacy_" in str(profile_port.get_script().resource_path):
			errors.append("legacy_main_profile_port_forbidden:" + name)
	if context.profile._feature_port == null or context.profile._feature_port._source is Node: errors.append("main_feature_source_forbidden")
	if context.profile._content_port != context.content or not context.content.simulation_owner:
		errors.append("same_owner_content_required")
	if context.content._owner_thread_id != OS.get_thread_caller_id(): errors.append("content_owner_mismatch")
	if not context.content.has_method("potion_recovery_profile"): errors.append("single_source_potion_projection_required")
	if not Gate.owns_reader(context.content._source.catalog_lease): errors.append("content_reader_not_active")
	if context.host.get_class() != "HardCoreSimulationHost" or not context.host.has_method("create_timer"):
		errors.append("production_native_host_required")
	if context.native_world.get_class() != "HardCoreSimulationWorld2D": errors.append("production_native_world_required")
	else:
		var world_state: Dictionary = context.native_world.call("state")
		if world_state.get("ok") != true or world_state.get("owner_thread") != OS.get_thread_caller_id() or not world_state.get("space_rid", RID()).is_valid():
			errors.append("initialized_same_owner_native_world_required")
	for method: String in REQUIRED_WORLD_METHODS:
		if not context.world_core.has_method(method): errors.append("missing_world_method:" + method)
	if not context.action_timing.has_method("primary_action_completion_seconds"): errors.append("numeric_action_timing_required")
	for key: String in ["screen_to_ground", "ground_to_screen"]:
		if not context[key] is Callable or not context[key].is_valid(): errors.append("missing_projection:" + key)
	if not context.life_generation is int or context.life_generation <= 0: errors.append("positive_original_life_required")
	if not context.stable_combat_order is int or context.stable_combat_order < 0: errors.append("stable_order_required")
	if not context.parent_scope_id is int or context.parent_scope_id <= 0: errors.append("original_parent_scope_required")
	for key: String in ["can_process", "physics_processing_enabled", "visual_available", "damage_recording_enabled"]:
		if not context[key] is bool: errors.append("boolean_qualification_required:" + key)
	if not (context.combat_radius_gu is float or context.combat_radius_gu is int) or not is_finite(context.combat_radius_gu) or context.combat_radius_gu < 0:
		errors.append("canonical_combat_radius_required")
	if not context.motion_configuration is Dictionary:
		errors.append("numeric_motion_configuration_required")
	else:
		var configuration: Dictionary = context.motion_configuration
		for key: String in ["position_screen_px", "footprint_points", "collision_layer", "collision_mask", "motion_mode", "safe_margin", "max_slides", "wall_min_slide_angle", "collision_priority"]:
			if not configuration.has(key): errors.append("missing_motion_field:" + key)
		if not configuration.get("position_screen_px") is Vector2 or not configuration.get("footprint_points") is PackedVector2Array:
			errors.append("published_exact_motion_shape_required")
		elif configuration.footprint_points.size() != 16: errors.append("original_16_point_footprint_required")
	# CombatResolutionRules currently has one static cache. Never let S perform
	# its lazy population. Root includes this cache in the frozen catalog DAG.
	if Combat._contract_cache.is_empty(): errors.append("combat_contract_not_published")
	elif not Combat._contract_cache.is_read_only() or not context.combat_contract_sha256 is String or ValueGraph.fingerprint(Combat._contract_cache) != context.combat_contract_sha256:
		errors.append("combat_contract_publication_mismatch")
	return {"ok":errors.is_empty(),"errors":errors}

static func _begin(context: Dictionary, model: RefCounted, kind: StringName) -> RefCounted:
	# Source temporal scope life describes its original Node incarnation; it
	# must not overwrite Player.combat_epoch. That property starts at zero and
	# advances only at the original begin_combat_transition call.
	var actor_life: int = model.current_life() if kind == &"player" else int(context.life_generation)
	var record: Object = context.registry.register_actor(model, actor_life, kind, context.stable_combat_order)
	if record == null:
		context.world_core.fault("actor_registration_failed", {"kind":kind})
		return null
	if not record.has_method("set_runtime_qualification") or not record.set_runtime_qualification(context.parent_scope_id, context.can_process, context.physics_processing_enabled):
		context.world_core.fault("actor_runtime_qualification_missing", {"kind":kind})
		context.registry.retire_runtime_actor(record.get_instance_id())
		return null
	if not model.bind_runtime_actor_id(record.get_instance_id()):
		context.world_core.fault("actor_identity_binding_failed", {"kind":kind})
		context.registry.retire_runtime_actor(record.get_instance_id())
		return null
	var native_motion: Object = context.native_world.call("create_actor", record.get_instance_id(), context.motion_configuration)
	if native_motion == null:
		context.world_core.fault("actor_native_creation_failed", {"kind":kind})
		context.registry.retire_runtime_actor(record.get_instance_id())
		return null
	var ports := Ports.new(context.world_core, context.registry, record, model, context.host, context.screen_to_ground,
		float(context.combat_radius_gu), context.visual_available, context.damage_recording_enabled)
	var motion := Motion.new(context.world_core, context.native_world, native_motion, ports)
	ports.bind_motion(motion)
	var created := Runtime.new(model, record, ports, motion, context.registry, context.native_world, kind)
	if not context.world_core.actor_native_birth_registered(created, context):
		created.final_retire()
		return null
	return created

static func create_player(context: Dictionary) -> Dictionary:
	var validation := validate_required(context)
	if not validation.ok: return validation
	for name: String in ["hc_world_skill_preflight", "hc_action_configuration_provider", "hc_melee_configuration_provider", "hc_action_configuration_identity"]:
		if not context.get(name) is Callable or not context[name].is_valid(): return {"ok":false,"errors":["missing_provider:" + name]}
	var model := PlayerModel.new()
	# Player's original combat_epoch remains the only life authority.
	var runtime: RefCounted = _begin(context, model, &"player")
	if runtime == null: return {"ok":false,"errors":["player_assembly_failed"]}
	var rules: RefCounted = context.profile._rules
	model.configure_ports({"profile":context.profile,"content":context.content,"profession_rules":rules.professions,
		"equipment_rules":rules.equipment,"relic_rules":rules.relic,"warrior_rules":Warrior,"combat_rules":Combat,
		"phase_scheduler":runtime.ports,"lifetime":runtime.ports,"motion":runtime.motion,
		"presentation":runtime.ports,"damage_observer":runtime.ports,"status":runtime.ports})
	model.configure_execution_ports({"input_state":runtime.ports,"actor_lookup":runtime.ports,"action_timing":context.action_timing,
		"art_rules":Art,"skill_data":Skills,"skill_resources":Resources,"skill_visibility":Visibility,"skill_input":InputPortScript})
	# Mandatory configuration providers come from the existing WorldSkill owner.
	for name: String in ["hc_world_skill_preflight", "hc_action_configuration_provider", "hc_melee_configuration_provider", "hc_action_configuration_identity"]:
		if not context.get(name) is Callable or not context[name].is_valid():
			runtime.ports.fail("player_configuration_provider_missing", {"name":name})
			runtime.final_retire()
			return {"ok":false,"errors":["missing_provider:" + name]}
		model.set(name, context[name])
	model.stats_changed.connect(runtime.ports.on_stats_changed)
	model.resources_changed.connect(runtime.ports.on_resources_changed)
	model.passive_wakeup_changed.connect(runtime.ports.on_passive_wakeup_changed)
	model.attack_requested.connect(runtime.ports.on_attack_requested)
	model.skill_requested.connect(runtime.ports.on_skill_requested)
	model.death_requested.connect(runtime.ports.on_death_requested)
	model.movement_performed.connect(runtime.ports.on_movement_performed)
	model.skill_cast_started.connect(runtime.ports.on_skill_cast_started)
	model.warrior_skill_state_changed.connect(runtime.ports.on_warrior_skill_state_changed)
	# Same Source child/qualification boundary and pre-ready subscriptions as
	# original GameRoot.add_child(player). Preserve model.current_life()==0.
	if not context.world_core.prepare_original_player_ready(runtime): return {"ok":false,"errors":["original_player_pre_ready_failed"],"runtime":runtime}
	if not runtime.ports.publish_pose(): return {"ok":false,"errors":["initial_pose_failed"],"runtime":runtime}
	model.initialize_gameplay()
	# PlayerCharacter._ready constructs/enters its actual PlayerVisual child
	# after initialize_gameplay. Retain that child's P scope on Source; Main
	# still owns all render objects and receives the same numerical model facts.
	if not context.world_core.enter_original_player_visual_ready(runtime): return {"ok":false,"errors":["original_player_visual_ready_failed"],"runtime":runtime}
	model.stats_changed.emit(model.current_hp, model.max_hp)
	model.resources_changed.emit(model.current_hp, model.max_hp, model.current_mp, model.max_mp)
	return {"ok":runtime.healthy(),"runtime":runtime}

static func create_summon(context: Dictionary, owner: RefCounted, birth: Dictionary) -> Dictionary:
	var validation := validate_required(context)
	if not validation.ok: return validation
	if owner == null or owner.resolve_record() == null: return {"ok":false,"errors":["canonical_owner_link_required"]}
	var owner_record: Object = owner.resolve_record()
	if context.registry.resolve_runtime_actor(owner_record.get_instance_id()) != owner_record or owner_record.kind() != &"player" or not owner_record.is_inside_world() or owner_record.is_queued_for_retirement():
		return {"ok":false,"errors":["same_world_active_player_owner_required"]}
	for key: String in ["display_name", "power", "skill_rank", "skill_id", "owner_level", "maximum_pet_level", "pet_slot_index", "release_id", "visual_timing_profile", "visual_profile_complete", "visual_preview_active"]:
		if not birth.has(key): return {"ok":false,"errors":["missing_birth:" + key]}
	if birth.skill_id not in ["taoist.summon_skeleton", "taoist.summon_divine_beast"]:
		return {"ok":false,"errors":["stable_summon_skill_required"]}
	if not birth.display_name is String or not birth.release_id is String or birth.release_id.is_empty() or not birth.visual_timing_profile is Dictionary:
		return {"ok":false,"errors":["numeric_birth_profile_required"]}
	if not birth.visual_profile_complete is bool or not birth.visual_preview_active is bool:
		return {"ok":false,"errors":["published_visual_presence_required"]}
	for key: String in ["power", "skill_rank", "owner_level", "maximum_pet_level", "pet_slot_index"]:
		if not birth[key] is int or birth[key] < 0: return {"ok":false,"errors":["invalid_birth_integer:" + key]}
	var model := SummonModel.new(SummonRules, Ranks, 0.0)
	var runtime: RefCounted = _begin(context, model, &"summon")
	if runtime == null: return {"ok":false,"errors":["summon_assembly_failed"]}
	model.configure_ports({"profile":context.profile,"profession_rules":context.profile._rules.professions,
		"warrior_rules":Warrior,"combat_rules":Combat,"art_rules":Art,"actor_links":runtime.ports,
		"motion":runtime.motion,"lifetime":runtime.ports,"presentation":runtime.ports,
		"damage_observer":runtime.ports,"landing":runtime.ports,"spatial":runtime.ports})
	model.configure_runtime_map_projection(context.registry.capture_world().runtime_map_id, context.ground_to_screen, context.screen_to_ground)
	model.pet_slot_index = birth.pet_slot_index
	model.combat_radius_gu = context.combat_radius_gu
	model.setup(owner, birth.display_name, birth.power, birth.skill_rank, birth.skill_id, birth.owner_level, birth.maximum_pet_level)
	model.activate_numeric_visual_profile(birth.visual_timing_profile)
	model._visual_profile_complete = birth.visual_profile_complete
	model._visual_preview_active = birth.visual_preview_active
	model.passive_wakeup_changed.connect(runtime.ports.on_passive_wakeup_changed)
	model.summon_state_changed.connect(runtime.ports.on_summon_state_changed)
	if not runtime.ports.publish_pose(): return {"ok":false,"errors":["initial_pose_failed"],"runtime":runtime}
	model.initialize_gameplay()
	model.configure_spawn_release_footprint(birth.release_id)
	return {"ok":runtime.healthy(),"runtime":runtime}

## Original SummonActor.new/configure boundary; setup and _ready remain at the
## original caller positions. Never pre-call setup/initialize with guessed birth.
static func create_unconfigured_summon(context: Dictionary) -> Dictionary:
	var validation := validate_required(context)
	if not validation.ok: return validation
	var model := SummonModel.new(SummonRules, Ranks, 0.0)
	var runtime: RefCounted = _begin(context, model, &"summon")
	if runtime == null: return {"ok":false,"errors":["summon_assembly_failed"]}
	model.configure_ports({"profile":context.profile,"profession_rules":context.profile._rules.professions,
		"warrior_rules":Warrior,"combat_rules":Combat,"art_rules":Art,"actor_links":runtime.ports,
		"motion":runtime.motion,"lifetime":runtime.ports,"presentation":runtime.ports,
		"damage_observer":runtime.ports,"landing":runtime.ports,"spatial":runtime.ports})
	model.configure_runtime_map_projection(context.registry.capture_world().runtime_map_id, context.ground_to_screen, context.screen_to_ground)
	model.combat_radius_gu = context.combat_radius_gu
	model.passive_wakeup_changed.connect(runtime.ports.on_passive_wakeup_changed)
	model.summon_state_changed.connect(runtime.ports.on_summon_state_changed)
	return {"ok":runtime.healthy(),"runtime":runtime}


static func create_interactable(context: Dictionary,kind: StringName) -> Dictionary:
	if OS.get_thread_caller_id()==OS.get_main_thread_id() or kind not in [&"npc",&"zone_portal"]: return {"ok":false,"errors":["same_S_interactable_owner_required"]}
	for name: String in ["world_core","registry","scope","ports","source_publication"]:
		if not context.has(name): return {"ok":false,"errors":["missing_interactable_context:"+name]}
	for name: String in ["world_core","registry","scope","ports"]:
		if not context[name] is Object or context[name] is Node or context[name] is Resource or not is_instance_valid(context[name]): return {"ok":false,"errors":["interactable_owner_boundary"]}
	if not context.registry is Registry or context.scope.owner_thread_id()!=OS.get_thread_caller_id() or context.ports.owner_thread_id()!=OS.get_thread_caller_id() or context.world_core.owner_thread_id()!=OS.get_thread_caller_id(): return {"ok":false,"errors":["canonical_interactable_owner_required"]}
	var source: Dictionary=context.source_publication
	if source.get("source_kind")!=String(kind) or not source.get("scope") is Dictionary or not source.get("stable_combat_order") is int: return {"ok":false,"errors":["actual_interactable_birth_required"]}
	# Actual Node2D captured no ordinary callback. No fabricated H/P callback.
	if context.scope.ordinary_p_enabled or context.scope.raw_h_enabled or context.scope.process_processing_enabled or context.scope.physics_processing_enabled or context.scope.inside_world: return {"ok":false,"errors":["original_interactable_no_callback_contract"]}
	var model: RefCounted=preload("npc_actor_model.gd").new() if kind==&"npc" else preload("zone_portal_model.gd").new()
	if not model.configure_owner(context.ports,context.scope): return {"ok":false,"errors":["interactable_model_owner_failed"]}
	var handle: Object=context.registry.register_actor(model,context.scope.life_generation,kind,source.stable_combat_order)
	if handle==null: return {"ok":false,"errors":["interactable_registration_failed"]}
	if not model.bind_runtime_actor_id(handle.get_instance_id()) or not handle.bind_original_temporal_scope(context.scope):
		context.registry.retire_runtime_actor(handle.get_instance_id()); return {"ok":false,"errors":["interactable_original_scope_failed"]}
	var runtime: RefCounted=preload("interactable_runtime_instance.gd").new(model,handle,context.ports,context.registry,context.scope)
	return {"ok":true,"runtime":runtime}
