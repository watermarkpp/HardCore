extends RefCounted

const CONTRACT := "hardcore.actor.visual_projection.v1"
const PREMAP_PLAYER_CONTRACT := "hardcore.player.premap_visual_projection.v1"
const KEYS := ["contract_id","identity","kind","publication_sequence","source_process_frame","source_physics_frame","clock_epoch","scaled_delta","advance_visual","combat_time_s","actor","profile","enemy_visual","enemy_root"]

static func capture(value: Dictionary) -> Dictionary:
	if not ClassDB.class_exists("HardCoreContentValueGraph"): return {}
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var result: Dictionary = graph.capture(value,true,false)
	if result.get("success") != true: return {}
	return result.value

static func valid_identity(identity: Dictionary) -> bool:
	if identity.size() != 3 or not identity.get("runtime_id") is int or identity.runtime_id <= 0 or not identity.get("life_generation") is int or identity.life_generation <= 0 or not identity.get("world") is Dictionary: return false
	var world: Dictionary = identity.world
	return world.size() == 5 and world.get("contract_id") == "hardcore.execution.world_context.v1" and world.get("world_runtime_id") is int and world.world_runtime_id > 0 and world.get("world_epoch") is int and world.world_epoch >= 0 and world.get("runtime_map_id") is int and world.runtime_map_id >= 0 and world.get("profile_id") is String and not world.profile_id.is_empty()

static func validate(value: Dictionary) -> bool:
	return _validate_presentation_payload(value,false)

static func valid_premap_player_identity(identity: Dictionary) -> bool:
	if identity.size() != 3 or not identity.get("runtime_id") is int or identity.runtime_id <= 0 or not identity.get("life_generation") is int or identity.life_generation < 0 or not identity.get("world") is Dictionary: return false
	var world: Dictionary = identity.world
	return world.size() == 5 and world.get("contract_id") == "hardcore.execution.world_context.v1" and world.get("world_runtime_id") is int and world.world_runtime_id > 0 and world.get("world_epoch") is int and world.world_epoch == 0 and world.get("runtime_map_id") is int and world.runtime_map_id == -1 and world.get("profile_id") is String and not world.profile_id.is_empty()

static func validate_presentation(value: Dictionary) -> bool:
	return _validate_presentation_payload(value,value.get("contract_id") == PREMAP_PLAYER_CONTRACT)

static func _validate_presentation_payload(value: Dictionary, premap: bool) -> bool:
	if value.size() != KEYS.size() or value.get("contract_id") != (PREMAP_PLAYER_CONTRACT if premap else CONTRACT): return false
	for key: String in KEYS:
		if not value.has(key): return false
	if not value.identity is Dictionary or value.kind not in ["player","enemy"]: return false
	if premap:
		if value.kind != "player" or not valid_premap_player_identity(value.identity): return false
	elif not valid_identity(value.identity): return false
	for key: String in ["publication_sequence","source_process_frame","source_physics_frame","clock_epoch"]:
		if not value[key] is int or value[key] < 0: return false
	if value.publication_sequence <= 0 or not value.advance_visual is bool or not value.scaled_delta is float or not is_finite(value.scaled_delta) or value.scaled_delta < 0.0 or not value.combat_time_s is float or not is_finite(value.combat_time_s) or value.combat_time_s < 0.0: return false
	for key: String in ["actor","profile","enemy_visual","enemy_root"]:
		if not value[key] is Dictionary: return false
	var actor: Dictionary = value.actor
	for key: String in ["source_present","source_inside_world","source_retiring"]:
		if not actor.get(key) is bool: return false
	for key: String in ["position_screen_px","velocity","facing"]:
		if not actor.get(key) is Vector2 or not actor[key].is_finite(): return false
	for key: String in ["current_hp","max_hp"]:
		if not actor.get(key) is int: return false
	for key: String in ["control_time","poison_remaining"]:
		if not actor.get(key) is float or not is_finite(actor[key]): return false
	if value.kind == "player":
		for key: String in ["movement_facing","actual_motion_facing"]:
			if not actor.get(key) is Vector2 or not actor[key].is_finite(): return false
		if not actor.get("movement_input_active") is bool or not actor.get("locomotion_state") is String or not value.profile.get("profession_id") is String or not value.profile.get("gender") is String or not value.profile.get("level") is int or not value.profile.get("equipment") is Dictionary: return false
		if not value.enemy_visual.is_empty() or not value.enemy_root.is_empty(): return false
	else:
		for key: String in ["is_boss","dying","targeted","boss_phase_two"]:
			if not actor.get(key) is bool: return false
		for key: String in ["charm_time","boss_warning"]:
			if not actor.get(key) is float or not is_finite(actor[key]): return false
		if not actor.get("monster_id") is int or not actor.get("display_name") is String or not actor.get("monster_data") is Dictionary or not actor.get("spawn_context") is Dictionary: return false
		if not value.enemy_visual.get("service_id") is int or value.enemy_visual.service_id <= 0: return false
		for key: String in ["present","uses_final_art","burrowed","dying","targeted","airborne"]:
			if not value.enemy_visual.get(key) is bool: return false
		for key: String in ["contact_center","ring_radii","foot_radii","ring_center"]:
			if not value.enemy_visual.get(key) is Vector2 or not value.enemy_visual[key].is_finite(): return false
		for key: String in ["ground_center","ground_radii","poison_center","red_poison_center"]:
			if not value.enemy_root.get(key) is Vector2 or not value.enemy_root[key].is_finite(): return false
		for key: String in ["procedural_fallback","red_poison_active","warning_is_cone"]:
			if not value.enemy_root.get(key) is bool: return false
		if not value.enemy_root.get("health_bar_anchor_y") is float or not is_finite(value.enemy_root.health_bar_anchor_y) or not value.enemy_root.get("warning_polygon") is PackedVector2Array or not value.enemy_root.get("fallback") is Dictionary: return false
		var fallback: Dictionary = value.enemy_root.fallback
		if not fallback.get("attacking") is bool or not fallback.get("scale") is Vector2 or not fallback.get("offset") is Vector2 or not fallback.get("angle") is float or not fallback.get("progress") is float: return false
	return not capture(value).is_empty()
