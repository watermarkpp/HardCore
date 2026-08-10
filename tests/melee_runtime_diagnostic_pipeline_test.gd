extends Node

const DiagnosticLog := preload("res://scripts/layers/runtime/combat_diagnostic_log.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")
const MeleeGeometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const DiagnosticGate := preload("res://scripts/runtime_diagnostics.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	var previous_log_enabled: bool = bool(ProjectSettings.get_setting(
		DiagnosticGate.SETTING_ENABLED, false
	))
	var previous_combat_enabled: bool = bool(ProjectSettings.get_setting(
		DiagnosticGate.SETTING_COMBAT, false
	))
	var previous_file_output_enabled: bool = bool(ProjectSettings.get_setting(
		DiagnosticGate.SETTING_FILE_OUTPUT, false
	))
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	ProjectSettings.set_setting(DiagnosticGate.SETTING_ENABLED, true)
	ProjectSettings.set_setting(DiagnosticGate.SETTING_COMBAT, true)
	ProjectSettings.set_setting(DiagnosticGate.SETTING_FILE_OUTPUT, false)
	DiagnosticLog.clear_recent_events()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = game.player.global_position + Vector2(3000, 3000)

	game.player.global_position = game._bich_home_screen_position_px() + Vector2(600, 0)
	var origin_tile: Vector2 = game._canonical_screen_px_to_ground_gu(
		game.player.global_position
	)
	var enemy := _make_enemy(
		game,
		game._canonical_ground_gu_to_screen_px(origin_tile + Vector2(1, 1))
	)
	game.locked_target = enemy
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	PlayerState.computed_stats["accuracy"] = 0
	PlayerState.test_mode = false

	var hp_before := enemy.current_hp
	assert(game._request_mobile_attack(), "real melee input was rejected before diagnostic release")
	await get_tree().create_timer(game.player.attack_hit_windup + 0.08).timeout
	assert(enemy.current_hp == hp_before, "zero accuracy should produce a formal MISS")

	var release_event := _last_release_event()
	assert(not release_event.is_empty(), "real melee release produced no diagnostic event")
	assert(
		str(release_event.get("result_code", "")) == "ACCURACY_MISS",
		"real MISS was not distinguished from geometry or damage failure"
	)
	assert(
		bool(release_event.get("visual_geometry_direction_match", false)),
		"animation row and damage direction diverged in the exact-direction fixture"
	)
	var candidate_decisions: Array = release_event.get("selection_candidate_decisions", [])
	assert(not candidate_decisions.is_empty(), "release log omitted candidate decisions")
	assert(
		(candidate_decisions[0] as Dictionary).has("angle_quantization_audit"),
		"release log omitted screen-vs-tile angle evidence"
	)
	var hit_attempts: Array = release_event.get("physical_hit_attempts", [])
	assert(
		hit_attempts.size() == 1
		and str((hit_attempts[0] as Dictionary).get("result_code", "")) == "ACCURACY_MISS",
		"physical accuracy roll was not captured exactly once"
	)

	# Phone reproduction melee:205-216. The target is only 1.31 tiles away,
	# but the former screen-angle quantizer selected direction 5 and rejected
	# all twelve attacks. The canonical 64x32 tile quantizer selects direction 4.
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game.player.velocity = Vector2.ZERO
	game.player.set_touch_vector(Vector2.ZERO)
	PlayerState.test_mode = true
	origin_tile = game._canonical_screen_px_to_ground_gu(game.player.global_position)
	game._active_safe_zones.clear()
	enemy.velocity = Vector2.ZERO
	enemy.control_time = 0.0
	enemy.global_position = game.player.global_position + (
		DirectionSpace.ground_delta_gu_to_screen_delta_px(Vector2(-0.56, -1.31))
	)
	enemy.apply_control(60.0)
	var measured_delta: Vector2 = (
		game._canonical_screen_px_to_ground_gu(enemy.global_position) - origin_tile
	)
	assert(measured_delta.is_equal_approx(Vector2(-0.56, -1.31)))
	hp_before = enemy.current_hp
	assert(game._request_mobile_attack(), "phone angle regression input was rejected")
	await get_tree().create_timer(game.player.attack_hit_windup + 0.08).timeout
	assert(enemy.current_hp < hp_before, "phone angle regression still produced an empty swing")
	release_event = _last_release_event()
	assert(release_event.result_code == "HIT_COMMITTED")
	assert(release_event.attack_direction_index_at_input == 4)
	assert(release_event.release_direction_index == 4)
	assert(release_event.input_release_direction_match)
	assert(release_event.actual_visual_row_at_release == 0)
	assert(release_event.expected_visual_row_at_release == 0)
	assert(release_event.visual_geometry_direction_match)
	assert(
		str(release_event.release_geometry.get("direction_space_contract_id", ""))
		== "gameplay.professions.combat_direction_space.ground_gu_8dir.v3"
	)

	# Hit-and-run footprint regression: movement input remains held when the
	# attack begins, and the monster centre is beyond the 2.5 GU thrust end.
	# Its unchanged physics ellipse only touches the fixed attack rectangle.
	# The historical point test must reject it while the production resolver
	# accepts the area contact and commits damage.
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game.player.thrusting_enabled = true
	PlayerState.learned_skills["warrior.thrusting"] = 3
	game.player.set_touch_vector(Vector2.DOWN)
	# Reproduce the exact input-frame state before request_attack_toward() starts
	# the action lock; the following physics frame would intentionally zero the
	# runtime movement flag once the attack action begins.
	game.player.movement_input_active = true
	assert(game.player.touch_vector.length() > 0.08)
	origin_tile = game._canonical_screen_px_to_ground_gu(game.player.global_position)
	var footprint_direction_index := 7
	var footprint_step := Vector2(MeleeGeometry.facing_tile_step(footprint_direction_index))
	var forward_support := 0.0
	for point: Vector2 in MeleeGeometry.target_footprint_polygon_ground_gu(
		Vector2.ZERO,
		enemy.combat_radius_gu
	):
		forward_support = maxf(
			forward_support,
			absf(MeleeGeometry.line_coordinates(point, footprint_direction_index).x)
		)
	enemy.global_position = game._canonical_ground_gu_to_screen_px(
		origin_tile
		+ footprint_step * (
			MeleeGeometry.reach_tiles(MeleeGeometry.SKILL_THRUST) + forward_support
		)
	)
	enemy.velocity = Vector2.ZERO
	enemy.apply_control(60.0)
	enemy.current_hp = enemy.max_hp
	game.locked_target = enemy
	hp_before = enemy.current_hp
	assert(game._request_mobile_attack(), "footprint edge contact was rejected at input")
	await get_tree().create_timer(game.player.attack_hit_windup + 0.08).timeout
	assert(enemy.current_hp < hp_before, "footprint edge contact still produced an empty swing")
	release_event = _last_release_event()
	assert(release_event.result_code == "HIT_COMMITTED")
	assert(bool(release_event.get("movement_input_active_at_input", false)))
	var footprint_decision := _candidate_for_target(
		release_event.get("selection_candidate_decisions", []),
		enemy.get_instance_id()
	)
	assert(not footprint_decision.is_empty(), "footprint target was omitted from diagnostics")
	assert(not bool(footprint_decision.get("point_accepted", true)))
	assert(bool(footprint_decision.get("footprint_accepted", false)))
	assert(int(footprint_decision.get("footprint_thrust_slot", 0)) == 2)
	var release_geometry_payload: Dictionary = release_event.get(
		"release_geometry", {}
	)
	assert(is_equal_approx(
		float(release_geometry_payload.get(
			"locked_target_combat_radius_gu_at_release", -1.0
		)),
		enemy.combat_radius_gu
	), "release geometry did not freeze the target combat footprint radius")
	var snapshot_payload: Dictionary = release_geometry_payload.get(
		"skill_footprint_snapshot", {}
	)
	var footprint_snapshot_id := str(snapshot_payload.get("snapshot_id", ""))
	assert(not footprint_snapshot_id.is_empty())
	var thrust_client_effect := game.player.visual.get_node(
		"ClientSkillEffect"
	) as Sprite2D
	assert(
		thrust_client_effect.visible,
		"valid thrust release did not reveal the snapshot-aligned client effect"
	)
	var thrust_alignment: Dictionary = game.player.visual.get(
		"_thrust_client_effect_alignment"
	)
	assert(str(thrust_alignment.get("snapshot_id", "")) == footprint_snapshot_id)
	assert(
		_has_target_aligned_visual(footprint_snapshot_id),
		"footprint edge hit committed damage but did not present the same-snapshot thrust band"
	)
	game.player.set_touch_vector(Vector2.ZERO)

	game.queue_free()
	await get_tree().process_frame
	DiagnosticLog.clear_recent_events()
	ProjectSettings.set_setting(DiagnosticGate.SETTING_ENABLED, previous_log_enabled)
	ProjectSettings.set_setting(
		DiagnosticGate.SETTING_COMBAT, previous_combat_enabled
	)
	ProjectSettings.set_setting(
		DiagnosticGate.SETTING_FILE_OUTPUT, previous_file_output_enabled
	)
	PlayerState.test_mode = previous_test_mode
	print("MELEE_RUNTIME_DIAGNOSTIC_PIPELINE_PASS: accuracy, angle, and footprint-area evidence are observable")
	get_tree().quit(0)


func _last_release_event() -> Dictionary:
	var events := DiagnosticLog.recent_events()
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		if str(event.get("event", "")) == "attack_release_resolved":
			return event
	return {}


func _candidate_for_target(candidates: Array, target_id: int) -> Dictionary:
	for candidate: Dictionary in candidates:
		if int(candidate.get("target_id", 0)) == target_id:
			return candidate
	return {}


func _has_target_aligned_visual(snapshot_id: String) -> bool:
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if str(node.get_meta("snapshot_id", "")) == snapshot_id:
			return true
	return false


func _make_enemy(game: Node, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{
			"name": "diagnostic_target",
			"hp": 200,
			"attackMin": 1,
			"attackMax": 1,
			"level": 1,
			"agility": 100,
			"defMin": 0,
			"defMax": 0,
		},
		game.player,
		false
	)
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy
