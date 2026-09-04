extends Node

const RUNTIME_MAP_IDS := [910001, 910004]
const MAX_WAIT_FRAMES := 1800

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	assert(await _wait_for_transition(), "initial production world bootstrap timed out")

	for map_id: int in RUNTIME_MAP_IDS:
		if int(_game.current_map_id) != map_id:
			var operation := Callable(_game, "_travel_to_map_immediate").bind(map_id)
			assert(_game._begin_map_transition(operation, map_id))
			assert(await _wait_for_transition(), "map transition timed out: %d" % map_id)
		await get_tree().process_frame
		_assert_runtime_actor_plan(map_id)

	_assert_no_total_monster_scan_in_per_frame_world_paths()
	_game.queue_free()
	await get_tree().process_frame
	print("WORLD_ACTOR_STAGED_SPAWN_TEST_PASS")
	get_tree().quit(0)


func _wait_for_transition() -> bool:
	for _frame: int in range(MAX_WAIT_FRAMES):
		if (
			not bool(_game._map_transition_in_progress)
			and _game._world_bootstrap_coordinator.stage
			== WorldBootstrapCoordinator.Stage.READY
		):
			return true
		if (
			_game._world_bootstrap_coordinator.stage
			== WorldBootstrapCoordinator.Stage.FAILED
		):
			return false
		await get_tree().process_frame
	return false


func _assert_runtime_actor_plan(map_id: int) -> void:
	assert(int(_game.current_map_id) == map_id)
	var content: Dictionary = MapEditorRuntimeBridge.game_content_for_map(map_id)
	assert(not content.is_empty(), "runtime content missing: %d" % map_id)
	var expected_enemy_slots := _expected_enemy_slots(content, map_id)
	var expected_actor_count := (
		expected_enemy_slots.size()
		+ (content.get("npcs", []) as Array).size()
		+ (content.get("portals", []) as Array).size()
	)
	var coordinator: WorldBootstrapCoordinator = _game._world_bootstrap_coordinator
	var diagnostic := coordinator.snapshot()
	assert(int(diagnostic.get("planned_actors", -1)) == expected_actor_count)
	assert(int(diagnostic.get("spawned_actors", -1)) == expected_actor_count)
	assert(int(diagnostic.get("deferred_actors", -1)) == 0)
	assert(int(diagnostic.get("failed_actors", -1)) == 0)
	assert(int(diagnostic.get("duplicate_actors", -1)) == 0)
	assert(int(diagnostic.get("actor_slice_count", 0)) > 0)
	assert(
		int(diagnostic.get("actor_max_items_in_slice", 0))
		<= WorldBootstrapCoordinator.DEFAULT_MAX_ITEMS_PER_FRAME
	)
	assert(float(diagnostic.get("actor_total_ms", -1.0)) >= 0.0)
	assert(float(diagnostic.get("actor_max_item_ms", -1.0)) >= 0.0)
	assert(coordinator._actor_spawn_queue.is_empty())

	var actual_slots: Array[String] = []
	var boss_count := 0
	var npc_count := 0
	var portal_count := 0
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if not value is EnemyActor or value.is_queued_for_deletion():
			continue
		var enemy := value as EnemyActor
		actual_slots.append(str(enemy.get_meta("spawn_slot_id", "")))
		if enemy.is_boss:
			boss_count += 1
	for child: Node in _game.get_children():
		if child is NPCActor:
			npc_count += 1
		elif child is ZonePortal:
			portal_count += 1
	assert(actual_slots == expected_enemy_slots, "actor source order or stable slot changed")
	assert(_game._active_enemy_cache.size() == actual_slots.size())
	assert(_game._active_boss_cache.size() == boss_count)
	assert(npc_count == (content.get("npcs", []) as Array).size())
	assert(portal_count == (content.get("portals", []) as Array).size())


func _expected_enemy_slots(content: Dictionary, map_id: int) -> Array[String]:
	var result: Array[String] = []
	var spawn_index := -1
	for spawn: Dictionary in content.get("spawns", []):
		spawn_index += 1
		var count := mini(
			int(spawn.get("count", 1)),
			int(spawn.get("max_alive", spawn.get("count", 1)))
		)
		var raw_group: Dictionary = spawn.get("spawn_group", {})
		var group_id := str(spawn.get(
			"spawnGroupId",
			raw_group.get("id", "editor:%d:%d" % [map_id, spawn_index])
		))
		for copy_index: int in maxi(1, count):
			result.append("%s:%d" % [group_id, copy_index])
	var boss_index := -1
	for spawn: Dictionary in content.get("bosses", []):
		boss_index += 1
		var raw_group: Dictionary = spawn.get("spawn_group", {})
		var group_id := str(raw_group.get(
			"spawn_group_id",
			"editor:%d:boss:%d" % [map_id, boss_index]
		))
		result.append("%s:0" % group_id)
	return result


func _assert_no_total_monster_scan_in_per_frame_world_paths() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	assert(not source.is_empty())
	var boss_start := source.find("func _update_boss_world_mechanics")
	var boss_end := source.find("\nfunc ", boss_start + 1)
	var boss_body := source.substr(boss_start, boss_end - boss_start)
	assert('get_nodes_in_group("enemies")' not in boss_body)
	assert("_active_boss_cache.values()" in boss_body)
	var process_start := source.find("func _process(delta: float)")
	var process_end := source.find("\nfunc ", process_start + 1)
	var process_body := source.substr(process_start, process_end - process_start)
	assert("_tick_bich_safe_zone_enforcement(delta)" in process_body)
	assert("_enforce_bich_safe_zone()" not in process_body)
