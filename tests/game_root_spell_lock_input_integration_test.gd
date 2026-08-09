extends Node

const SpellLockPolicy := preload("res://scripts/skills/spell_target_lock_policy.gd")
const SkillDataLoader := preload("res://scripts/skills/skill_data_loader.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.learned_skills = {
		"火球术": 0,
		"魔法盾": 0,
	}
	PlayerState.attack_skill_slots = [""]
	PlayerState.attack_ring_slots = ["火球术", "魔法盾", "", "", "", ""]
	PlayerState.recalculate_stats()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = game.player.global_position + Vector2(4000, 4000)

	game.player.max_mp = 999
	game.player.current_mp = 999
	var origin_tile: Vector2 = game._canonical_screen_px_to_ground_gu(
		game.player.global_position
	)
	var near_target := _make_enemy(game, origin_tile + Vector2(2, 0), "spell-lock-near")
	var far_target := _make_enemy(game, origin_tile + Vector2(8, 0), "spell-lock-far")

	_test_idle_cycle_and_lock_range(game, origin_tile, near_target, far_target)
	_test_spell_range_is_not_lock_range(game, near_target, far_target)
	_test_fire_wall_uses_locked_footpoint_only(game, near_target)
	_test_target_centered_release_rejects_lost_lock(game, origin_tile, near_target)
	_test_footprint_geometry_contact(game, origin_tile)
	_test_spell_click_hold_and_cancel(game, near_target)
	_test_busy_hold_retry_preserves_movement_facing(game, near_target)
	_test_attack_button_bound_spell_uses_same_lifecycle(game, near_target)
	_test_magic_shield_toggle_and_auto_refresh(game)
	_test_projectile_exact_gu_range(game)

	game.queue_free()
	await get_tree().process_frame
	print("GAME_ROOT_SPELL_LOCK_INPUT_INTEGRATION_PASS: idle 12-tile magic lock, exact spell range, footprint contact, click/hold cast, and shield auto-refresh are integrated")
	get_tree().quit(0)


func _test_idle_cycle_and_lock_range(
	game: Node,
	origin_tile: Vector2,
	near_target: EnemyActor,
	far_target: EnemyActor
) -> void:
	var mana_before: int = game.player.current_mp
	var action_sequence_before: int = game.player._combat_action_sequence
	game._cycle_target()
	assert(game.magic_locked_target == near_target)
	assert(game.manual_magic_target_lock)
	assert(game.player.current_mp == mana_before)
	assert(game.player._combat_action_sequence == action_sequence_before)
	game._cycle_target()
	assert(game.magic_locked_target == far_target)
	assert(game.player.current_mp == mana_before)
	assert(game.player._combat_action_sequence == action_sequence_before)

	far_target.global_position = game._canonical_ground_gu_to_screen_px(
		origin_tile + Vector2(12.0, 0.0)
	)
	game._validate_locked_target()
	assert(game.magic_locked_target == far_target)
	far_target.global_position = game._canonical_ground_gu_to_screen_px(
		origin_tile + Vector2(12.01, 0.0)
	)
	game._validate_locked_target()
	assert(game.magic_locked_target == null)
	assert(SpellLockPolicy.LOCK_RANGE_GU == 12.0)
	far_target.global_position = game._canonical_ground_gu_to_screen_px(
		origin_tile + Vector2(8, 0)
	)


func _test_spell_range_is_not_lock_range(
	game: Node,
	near_target: EnemyActor,
	far_target: EnemyActor
) -> void:
	game._set_magic_locked_target(far_target, true)
	var short_spell := {
		"target": {"relation": "hostile", "mode": "single"},
		"geometry": {"maximum_range_gu": 4.0},
	}
	assert(game._is_magic_target_in_range(far_target))
	## Unified range rule: hostile cast eligibility is lock-only; the skill's
	## own geometry range no longer double-rejects a locked target.
	assert(game._spell_definition_allows_target(short_spell, far_target))
	assert(game._spell_definition_allows_target(short_spell, near_target))
	assert(
		game._ensure_skill_cast_target() == far_target,
		"a valid persistent spell lock was silently replaced by a nearer target"
	)
	assert(game.magic_locked_target == far_target)
	var target_context: Dictionary = game._canonical_target_context(
		short_spell,
		game.player.global_position,
		game.player.facing,
		false
	)
	assert(target_context.has_target)
	assert(target_context.target_within_skill_range)
	assert(game.magic_locked_target == far_target)
	var ground_spell := {
		"target": {"relation": "hostile_area", "mode": "ground_point"},
		"geometry": {"maximum_range_gu": 4.0},
	}
	var ground_context: Dictionary = game._canonical_target_context(
		ground_spell,
		game.player.global_position,
		game.player.facing,
		false
	)
	assert(ground_context.has_target)
	assert(ground_context.target_within_skill_range)
	assert(
		ground_context.target_tile
		== game._canonical_screen_px_to_grid_cell(far_target.global_position),
		"a locked ground spell must use the persistent lock footpoint"
	)
	assert(game.magic_locked_target == far_target)


