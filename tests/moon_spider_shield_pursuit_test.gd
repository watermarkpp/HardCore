extends "res://tests/hc_monster_ai/runtime_test.gd"

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "法师"
	player = PlayerCharacter.new()
	player.global_position = ground_to_screen(Vector2(20, 20))
	player.set_meta("runtime_map_id", 1)
	player.set_meta("zone_generation", 1)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 10000
	player.current_hp = 10000
	player.current_mp = 1000
	player.shield_time = 60.0
	player.shield_capacity = 10000.0
	player.damage_reduction = 0.8
	PlayerState.computed_stats["anti_magic_points"] = 0
	PlayerState.computed_stats["magic_defense_min"] = 0
	PlayerState.computed_stats["magic_defense_max"] = 0
	for direction_index in range(8):
		var direction := Vector2.from_angle(TAU * direction_index / 8.0)
		var spider := make_enemy(Vector2(20, 20) + direction * 1.501, 168)
		check(spider._hc_access(player) == "OUT_OF_RANGE", "moon-boundary-out-%d" % direction_index, "Moon spider uses the common1.5GU outer boundary")
		spider.set_combat_position(ground_to_screen(Vector2(20, 20) + direction * 1.499), &"moon-range-entry")
		var source := EnemyActor.new()
		source.setup(GameData.get_monster_by_id(168), player, false)
		spider.attack_min = source.attack_min
		spider.attack_max = source.attack_max
		spider._attack_hit_delay = source._attack_hit_delay
		source.free()
		spider._attack_timer = 0.0
		var hp_before := player.current_hp
		for frame in range(90):
			await get_tree().physics_frame
			if not spider._movement_step_active:
				ready_cadence(spider)
			spider._physics_process_internal(1.0 / 60.0)
			if player.current_hp < hp_before:
				break
		print("MOON_SPIDER direction=", direction_index, " hp_loss=", hp_before - player.current_hp, " range=", spider.attack_range_gu, " contact=", spider._contact_distance_gu_to_target(player), " actual_distance=", screen_to_ground(spider.global_position).distance_to(Vector2(20, 20)), " result=", spider.last_magic_attack_resolution)
		check(player.current_hp < hp_before, "moon-shield-%d" % direction_index, "Real moon spider damages shielded wizard at the common1.5GU boundary")
		index.unregister(spider.spatial_actor_runtime_id)
		spider.queue_free()
		await get_tree().process_frame
	player.queue_free()
	await get_tree().process_frame
	finish("moon_spider_shield_pursuit")
