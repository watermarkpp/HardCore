extends Node

## SOT wizard.fire_wall stacking contract regression:
##   "same_caster_same_tile_refreshes_duration" — a recast on the same center
##   tile refreshes the existing field (no new controller, no new cells).
##   "max_active_fields_per_caster": "config_required_default_8" — the cap
##   counts one caster's fields. R2 ruling (user device ruling 2026-09-15):
##   the SOT now records "cap_policy": "evict_oldest" — casting always
##   succeeds and the oldest field is cancelled at the cap; UNCONFIGURED
##   data still fails closed to reject_new. The registry key is
##   source-aware (caster/map/generation/family/tile). Field lifetime is
##   wall-clock real time: an expired field frees on the next simulated
##   frame even when its duration countdown was frozen, and its registry
##   slot is released proactively (R2-2 tree_exited hook), not lazily.

const FireWallFieldController := preload(
	"res://scripts/fire_wall_field_controller.gd"
)
const SkillDataLoader := preload("res://scripts/skills/skill_data_loader.gd")
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
	var doomed_key := ""
	for key: Variant in _game._fire_wall_field_registry:
		if _game._fire_wall_field_registry[key] == doomed:
			doomed_key = str(key)
			break
	assert(doomed_key != "", "expired field must still own its registry slot")
	var registry_size_before: int = _game._fire_wall_field_registry.size()

	# 4b) R2-2 identity guard (dedicated probe — the live capped fields stay
	#     untouched, so this test never fabricates untracked-live-controller
	#     state): a stale tree_exited signal must not evict the field owning
	#     the key; the owner's own signal must.
	var probe: FireWallFieldController = FireWallFieldController.new()
	_game.add_child(probe)
	var probe_key: String = _game._fire_wall_registry_key(
		_game.player, "wizard.fire_wall_guard_probe", Vector2i(9999, 9999)
	)
	_game._fire_wall_field_registry[probe_key] = probe
	_game._fire_wall_field_order.append(probe_key)
	_game._on_fire_wall_field_tree_exited(probe_key, doomed)
	assert(
		_game._fire_wall_field_registry.get(probe_key) == probe,
		"stale controller signal must not evict the field owning the key"
	)
	_game._on_fire_wall_field_tree_exited(probe_key, probe)
	assert(
		not _game._fire_wall_field_registry.has(probe_key)
		and not _game._fire_wall_field_order.has(probe_key),
		"the owning controller's release must erase registry and order slots"
	)
	probe.queue_free()

	# 4c) R2-2 proactive lifecycle: once the expired controller actually
	#     leaves the tree, its registry slot is gone WITHOUT any further
	#     cast (no lazy-prune dependency), and the R2-5 debug invariant
	#     still holds.
	await get_tree().process_frame
	await get_tree().process_frame
	assert(
		not is_instance_valid(doomed),
		"expired controller must be freed by the engine"
	)
	_game._debug_validate_fire_wall_registry("test:post_expiry")
	assert(
		_game._fire_wall_field_registry.size() == registry_size_before - 1,
		"expired field must release its registry slot proactively: %d vs %d"
		% [
			_game._fire_wall_field_registry.size(),
			registry_size_before - 1,
		]
	)
	assert(
		not _game._fire_wall_field_registry.has(doomed_key),
		"the expired field's slot must be released by its tree_exited hook"
	)
	var data_mechanics: Dictionary = SkillDataLoader.skill(
		"wizard.fire_wall"
	).get("mechanics", {})
	assert(
		str(data_mechanics.get("cap_policy", "")) == "evict_oldest",
		"SOT mechanics must record the R2 evict_oldest ruling"
	)

	# 5) R2-4 ninth-field E2E: the replacement field must have real visuals,
	#    a valid canonical snapshot and must actually burn a monster. The
	#    user-visible bug was "cast animation + sound, but no visuals and no
	#    damage" — locking only the registry size is not enough.
	game.set_process(false)
	game.set_physics_process(false)
	var e2e_field_index := 12
	var e2e_cells: Array[Vector2i] = []
	for cell: Vector2i in field_a_cells:
		e2e_cells.append(cell + Vector2i(10 * e2e_field_index, 0))
	var e2e_center: Vector2i = e2e_cells[4]
	var monster_data: Dictionary = GameData.get_monster_by_id(
		FIXTURE_MONSTER_ID
	)
	assert(
		not monster_data.is_empty(),
		"fixture monster must exist in canonical monster data"
	)
	var monster: Node = game._spawn_enemy(
		monster_data,
		game._canonical_grid_cell_to_screen_px(e2e_center),
		false,
		-1.0,
		{"respawn_enabled": false}
	)
	assert(monster != null, "E2E fixture monster must spawn")
	await get_tree().physics_frame
	await get_tree().physics_frame
	monster.set_physics_process(false)
	var hp_before: int = int(monster.current_hp)
	# Refill to the cap first (section 4's expiry freed one slot), so the
	# E2E cast below exercises the evict-oldest replacement path exactly as
	# the user's ninth-cast bug did.
	var refill_cells: Array[Vector2i] = []
	for cell: Vector2i in field_a_cells:
		refill_cells.append(cell + Vector2i(110, 0))
	game._spawn_canonical_ground_field(
		"wizard.fire_wall",
		refill_cells,
		game.player.global_position,
		evict_effect
	)
	assert(
		_valid_controller_count() == 8,
		"refill cast must restore the caster to the cap"
	)
	var controllers_before := _valid_controllers()
	assert(
		controllers_before.size() == 8,
		"E2E precondition: the caster must be at the cap"
	)
	game._spawn_canonical_ground_field(
		"wizard.fire_wall",
		e2e_cells,
		game.player.global_position,
		evict_effect
	)
	var controllers_after := _valid_controllers()
	assert(
		controllers_after.size() == 8,
		"the replacement cast must keep the caster at the cap: %d"
		% controllers_after.size()
	)
	var newest: FireWallFieldController = null
	for controller: FireWallFieldController in controllers_after:
		if not controllers_before.has(controller):
			newest = controller
			break
	assert(newest != null, "the ninth-class cast must create a new field")
	assert(
		not newest.is_queued_for_deletion(),
		"the replacement field must stay alive"
	)
	assert(
		newest.visual_cells.size() == 9,
		"the replacement field must own nine visual cells: %d"
		% newest.visual_cells.size()
	)
	assert(
		newest._canonical_snapshot_valid,
		"the replacement field must hold a valid canonical snapshot"
	)
	newest._apply_field_tick()
	assert(newest.tick_count >= 1, "the replacement field must tick")
	assert(
		newest.damage_application_count >= 1,
		"the replacement field must apply damage to the indexed monster"
	)
	assert(
		int(monster.current_hp) < hp_before,
		"the replacement field must actually damage the monster: %d -> %d"
		% [hp_before, int(monster.current_hp)]
	)
	_game._debug_validate_fire_wall_registry("test:ninth_field_e2e")

	# 5b) Consecutive ninth-class casts keep working (evict-oldest rolls on).
	for followup_index: int in range(13, 15):
		var followup_cells: Array[Vector2i] = []
		for cell: Vector2i in field_a_cells:
			followup_cells.append(cell + Vector2i(10 * followup_index, 0))
		game._spawn_canonical_ground_field(
			"wizard.fire_wall",
			followup_cells,
			game.player.global_position,
			evict_effect
		)
		assert(
			_valid_controller_count() == 8,
			"consecutive ninth-class casts must keep working: %d"
			% _valid_controller_count()
		)
	_game._debug_validate_fire_wall_registry("test:consecutive_casts")

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
