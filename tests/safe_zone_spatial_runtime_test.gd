extends Node

const SpatialRules := preload("res://scripts/world_spatial_rules.gd")
const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")
const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")
const MainScene := preload("res://scenes/main.tscn")

const RUNTIME_MAP_ID := 9404
const BICH_RUNTIME_MAP_ID := 910001
const MAX_WORLD_READY_FRAMES := 1800
const TEST_ZONE_RADIUS_GU := 9.0


class TrackingEnemy extends EnemyActor:
	var safe_zone_set_positions: Array[Vector2] = []
	var safe_zone_set_reasons: Array[StringName] = []

	func set_combat_position(
		position_px: Vector2,
		reason: StringName = &"",
	) -> void:
		safe_zone_set_positions.append(position_px)
		safe_zone_set_reasons.append(reason)
		super.set_combat_position(position_px, reason)


var _game: Node
var _fixture_enemies: Array[TrackingEnemy] = []
var _failed := false
var _failure_messages: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual.set_synchronous_loading_for_tests(true)
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(true)
	RuntimeDiagnosticsScript.reset_performance_window()
	_verify_safe_zone_compilation()
	_verify_index_candidates_and_lifecycle()
	_verify_production_paths_are_indexed_and_cached()
	await _verify_game_root_runtime()
	_finish_test()


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
	_expect(bool(context.get("valid", false)), "valid formal zones must compile")
	_expect(int(context.get("map_id", -1)) == RUNTIME_MAP_ID, "compiled context map id mismatch")
	_expect(int(context.get("revision", -1)) == 7, "compiled context revision mismatch")
	_expect(int(context.get("generation", -1)) == 12, "compiled context generation mismatch")
	var zones: Array = context.get("zones", [])
	_expect(zones.size() == 2, "compiled zones must preserve authored order")
	if zones.size() == 2:
		_expect(zones[0].get("zone_id") == "safe.circle", "compiled circle id/order mismatch")
		_expect(zones[1].get("zone_id") == "safe.polygon", "compiled polygon id/order mismatch")
		_expect(zones[0].get("aabb_ground_gu") is Rect2, "compiled circle AABB missing")
		_expect(zones[1].get("polygon_ground_gu") is PackedVector2Array, "compiled polygon missing")
		_expect(SpatialRules.point_inside_safe_zone_ground_gu(Vector2(10.0, -4.0), zones[0]), "compiled circle inside parity failed")
		_expect(not SpatialRules.point_inside_safe_zone_ground_gu(Vector2(20.1, -4.0), zones[0]), "compiled circle outside parity failed")
		_expect(SpatialRules.point_inside_safe_zone_ground_gu(Vector2.ZERO, zones[1]), "compiled polygon inside parity failed")
		_expect(not SpatialRules.point_inside_safe_zone_ground_gu(Vector2(4.1, 0.0), zones[1]), "compiled polygon outside parity failed")

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
		_expect(not bool(invalid_context.get("valid", true)))
		_expect((invalid_context.get("zones", []) as Array).is_empty())
		_expect(not str(invalid_context.get("failure_reason", "")).is_empty())


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
	_expect(output.size() == 82, "safe-zone AABB must exclude remote actors")
	for actor_index: int in range(mini(output.size(), 82)):
		_expect(output[actor_index] == enemies[actor_index], "safe-zone candidate order mismatch")
	var wrong_map: Array = []
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID + 1,
		Rect2(Vector2(-9.0, -5.0), Vector2(18.0, 10.0)),
		wrong_map,
	)
	_expect(wrong_map.is_empty(), "safe-zone candidate query must be map scoped")

	enemies[0]._death_pending = true
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		Rect2(Vector2(-9.0, -5.0), Vector2(18.0, 10.0)),
		output,
	)
	_expect(output.size() == 81 and not output.has(enemies[0]), "death-pending candidate was not excluded")
	index.update_actor(2, Vector2(110.0, 110.0))
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		Rect2(Vector2(-9.0, -5.0), Vector2(18.0, 10.0)),
		output,
	)
	_expect(output.size() == 80 and not output.has(enemies[0]), "cross-bucket moved actor remained in query")
	index.clear_map(RUNTIME_MAP_ID)
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		Rect2(Vector2(-1000.0, -1000.0), Vector2(2000.0, 2000.0)),
		output,
	)
	_expect(output.is_empty(), "map clear must remove safe-zone candidates")
	for actor_index: int in range(96):
		index.unregister(actor_index + 1)
		if is_instance_valid(enemies[actor_index]):
			enemies[actor_index].queue_free()


