extends Node

const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const FireWallFieldController := preload(
	"res://scripts/fire_wall_field_controller.gd"
)
const GroundSkillVisualCell := preload(
	"res://scripts/ground_skill_visual_cell.gd"
)
const SkillFootprintSnapshot := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const SkillFootprintDiagnosticLog := preload(
	"res://scripts/layers/runtime/skill_footprint_diagnostic_log.gd"
)
const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload(
	"res://scripts/caster_skill_visual_registry.gd"
)
const CasterSkillVisualEffect := preload(
	"res://scripts/caster_skill_visual_effect.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	ProjectSettings.set_setting(&"hardcore/debug/diagnostics/enabled", false)
	SkillFootprintDiagnosticLog.clear_recent_events()
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.recalculate_stats()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var generated_release_a: String = game._next_skill_footprint_release_id(
		"wizard.laser"
	)
	var generated_release_b: String = game._next_skill_footprint_release_id(
		"wizard.laser"
	)
	assert(not generated_release_a.is_empty())
	assert(generated_release_a != generated_release_b)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = game.player.global_position + Vector2(4000, 4000)

	var origin_tile: Vector2i = game._canonical_screen_px_to_grid_cell(
		game.player.global_position
	)
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

	var origin_ground_gu: Vector2 = game._canonical_screen_px_to_ground_gu(
		game.player.global_position
	)
	var free_aim_direction_ground_gu := Vector2(1.0, 0.45).normalized()
	var free_aim_screen_px: Vector2 = (
		game._canonical_ground_gu_to_screen_px(
			origin_ground_gu + free_aim_direction_ground_gu
		)
		- game.player.global_position
	)
	var hellfire_effect := {
		"line_geometry_contract": SpellGeometry.CONTINUOUS_AIM_LINE_CONTRACT_ID,
		"effect_length_gu": 5.0,
		"effect_width_gu": 1.0,
		"pierces_units": false,
		"stops_on_terrain": false,
	}
	var hellfire_strip: Dictionary = game._canonical_continuous_line_strip_ground_gu(
		"wizard.hellfire",
		hellfire_effect,
		game.player.global_position,
		free_aim_screen_px,
		"test:hellfire:release:1"
	)
	assert((hellfire_strip.direction_ground_gu as Vector2).is_equal_approx(
		free_aim_direction_ground_gu
	))
	assert(is_equal_approx(float(hellfire_strip.effect_length_gu), 5.0))
	assert(is_equal_approx(float(hellfire_strip.effect_width_gu), 1.0))
	var hellfire_snapshot: Dictionary = hellfire_strip.get(
		"skill_footprint_snapshot", {}
	)
	assert(game._snapshot_strict_ok(hellfire_snapshot))
	assert(hellfire_snapshot.is_read_only())
	assert(hellfire_snapshot.skill_id == "wizard.hellfire")
	assert(hellfire_snapshot.release_id == "test:hellfire:release:1")
	var first_line_target := _make_enemy_at_fractional_tile(
		game, game.player, origin_ground_gu + free_aim_direction_ground_gu, "地狱火首个目标"
	)
	var rear_line_target := _make_enemy_at_fractional_tile(
		game,
		game.player,
		origin_ground_gu + free_aim_direction_ground_gu * 4.5,
		"地狱火后方目标"
	)
	var off_line_target := _make_enemy_at_fractional_tile(
		game,
		game.player,
		origin_ground_gu
		+ free_aim_direction_ground_gu * 2.0
		+ Vector2(-free_aim_direction_ground_gu.y, free_aim_direction_ground_gu.x) * 2.0,
		"地狱火线外目标"
	)
	var first_hp := first_line_target.current_hp
	var rear_hp := rear_line_target.current_hp
	var off_line_hp := off_line_target.current_hp
	var hellfire_hit: bool = game._apply_canonical_spell_damage(
		"wizard.hellfire",
		20,
		game.player.global_position,
		free_aim_screen_px,
		"line_damage",
		null,
		[],
		hellfire_effect,
		hellfire_strip
	)
	assert(hellfire_hit and first_line_target.current_hp < first_hp, "地狱火未命中连续五格直线内首个目标")
	assert(rear_line_target.current_hp < rear_hp, "地狱火未命中连续五格直线内后方目标")
	assert(off_line_target.current_hp == off_line_hp, "宽一格地狱火错误命中正式条带外单位")
	var hellfire_diagnostics := SkillFootprintDiagnosticLog.recent_events()
	assert(hellfire_diagnostics.size() == 1)
	assert(hellfire_diagnostics[0].release_id == "test:hellfire:release:1")
	assert(int(hellfire_diagnostics[0].eligible_target_count) == 2)
	assert(bool(hellfire_diagnostics[0].damage_applied))
	assert(is_zero_approx(float(
		hellfire_diagnostics[0].maximum_corner_error_px
	)))

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
	assert(game._canonical_screen_px_to_grid_cell(ring_target.global_position) == origin_tile + Vector2i(2, 0))
	assert(game._canonical_screen_px_to_grid_cell(center_target.global_position) == origin_tile)
	assert(game._canonical_screen_px_to_grid_cell(outside_target.global_position) == origin_tile + Vector2i(3, 0))
	var ring_targets: Array[EnemyActor] = game._canonical_spell_geometry_targets(
		"wizard.hell_lightning",
		ring_cells,
		{"maximum_targets": 24, "exclude_center": true, "radius_grid_steps": 2}
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
		{"maximum_targets": 24, "exclude_center": true, "radius_grid_steps": 2}
	)
	assert(lightning_hit and ring_target.current_hp < ring_hp, "地狱雷光未命中正式半径二格外环目标")
	assert(center_target.current_hp == center_hp, "地狱雷光错误命中施法者脚下中心格")
	assert(outside_target.current_hp == outside_hp, "地狱雷光错误命中半径二格以外目标")
	ring_target.queue_free()
	center_target.queue_free()
	outside_target.queue_free()
	await get_tree().process_frame

	var laser_aim_direction_ground_gu := Vector2(0.35, -1.0).normalized()
	var laser_aim_screen_px: Vector2 = (
		game._canonical_ground_gu_to_screen_px(
			origin_ground_gu + laser_aim_direction_ground_gu
		)
		- game.player.global_position
	)
	var laser_effect := {
		"line_geometry_contract": SpellGeometry.CONTINUOUS_AIM_LINE_CONTRACT_ID,
		"effect_length_gu": 8.0,
		"effect_width_gu": 1.0,
		"pierces_units": true,
		"stops_on_terrain": false,
	}
	var laser_strip: Dictionary = game._canonical_continuous_line_strip_ground_gu(
		"wizard.laser",
		laser_effect,
		game.player.global_position,
		laser_aim_screen_px,
		"test:laser:release:1"
	)
	assert((laser_strip.direction_ground_gu as Vector2).is_equal_approx(
		laser_aim_direction_ground_gu
	))
	assert(is_equal_approx(float(laser_strip.effect_length_gu), 8.0))
	var laser_snapshot: Dictionary = laser_strip.get(
		"skill_footprint_snapshot", {}
	)
	assert(game._snapshot_strict_ok(laser_snapshot))
	assert(laser_snapshot.is_read_only())
	assert(laser_snapshot.skill_id == "wizard.laser")
	assert(laser_snapshot.release_id == "test:laser:release:1")
	var visual_children_before := game.get_child_count()
	# Q3-C: the legacy visual spawner was removed; the shared line-strip visual
	# is created through the canonical node adapter from a frozen
	# canonical-shaped presentation plan.
	var expected_laser_screen_points: Array[Vector2] = (
		SpellGeometry.continuous_line_screen_points_px(
			laser_strip,
			Callable(game, "_canonical_ground_gu_to_screen_px")
		)
	)
	var presentation_plan := {
		"contract": "skill_execution_plan.v1",
		"release_id": "test:laser:release:1",
		"skill_id": "wizard.laser",
		"canonical_snapshot": laser_snapshot,
		"success": true,
		"operation": "canonical_visual_only",
		"visual": CasterSkillVisualRegistry.profile("wizard.laser"),
		"visual_radius_px": 72.0,
		"visual_duration": 0.8,
		"canonical_geometry_contract": (
			SpellGeometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID
		),
		"geometry_origin_screen_px": game.player.global_position,
		"geometry_grid_cells": [],
		"geometry_screen_points_px": expected_laser_screen_points,
		"skill_footprint_snapshot": laser_snapshot,
		"presentation_actions": [{
			"type": "visual",
			"skill_id": "wizard.laser",
			"role": CasterSkillVisualRegistry.ROLE_LINE_EFFECT,
			"phase": "",
			"visual_radius_px": 72.0,
			"visual_duration": 0.8,
			"canonical_geometry_contract": (
				SpellGeometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID
			),
			"geometry_origin_screen_px": game.player.global_position,
			"target_position_screen_px": (
				game.player.global_position + laser_aim_screen_px
			),
			"geometry_grid_cells": [],
			"geometry_screen_points_px": expected_laser_screen_points,
			"ground_gu_to_screen_position_px": (
				Callable(game, "_canonical_ground_gu_to_screen_px")
			),
			"snapshot_validation_context": (
				game._canonical_snapshot_validation_context(
					game._canonical_screen_px_to_ground_gu(
						game.player.global_position
					)
				)
			),
		}],
		"gameplay_actions": [],
		"projectile_descriptors": [],
		"ground_effect_descriptors": [],
		"summon_descriptors": [],
	}
	var shared_geometry_visuals := (
		CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
			presentation_plan,
			game.player.global_position,
			laser_aim_screen_px,
			Color.WHITE,
			null,
			game.player
		)
	)
	assert(shared_geometry_visuals.size() == 1)
	for raw_node: Node2D in shared_geometry_visuals:
		game.add_child(raw_node)
	assert(game.get_child_count() == visual_children_before + 1)
	var shared_geometry_visual := game.get_child(game.get_child_count() - 1)
	assert(shared_geometry_visual is CasterSkillVisualEffect)
	assert(not expected_laser_screen_points.is_empty())
	assert(not shared_geometry_visual._geometry_screen_offsets_px.is_empty())
	assert(shared_geometry_visual._geometry_screen_offsets_px.back().is_equal_approx(
		expected_laser_screen_points.back() - game.player.global_position
	))
	assert(
		shared_geometry_visual.formal_core_polygon_screen_offset_px()
		== SkillFootprintSnapshot.projected_polygon_screen_offset_px(
			laser_snapshot
		)
	)
	assert(
		str(shared_geometry_visual.get_meta("formal_line_snapshot_id", ""))
		== str(laser_snapshot.snapshot_id)
	)
	shared_geometry_visual.free()
	var near_laser_target := _make_enemy_at_fractional_tile(
		game,
		game.player,
		origin_ground_gu + laser_aim_direction_ground_gu,
		"疾光近端目标"
	)
	var far_laser_target := _make_enemy_at_fractional_tile(
		game,
		game.player,
		origin_ground_gu + laser_aim_direction_ground_gu * 7.5,
		"疾光远端目标"
	)
	var off_laser_target := _make_enemy_at_fractional_tile(
		game,
		game.player,
		origin_ground_gu
		+ laser_aim_direction_ground_gu * 4.0
		+ Vector2(-laser_aim_direction_ground_gu.y, laser_aim_direction_ground_gu.x) * 2.0,
		"疾光线外目标"
	)
	var stacked_laser_targets: Array[EnemyActor] = []
	var stacked_laser_hp: Array[int] = []
	for stacked_index: int in range(7):
		var stacked_target := _make_enemy_at_fractional_tile(
			game,
			game.player,
			origin_ground_gu
			+ laser_aim_direction_ground_gu * (2.0 + float(stacked_index) * 0.5),
			"疾光穿透目标%d" % stacked_index
		)
		stacked_laser_targets.append(stacked_target)
		stacked_laser_hp.append(stacked_target.current_hp)
	var near_laser_hp := near_laser_target.current_hp
	var far_laser_hp := far_laser_target.current_hp
	var off_laser_hp := off_laser_target.current_hp
	var laser_hit: bool = game._apply_canonical_spell_damage(
		"wizard.laser",
		20,
		game.player.global_position,
		laser_aim_screen_px,
		"piercing_line_damage",
		null,
		[],
		laser_effect,
		laser_strip
	)
	assert(laser_hit, "疾光电影连续八格直线没有产生命中")
	assert(near_laser_target.current_hp < near_laser_hp, "疾光电影未命中连续八格近端目标")
	assert(far_laser_target.current_hp < far_laser_hp, "穿透疾光电影未命中连续八格远端目标")
	assert(off_laser_target.current_hp == off_laser_hp, "宽一格疾光电影错误命中连续条带外单位")
	for stacked_index: int in range(stacked_laser_targets.size()):
		assert(
			stacked_laser_targets[stacked_index].current_hp < stacked_laser_hp[stacked_index],
			"疾光电影错误保留八目标上限：第%d个附加目标未受伤" % stacked_index
		)
	var line_diagnostics := SkillFootprintDiagnosticLog.recent_events()
	assert(line_diagnostics.size() == 2)
	assert(line_diagnostics[1].release_id == "test:laser:release:1")
	assert(int(line_diagnostics[1].eligible_target_count) == 9)
	assert(bool(line_diagnostics[1].damage_applied))
	assert(
		line_diagnostics[1].expected_projected_polygon_px
		== line_diagnostics[1].actual_visual_core_polygon_px
	)

	near_laser_target.queue_free()
	far_laser_target.queue_free()
	off_laser_target.queue_free()
	for stacked_target: EnemyActor in stacked_laser_targets:
		stacked_target.queue_free()
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
	var shared_snapshot_ids: Dictionary = {}
	for child: Node in game.get_children():
		if not child is FireWallFieldController:
			continue
		var field_controller := child as FireWallFieldController
		for cell: GroundSkillVisualCell in field_controller.visual_cells:
			assert(
				cell.visual_only
				and cell.damage_owner == GroundSkillVisualCell.DAMAGE_OWNER,
				"Q2-C: fire-wall cells must be pure visual presentation nodes"
			)
			formal_cell_fields += 1
			shared_snapshot_ids[cell.canonical_snapshot_id] = true
	assert(
		formal_cell_fields == 4 and shared_snapshot_ids.size() == 1,
		"Q2-C: the formal fire wall must keep exactly 4 cells sharing one canonical snapshot id"
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
	enemy.global_position = game._canonical_grid_cell_to_screen_px(tile)
	enemy.set_physics_process(false)
	return enemy


func _make_enemy_at_fractional_tile(
	game: Node,
	caster: PlayerCharacter,
	tile: Vector2,
	display_name: String
) -> EnemyActor:
	var enemy := _make_enemy(
		game,
		caster,
		Vector2i(roundi(tile.x), roundi(tile.y)),
		display_name
	)
	enemy.global_position = game._canonical_ground_gu_to_screen_px(tile)
	return enemy
