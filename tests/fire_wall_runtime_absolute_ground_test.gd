extends Node


const RuntimeBridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const FireWallFieldController := preload(
	"res://scripts/fire_wall_field_controller.gd"
)
const GroundSkillVisualCell := preload(
	"res://scripts/ground_skill_visual_cell.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var runtime: Dictionary = RuntimeBridge.load_map(game.current_map_id)
	assert(not runtime.is_empty(), "runtime map is required for absolute ground verification")

	var origin_cell: Vector2i = game._canonical_screen_px_to_grid_cell(game.player.global_position)
	var fire_wall_cells: Array[Vector2i] = [
		origin_cell,
		origin_cell + Vector2i.RIGHT,
		origin_cell + Vector2i.DOWN,
		origin_cell + Vector2i.ONE,
	]
	game._spawn_canonical_ground_field(
		"wizard.fire_wall",
		fire_wall_cells,
		game.player.global_position,
		{
			"raw_power": 47,
			"radius_gu": 0.2,
			"duration_seconds": 1.5,
			"tick_interval_ms": 1000,
		}
	)

	await get_tree().physics_frame
	await get_tree().process_frame

	var fire_wall_controllers: Array[FireWallFieldController] = []
	var fire_wall_fields: Array[GroundSkillEffect] = []
	for child: Node in game.get_children():
		if child is FireWallFieldController:
			fire_wall_controllers.append(child as FireWallFieldController)
		elif child is GroundSkillEffect and child.skill_id == "wizard.fire_wall":
			fire_wall_fields.append(child as GroundSkillEffect)
			assert(
				child.runtime_target_filter.is_valid(),
				"a runtime map-backed fire-wall field should use a runtime target filter"
			)

	assert(
		not fire_wall_controllers.is_empty() or fire_wall_fields.size() == 4,
		"expected either one fire-wall field controller or four legacy fire-wall fields"
	)
	var fire_wall_origin_position: Vector2 = Vector2.ZERO
	if not fire_wall_controllers.is_empty():
		var fire_wall_controller: FireWallFieldController = fire_wall_controllers[0]
		assert(
			fire_wall_controller.visual_cells.size() == 4,
			"expected four visual cells for a 2x2 fire-wall controller"
		)
		for visual_cell: GroundSkillVisualCell in fire_wall_controller.visual_cells:
			assert(
				visual_cell.visual_only
				and visual_cell.damage_owner == GroundSkillVisualCell.DAMAGE_OWNER
				and not visual_cell.runtime_target_filter.is_valid(),
				"Q2-C: a fire-wall visual cell must be pure presentation without a per-cell damage filter"
			)
			assert(
				visual_cell.cell_index >= 0
				and not visual_cell.canonical_snapshot_id.is_empty(),
				"Q2-C: each visual cell must carry its index and the shared canonical snapshot id"
			)
		assert(fire_wall_controller.visual_cells.size() > 0, "fire-wall controller should expose visual cells")
		fire_wall_origin_position = fire_wall_controller.visual_cells[0].global_position
	else:
		fire_wall_origin_position = fire_wall_fields[0].global_position

	var inside_target := _make_enemy(game, fire_wall_origin_position, "runtime-fire-wall-inside")
	var outside_target := _make_enemy(game, fire_wall_origin_position + Vector2(512, 0), "runtime-fire-wall-outside")

	var inside_detected := false
	var outside_detected := false
	if not fire_wall_fields.is_empty():
		for fire_wall_field in fire_wall_fields:
			inside_detected = inside_detected or fire_wall_field.runtime_target_is_inside(
				inside_target
			)
			outside_detected = outside_detected or fire_wall_field.runtime_target_is_inside(
				outside_target
			)
	elif not fire_wall_controllers.is_empty():
		var fire_wall_controller: FireWallFieldController = fire_wall_controllers[0]
		for visual_cell: GroundSkillVisualCell in fire_wall_controller.visual_cells:
			inside_detected = inside_detected or visual_cell.runtime_target_is_inside(
				inside_target
			)
			outside_detected = outside_detected or visual_cell.runtime_target_is_inside(
				outside_target
			)

	assert(
		inside_detected,
		"runtime fire-wall field failed to detect a target converted from absolute runtime ground GU"
	)
	assert(
		not outside_detected,
		"runtime fire-wall fields should not detect an outside target when using runtime absolute ground coordinates"
	)

	inside_target.queue_free()
	outside_target.queue_free()
	game.queue_free()
	await get_tree().process_frame
	print(
		"FIRE_WALL_RUNTIME_ABSOLUTE_GROUND_PASS: "
		+ "2x2 runtime-map fire-wall fields use runtime coordinate filtering for absolute GU targets"
	)
	get_tree().quit(0)


func _make_enemy(game: Node, screen_position: Vector2, display_name: String) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": display_name,
		"hp": 999,
		"attackMin": 1,
		"attackMax": 1,
		"level": 1,
		"anti_magic_points": 0,
		"magic_defense_min": 0,
		"magic_defense_max": 0,
	}, game.player, false)
	enemy.global_position = screen_position
	enemy.combat_radius_gu = 0.6
	enemy.set_physics_process(false)
	game.add_child(enemy)
	return enemy
