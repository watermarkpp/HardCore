extends Node

const SpatialRules := preload("res://scripts/world_spatial_rules.gd")
const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")

const RUNTIME_MAP_ID := 9404


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_verify_safe_zone_compilation()
	_verify_index_candidates_and_lifecycle()
	_verify_production_paths_are_indexed_and_cached()
	print("SAFE_ZONE_SPATIAL_RUNTIME_PASS")
	get_tree().quit(0)


func _verify_safe_zone_compilation() -> void:
	var circle := {
		"area_id": "safe.circle",
		"shape": "circle",
		"center_ground_gu": Vector2(10.0, -4.0),
		"radius_gu": 9.0,
		"blocks_monster_damage": true,
		"blocks_monster_entry": true,
		"blocks_pvp": true,
		"return_anchor": true,
		"policy_override": "test_circle",
	}
	var polygon := {
		"area_id": "safe.polygon",
		"shape": "polygon",
		"polygon_ground_gu": [
			[-4.0, -3.0],
			[4.0, -3.0],
			[4.0, 3.0],
			[-4.0, 3.0],
		],
		"blocks_monster_damage": true,
	}
	var context := SpatialRules.compile_safe_zone_context(
		RUNTIME_MAP_ID,
		7,
		12,
		[circle, polygon],
	)
	assert(bool(context.get("valid", false)), "valid formal zones must compile")
	assert(int(context.get("map_id", -1)) == RUNTIME_MAP_ID)
	assert(int(context.get("revision", -1)) == 7)
	assert(int(context.get("generation", -1)) == 12)
	var zones: Array = context.get("zones", [])
	assert(zones.size() == 2, "compiled zones must preserve authored order")
	assert(zones[0].get("zone_id") == "safe.circle")
	assert(zones[1].get("zone_id") == "safe.polygon")
	assert(zones[0].get("aabb_ground_gu") is Rect2)
	assert(zones[1].get("polygon_ground_gu") is PackedVector2Array)
	assert(SpatialRules.point_inside_safe_zone_ground_gu(Vector2(10.0, -4.0), zones[0]))
	assert(not SpatialRules.point_inside_safe_zone_ground_gu(Vector2(20.1, -4.0), zones[0]))
	assert(SpatialRules.point_inside_safe_zone_ground_gu(Vector2.ZERO, zones[1]))
	assert(not SpatialRules.point_inside_safe_zone_ground_gu(Vector2(4.1, 0.0), zones[1]))

	for invalid_zone: Dictionary in [
		{
			"center_ground_gu": Vector2.ZERO,
			"radius_gu": 9.0,
		},
		{
			"shape": "triangle",
			"center_ground_gu": Vector2.ZERO,
			"radius_gu": 9.0,
		},
		{
			"shape": "circle",
			"center_ground_gu": Vector2(NAN, 0.0),
			"radius_gu": 9.0,
		},
		{
			"shape": "circle",
			"center_ground_gu": Vector2.ZERO,
			"radius_gu": 0.0,
		},
		{
			"shape": "polygon",
			"polygon_ground_gu": [[0.0, 0.0], [1.0, 1.0]],
		},
		{
			"shape": "polygon",
			"polygon_ground_gu": [
				[-2.0, -2.0],
				[2.0, 2.0],
				[-2.0, 2.0],
				[2.0, -2.0],
			],
		},
	]:
		var invalid_context := SpatialRules.compile_safe_zone_context(
			RUNTIME_MAP_ID,
			8,
			13,
			[invalid_zone],
		)
		assert(not bool(invalid_context.get("valid", true)))
		assert((invalid_context.get("zones", []) as Array).is_empty())
		assert(not str(invalid_context.get("failure_reason", "")).is_empty())


func _verify_index_candidates_and_lifecycle() -> void:
	var index := SpatialIndex.new()
	var enemies: Array[EnemyActor] = []
	for actor_index: int in range(96):
		var enemy := EnemyActor.new()
		enemy.current_hp = 100
		enemy.max_hp = 100
		enemy._dying = false
		enemy._death_pending = false
		enemies.append(enemy)
		var inside_position := Vector2(
			-8.0 + float(actor_index % 16),
			-4.0 + float(actor_index / 16),
		)
		var position := inside_position if actor_index < 82 else Vector2(100.0 + actor_index, 100.0)
		index.register(
			actor_index + 1,
			RUNTIME_MAP_ID,
			position,
			0.25,
			actor_index,
			enemy,
		)
	var output: Array = []
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		Rect2(Vector2(-9.0, -5.0), Vector2(18.0, 10.0)),
		output,
	)
	assert(output.size() == 82, "safe-zone AABB must exclude remote actors")
	for actor_index: int in range(output.size()):
		assert(output[actor_index] == enemies[actor_index])
	var wrong_map: Array = []
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID + 1,
		Rect2(Vector2(-9.0, -5.0), Vector2(18.0, 10.0)),
		wrong_map,
	)
	assert(wrong_map.is_empty(), "safe-zone candidate query must be map scoped")

	enemies[0]._death_pending = true
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		Rect2(Vector2(-9.0, -5.0), Vector2(18.0, 10.0)),
		output,
	)
	assert(output.size() == 81 and not output.has(enemies[0]))
	index.update_actor(2, Vector2(110.0, 110.0))
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		Rect2(Vector2(-9.0, -5.0), Vector2(18.0, 10.0)),
		output,
	)
	assert(output.size() == 80 and not output.has(enemies[0]))
	index.clear_map(RUNTIME_MAP_ID)
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		Rect2(Vector2(-1000.0, -1000.0), Vector2(2000.0, 2000.0)),
		output,
	)
	assert(output.is_empty(), "map clear must remove safe-zone candidates")
	for actor_index: int in range(96):
		index.unregister(actor_index + 1)
		if is_instance_valid(enemies[actor_index]):
			enemies[actor_index].queue_free()


func _verify_production_paths_are_indexed_and_cached() -> void:
	var game_source := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	var enforcement_start := game_source.find("func _enforce_bich_safe_zone")
	var enforcement_end := game_source.find("\nfunc ", enforcement_start + 1)
	assert(enforcement_start >= 0 and enforcement_end > enforcement_start)
	var enforcement_body := game_source.substr(
		enforcement_start,
		enforcement_end - enforcement_start,
	)
	assert("query_enemy_nodes_aabb_into" in enforcement_body)
	assert("_active_enemy_cache.values()" not in enforcement_body)
	assert('get_nodes_in_group("enemies")' not in enforcement_body)
	assert("set_combat_position" in game_source)

	var enemy_source := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var redraw_start := enemy_source.find("func _request_actor_redraw_if_dynamic")
	var redraw_end := enemy_source.find("\nfunc ", redraw_start + 1)
	assert(redraw_start >= 0 and redraw_end > redraw_start)
	var redraw_body := enemy_source.substr(redraw_start, redraw_end - redraw_start)
	assert("uses_final_art" in redraw_body)
	assert("should_draw_synthetic_ground_shadow" in redraw_body)
	assert("_request_actor_redraw()" in redraw_body)
	var physics_start := enemy_source.find("func _physics_process(delta: float)")
	var physics_end := enemy_source.find("\nfunc ", physics_start + 1)
	var physics_body := enemy_source.substr(physics_start, physics_end - physics_start)
	assert("_request_actor_redraw_if_dynamic()" in physics_body)
	assert("_request_actor_redraw()" not in physics_body)