func _verify_game_root_runtime() -> void:
	_game = MainScene.instantiate()
	add_child(_game)
	if not await _wait_for_world_ready():
		_expect(false, "GameRoot production bootstrap did not reach READY")
		return
	if int(_game.current_map_id) != BICH_RUNTIME_MAP_ID:
		_game.travel_to_map(4)
		if not await _wait_for_world_ready():
			_expect(false, "GameRoot could not arrive at formal Bich map")
			return
	_expect(int(_game.current_map_id) == BICH_RUNTIME_MAP_ID, "fixture did not reach formal Bich map")
	# Freeze the world scheduler while the fixture drives the actual private
	# enforcement entry. This leaves the player valid and prevents teardown from
	# racing an empty player through GameRoot._process.
	_game.set_process(false)
	_game.set_physics_process(false)
	await _clear_existing_game_enemies()
	var raw_zones := _runtime_overlap_zones()
	_game._compile_active_safe_zones(raw_zones)
	_game._set_player_world_position(
		_game._canonical_ground_gu_to_screen_px(Vector2(30.0, 30.0))
	)
	_game._refresh_player_safe_zone_cache(true)
	_fixture_enemies = await _create_formal_enemy_fixture(raw_zones)
	_expect(_fixture_enemies.size() == 96, "real GameRoot fixture must create 96 enemies")
	if _fixture_enemies.size() != 96:
		return
	_verify_padding_semantics()
	_verify_real_enforcement_and_order()
	_verify_player_cache_runtime(raw_zones)
	_verify_enemy_live_context()
	_verify_context_invalidation(raw_zones)
	await _clear_fixture_index_and_enemies()


func _wait_for_world_ready() -> bool:
	for _frame: int in range(MAX_WORLD_READY_FRAMES):
		if (
			not bool(_game._world_bootstrap_in_progress)
			and not bool(_game._map_transition_in_progress)
			and _game._world_bootstrap_coordinator.stage
			== WorldBootstrapCoordinator.Stage.READY
		):
			return true
		if _game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.FAILED:
			return false
		await get_tree().process_frame
	return false


func _clear_existing_game_enemies() -> void:
	var index: Variant = _game.get("_combat_spatial_index")
	if index != null and is_instance_valid(index):
		index.clear_map(int(_game.current_map_id))
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and is_instance_valid(value):
			(value as EnemyActor).set_physics_process(false)
			(value as EnemyActor).queue_free()
	await get_tree().process_frame
	_game._active_enemy_cache.clear()
	_game._active_boss_cache.clear()


func _runtime_overlap_zones() -> Array:
	return [
		{
			"area_id": "r3_4.primary",
			"shape": "circle",
			"center_ground_gu": Vector2.ZERO,
			"radius_gu": TEST_ZONE_RADIUS_GU,
			"blocks_monster_entry": true,
			"return_anchor": true,
			"policy_override": "r3_4_primary",
		},
		{
			"area_id": "r3_4.overlap",
			"shape": "circle",
			"center_ground_gu": Vector2.ZERO,
			"radius_gu": TEST_ZONE_RADIUS_GU,
			"blocks_monster_entry": true,
			"return_anchor": true,
			"policy_override": "r3_4_overlap",
		},
	]