func _test_fire_wall_uses_locked_footpoint_only(
	game: Node,
	near_target: EnemyActor
) -> void:
	var fire_wall := SkillDataLoader.skill("wizard.fire_wall")
	assert(not fire_wall.is_empty())
	game._set_magic_locked_target(near_target, true)
	game._skill_cast_target = near_target
	var locked_context: Dictionary = game._canonical_target_context(
		fire_wall,
		game.player.global_position,
		game.player.facing,
		false
	)
	assert(locked_context.has_target)
	assert(
		locked_context.target_tile
		== game._canonical_screen_px_to_grid_cell(near_target.global_position),
		"fire wall did not use the locked monster footpoint"
	)

	game._set_magic_locked_target(null, false)
	game._skill_cast_target = null
	var unlocked_context: Dictionary = game._canonical_target_context(
		fire_wall,
		game.player.global_position,
		game.player.facing,
		false
	)
	assert(
		not unlocked_context.has_target,
		"fire wall silently fell back to an arbitrary ground point without a lock"
	)
	game._set_magic_locked_target(near_target, true)


func _test_target_centered_release_rejects_lost_lock(
	game: Node,
	origin_tile: Vector2,
	near_target: EnemyActor
) -> void:
	var exploding_flame := SkillDataLoader.skill("wizard.exploding_flame")
	assert(not exploding_flame.is_empty())
	var release_geometry := {
		"origin_screen_px": game.player.global_position,
		"origin_ground_gu": game._canonical_screen_px_to_ground_gu(
			game.player.global_position
		),
		"direction_screen_px": Vector2.RIGHT,
		"direction_ground_gu": GroundUnitSpace.screen_delta_px_to_ground_delta_gu(
			Vector2.RIGHT
		).normalized(),
		"locked_target_instance_id": near_target.get_instance_id(),
		"locked_target_valid_at_release": true,
	}
	near_target.global_position = game._canonical_ground_gu_to_screen_px(
		origin_tile + Vector2(12.01, 0.0)
	)
	assert(game._combat_release_target(release_geometry) == near_target)
	assert(not game._is_magic_target_in_range(near_target))
	var serial_before: int = game._canonical_cast_serial
	var mana_before: int = game.player.current_mp
	game.player._pending_skill_context = {"release_geometry": release_geometry}
	game._on_player_skill(
		str(exploding_flame.get("display_name", "爆裂火焰")),
		game.player.global_position,
		Vector2.RIGHT,
		0
	)
	assert(
		game._canonical_cast_serial == serial_before,
		"target-centred spell fell back to a ground cast after its lock left 12 tiles"
	)
	assert(game.player.current_mp == mana_before)
	assert(game._skill_cast_target == null)
	near_target.global_position = game._canonical_ground_gu_to_screen_px(
		origin_tile + Vector2(2, 0)
	)
	game._set_magic_locked_target(near_target, true)


func _test_footprint_geometry_contact(game: Node, origin_tile: Vector2) -> void:
	var affected_cell := Vector2i(roundi(origin_tile.x), roundi(origin_tile.y)) + Vector2i(4, 4)
	var edge_target := _make_enemy(
		game,
		Vector2(affected_cell) + Vector2(0.60, 0.0),
		"footprint-edge-contact"
	)
	assert(
		game._canonical_screen_px_to_grid_cell(edge_target.global_position) != affected_cell,
		"fixture center must stay outside the affected cell"
	)
	assert(
		game._canonical_spell_geometry_targets(
			"wizard.laser",
			[affected_cell],
			{"maximum_targets": 8, "pierces_units": true}
		).has(edge_target),
		"monster footprint touching the laser cell was reduced to a center point"
	)
	edge_target.queue_free()


