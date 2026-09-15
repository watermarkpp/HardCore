extends Node

## SOT wizard.fire_wall stacking contract regression:
##   "same_caster_same_tile_refreshes_duration" — a recast on the same center
##   tile refreshes the existing field (no new controller, no new cells).
##   "max_active_fields_per_caster": "config_required_default_8" — the cap
##   counts one caster's fields. The SOT records no ninth-field behavior, so
##   the default cap policy fails closed to reject_new (no ninth field, no
##   eviction); an explicit "cap_policy": "evict_oldest" opts into eviction.
##   The registry key is source-aware (caster/map/generation/family/tile).
##   Field lifetime is wall-clock real time: an expired field frees on the
##   next simulated frame even when its duration countdown was frozen.

const FireWallFieldController := preload(
	"res://scripts/fire_wall_field_controller.gd"
)
const FIXTURE_MONSTER_ID := 19

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	var game: Node = load("res://scenes/main.tscn").instantiate()
	_game = game
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
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
	var field_a_cells: Array[Vector2i] = []
	for offset_x: int in range(-1, 2):
		for offset_y: int in range(-1, 2):
			field_a_cells.append(origin_cell + Vector2i(offset_x, offset_y))

	var effect := {
		"raw_power": 5,
		"radius_gu": 0.2,
		"duration_seconds": 30.0,
		"tick_interval_ms": 3000,
	}

	# 1) First cast on tile A creates exactly one controller with 9 cells.
	game._spawn_canonical_ground_field(
		"wizard.fire_wall", field_a_cells, game.player.global_position, effect
	)
	var controller_a := _only_controller()
	assert(controller_a != null, "first cast must create one controller")
	assert(
		controller_a.visual_cells.size() == 9,
		"3x3 footprint must own nine visual cells: %d"
		% controller_a.visual_cells.size()
	)

	# 2) Recast on the same tile refreshes instead of stacking.
	game._spawn_canonical_ground_field(
		"wizard.fire_wall", field_a_cells, game.player.global_position, effect
	)
	assert(
		_valid_controller_count() == 1,
		"same-tile recast must not spawn a second controller"
	)
	assert(is_instance_valid(controller_a), "refresh reuses the same field")
	assert(
		int(controller_a.refresh_count) == 1,
		"same-tile recast must refresh the field once: %d"
		% int(controller_a.refresh_count)
	)
	assert(
		controller_a.visual_cells.size() == 9,
		"refresh must not add visual cells"
	)

	# 3) Default cap policy is fail-closed reject_new (GPT audit R1-P0: the
	#    SOT records no ninth-field behavior): the ninth distinct tile
	#    neither creates a field nor evicts the oldest one.
	for field_index: int in range(1, 9):
		var shifted_cells: Array[Vector2i] = []
		for cell: Vector2i in field_a_cells:
			shifted_cells.append(cell + Vector2i(10 * field_index, 0))
		game._spawn_canonical_ground_field(
			"wizard.fire_wall",
			shifted_cells,
			game.player.global_position,
			effect
		)
	assert(
		_valid_controller_count() == 8,
		"active fields must cap at the canonical 8: %d"
		% _valid_controller_count()
	)
	assert(
		is_instance_valid(controller_a),
		"reject_new must not evict the oldest field"
	)

	# 3b) Explicit "cap_policy": "evict_oldest" opts into eviction: casts 9
	#     and 10 evict this caster's oldest fields to stay at the cap.
	var evict_effect: Dictionary = effect.duplicate()
	evict_effect["cap_policy"] = "evict_oldest"
	for field_index: int in range(9, 11):
		var evict_cells: Array[Vector2i] = []
		for cell: Vector2i in field_a_cells:
			evict_cells.append(cell + Vector2i(10 * field_index, 0))
		game._spawn_canonical_ground_field(
			"wizard.fire_wall",
			evict_cells,
			game.player.global_position,
			evict_effect
		)
	assert(
		_valid_controller_count() == 8,
		"evict_oldest must keep the caster at the cap: %d"
		% _valid_controller_count()
	)
	assert(
		not is_instance_valid(controller_a)
		or controller_a.is_queued_for_deletion(),
		"explicit evict_oldest must evict the oldest field"
	)

	# 3c) Registry key is source-aware (GPT audit R1-P0): caster identity,
	#     skill family, tile, map and zone generation all participate, so two
	#     casters on one tile own separate fields and never cross-refresh.
	var key_a: String = game._fire_wall_registry_key(
		game.player, "wizard.fire_wall", Vector2i(50, 50)
	)
	var other_caster := Node2D.new()
	game.add_child(other_caster)
	var key_other_caster: String = game._fire_wall_registry_key(
		other_caster, "wizard.fire_wall", Vector2i(50, 50)
	)
	var key_other_family: String = game._fire_wall_registry_key(
		game.player, "wizard.other", Vector2i(50, 50)
	)
	var key_other_tile: String = game._fire_wall_registry_key(
		game.player, "wizard.fire_wall", Vector2i(51, 50)
	)
	var saved_generation: int = int(game._zone_generation)
	game._zone_generation = saved_generation + 1
	var key_other_generation: String = game._fire_wall_registry_key(
		game.player, "wizard.fire_wall", Vector2i(50, 50)
	)
	game._zone_generation = saved_generation
	assert(
		key_a != key_other_caster
		and key_a != key_other_family
		and key_a != key_other_tile
		and key_a != key_other_generation,
		"registry key must separate caster, family, tile and generation"
	)
	other_caster.queue_free()

	# 4) Wall-clock expiry: a field whose real-time deadline passed frees on
	# the next simulated frame even if its duration countdown was frozen.
	var remaining := _valid_controllers()
	assert(not remaining.is_empty(), "capped fields must remain for expiry test")
	var doomed: FireWallFieldController = remaining[0]
	doomed.set_physics_process(true)
	doomed.expires_at_ticks_msec = Time.get_ticks_msec() - 1
	doomed._physics_process(0.016)
	assert(doomed.expired, "wall-clock expired field must flag expired")
	assert(
		doomed.is_queued_for_deletion(),
		"wall-clock expired field must free on the next frame"
	)

	game.queue_free()
	await game.tree_exited
	print("FIRE_WALL_FIELD_REGISTRY_PASS")
	get_tree().quit(0)


func _only_controller() -> FireWallFieldController:
	var controllers := _valid_controllers()
	return controllers[0] if controllers.size() == 1 else null


func _valid_controllers() -> Array[FireWallFieldController]:
	var controllers: Array[FireWallFieldController] = []
	for child: Node in _game.get_children():
		if child is FireWallFieldController and not child.is_queued_for_deletion():
			controllers.append(child as FireWallFieldController)
	return controllers


func _valid_controller_count() -> int:
	return _valid_controllers().size()