func _create_formal_enemy_fixture(raw_zones: Array) -> Array[TrackingEnemy]:
	var result: Array[TrackingEnemy] = []
	var index: RuntimeCombatSpatialIndex = _game.get("_combat_spatial_index")
	var monster_data := GameData.get_monster_by_id(18)
	_expect(not monster_data.is_empty(), "fixture canonical monster 18 missing")
	for actor_index: int in range(96):
		var ground_position := _fixture_ground_position(actor_index)
		var enemy := TrackingEnemy.new()
		enemy.name = "R3_4_SafeZoneEnemy_%02d" % actor_index
		enemy.setup(monster_data, _game.player, false)
		enemy.configure_runtime_map_projection(
			BICH_RUNTIME_MAP_ID,
			Callable(_game, "_canonical_ground_gu_to_screen_px"),
			Callable(_game, "_canonical_screen_px_to_ground_gu"),
		)
		enemy.configure_spatial_index(index, 10000 + actor_index)
		enemy.set_meta("spawn_serial", actor_index + 1)
		enemy.set_meta("zone_generation", int(_game.get("_zone_generation")))
		enemy.set_combat_position(
			_game._canonical_ground_gu_to_screen_px(ground_position),
			&"r3_4_fixture_spawn",
		)
		_game.add_child(enemy)
		# EnemyActor._ready creates the real MonsterVisual and enters the normal
		# enemies/zone_content groups. Disable only its scheduler for deterministic
		# fixture control; registration remains the production index transaction.
		enemy.set_physics_process(false)
		enemy.set_process(false)
		# `_ready()` performs the normal spawn-overlap guard before production
		# registration. Re-apply the authored test coordinate through the same
		# sanctioned setter after that lifecycle hook so this fixture's intended
		# inside/outside partition is exact and auditable.
		enemy.set_combat_position(
			_game._canonical_ground_gu_to_screen_px(ground_position),
			&"r3_4_fixture_position",
		)
		enemy.set_meta("safe_zone_context", _game.get("_safe_zone_context"))
		enemy.set_meta("safe_zones", _game.get("_active_safe_zones"))
		_game._active_enemy_cache[enemy.get_instance_id()] = enemy
		index.register(
			10000 + actor_index,
			BICH_RUNTIME_MAP_ID,
			ground_position,
			enemy.combat_radius_gu,
			actor_index + 1,
			enemy,
			Callable(enemy, "spatial_index_position"),
		)
		result.append(enemy)
		if actor_index % 16 == 15:
			await get_tree().process_frame
	return result


func _fixture_ground_position(actor_index: int) -> Vector2:
	if actor_index == 0:
		# Outside the circle but inside its AABB and the radius + footprint +
		# padding band. It must not be treated as an illegal entry.
		return Vector2(TEST_ZONE_RADIUS_GU + 0.01, 0.0)
	if actor_index == 1:
		return Vector2.ZERO
	if actor_index >= 82:
		# Keep the final fourteen actors formally registered on this map but well
		# outside the compiled zone AABB.  This is the runtime counterpart of the
		# old synthetic fixture's remote population and proves broadphase
		# exclusion without a group/cache scan.
		return Vector2(100.0 + float(actor_index - 82) * 4.0, 100.0)
	var angle := float(actor_index - 2) * TAU / 80.0
	var distance := 2.0 + float((actor_index - 2) % 6) * 0.75
	return Vector2.from_angle(angle) * distance


func _verify_padding_semantics() -> void:
	var outside := _fixture_enemies[0]
	var outside_before := outside.spatial_index_position()
	_expect(
		outside_before.length() > TEST_ZONE_RADIUS_GU
		and outside_before.length() < TEST_ZONE_RADIUS_GU + outside.combat_radius_gu + 0.05,
		"padding fixture must be outside center radius but inside the clearance band",
	)
	RuntimeDiagnosticsScript.reset_performance_window()
	var inside := _fixture_enemies[1]
	var inside_before := inside.spatial_index_position()
	var inside_distance := inside_before.distance_to(Vector2.ZERO)
	_expect(inside_distance <= TEST_ZONE_RADIUS_GU, "padding probe center was not inside zone")
	_game._enforce_bich_safe_zone()
	_expect(
		outside.spatial_index_position().is_equal_approx(outside_before),
		"an outside center must not be ejected merely because padding reaches it",
	)
	var expected_distance := TEST_ZONE_RADIUS_GU + inside.combat_radius_gu + 0.05
	_expect(
		is_equal_approx(inside.spatial_index_position().length(), expected_distance),
		"an inside center must project to radius + actor footprint + padding",
	)
	# Reset the padding-only probe before the full overlap/order pass.  The
	# production enforcement correctly moves every inside candidate once; the
	# next pass must start from the same pre-enforcement state as every local
	# actor, while preserving the outside-boundary assertion above.
	for actor_index: int in range(1, 82):
		var local_enemy := _fixture_enemies[actor_index]
		local_enemy.set_combat_position(
			_game._canonical_ground_gu_to_screen_px(
				_fixture_ground_position(actor_index),
			),
			&"r3_4_fixture_reset",
		)
		local_enemy.safe_zone_set_positions.clear()
		local_enemy.safe_zone_set_reasons.clear()


