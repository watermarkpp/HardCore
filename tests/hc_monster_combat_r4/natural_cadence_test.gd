extends Node

## R4 T5 natural cadence + bounded diagnostic: the Actor must reach >=20
## attack admissions on its OWN physics frames. The fixture never writes
## _attack_timer / _pending_attack_time / _hc_last_start_tick and never calls
## _physics_process / _advance_combat_action_clock directly. Rejection
## diagnosis reads ONLY the production chain's own counters and reason state
## (hc_package_policy_snapshot / _hc_last_reason / _hc_exclusion_reason)
## once per state change plus one final summary - never a per-frame extra
## admission or world query.

const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const SAMPLE_TARGET := 20
## Heavy-scene budget (60s): the natural cadence includes the FIRST chase from
## spawn to contact and the identity's full ATTACK_SPD cycle between starts.
## The diagnostic run proved the production chain alive (9 natural starts in
## a 25s window with a ~2.5s cycle + chase); 60s covers 20 cycles with margin.
const SAMPLE_LIMIT_S := 60.0


var enemy: EnemyActor
var player: PlayerCharacter
var game: Node
var start_ticks: Array = []
var hp_events: Array = []
var last_hp: int = 0
var sampled_frames: int = 0
var position_changes: int = 0
var last_position: Vector2 = Vector2.INF
var min_target_distance_px: float = INF
var target_ids_seen: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var monster_id: int = int(OS.get_environment("HC_NATURAL_CADENCE_MONSTER_ID")) if OS.get_environment("HC_NATURAL_CADENCE_MONSTER_ID") != "" else 24
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var deadline_boot: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline_boot:
		if int(game.get("current_map_id")) >= 0 and bool(game.call("gameplay_input_is_enabled")):
			break
		await get_tree().process_frame
	var world_ready: bool = int(game.get("current_map_id")) == GameData.service_runtime_map_id(0) and bool(game.call("gameplay_input_is_enabled"))

	player = game.player
	player.set_physics_process(false)
	player.max_hp = 100000
	player.current_hp = player.max_hp
	player.defense_min = 0
	player.defense_max = 0
	# Authored outdoor corner used by the R2/R3 census fixtures, asserted
	# OUTSIDE the safe zones so admission cannot fail on the safe-zone gate.
	var fixture_ground := Vector2(40.5, 13.5)
	var safe_zone_hit: bool = WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
		fixture_ground, game._active_safe_zones
	)
	var fixture_screen: Vector2 = game._canonical_ground_gu_to_screen_px(fixture_ground)
	player.global_position = fixture_screen
	game._set_player_world_position(fixture_screen)
	last_hp = player.current_hp
	player.stats_changed.connect(_on_player_stats_changed)

	enemy = game._spawn_enemy(
		GameData.get_monster_by_id(monster_id),
		fixture_screen + Vector2(60.0, 0.0),
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_slot_id": "test:r4-natural-cadence"},
	)
	var spawn_ok: bool = enemy != null and enemy.combat_enabled and not bool(enemy.get_meta("body_policy_rejected", false))
	var index_registered: int = -1
	var zone_generation: int = -999
	if spawn_ok:
		index_registered = enemy.spatial_actor_runtime_id
		zone_generation = int(enemy.get_meta("zone_generation", -999))
		last_position = enemy.global_position
		await get_tree().physics_frame

	var deadline_ms: int = Time.get_ticks_msec() + int(SAMPLE_LIMIT_S * 1000.0)
	var last_serial: int = -1
	while Time.get_ticks_msec() < deadline_ms:
		await get_tree().physics_frame
		sampled_frames += 1
		if not is_instance_valid(enemy):
			break
		var serial: int = enemy._attack_logic_serial
		if serial != last_serial and enemy._attack_action_active:
			last_serial = serial
			start_ticks.append(Time.get_ticks_msec())
		var pos: Vector2 = enemy.global_position
		if pos.distance_to(last_position) > 0.01:
			position_changes += 1
			last_position = pos
		if is_instance_valid(player):
			var distance: float = pos.distance_to(player.global_position)
			if distance < min_target_distance_px:
				min_target_distance_px = distance
		var target_id: int = enemy.target.get_instance_id() if is_instance_valid(enemy.target) else 0
		if target_ids_seen.is_empty() or int(target_ids_seen.back()) != target_id:
			target_ids_seen.append(target_id)
		if hp_events.size() >= SAMPLE_TARGET and start_ticks.size() >= SAMPLE_TARGET:
			break

	var snapshot: Dictionary = {}
	if is_instance_valid(enemy):
		snapshot = enemy.hc_package_policy_snapshot()
	var valid: bool = (
		world_ready and not safe_zone_hit and spawn_ok
		and start_ticks.size() >= SAMPLE_TARGET
		and hp_events.size() >= SAMPLE_TARGET
	)
	if valid:
		var interval: float = enemy._current_attack_interval()
		for i: int in range(1, start_ticks.size()):
			var gap_s: float = float(start_ticks[i] - start_ticks[i - 1]) / 1000.0
			if gap_s < interval * 0.9:
				valid = false
				break
		for event: Variant in hp_events:
			if int(event) <= 0:
				valid = false
				break

	# Bounded final failure-evidence block (review T5 checklist).
	var evidence := "\n".join([
		"R4_CADENCE_EVIDENCE monster=%d valid=%s" % [monster_id, valid],
		"world_ready=%s safe_zone_hit=%s spawn_ok=%s body_rejected=%s" % [world_ready, safe_zone_hit, spawn_ok, str(enemy != null and bool(enemy.get_meta("body_policy_rejected", false)))],
		"spawn_map=%s zone_generation=%d index_runtime_id=%d" % [str(game.get("current_map_id")), zone_generation, index_registered],
		"sampled_physics_frames=%d enemy_position_changes=%d min_target_distance_px=%.1f" % [sampled_frames, position_changes, min_target_distance_px],
		"target_ids_seen=%s" % str(target_ids_seen),
		"starts=%d settlements=%s hp_events=%d" % [start_ticks.size(), str(snapshot.get("starts", "?")), hp_events.size()],
		"hc_reason=%s exclusion_reason=%s path_status=%s route_remaining=%s" % [
			str(snapshot.get("reason", "?")), str(snapshot.get("exclusion_reason", "?")),
			str(snapshot.get("path_status", "?")), str(snapshot.get("route_remaining", "?")),
		],
		"known_ground_gu=%s world_collision_count=%s" % [str(snapshot.get("known_ground_gu", "?")), str(snapshot.get("world_collision_count", "?"))],
	])
	if is_instance_valid(enemy):
		enemy.queue_free()
	game.queue_free()
	if not valid:
		printerr(evidence)
		printerr("R4_NATURAL_CADENCE_FAIL: monster=%d starts=%d hp_events=%d" % [monster_id, start_ticks.size(), hp_events.size()])
		get_tree().quit(1)
		return
	print("R4_NATURAL_CADENCE_PASS: monster=%d starts=%d hp_events=%d" % [monster_id, start_ticks.size(), hp_events.size()])
	get_tree().quit(0)


func _on_player_stats_changed(hp: int, _maximum: int) -> void:
	var delta: int = last_hp - hp
	last_hp = hp
	if delta > 0:
		hp_events.append(delta)