func _test_spell_click_hold_and_cancel(game: Node, near_target: EnemyActor) -> void:
	game._set_magic_locked_target(near_target, true)
	_reset_cast_gate(game)
	var sequence_before: int = game.player._combat_action_sequence
	game._on_skill_input_started(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 0, 100, 1, &"touch"
	)
	assert(game.player._combat_action_sequence == sequence_before + 1)
	assert(game._active_skill_inputs.size() == 1)
	game._on_skill_input_started(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 0, 100, 1, &"touch"
	)
	assert(game.player._combat_action_sequence == sequence_before + 1)
	assert(game._active_skill_inputs.size() == 1)
	game._on_skill_input_ended(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 0, 100, 1, &"touch"
	)
	assert(game._active_skill_inputs.is_empty())

	game.player._attack_timer = 1.0
	game.player._attack_action_timer = 1.0
	sequence_before = game.player._combat_action_sequence
	for token: int in [101, 102, 103]:
		game._on_skill_input_started(
			PlayerState.SKILL_SLOT_GROUP_ATTACK_RING,
			0,
			token,
			token,
			&"touch"
		)
		game._on_skill_input_ended(
			PlayerState.SKILL_SLOT_GROUP_ATTACK_RING,
			0,
			token,
			token,
			&"touch"
		)
	_reset_cast_gate(game)
	game._process_skill_input_actions(1.0)
	assert(
		game.player._combat_action_sequence == sequence_before,
		"rapid taps during one cast interval were buffered into forced casts"
	)

	_reset_cast_gate(game)
	game._on_skill_input_started(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 0, 104, 3, &"touch"
	)
	sequence_before = game.player._combat_action_sequence
	_reset_cast_gate(game)
	game._process_skill_input_actions(1.0)
	assert(
		game.player._combat_action_sequence == sequence_before,
		"a fresh click was misclassified as a continuous hold"
	)
	_reset_cast_gate(game)
	var held_key: String = game._skill_input_key(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 0, 104, 3
	)
	var held_entry: Dictionary = game._active_skill_inputs[held_key]
	held_entry["started_at_ms"] = (
		Time.get_ticks_msec() - game.SKILL_HOLD_REPEAT_THRESHOLD_MS
	)
	game._active_skill_inputs[held_key] = held_entry
	game._process_skill_input_actions(1.0)
	assert(
		game.player._combat_action_sequence == sequence_before + 1,
		"held offensive spell did not repeat after the normal cast gate reopened"
	)
	game._on_skill_input_ended(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 0, 104, 3, &"touch"
	)
	sequence_before = game.player._combat_action_sequence
	_reset_cast_gate(game)
	game._process_skill_input_actions(1.0)
	assert(
		game.player._combat_action_sequence == sequence_before,
		"released offensive spell left a ghost held cast"
	)

	game.player._attack_timer = 1.0
	game.player._attack_action_timer = 1.0
	game._on_skill_input_started(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 0, 105, 4, &"touch"
	)
	game._on_skill_input_cancelled(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING,
		0,
		105,
		4,
		&"touch",
		&"test_cancel"
	)
	assert(game._active_skill_inputs.is_empty())


func _test_busy_hold_retry_preserves_movement_facing(
	game: Node,
	near_target: EnemyActor
) -> void:
	_reset_cast_gate(game)
	game._set_magic_locked_target(near_target, true)
	game._on_skill_input_started(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 0, 106, 5, &"touch"
	)
	var held_key: String = game._skill_input_key(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 0, 106, 5
	)
	var held_entry: Dictionary = game._active_skill_inputs[held_key]
	held_entry["started_at_ms"] = (
		Time.get_ticks_msec() - game.SKILL_HOLD_REPEAT_THRESHOLD_MS
	)
	game._active_skill_inputs[held_key] = held_entry

	var sequence_before: int = game.player._combat_action_sequence
	var movement_direction := Vector2.LEFT
	var movement_velocity := Vector2(-96.0, 0.0)
	game.player.facing = movement_direction
	game.player.movement_facing = movement_direction
	game.player.actual_motion_facing = movement_direction
	game.player.movement_input_active = true
	game.player.velocity = movement_velocity
	game.player._movement_visual_lock_timer = 0.0
	game.player._attack_timer = 0.9
	game.player._attack_action_timer = 0.0
	game.player._skill_cooldown_remaining["wizard.fireball"] = 0.9
	game._skill_input_retry_remaining = 0.0
	game._process_skill_input_actions(0.05)

	assert(game.player._combat_action_sequence == sequence_before)
	assert(game.player.facing == movement_direction)
	assert(game.player.movement_facing == movement_direction)
	assert(game.player.actual_motion_facing == movement_direction)
	assert(game.player.movement_input_active)
	assert(game.player.velocity == movement_velocity)

	game.player._attack_timer = 0.0
	game._skill_input_retry_remaining = 0.0
	game._process_skill_input_actions(0.05)
	assert(
		game.player._combat_action_sequence == sequence_before,
		"held cast ignored the skill-specific cooldown gate"
	)
	assert(game.player.facing == movement_direction)
	assert(game.player.movement_facing == movement_direction)
	assert(game.player.actual_motion_facing == movement_direction)
	assert(game.player.movement_input_active)
	assert(game.player.velocity == movement_velocity)

	game.player._skill_cooldown_remaining.clear()
	game._skill_input_retry_remaining = 0.0
	game._process_skill_input_actions(0.05)
	assert(
		game.player._combat_action_sequence == sequence_before + 1,
		"held cast did not commit after both release gates reopened"
	)
	assert(
		game.player.facing != movement_direction,
		"committed held cast did not preserve normal target auto-facing"
	)
	game._on_skill_input_ended(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 0, 106, 5, &"touch"
	)
	assert(game._active_skill_inputs.is_empty())