func _verify_real_enforcement_and_order() -> void:
	var index: RuntimeCombatSpatialIndex = _game.get("_combat_spatial_index")
	var candidates: Array = []
	index.query_enemy_nodes_aabb_into(
		BICH_RUNTIME_MAP_ID,
		Rect2(
			Vector2(-TEST_ZONE_RADIUS_GU, -TEST_ZONE_RADIUS_GU),
			Vector2.ONE * TEST_ZONE_RADIUS_GU * 2.0,
		),
		candidates,
	)
	_expect(candidates.size() == 82, "real zone AABB must return 82 local actors")
	for index_value: int in range(mini(82, candidates.size())):
		_expect(candidates[index_value] == _fixture_enemies[index_value], "real safe-zone candidate order mismatch")
	var before_bucket_changes := index.index_bucket_change_count
	var before_registered := index.registered_actor_count()
	for enemy: TrackingEnemy in _fixture_enemies:
		enemy.safe_zone_set_positions.clear()
		enemy.safe_zone_set_reasons.clear()
	RuntimeDiagnosticsScript.reset_performance_window()
	_game._enforce_bich_safe_zone()
	var metrics := RuntimeDiagnosticsScript.performance_counters()
	_expect(
		int(metrics.get("safe_zone_queries", 0)) == 82,
		"overlapping zones must enforce each candidate once",
	)
	_expect(int(metrics.get("safe_zone_global_actor_scans", 0)) == 0, "safe-zone path performed a global actor scan")
	_expect(index.registered_actor_count() == before_registered, "safe-zone enforcement changed registration count")
	_expect(index.index_bucket_change_count >= before_bucket_changes, "safe-zone correction did not update index bucket")
	var last_serial := -1
	var moved_count := 0
	for enemy: TrackingEnemy in _fixture_enemies:
		for event_index: int in range(enemy.safe_zone_set_positions.size()):
			if enemy.safe_zone_set_reasons[event_index] != &"safe_zone_enforcement":
				continue
			var serial := int(enemy.get_meta("spawn_serial", -1))
			_expect(serial > last_serial, "safe-zone enforcement order must follow stable spawn order")
			last_serial = serial
			moved_count += 1
	_expect(moved_count == 81, "only the 81 inside-center actors should be corrected")
	# A forced correction must be visible to the next index query in the same
	# frame, proving set_combat_position and the broadphase share one transaction.
	var endpoint_query: Array = []
	index.query_enemy_nodes_aabb_into(
		BICH_RUNTIME_MAP_ID,
		Rect2(_fixture_enemies[1].spatial_index_position() - Vector2.ONE * 0.01, Vector2.ONE * 0.02),
		endpoint_query,
	)
	_expect(endpoint_query.has(_fixture_enemies[1]), "corrected actor was not reindexed immediately")
	# Cross-bucket movement is also an immediate transaction, not a deferred
	# maintenance pass.
	var moved_enemy := _fixture_enemies[2]
	var bucket_before := index.index_bucket_change_count
	moved_enemy.set_combat_position(
		_game._canonical_ground_gu_to_screen_px(Vector2(24.0, 0.0)),
		&"r3_4_cross_bucket",
	)
	_expect(index.index_bucket_change_count > bucket_before)
	index.query_enemy_nodes_aabb_into(
		BICH_RUNTIME_MAP_ID,
		Rect2(Vector2(-TEST_ZONE_RADIUS_GU, -TEST_ZONE_RADIUS_GU), Vector2.ONE * TEST_ZONE_RADIUS_GU * 2.0),
		candidates,
	)
	_expect(not candidates.has(moved_enemy), "cross-bucket actor remained in zone candidates")


func _count_safe_zone_moves() -> int:
	var result := 0
	for enemy: TrackingEnemy in _fixture_enemies:
		for event_index: int in range(enemy.safe_zone_set_reasons.size()):
			if enemy.safe_zone_set_reasons[event_index] == &"safe_zone_enforcement":
				result += 1
	return result


