extends RefCounted

# Read-only lab sampling; not called by production. Coordinates are explicitly
# named, and missing objects stay missing rather than invented defaults.
const GU := preload("res://scripts/ground_unit_space.gd")

static func vector_json(point: Vector2) -> Array:
	return [point.x, point.y] if point.is_finite() else []

static func capture(game: Node, source: EnemyActor) -> Dictionary:
	var out: Dictionary = {"tick": Engine.get_physics_frames(), "msec": Time.get_ticks_msec(),
		"source_present": is_instance_valid(source)}
	if not is_instance_valid(game):
		out["classification"] = "HOST_MISSING"
		return out
	out["map_id"] = int(game.current_map_id)
	out["generation"] = int(game._zone_generation)
	out["paused"] = game.get_tree().paused
	out["map_transition"] = bool(game._map_transition_in_progress)
	out["bootstrap"] = bool(game._world_bootstrap_in_progress)
	out["input_enabled"] = game.gameplay_input_is_enabled()
	out["queue"] = game.hc_m30_summon_snapshot()
	var player: PlayerCharacter = game.player
	if not is_instance_valid(player):
		out["classification"] = "PLAYER_MISSING"
		return out
	out["player"] = {
		"instance_id": player.get_instance_id(), "hp": player.current_hp, "max_hp": player.max_hp,
		"dead": player._dead, "transition": player.combat_transition_is_active(), "epoch": player.combat_epoch,
		"position_screen_px": vector_json(player.global_position),
		"position_ground_gu": vector_json(game._canonical_screen_px_to_ground_gu(player.global_position)),
		"stealthed": player.is_stealthed(), "control_seconds": player.control_time,
		"physics_enabled": player.is_physics_processing(), "can_process": player.can_process(),
	}
	if not is_instance_valid(source):
		out["classification"] = "SOURCE_NOT_CURRENTLY_ALIVE"
		return out
	var live_target: Node2D = source.target if is_instance_valid(source.target) else null
	var timer: Timer = source.get_node_or_null("BackgroundAIWakeupTimer") as Timer
	var delta_gu: Vector2 = GU.screen_delta_px_to_ground_delta_gu(player.global_position - source.global_position)
	var rule: Dictionary = source.summon_rule
	out["source"] = {
		"instance_id": source.get_instance_id(), "life": int(source.get_meta("hc_combat_life_epoch", -1)),
		"monster_id": source.monster_id, "slot": str(source.get_meta("spawn_slot_id", "")),
		"map_id": source.runtime_map_id, "generation": int(source.get_meta("zone_generation", -1)),
		"same_parent": source.get_parent() == game,
		"hp": source.current_hp, "dying": source._dying, "death_pending": source._death_pending,
		"physics_enabled": source.is_physics_processing(), "can_process": source.can_process(),
		"deep_sleeping": source._background_deep_sleeping,
		"wake_timer_exists": timer != null,
		"wake_timer_stopped": timer.is_stopped() if timer != null else true,
		"wake_timer_time_left": timer.time_left if timer != null else -1.0,
		"retarget_timer": source._retarget_timer,
		"combat_enabled": source.combat_enabled, "dormant": source.dormant, "burrowed": source._burrowed,
		"stationary": source.stationary, "control_seconds": source.control_time, "charm_seconds": source.charm_time,
		"rule_enabled": bool(rule.get("enabled", false)), "max_active": int(rule.get("maxActive", 0)),
		"count": int(rule.get("count", 0)), "child_ids": rule.get("monsterIds", []).duplicate(),
		"warning": source._summon_warning, "cooldown": source._summon_cooldown,
		"release_serial": int(source.get_meta("m30_summon_release_serial", 0)),
		"warning_life": int(source.get_meta("m30_summon_warning_life", -1)),
		"target_id": live_target.get_instance_id() if live_target != null else 0,
		"target_is_player": live_target == player,
		"target_usable": source._hc_target_usable(live_target),
		"player_live_candidate": source._target_candidate_is_live(player),
		"player_in_safe_zone": source._point_inside_safe_zone(player.global_position),
		"player_in_initial_acquisition": source._initial_acquisition_contains_ground_delta_gu(delta_gu),
		"player_initial_static_los": source._initial_acquisition_static_los_clear(player),
		"distance_to_player_gu": delta_gu.length(),
		"position_screen_px": vector_json(source.global_position),
		"position_ground_gu": vector_json(source.spatial_index_position()),
		"attack_interval": source._attack_interval,
	}
	out["classification"] = classify(out)
	return out

static func classify(data: Dictionary) -> String:
	var p: Dictionary = data.get("player", {})
	var s: Dictionary = data.get("source", {})
	if p.is_empty():
		return "PLAYER_MISSING"
	if bool(p.get("dead", false)) or int(p.get("hp", 0)) <= 0:
		return "PLAYER_DEAD_NO_TARGET_ALLOWED"
	if bool(p.get("transition", false)):
		return "PLAYER_TRANSITION_NO_TARGET_ALLOWED"
	if bool(data.get("paused", false)) or bool(data.get("map_transition", false)) or bool(data.get("bootstrap", false)):
		return "WORLD_PROCESSING_OR_TRANSITION_LOCK"
	if s.is_empty():
		return "SOURCE_NOT_CURRENTLY_ALIVE"
	if int(s.get("hp", 0)) <= 0 or bool(s.get("dying", false)) or bool(s.get("death_pending", false)):
		return "SOURCE_DYING"
	if not bool(s.get("combat_enabled", false)) or not bool(s.get("rule_enabled", false)):
		return "SOURCE_COMBAT_OR_RULE_DISABLED"
	if float(s.get("control_seconds", 0.0)) > 0.0 or float(s.get("charm_seconds", 0.0)) > 0.0 or bool(s.get("dormant", false)) or bool(s.get("burrowed", false)):
		return "SOURCE_ACTION_LOCKED"
	if not bool(s.get("can_process", false)):
		return "SOURCE_PROCESS_MODE_BLOCKED"
	if not bool(s.get("physics_enabled", false)) and not bool(s.get("deep_sleeping", false)):
		return "SOURCE_PHYSICS_DISABLED_WITHOUT_SLEEP"
	if bool(s.get("deep_sleeping", false)) and bool(s.get("wake_timer_stopped", true)):
		return "SOURCE_SLEEP_TIMER_STOPPED_AT_SAMPLE"
	if not bool(s.get("target_usable", false)):
		if not bool(s.get("player_live_candidate", false)) or bool(s.get("player_in_safe_zone", false)):
			return "NO_TARGET_PLAYER_NOT_ELIGIBLE"
		if not bool(s.get("player_in_initial_acquisition", false)) or not bool(s.get("player_initial_static_los", false)):
			return "NO_TARGET_ACQUISITION_RANGE_OR_STATIC_LOS"
		return "NO_TARGET_DESPITE_SAMPLED_ACQUISITION_GATES"
	if float(s.get("warning", 0.0)) > 0.0:
		return "SUMMON_WARNING_ACTIVE"
	if float(s.get("cooldown", 0.0)) > 0.0:
		return "SUMMON_COOLDOWN_ACTIVE"
	return "READY_AT_SAMPLE_NEEDS_PRODUCER_SIGNAL_TIMELINE"
