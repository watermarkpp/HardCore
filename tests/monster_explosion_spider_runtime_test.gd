extends Node2D

const GroundUnit := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.computed_stats["anti_magic_points"] = 0
	PlayerState.computed_stats["magic_defense_min"] = 0
	PlayerState.computed_stats["magic_defense_max"] = 0
	for monster_id: int in [183]:
		await _verify_explosion(monster_id)
	assert(not MonsterIdentity.is_runtime_allowed(184), "source-only ID184 unexpectedly became a runtime actor")
	PlayerState.test_mode = previous_test_mode
	print("MONSTER_EXPLOSION_SPIDER_RUNTIME_PASS id183=1 id184_excluded=1 mixed_damage=1 self_death=1")
	get_tree().quit(0)


func _verify_explosion(monster_id: int) -> void:
	var player := PlayerCharacter.new()
	player.global_position = _ground_to_screen(Vector2(11.5, 10.5))
	player.set_meta("runtime_map_id", 1)
	player.set_meta("safe_zones", [])
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000
	player.current_hp = 1000
	player.defense_min = 0
	player.defense_max = 0
	var spider := EnemyActor.new()
	spider.setup(GameData.get_monster_by_id(monster_id), player, false)
	assert(spider.monster_id == monster_id, "ID%d setup rejected: %s" % [monster_id, str(spider.get_meta("canonical_rejected", false))])
	spider.configure_runtime_map_projection(
		1, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"),
	)
	spider.configure_terrain_navigation_context({})
	spider.global_position = _ground_to_screen(Vector2(10.5, 10.5))
	add_child(spider)
	spider.set_physics_process(false)
	await get_tree().process_frame
	assert(str(spider.attack_delivery_rule.get("kind", "")) == "self_detonation")
	assert(int(spider.behavior_profile.get("serviceClass", {}).get("race", -1)) == 117, "ID%d must bind server class 117" % monster_id)
	spider.target = player
	spider.attack_min = 30
	spider.attack_max = 30
	spider._attack_timer = 0.0
	var hp_before := player.current_hp
	spider._physics_process(0.01)
	assert(spider.current_hp == 0 and spider._death_pending, "spider survived its own blast")
	assert(player.current_hp == hp_before - 30, "spider did not apply split AC/MAC explosion")
	spider.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
