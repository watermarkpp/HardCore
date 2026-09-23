extends "res://tests/hc_monster_ai/runtime_test.gd"

const SpatialRules := preload("res://scripts/world_spatial_rules.gd")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	player = PlayerCharacter.new()
	player.global_position = ground_to_screen(Vector2(20, 20))
	player.set_meta("runtime_map_id", 1)
	player.set_meta("zone_generation", 1)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 10000
	player.current_hp = 10000
	player.current_mp = 1000
	player.defense_min = 999
	player.defense_max = 999
	player.shield_time = 60.0
	player.shield_capacity = 10000.0
	player.damage_reduction = 0.8
	check(not PlayerState.has_special_effect("magic_shield"), "shield-fixture", "No protection ring converts HP damage into MP")
	var spider := make_enemy(Vector2(21.4, 20), 170)
	# Restore the real source stats and presentation delay overridden by the base fixture.
	var source := EnemyActor.new()
	source.setup(GameData.get_monster_by_id(170), player, false)
	spider.attack_min = source.attack_min
	spider.attack_max = source.attack_max
	spider._attack_hit_delay = source._attack_hit_delay
	print("BLACK_SPIDER_PROFILE ", {"attack_min": source.attack_min, "attack_max": source.attack_max, "accuracy": source.accuracy, "reach": source.attack_range_gu, "delay": source._attack_hit_delay, "delivery": source.attack_delivery_rule, "preferred": spider._hc_preferred(player)})
	source.free()
	for trial in range(3):
		await get_tree().physics_frame
		var hp_before := player.current_hp
		spider._attack_timer = 0.0
		spider._physics_process_internal(1.0 / 60.0)
		spider._update_pending_attack(1.0)
		check(player.current_hp < hp_before, "black-spider-shield-%d" % trial, "Real black spider attack damages a shielded high-AC wizard")
		print("BLACK_SPIDER_RESULT hp_loss=", hp_before - player.current_hp, " starts=", spider._hc_starts, " settled=", spider._hc_settlements, " reason=", spider._hc_last_reason)
	# Boundary and same-tick interception of a circling player use the real AI.
	for direction_index in range(8):
		await get_tree().physics_frame
		var direction := Vector2.from_angle(TAU * direction_index / 8.0)
		player.global_position = ground_to_screen(Vector2(20, 20))
		spider.set_combat_position(ground_to_screen(Vector2(20, 20) + direction * 1.501), &"boundary")
		check(spider._hc_access(player) == "OUT_OF_RANGE", "reach-out-%d" % direction_index, "Ordinary attack cannot start beyond 1.5 GU")
		spider.set_combat_position(ground_to_screen(Vector2(20, 20) + direction * 1.499), &"boundary")
		spider._attack_timer = 0.0
		var starts_before := spider._hc_starts
		spider._movement_step_active = true
		spider._movement_step_reason = &"pursuit"
		spider._physics_process_internal(1.0 / 60.0)
		check(spider._hc_starts == starts_before + 1, "moving-entry-%d" % direction_index, "Moving pursuer attacks immediately when player enters the 1.5-GU gate")
		spider._update_pending_attack(1.0)
	# A protected target must be forgotten, including observations and queued paths.
	spider.set_combat_position(ground_to_screen(Vector2(21.4, 20)), &"safe-boundary")
	spider._hc_known_ground = Vector2(20, 20)
	spider._hc_known_target_id = player.get_instance_id()
	spider._hc_observed = true
	spider._hc_path_pending = true
	spider._threat_table[player.get_instance_id()] = {"node": weakref(player), "score": 10.0}
	spider.set_meta("safe_zone_context", SpatialRules.compile_safe_zone_context(1, 1, 1, [{"shape": "circle", "center_ground_gu": Vector2(20, 20), "radius_gu": 0.5, "blocks_monster_damage": true, "blocks_monster_entry": true}]))
	var hp_before_safe := player.current_hp
	spider._physics_process_internal(1.0 / 60.0)
	check(spider.target == null, "safe-forget-target", "Entering safe zone immediately drops pursuit target")
	check(not spider._hc_known_ground.is_finite() and not spider._hc_path_pending, "safe-forget-path", "Safe-zone entry invalidates observations and queued navigation")
	check(not spider._threat_table.has(player.get_instance_id()), "safe-forget-threat", "Safe-zone entry removes protected-player threat")
	check(player.current_hp == hp_before_safe and not spider._movement_step_active, "safe-no-hit-motion", "Safe-zone target cannot be hit or chased")
	index.unregister(spider.spatial_actor_runtime_id)
	spider.queue_free()
	# A fixed-body physical attacker is still melee, never a hidden >2GU
	# exception; its authored stationarity must survive the shared AI override.
	var flower := make_enemy(Vector2(22.1, 20), 30)
	check(flower._hc_standard_melee() and flower.stationary, "fixed-melee-policy", "Physical fixed-body monster uses the common1.5GU melee policy")
	var fixed_position := flower.global_position
	flower._attack_timer = 0.0
	for frame in range(10):
		await get_tree().physics_frame
		ready_cadence(flower)
		flower._physics_process_internal(1.0 / 60.0)
	check(flower.global_position == fixed_position and flower._hc_starts == 0, "fixed-melee-outside", "Stationary melee neither chases nor attacks beyond1.5GU")
	flower.set_combat_position(ground_to_screen(Vector2(21.49, 20)), &"fixed-range-entry")
	flower._physics_process_internal(1.0 / 60.0)
	check(flower._hc_starts == 1, "fixed-melee-inside", "Stationary melee attacks inside the shared reach")
	index.unregister(flower.spatial_actor_runtime_id)
	flower.queue_free()
	player.queue_free()
	await get_tree().process_frame
	finish("repair_six_combat")
