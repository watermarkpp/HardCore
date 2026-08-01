extends Node

const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.recalculate_stats()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = game.player.global_position + Vector2(4000, 4000)

	var origin_tile: Vector2i = game._canonical_world_to_tile(game.player.global_position)
	assert(
		game._canonical_facing_for_skill("wizard.hellfire", Vector2.DOWN) == Vector2i(1, 1),
		"地狱火屏幕S方向未转换为64x32地图格S方向"
	)
	assert(
		game._canonical_facing_for_skill("wizard.hellfire", Vector2.RIGHT) == Vector2i(1, -1),
		"地狱火屏幕E方向未转换为64x32地图格E方向"
	)
	var runtime: Dictionary = RuntimeBridge.load_map(game.current_map_id)
	var blocked_tiles: Array = runtime.get("collision", {}).get("blocked_tiles", [])
	if not blocked_tiles.is_empty():
		var parts := str(blocked_tiles[0]).split(",")
		var blocked_cell := Vector2i(int(parts[0]), int(parts[1]))
		assert(
			game._canonical_effective_spell_geometry_cells(
				"wizard.hellfire",
				[blocked_cell, blocked_cell + Vector2i.ONE],
				{"stops_on_terrain": true}
			).is_empty(),
			"地狱火正式直线没有在首个阻挡格前截断"
		)
		assert(
			game._canonical_effective_spell_geometry_cells(
				"wizard.laser",
				[blocked_cell, blocked_cell + Vector2i.ONE],
				{"stops_on_terrain": true}
			).is_empty(),
			"疾光电影正式直线没有在首个阻挡格前截断"
		)

	var line_cells: Array[Vector2i] = []
	for distance: int in range(1, 6):
		line_cells.append(origin_tile + Vector2i(1, 1) * distance)
	var first_line_target := _make_enemy(game, game.player, line_cells[0], "地狱火首个目标")
	var rear_line_target := _make_enemy(game, game.player, line_cells[2], "地狱火后方目标")
	var off_line_target := _make_enemy(game, game.player, origin_tile + Vector2i(1, 0), "地狱火线外目标")
	var first_hp := first_line_target.current_hp
	var rear_hp := rear_line_target.current_hp
	var off_line_hp := off_line_target.current_hp
	var hellfire_hit: bool = game._apply_canonical_spell_damage(
		"wizard.hellfire",
		20,
		game.player.global_position,
		Vector2.DOWN,
		"line_damage",
		null,
		line_cells,
		{"pierces_units": false, "stops_on_terrain": true}
	)
	assert(hellfire_hit and first_line_target.current_hp < first_hp, "地狱火未命中正式五格直线内首个目标")
	assert(rear_line_target.current_hp < rear_hp, "地狱火未命中正式五格直线内后方目标")
	assert(off_line_target.current_hp == off_line_hp, "宽一格地狱火错误命中正式直线外单位")

	first_line_target.queue_free()
	rear_line_target.queue_free()
	off_line_target.queue_free()
	await get_tree().process_frame

	var ring_cells: Array[Vector2i] = []
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			if x != 0 or y != 0:
				ring_cells.append(origin_tile + Vector2i(x, y))
	assert(ring_cells.size() == 24, "地狱雷光正式外环不是24格")
	var ring_target := _make_enemy(game, game.player, origin_tile + Vector2i(2, 0), "雷光环内目标")
	var center_target := _make_enemy(game, game.player, origin_tile, "雷光中心目标")
	var outside_target := _make_enemy(game, game.player, origin_tile + Vector2i(3, 0), "雷光环外目标")
	var ring_hp := ring_target.current_hp
	var center_hp := center_target.current_hp
	var outside_hp := outside_target.current_hp
	assert(game._canonical_world_to_tile(ring_target.global_position) == origin_tile + Vector2i(2, 0))
	assert(game._canonical_world_to_tile(center_target.global_position) == origin_tile)
	assert(game._canonical_world_to_tile(outside_target.global_position) == origin_tile + Vector2i(3, 0))
	var ring_targets: Array[EnemyActor] = game._canonical_spell_geometry_targets(
		"wizard.hell_lightning",
		ring_cells,
		{"maximum_targets": 24, "exclude_center": true, "radius_tiles": 2}
	)
	assert(ring_targets.has(ring_target), "地狱雷光正式外环未选择环内目标")
	assert(not ring_targets.has(center_target), "地狱雷光正式外环错误选择中心目标")
	assert(not ring_targets.has(outside_target), "地狱雷光正式外环错误选择环外目标")
	var lightning_hit: bool = game._apply_canonical_spell_damage(
		"wizard.hell_lightning",
		20,
		game.player.global_position,
		Vector2.DOWN,
		"caster_centered_area_damage",
		null,
		ring_cells,
		{"maximum_targets": 24, "exclude_center": true, "radius_tiles": 2}
	)
	assert(lightning_hit and ring_target.current_hp < ring_hp, "地狱雷光未命中正式半径二格外环目标")
	assert(center_target.current_hp == center_hp, "地狱雷光错误命中施法者脚下中心格")
	assert(outside_target.current_hp == outside_hp, "地狱雷光错误命中半径二格以外目标")
	ring_target.queue_free()
	center_target.queue_free()
	outside_target.queue_free()
	await get_tree().process_frame

	var laser_cells: Array[Vector2i] = []
	for distance: int in range(1, 9):
		laser_cells.append(origin_tile + Vector2i(1, -1) * distance)
	var near_laser_target := _make_enemy(game, game.player, laser_cells[0], "疾光近端目标")
	var far_laser_target := _make_enemy(game, game.player, laser_cells[6], "疾光远端目标")
	var off_laser_target := _make_enemy(game, game.player, origin_tile + Vector2i(1, 0), "疾光线外目标")
	var near_laser_hp := near_laser_target.current_hp
	var far_laser_hp := far_laser_target.current_hp
	var off_laser_hp := off_laser_target.current_hp
	var laser_hit: bool = game._apply_canonical_spell_damage(
		"wizard.laser",
		20,
		game.player.global_position,
		Vector2.RIGHT,
		"piercing_line_damage",
		null,
		laser_cells,
		{"pierces_units": true, "stops_on_terrain": true}
	)
	assert(laser_hit, "疾光电影正式八格直线没有产生命中")
	assert(near_laser_target.current_hp < near_laser_hp, "疾光电影未命中八格直线近端目标")
	assert(far_laser_target.current_hp < far_laser_hp, "穿透疾光电影未命中八格直线远端目标")
	assert(off_laser_target.current_hp == off_laser_hp, "宽一格疾光电影错误命中正式直线外单位")

	near_laser_target.queue_free()
	far_laser_target.queue_free()
	off_laser_target.queue_free()
	await get_tree().process_frame

	var adjacent_repulsion_target := _make_enemy(
		game,
		game.player,
		origin_tile + Vector2i(1, 0),
		"抗拒火环相邻目标"
	)
	var outside_repulsion_target := _make_enemy(
		game,
		game.player,
		origin_tile + Vector2i(2, 0),
		"抗拒火环范围外目标"
	)
	var repulsion_definition: Dictionary = SkillDataLoader.skill(
		"wizard.repulsion_ring"
	)
	var repulsion_context: Dictionary = game._canonical_target_context(
		repulsion_definition,
		game.player.global_position,
		Vector2.DOWN,
		false
	)
	var repulsion_ids: Array[int] = []
	for repulsion_entry: Dictionary in repulsion_context.get("targets", []):
		repulsion_ids.append(int(repulsion_entry.get("instance_id", 0)))
	assert(
		repulsion_ids.has(adjacent_repulsion_target.get_instance_id()),
		"抗拒火环没有选中与相邻一格接触的怪物占位"
	)
	assert(
		not repulsion_ids.has(outside_repulsion_target.get_instance_id()),
		"抗拒火环错误选中相邻一圈以外的怪物"
	)
	assert(
		game._canonical_effect_enemy({
			"target_instance_id": adjacent_repulsion_target.get_instance_id(),
		}) == adjacent_repulsion_target,
		"抗拒火环效果没有映射回其各自的真实怪物实例"
	)
	adjacent_repulsion_target.queue_free()
	outside_repulsion_target.queue_free()
	await get_tree().process_frame

	var fire_wall_cells: Array[Vector2i] = [
		origin_tile,
		origin_tile + Vector2i.RIGHT,
		origin_tile + Vector2i.DOWN,
		origin_tile + Vector2i.ONE,
	]
	var fire_wall_inside := _make_enemy(
		game,
		game.player,
		origin_tile + Vector2i.ONE,
		"火墙四格内目标"
	)
	var fire_wall_outside := _make_enemy(
		game,
		game.player,
		origin_tile + Vector2i(4, 4),
		"火墙四格外目标"
	)
	assert(
		game._canonical_ground_cell_contains_enemy(
			fire_wall_inside,
			origin_tile + Vector2i.ONE
		),
		"火墙正式格没有按怪物占位接触判定目标"
	)
	var outside_touches_any := false
	for fire_wall_cell: Vector2i in fire_wall_cells:
		outside_touches_any = (
			outside_touches_any
			or game._canonical_ground_cell_contains_enemy(
				fire_wall_outside,
				fire_wall_cell
			)
		)
	assert(not outside_touches_any, "火墙仍使用越出正式2×2的圆形像素范围")
	game._spawn_canonical_ground_field(
		"wizard.fire_wall",
		fire_wall_cells,
		game.player.global_position,
		{
			"raw_power": 37,
			"duration_seconds": 3,
			"tick_interval_ms": 1000,
		}
	)
	var formal_cell_fields := 0
	for child: Node in game.get_children():
		if child is GroundSkillEffect and child.skill_id == "wizard.fire_wall":
			if child.runtime_target_filter.is_valid():
				formal_cell_fields += 1
	assert(
		formal_cell_fields >= 4,
		"火墙没有让四个正式格分别承担占位接触判定"
	)

	game.queue_free()
	await get_tree().process_frame
	print("GAME_ROOT_WIZARD_GEOMETRY_INTEGRATION_PASS")
	get_tree().quit(0)


func _make_enemy(
	game: Node,
	caster: PlayerCharacter,
	tile: Vector2i,
	display_name: String
) -> EnemyActor:
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
	}, caster, false)
	enemy.control_time = 60.0
	game.add_child(enemy)
	# Enemy._ready() repairs player overlap for production spawns. Tests place
	# exact footpoints after that one-time repair and then freeze AI movement.
	enemy.global_position = game._canonical_tile_to_world(tile)
	enemy.set_physics_process(false)
	return enemy
