extends Node

const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await Fixture.wait_for_formal_world(self, game, "zuma_saved_spawn")
	var data: Dictionary = GameData.get_map_by_id(913106)
	assert(not data.is_empty())
	game._load_zone(str(data.name), false, data)
	assert(game.current_map_id == 913106, "saved map must load without fallback")
	var counts := {}
	for enemy: EnemyActor in game._active_enemy_cache.values():
		if enemy.runtime_map_id == 913106 and not enemy.is_queued_for_deletion() and str(enemy.get_meta("summoner_spawn_slot", "")).is_empty():
			counts[enemy.monster_id] = int(counts.get(enemy.monster_id, 0)) + 1
			enemy.set_physics_process(false)
	assert(counts == {126: 2, 128: 2, 159: 3, 155: 2, 160: 1}, "live map actors must match latest manual save: %s" % counts)
	print("ZUMA_SAVED_SPAWN_RELEASE_PASS map_id=913106 ordinary=4 elite=5 boss=1 actual=%s" % counts)
	get_tree().quit(0)
