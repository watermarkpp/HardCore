extends Node


const GroundSkillEffect := preload("res://scripts/ground_effect.gd")
const FireWallFieldController := preload(
	"res://scripts/fire_wall_field_controller.gd"
)
const GroundSkillVisualCell := preload(
	"res://scripts/ground_skill_visual_cell.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

var _recorded_tick_powers: Array[int] = []
var _enemy_serial := 0
var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	_game = game
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
	fwc.set_physics_process(false)

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

	# Q2-C: drive one deterministic controller tick (no wall-clock dependence).
	fwc._apply_field_tick()

	var diag: Dictionary = fwc.runtime_diagnostics()
	var q2c_diag: Dictionary = fwc.fire_wall_controller_diagnostics()
	# Q2-C: no enemy-group query at all; one shared-index broadphase query per
	# tick and at least one canonical exact test against the inside target.
	assert(diag.get("enemy_group_queries", -1) == 0,
		"controller must never query the enemies group")
	assert(
		int(q2c_diag.get("group_scan_count", -1)) == 0
		and int(q2c_diag.get("group_nodes_examined", -1)) == 0,
		"controller must never group-scan enemies"
	)
	assert(int(q2c_diag.get("broadphase_query_count", 0)) >= 1,
		"controller must run one broadphase query per tick")
	assert(int(q2c_diag.get("controller_exact_test_count", 0)) >= 1,
		"controller must exact-test candidates through the canonical snapshot: %s"
		% str(q2c_diag))
	assert(int(q2c_diag.get("visual_cell_exact_test_count", -1)) == 0,
		"visual cells must never run exact tests")
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
	# Q2-C: the controller queries the shared RuntimeCombatSpatialIndex, so the
	# test enemy must be registered exactly like a production spawn.
	_enemy_serial += 1
	enemy.configure_runtime_map_projection(
		int(game.get("current_map_id")),
		Callable(self, "_ground_to_screen"),
		Callable(game, "_canonical_screen_px_to_ground_gu")
	)
	enemy.configure_spatial_index(
		game.get("_combat_spatial_index"),
		_enemy_serial
	)
	# Register with the same conversion the enemy's spatial_index_position
	# provider uses, so the lazy re-home never moves the entry out of range.
	# Register AFTER add_child: EnemyActor._ready may call set_combat_position
	# (spawn-overlap resolution) which would otherwise re-home the index entry
	# into a different coordinate space before the canonical registration.
	game.add_child(enemy)
	# FREEZE-P0: the shared index and the controller both live in absolute
	# runtime-map Ground GU; the enemy must register with the same map-aware
	# conversion its provider uses.
	var ground_gu: Vector2 = game._canonical_screen_px_to_ground_gu(pos)
	game._combat_spatial_index.register(
		_enemy_serial,
		int(game.get("current_map_id")),
		ground_gu,
		enemy.combat_radius_gu,
		_enemy_serial,
		enemy,
		Callable(enemy, "spatial_index_position")
	)
	enemy.set_process(false)
	enemy.combat_radius_gu = 0.6
	enemy.set_physics_process(false)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.add_to_group("enemies")
	return enemy


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