func _test_magic_shield_toggle_and_auto_refresh(game: Node) -> void:
	game.player.apply_magic_shield(10.0, 0.5)
	_reset_cast_gate(game)
	var sequence_before: int = game.player._combat_action_sequence
	game._on_skill_input_started(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 1, 200, 5, &"touch"
	)
	assert(game._magic_shield_auto_enabled)
	assert(game.player._combat_action_sequence == sequence_before)
	assert(game._active_skill_inputs.size() == 1)
	game._on_skill_input_started(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 1, 200, 5, &"touch"
	)
	assert(game._magic_shield_auto_enabled)
	assert(game._active_skill_inputs.size() == 1)
	game._on_skill_input_ended(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 1, 200, 5, &"touch"
	)

	game.player.shield_capacity = game.player.shield_capacity_max * 0.20
	_reset_cast_gate(game)
	game._magic_shield_auto_retry_remaining = 0.0
	sequence_before = game.player._combat_action_sequence
	game._process_magic_shield_auto_refresh(1.0)
	assert(
		game.player._combat_action_sequence == sequence_before + 1,
		"magic shield did not auto-cast through the normal action pipeline at 20 percent capacity"
	)

	game._on_skill_input_started(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 1, 201, 6, &"touch"
	)
	assert(not game._magic_shield_auto_enabled)
	game._on_skill_input_started(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, 1, 201, 6, &"touch"
	)
	assert(not game._magic_shield_auto_enabled)
	game._on_skill_input_cancelled(
		PlayerState.SKILL_SLOT_GROUP_ATTACK_RING,
		1,
		201,
		6,
		&"touch",
		&"test_cancel"
	)
	assert(game._active_skill_inputs.is_empty())


func _test_attack_button_bound_spell_uses_same_lifecycle(
	game: Node,
	near_target: EnemyActor
) -> void:
	PlayerState.attack_skill_slots = ["火球术"]
	game._set_magic_locked_target(near_target, true)
	_reset_cast_gate(game)
	var sequence_before: int = game.player._combat_action_sequence
	game._on_mobile_attack_input_started(300, 7, &"touch")
	assert(game.player._combat_action_sequence == sequence_before + 1)
	assert(game._active_mobile_attack_tokens.is_empty())
	assert(game._active_skill_inputs.size() == 1)
	game._on_mobile_attack_input_ended(300, 7, &"touch")
	assert(game._active_skill_inputs.is_empty())
	PlayerState.attack_skill_slots = [""]


func _test_projectile_exact_gu_range(game: Node) -> void:
	var definition := SkillDataLoader.skill("wizard.fireball")
	var expected_range := float(
		definition.get("geometry", {}).get("maximum_range_gu", 0.0)
	)
	assert(expected_range > 0.0)
	game._spawn_projectile(
		game.player.global_position,
		Vector2.RIGHT,
		10,
		9999.0,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball"
	)
	var projectile: SkillProjectile
	for child: Node in game.get_children():
		if child is SkillProjectile:
			projectile = child as SkillProjectile
	assert(projectile != null)
	assert(is_equal_approx(projectile.max_travel_distance_gu, expected_range))
	projectile.queue_free()


func _reset_cast_gate(game: Node) -> void:
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game.player._skill_cooldown_remaining.clear()
	game._skill_input_retry_remaining = 0.0


func _make_enemy(game: Node, tile: Vector2, display_name: String) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": display_name,
		"hp": 9999,
		"attackMin": 1,
		"attackMax": 1,
		"level": 1,
		"anti_magic_points": 0,
		"magic_defense_min": 0,
		"magic_defense_max": 0,
	}, game.player, false)
	enemy.control_time = 60.0
	game.add_child(enemy)
	enemy.global_position = game._canonical_ground_gu_to_screen_px(tile)
	enemy.set_physics_process(false)
	return enemy
