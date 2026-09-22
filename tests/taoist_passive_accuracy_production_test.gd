extends Node

const RootScript := preload("res://scripts/game_root.gd")
const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")
const SKILL_NAME := "精神力战法"
const RANK_THREE_BONUS := 8
const ORIGIN_GU := Vector2(38.5, 13.5)


class ObservedRoot extends RootScript:

	var hit_records: Array[Dictionary] = []


	func _apply_physical_hit(enemy: EnemyActor, damage: int, accuracy_bonus := 0, ignore_ac := false) -> bool:
		# Execute the real hit roll even though the surrounding fixture uses the
		# save-isolated test mode. Restore it before durability/resource handling.
		# Keep this observer's signature in step with the production hit entry.
		var previous_test_mode := PlayerState.test_mode
		var hp_before := enemy.current_hp
		PlayerState.test_mode = false
		var hit := super._apply_physical_hit(enemy, damage, accuracy_bonus, ignore_ac)
		PlayerState.test_mode = previous_test_mode
		hit_records.append({
			"target_id": enemy.get_instance_id(),
			"hit": hit,
			"hp_delta": hp_before - enemy.current_hp,
			"accuracy_bonus_argument": accuracy_bonus,
		})
		return hit


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "道士"
	PlayerState.level = 40
	PlayerState.equipment.clear()
	PlayerState.learned_skills = {}
	PlayerState.recalculate_stats(false)
	var base_accuracy := int(PlayerState.computed_stats.get("accuracy", 0))
	assert(base_accuracy > 0, "canonical Taoist base accuracy must be positive")
	var equipment_before := PlayerState.equipment.duplicate(true)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.set_script(ObservedRoot)
	add_child(game)
	var ready_deadline := Time.get_ticks_msec() + 10000
	while (
		(game._world_bootstrap_in_progress or game._map_transition_in_progress)
		and Time.get_ticks_msec() < ready_deadline
	):
		await get_tree().process_frame
	assert(game.gameplay_input_is_enabled(), "real world never reached input READY")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.auto_target_enabled = false
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:
			var actor := node as EnemyActor
			actor.set_physics_process(false)
			actor.set_combat_position(
				game.player.global_position + Vector2(4000.0, 4000.0),
				&"taoist_accuracy_fixture_clear",
			)
	var origin: Vector2 = game._canonical_ground_gu_to_screen_px(ORIGIN_GU)
	game._set_player_world_position(origin)
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(
		ORIGIN_GU + Vector2(1.0, 0.0)
	)
	var target: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(38),
		target_position,
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_group_id": "taoist_accuracy_contract"},
	)
	assert(target != null and target.monster_id == 38)
	assert(target.defense == 0, "accuracy fixture must not conflate AC with a miss")
	assert(target.agility > base_accuracy + RANK_THREE_BONUS)
	target.set_physics_process(false)
	await get_tree().physics_frame
	target.set_combat_position(target_position, &"taoist_accuracy_fixture_ready")
	assert(target.can_receive_damage())
	game.player.fire_sword_enabled = false
	game.player.thrusting_enabled = false
	game.player.half_moon_enabled = false
	game._set_canonical_fire_charge_expires_at(0)

	# Prove the production target/geometry can actually hit before comparing
	# skill ranks. All three rolls are exact boundaries in the same RNG domain.
	var ordinary_hit_roll := base_accuracy - 1
	var newly_allowed_roll := base_accuracy + RANK_THREE_BONUS - 1
	var still_rejected_roll := base_accuracy + RANK_THREE_BONUS
	var baseline_hit := _release(game, target, -1, ordinary_hit_roll)
	var baseline_inside := _release(game, target, -1, newly_allowed_roll)
	var baseline_edge := _release(game, target, -1, still_rejected_roll)
	var trained_inside := _release(game, target, 3, newly_allowed_roll)
	var trained_edge := _release(game, target, 3, still_rejected_roll)
	assert(bool(baseline_hit.hit) and int(baseline_hit.hp_delta) == 20)
	assert(not bool(baseline_inside.hit) and int(baseline_inside.hp_delta) == 0)
	assert(not bool(baseline_edge.hit) and int(baseline_edge.hp_delta) == 0)
	assert(
		bool(trained_inside.hit) and int(trained_inside.hp_delta) == 20,
		"rank3 spiritual warfare must turn base+7 into a real physical hit: %s"
		% str(trained_inside),
	)
	assert(
		not bool(trained_edge.hit) and int(trained_edge.hp_delta) == 0,
		"rank3 spiritual warfare must still miss at base+8 (strict <, no extra bonus)",
	)
	assert(PlayerState.level == 40 and PlayerState.equipment == equipment_before)
	assert(PlayerState.test_mode, "real hit probe leaked non-isolated test mode")
	game.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print("TAOIST_PASSIVE_ACCURACY_PRODUCTION_PASS: real normal melee +8 and strict miss boundary")
	get_tree().quit(0)


func _release(game: Node, target: EnemyActor, rank: int, exact_roll: int) -> Dictionary:
	PlayerState.learned_skills = {} if rank < 0 else {SKILL_NAME: rank}
	PlayerState.recalculate_stats(false)
	assert(PlayerState.effective_skill_level(SKILL_NAME) == maxi(0, rank))
	assert(PlayerState.is_skill_learned(SKILL_NAME) == (rank >= 0))
	target.current_hp = target.max_hp
	game.hit_records.clear()
	game.locked_target = target
	game.magic_locked_target = target
	game._skill_cast_target = target
	var origin: Vector2 = game.player.global_position
	var direction := origin.direction_to(target.global_position)
	var geometry := ReleaseGeometry.resolve(
		origin, direction, target.get_instance_id(), target.global_position,
		true, true, ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION,
	)
	assert(bool(geometry.get("locked_target_valid_at_release", false)))
	game.player._pending_attack_context = {
		"mode": "normal", "selected_body_mode": "normal",
		"skill_name": "attack", "skill_level": 0,
		"direct_toggle_release": false, "release_geometry": geometry,
	}
	game._rng.seed = _seed_for_exact_roll(target.agility, exact_roll)
	game._on_player_attack(origin, direction, 20)
	assert(game.hit_records.size() == 1, "normal melee must reach one real hit consumer")
	var result: Dictionary = game.hit_records[0].duplicate(true)
	assert(int(result.target_id) == target.get_instance_id())
	return result


func _seed_for_exact_roll(agility: int, exact_roll: int) -> int:
	var probe := RandomNumberGenerator.new()
	for candidate: int in range(1, 4097):
		probe.seed = candidate
		if probe.randi_range(0, agility - 1) == exact_roll:
			return candidate
	assert(false, "could not find deterministic physical-hit boundary seed")
	return 0