func _verify_player_cache_runtime(raw_zones: Array) -> void:
	var outside_ground := Vector2(30.0, 30.0)
	var inside_ground := Vector2.ZERO
	_game._set_player_world_position(_game._canonical_ground_gu_to_screen_px(outside_ground))
	var cache: Dictionary = _game.get("_player_safe_zone_cache")
	_expect(bool(cache.get("valid", false)), "initial player safe-zone cache invalid")
	_expect(not _game._player_inside_active_safe_zone(), "outside player unexpectedly inside safe-zone")
	_game.player.global_position = _game._canonical_ground_gu_to_screen_px(inside_ground)
	_game.player.movement_performed.emit(_game.player.global_position, Vector2.DOWN)
	cache = _game.get("_player_safe_zone_cache")
	_expect(bool(cache.get("valid", false)), "movement signal did not refresh player cache")
	_expect(bool(cache.get("inside", false)), "movement cache missed same-frame safe-zone entry")
	_expect((cache.get("ground_position_gu") as Vector2).is_equal_approx(inside_ground), "movement cache ground position mismatch")
	_game._set_player_world_position(_game._canonical_ground_gu_to_screen_px(outside_ground))
	_expect(not _game._player_inside_active_safe_zone(), "teleport setter left stale inside cache")
	# The same setter is used by route arrival, random teleport, boundary repair,
	# and death revival; exercise those production-equivalent write boundaries.
	_game._set_player_world_position(_game._canonical_ground_gu_to_screen_px(inside_ground))
	_expect(_game._player_inside_active_safe_zone(), "revive/arrival setter missed safe-zone entry")
	var context_before: Dictionary = _game.safe_zone_runtime_context()
	_game._begin_safe_zone_context(BICH_RUNTIME_MAP_ID)
	_expect(not bool((_game.get("_player_safe_zone_cache") as Dictionary).get("valid", false)), "map context change left player cache valid")
	_game._compile_active_safe_zones(raw_zones)
	var context_after: Dictionary = _game.safe_zone_runtime_context()
	_expect(int(context_after.get("revision", -1)) > int(context_before.get("revision", -1)), "safe-zone revision did not advance")
	_expect(_game._player_inside_active_safe_zone(), "cache did not repopulate after revision change")


func _verify_enemy_live_context() -> void:
	var enemy := _fixture_enemies[1]
	enemy.set_meta("safe_zone_context", _game.get("_safe_zone_context"))
	enemy.set_combat_position(
		_game._canonical_ground_gu_to_screen_px(Vector2.ZERO),
		&"r3_4_live_context_inside",
	)
	_game._player_safe_zone_cache["inside"] = false
	_expect(
		enemy._point_inside_safe_zone(enemy.global_position),
		"Enemy live safe-zone check must read shared compiled context, not player cache",
	)
	enemy.set_combat_position(
		_game._canonical_ground_gu_to_screen_px(Vector2(30.0, 30.0)),
		&"r3_4_live_context_outside",
	)
	_expect(not enemy._point_inside_safe_zone(enemy.global_position), "Enemy live context outside parity failed")


func _verify_context_invalidation(raw_zones: Array) -> void:
	var old_context: Dictionary = _game.safe_zone_runtime_context()
	var old_generation := int(old_context.get("generation", -1))
	_game.current_map_id = BICH_RUNTIME_MAP_ID + 1
	_game._begin_safe_zone_context(BICH_RUNTIME_MAP_ID + 1)
	var map_context: Dictionary = _game.safe_zone_runtime_context()
	_expect(int(map_context.get("map_id", -1)) == BICH_RUNTIME_MAP_ID + 1, "map invalidation context map id mismatch")
	_expect(not bool((_game.get("_player_safe_zone_cache") as Dictionary).get("valid", false)), "map invalidation left player cache valid")
	_game.current_map_id = BICH_RUNTIME_MAP_ID
	_game._zone_generation += 1
	_game._begin_safe_zone_context(BICH_RUNTIME_MAP_ID)
	_game._compile_active_safe_zones(raw_zones)
	var generation_context: Dictionary = _game.safe_zone_runtime_context()
	_expect(int(generation_context.get("generation", -1)) > old_generation, "zone generation did not advance")
	_expect(int(generation_context.get("revision", -1)) > int(old_context.get("revision", -1)), "generation revision did not advance")
	_expect(not bool((_game.get("_player_safe_zone_cache") as Dictionary).get("valid", false)), "generation invalidation left player cache valid")
	# Reattach the current immutable context to the actor before live checks or
	# cleanup; this mirrors the production spawn metadata boundary.
	for enemy: TrackingEnemy in _fixture_enemies:
		enemy.set_meta("safe_zone_context", _game.get("_safe_zone_context"))
		enemy.set_meta("safe_zones", _game.get("_active_safe_zones"))


