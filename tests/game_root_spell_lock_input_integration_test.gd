extends Node

const SpellLockPolicy := preload("res://scripts/skills/spell_target_lock_policy.gd")
const SkillDataLoader := preload("res://scripts/skills/skill_data_loader.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

var _skill_request_probe_count := 0


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
	await _test_taoist_entrapment_retains_locked_monster(game, origin_tile)
	await _test_projectile_target_range_contract(game, origin_tile)
	await _test_caster_empty_primary_uses_physical_lock(game, origin_tile)

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

	_move_enemy(game, far_target, origin_tile + Vector2(12.0, 0.0))
	game._validate_locked_target()
	assert(game.magic_locked_target == far_target)
	_move_enemy(game, far_target, origin_tile + Vector2(12.01, 0.0))
	game._validate_locked_target()
	assert(game.magic_locked_target == null)
	assert(SpellLockPolicy.LOCK_RANGE_GU == 12.0)
	_move_enemy(game, far_target, origin_tile + Vector2(8, 0))


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
	_move_enemy(game, near_target, origin_tile + Vector2(12.01, 0.0))
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
	_move_enemy(game, near_target, origin_tile + Vector2(2, 0))
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
	var release_id := "spell-lock:footprint-contact"
	var snapshot := SkillFootprintSnapshot.create_cell_union(
		"wizard.laser",
		release_id,
		origin_tile,
		[affected_cell],
		game._canonical_snapshot_absolute_context(origin_tile),
	)
	var plan: Dictionary = game._aoe_spell_query_plan(
		"wizard.laser",
		[affected_cell],
		{"maximum_targets": 8, "pierces_units": true},
		{},
		snapshot,
		origin_tile,
		{},
	)
	assert(
		game._canonical_spell_geometry_targets(
			"wizard.laser",
			[affected_cell],
			{"maximum_targets": 8, "pierces_units": true},
			{},
			snapshot,
			plan,
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


func _test_taoist_entrapment_retains_locked_monster(
	game: Node,
	origin_tile: Vector2
) -> void:
	PlayerState.profession = "道士"
	PlayerState.level = 50
	PlayerState.learned_skills = {"困魔咒": 3}
	PlayerState.recalculate_stats()
	game.player.max_mp = 999
	game.player.current_mp = 999
	for monster_name: String in ["钉耙猫", "森林雪人", "毒蜘蛛"]:
		_reset_cast_gate(game)
		var target := _make_enemy(
			game,
			origin_tile + Vector2(2, 0),
			monster_name
		)
		target.control_time = 0.0
		game._set_magic_locked_target(target, true)
		var mana_before: int = game.player.current_mp
		assert(
			game._try_release_skill("困魔咒", false) == &"accepted",
			"%s entrapment input was rejected before the body action" % monster_name
		)
		assert(not target.entrapment_active())
		await get_tree().create_timer(0.50).timeout
		assert(
			not target.entrapment_active(),
			"%s entrapment resolved before the canonical 600 ms release"
			% monster_name
		)
		assert(
			game.player.current_mp == mana_before,
			"%s entrapment committed MP before release" % monster_name
		)
		await get_tree().create_timer(0.20).timeout
		var entrapment_state := target.entrapment_state_snapshot()
		assert(
			bool(entrapment_state.get("active", false)),
			"%s lost its locked identity during the 600 ms entrapment windup: state=%s mp=%d/%d target_ground=%s target_cell=%s"
			% [monster_name, JSON.stringify(entrapment_state), game.player.current_mp, mana_before, str(game._canonical_screen_px_to_ground_gu(target.global_position)), str(game._canonical_screen_px_to_grid_cell(target.global_position))]
		)
		assert(
			str(entrapment_state.get("contract_id", ""))
			== "skills.taoist.entrapment.boundary_controller.v1"
		)
		assert(int(entrapment_state.get("boundary_cell_count", 0)) == 8)
		assert(int(entrapment_state.get("runtime_map_id", -1)) == game.current_map_id)
		assert(
			int(entrapment_state.get("caster_instance_id", 0))
			== game.player.get_instance_id()
		)
		assert(
			entrapment_state.get("center_cell", Vector2i.ZERO)
			== game._canonical_screen_px_to_grid_cell(target.global_position)
		)
		assert(not str(entrapment_state.get("snapshot_id", "")).is_empty())
		assert(target.control_time == 0.0, "entrapment must not apply generic control")
		assert(
			game.player.current_mp < mana_before,
			"successful entrapment did not commit MP for %s" % monster_name
		)
		game._set_magic_locked_target(null, false)
		target.queue_free()
		await get_tree().process_frame

	## Explicit non-boss immunity must reach the runtime plan before resource
	## commit. The body action may start, but release produces no trap and spends
	## neither MP nor material.
	_reset_cast_gate(game)
	var immune_target := _make_enemy(
		game,
		origin_tile + Vector2(2, 0),
		"explicit-control-immune"
	)
	immune_target.control_time = 0.0
	immune_target.set_meta(&"control_immune", true)
	game._set_magic_locked_target(immune_target, true)
	var immune_mana_before: int = game.player.current_mp
	var immune_inventory_before: Array = PlayerState.inventory.duplicate(true)
	assert(game._try_release_skill("困魔咒", false) == &"accepted")
	await get_tree().create_timer(0.70).timeout
	assert(not immune_target.entrapment_active())
	assert(immune_target.control_time == 0.0)
	assert(game.player.current_mp == immune_mana_before)
	assert(PlayerState.inventory == immune_inventory_before)
	game._set_magic_locked_target(null, false)
	immune_target.queue_free()
	await get_tree().process_frame


func _reset_cast_gate(game: Node) -> void:
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game.player._skill_cooldown_remaining.clear()
	game._skill_input_retry_remaining = 0.0


func _test_projectile_target_range_contract(
	game: Node,
	origin_tile: Vector2
) -> void:
	var original_profession: String = PlayerState.profession
	var original_learned: Dictionary = PlayerState.learned_skills.duplicate(true)
	var original_inventory: Array = PlayerState.inventory.duplicate(true)
	var original_mp: int = game.player.current_mp
	var original_attack_slots: Array[String] = PlayerState.attack_skill_slots.duplicate()
	var original_auto_target: bool = game.auto_target_enabled
	var original_domain_magic: bool = game._active_target_domain_magic
	var original_safe_zones: Array = game._active_safe_zones.duplicate(true)
	game._active_safe_zones = []
	game.auto_target_enabled = false
	var boundary_target := _make_enemy(
		game,
		origin_tile + Vector2(9.0, 0.0),
		"projectile-range-boundary"
	)
	var outer_target := _make_enemy(
		game,
		origin_tile + Vector2(11.0, 0.0),
		"projectile-range-outer"
	)
	var projectile_skill_ids: Array[String] = [
		"wizard.fireball",
		"wizard.great_fireball",
		"taoist.soul_fire_talisman",
	]
	for stable_skill_id: String in projectile_skill_ids:
		var definition: Dictionary = SkillDataLoader.skill(stable_skill_id)
		assert(str(definition.get("geometry", {}).get("shape", "")) == "projectile")
		var maximum_range_gu: float = float(
			definition.get("geometry", {}).get("maximum_range_gu", 0.0)
		)
		assert(is_equal_approx(maximum_range_gu, 9.0))
		game._set_magic_locked_target(boundary_target, true)
		assert(game._spell_definition_allows_target(definition, boundary_target))
		game._set_magic_locked_target(outer_target, true)
		assert(not game._spell_definition_allows_target(definition, outer_target))
	game._set_active_target_domain_magic(true)
	game._on_enemy_target_requested(outer_target)
	assert(game.magic_locked_target == outer_target)
	assert(game._active_display_target() == outer_target)
	var lightning_definition: Dictionary = SkillDataLoader.skill("wizard.lightning")
	assert(str(lightning_definition.get("geometry", {}).get("shape", "")) != "projectile")
	assert(game._spell_definition_allows_target(lightning_definition, outer_target))
	var skill_request_callback := Callable(self, "_capture_skill_request")
	game.player.skill_requested.connect(skill_request_callback)
	for stable_skill_id: String in [
		"wizard.fireball",
		"taoist.soul_fire_talisman",
	]:
		var profession_id := "taoist" if stable_skill_id.begins_with("taoist.") else "wizard"
		var profession_name := ProfessionRules.profession_display_name(profession_id)
		var skill_name := SkillDataLoader.display_name(stable_skill_id)
		PlayerState.profession = profession_name
		PlayerState.learned_skills = {skill_name: 0}
		if stable_skill_id == "taoist.soul_fire_talisman":
			var amulet_name := str(PlayerState.CANONICAL_MATERIAL_ITEMS.get("amulet", ""))
			if PlayerState.item_count(amulet_name) < 1:
				PlayerState.inventory.append({"name": amulet_name, "count": 1})
		PlayerState.recalculate_stats()
		game.player.current_mp = 999
		game._set_active_target_domain_magic(true)
		game._set_magic_locked_target(outer_target, true)
		game._skill_cast_target = outer_target
		_reset_cast_gate(game)
		var mp_before: int = game.player.current_mp
		var action_sequence_before: int = game.player._combat_action_sequence
		var attack_timer_before: float = game.player._attack_timer
		var action_timer_before: float = game.player._attack_action_timer
		var cooldown_before: Dictionary = game.player._skill_cooldown_remaining.duplicate(true)
		var inventory_before: Array = PlayerState.inventory.duplicate(true)
		var projectile_count_before: int = _projectile_count(game)
		_skill_request_probe_count = 0
		var result: StringName = game._try_release_skill(skill_name, false)
		assert(result == &"rejected")
		assert(game.player.current_mp == mp_before)
		assert(game.player._combat_action_sequence == action_sequence_before)
		assert(is_equal_approx(game.player._attack_timer, attack_timer_before))
		assert(is_equal_approx(game.player._attack_action_timer, action_timer_before))
		assert(game.player._skill_cooldown_remaining == cooldown_before)
		assert(PlayerState.inventory == inventory_before)
		assert(_skill_request_probe_count == 0)
		assert(_projectile_count(game) == projectile_count_before)
	game.player.skill_requested.disconnect(skill_request_callback)
	boundary_target.queue_free()
	outer_target.queue_free()
	await get_tree().process_frame
	PlayerState.profession = original_profession
	PlayerState.learned_skills = original_learned
	PlayerState.inventory = original_inventory
	PlayerState.attack_skill_slots = original_attack_slots
	PlayerState.recalculate_stats()
	game.player.current_mp = original_mp
	game.auto_target_enabled = original_auto_target
	game._active_safe_zones = original_safe_zones
	game._cancel_all_combat_targets()
	game._set_active_target_domain_magic(original_domain_magic)


func _projectile_count(game: Node) -> int:
	var count := 0
	for child: Node in game.get_children():
		if child is SkillProjectile:
			count += 1
	return count


func _test_caster_empty_primary_uses_physical_lock(
	game: Node,
	origin_tile: Vector2
) -> void:
	var original_profession := PlayerState.profession
	var original_attack_slots: Array[String] = PlayerState.attack_skill_slots.duplicate()
	var original_auto_target: bool = game.auto_target_enabled
	var original_domain_magic: bool = game._active_target_domain_magic
	var original_safe_zones: Array = game._active_safe_zones.duplicate(true)
	var skill_request_callback := Callable(self, "_capture_skill_request")
	game.player.skill_requested.connect(skill_request_callback)
	PlayerState.attack_skill_slots = [""]
	game.auto_target_enabled = false
	game._active_safe_zones = []
	game._cancel_all_combat_targets()
	for profession_id: String in ["wizard", "taoist"]:
		var profession_name := ProfessionRules.profession_display_name(profession_id)
		PlayerState.profession = profession_name
		PlayerState.recalculate_stats()
		game._set_active_target_domain_magic(false)
		var stale_physical_target := _make_enemy(
			game,
			origin_tile + Vector2(2.0, 0.0),
			"caster-basic-stale-%s" % profession_id
		)
		game._set_attack_locked_target(stale_physical_target, true)
		var far_target := _make_enemy(
			game,
			origin_tile + Vector2(11.0, 0.0),
			"caster-basic-far-%s" % profession_id
		)
		game._on_enemy_target_requested(far_target)
		assert(game.locked_target == stale_physical_target)
		assert(game.magic_locked_target == far_target)
		game._activate_magic_skill_domain()
		assert(game._active_display_target() == far_target)
		assert(game._ensure_skill_cast_target() == far_target)
		game._set_auto_target_enabled(true)
		assert(game.locked_target == null and game.magic_locked_target == null)
		stale_physical_target.queue_free()
		far_target.queue_free()
		await get_tree().process_frame
		game._set_auto_target_enabled(false)
		game._set_active_target_domain_magic(true)
		var target := _make_enemy(
			game,
			origin_tile + Vector2(1.0, 0.0),
			"caster-basic-%s" % profession_id
		)
		game._on_enemy_target_requested(target)
		assert(game.magic_locked_target == target)
		assert(game.locked_target == target)
		var hp_before: int = target.current_hp
		var mp_before: int = game.player.current_mp
		_skill_request_probe_count = 0
		_reset_cast_gate(game)
		assert(game.gameplay_input_is_enabled())
		game._on_mobile_attack_input_started(
			9000 + profession_name.length(),
			-1,
			&"test"
		)
		assert(
			game.locked_target == target
			and game._active_display_target() == target
			and target.is_targeted,
			"empty caster primary attack did not switch presentation to physical lock"
		)
		assert(game.magic_locked_target == target)
		assert(game.player.current_mp == mp_before)
		assert(_skill_request_probe_count == 0)
		game._on_mobile_attack_input_ended(
			9000 + profession_name.length(),
			-1,
			&"test"
		)
		await get_tree().create_timer(0.70).timeout
		assert(
			target.current_hp < hp_before,
			"%s empty primary physical attack did not reduce target HP" % profession_name
		)
		target.queue_free()
		await get_tree().process_frame
		_reset_cast_gate(game)
		game._cancel_all_combat_targets()
	game.player.skill_requested.disconnect(skill_request_callback)
	PlayerState.profession = original_profession
	PlayerState.recalculate_stats()
	PlayerState.attack_skill_slots = original_attack_slots
	game.auto_target_enabled = original_auto_target
	game._active_safe_zones = original_safe_zones
	game._set_active_target_domain_magic(original_domain_magic)


func _capture_skill_request(
	_skill_name: String,
	_origin: Vector2,
	_direction: Vector2,
	_damage: int
) -> void:
	_skill_request_probe_count += 1


func _make_enemy(game: Node, tile: Vector2, display_name: String) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"monster_id": 38,
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
	enemy.configure_runtime_map_projection(
		game.current_map_id,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu")
	)
	game._runtime_spawn_serial += 1
	var spawn_serial := int(game._runtime_spawn_serial)
	enemy.configure_spatial_index(game._combat_spatial_index, spawn_serial)
	enemy.set_meta("spawn_serial", spawn_serial)
	enemy.set_meta("zone_generation", int(game._zone_generation))
	enemy.set_combat_position(
		game._canonical_ground_gu_to_screen_px(tile),
		&"spell_lock_fixture_spawn",
	)
	game._combat_spatial_index.register(
		spawn_serial,
		game.current_map_id,
		game._canonical_screen_px_to_ground_gu(enemy.global_position),
		enemy.combat_radius_gu,
		spawn_serial,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)
	game.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _move_enemy(game: Node, enemy: EnemyActor, tile: Vector2) -> void:
	enemy.set_combat_position(
		game._canonical_ground_gu_to_screen_px(tile),
		&"spell_lock_fixture_move",
	)
