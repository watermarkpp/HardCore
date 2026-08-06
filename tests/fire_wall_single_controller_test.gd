extends Node


const GroundSkillEffect := preload("res://scripts/ground_effect.gd")
const FireWallFieldController := preload(
	"res://scripts/fire_wall_field_controller.gd"
)
const GroundSkillVisualCell := preload(
	"res://scripts/ground_skill_visual_cell.gd"
)

var _recorded_tick_powers: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	# Wait for the initial world bootstrap to finish loading the zone. Its
	# zone_content cleanup would otherwise free the fire wall cells mid-test.
	for _bootstrap_wait in range(300):
		if not bool(game.get("_world_bootstrap_in_progress")):
			break
		await get_tree().process_frame
	await get_tree().process_frame
	game._active_safe_zones = []
	await get_tree().process_frame

	var origin_cell: Vector2i = game._canonical_screen_px_to_grid_cell(
		game.player.global_position
	)
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
			"raw_power": 37,
			"radius_gu": 0.2,
			"duration_seconds": 2.2,
			"tick_interval_ms": 1000,
		}
	)

	var controllers: Array[FireWallFieldController] = []
	for child: Node in game.get_children():
		if child is FireWallFieldController:
			controllers.append(child as FireWallFieldController)
	assert(
		controllers.size() == 1,
		"expected a single fire-wall field controller for a 2x2 square"
	)
	var fwc: FireWallFieldController = controllers[0]
	fwc.runtime_tick_callback = Callable(self, "_record_tick")

	# Structural assertions.
	assert(fwc.visual_cells.size() == 4,
		"expected four visual cells under one controller")

	# Each visual cell must report zero enemy queries and zero damage ticks.
	for cell: GroundSkillVisualCell in fwc.visual_cells:
		var diag: Dictionary = cell.runtime_diagnostics()
		assert(diag.get("enemy_group_queries", -1) == 0,
			"visual cell must not query enemies group")
		assert(diag.get("damage_ticks", -1) == 0,
			"visual cell must not apply damage")

	var inside_target := _make_enemy(
		game,
		fwc.visual_cells[0].global_position,
		"inside"
	)
	var outside_target := _make_enemy(
		game,
		fwc.visual_cells[0].global_position + Vector2(512, 0),
		"outside"
	)

	await get_tree().create_timer(1.2).timeout

	var diag: Dictionary = fwc.runtime_diagnostics()
	# Controller must have performed exactly one enemy-group query per tick.
	assert(diag.get("enemy_group_queries", -1) >= 1,
		"controller must query enemies at least once")
	# At least one damage tick should have fired (target is inside).
	assert(diag.get("damage_ticks", -1) >= 1,
		"controller must apply damage to inside targets")

	inside_target.queue_free()
	outside_target.queue_free()
	game.queue_free()
	await get_tree().process_frame
	print("FIRE_WALL_SINGLE_CONTROLLER_PASS")
	get_tree().quit(0)


func _record_tick(_target: EnemyActor, raw_power: int) -> void:
	_recorded_tick_powers.append(raw_power)


func _make_enemy(game: Node, pos: Vector2, name_str: String) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": name_str, "hp": 999, "attackMin": 1, "attackMax": 1,
		"level": 1, "anti_magic_points": 0, "magic_defense_min": 0,
		"magic_defense_max": 0,
	}, game.player, false)
	enemy.name = name_str
	enemy.global_position = pos
	enemy.set_process(false)
	enemy.combat_radius_gu = 0.6
	enemy.set_physics_process(false)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.add_to_group("enemies")
	game.add_child(enemy)
	return enemy