func _clear_fixture_index_and_enemies() -> void:
	var index: RuntimeCombatSpatialIndex = _game.get("_combat_spatial_index")
	index.clear_map(BICH_RUNTIME_MAP_ID)
	_expect(index.registered_actor_count() == 0, "map clear must remove all real fixture actors")
	for enemy: TrackingEnemy in _fixture_enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)
			enemy.queue_free()
	_fixture_enemies.clear()
	await get_tree().process_frame
	_game.queue_free()
	await get_tree().process_frame


func _verify_production_paths_are_indexed_and_cached() -> void:
	var game_source := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	var enforcement_start := game_source.find("func _enforce_bich_safe_zone")
	var enforcement_end := game_source.find("\nfunc ", enforcement_start + 1)
	_expect(enforcement_start >= 0 and enforcement_end > enforcement_start)
	var enforcement_body := game_source.substr(
		enforcement_start,
		enforcement_end - enforcement_start,
	)
	_expect("query_enemy_nodes_aabb_into" in enforcement_body)
	_expect("_active_enemy_cache.values()" not in enforcement_body)
	_expect('get_nodes_in_group("enemies")' not in enforcement_body)
	_expect("set_combat_position" in game_source)

	var enemy_source := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var redraw_wrapper_start := enemy_source.find("func _request_actor_redraw_if_dynamic()")
	var redraw_wrapper_end := enemy_source.find("\nfunc ", redraw_wrapper_start + 1)
	_expect(redraw_wrapper_start >= 0 and redraw_wrapper_end > redraw_wrapper_start)
	_expect(
		"_request_actor_redraw_if_dynamic_internal()" in enemy_source.substr(
			redraw_wrapper_start, redraw_wrapper_end - redraw_wrapper_start
		),
		"timed redraw wrapper must delegate to the production gate"
	)
	var redraw_start := enemy_source.find("func _request_actor_redraw_if_dynamic_internal()")
	var redraw_end := enemy_source.find("\nfunc ", redraw_start + 1)
	_expect(redraw_start >= 0 and redraw_end > redraw_start)
	var redraw_body := enemy_source.substr(redraw_start, redraw_end - redraw_start)
	_expect("uses_final_art" in redraw_body)
	_expect("should_draw_synthetic_ground_shadow" in redraw_body)
	_expect("_request_actor_redraw()" in redraw_body)
	var physics_wrapper_start := enemy_source.find("func _physics_process(delta: float)")
	var physics_wrapper_end := enemy_source.find("\nfunc ", physics_wrapper_start + 1)
	_expect(physics_wrapper_start >= 0 and physics_wrapper_end > physics_wrapper_start)
	_expect(
		"_physics_process_internal(delta)" in enemy_source.substr(
			physics_wrapper_start, physics_wrapper_end - physics_wrapper_start
		),
		"timed physics wrapper must delegate to the production body"
	)
	var physics_start := enemy_source.find("func _physics_process_internal(delta: float)")
	var physics_end := enemy_source.find("\nfunc ", physics_start + 1)
	var physics_body := enemy_source.substr(physics_start, physics_end - physics_start)
	_expect("_request_actor_redraw_if_dynamic()" in physics_body)
	_expect("_request_actor_redraw()" not in physics_body)


func _expect(condition: bool, message := "assertion failed") -> bool:
	if condition:
		return true
	_failed = true
	_failure_messages.append(message)
	return false


func _finish_test() -> void:
	if _failed:
		push_error(
			"SAFE_ZONE_SPATIAL_RUNTIME_FAIL: "
			+ "; ".join(_failure_messages)
		)
		RuntimeDiagnosticsScript.set_device_lab_performance_enabled(false)
		get_tree().quit(1)
		return
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(false)
	print("SAFE_ZONE_SPATIAL_RUNTIME_PASS")
	get_tree().quit(0)
