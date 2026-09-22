extends Node2D


## R14-B1/B2/B3 Enemy hot-path projection equivalence test.
## Uses a formal EnemyActor with a counted projection Callable and the real
## combat spatial index, mirroring the proven runtime_test.gd fixture so the
## fast paths are validated against real authority, not an isolated helper.
const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")

var _index := Index.new()
var _player: PlayerCharacter
var _serial := 0
var _projection_calls := 0
var _failures := 0


class RevisionProvider:
	extends Node
	var revision := 0
	func environment_collision_revision() -> int:
		return revision


class ProjectionProvider:
	extends Node
	var calls := 0
	var shift := Vector2.ZERO
	func project(screen_position_px: Vector2) -> Vector2:
		calls += 1
		return GU.screen_delta_px_to_ground_delta_gu(screen_position_px) + shift


func _ground_to_screen(value: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(screen_position_px: Vector2) -> Vector2:
	_projection_calls += 1
	return GU.screen_delta_px_to_ground_delta_gu(screen_position_px)


func _open_context() -> Dictionary:
	return {
		"valid": true,
		"contract_id": Terrain.CONTRACT_ID,
		"runtime_map_id": 1,
		"build_sha256": "b".repeat(64),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(80, 80),
		"blocked_cells": {},
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("R14_B_FAIL: " + message)


func _ready() -> void:
	_run.call_deferred()


func _make_enemy(monster_id := 64) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(monster_id), _player, false)
	actor.global_position = _ground_to_screen(Vector2(30, 30))
	actor.set_meta("spawn_position", actor.global_position)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	actor.configure_terrain_navigation_context(_open_context())
	add_child(actor)
	actor.set_physics_process(false)
	actor.target = _player
	actor._retarget_timer = 999.0
	actor._attack_timer = 999.0
	actor._attack_hit_delay = 0.0
	actor.attack_min = 50
	actor.attack_max = 50
	_serial += 1
	actor.spatial_actor_runtime_id = _serial
	actor.combat_spatial_index = _index
	_index.register(
		_serial,
		1,
		actor.global_position,
		actor.combat_radius_gu,
		_serial,
		actor,
	)
	return actor


func _run() -> void:
	PlayerState.test_mode = true
	_player = PlayerCharacter.new()
	_player.global_position = _ground_to_screen(Vector2(26, 30))
	_player.set_meta("runtime_map_id", 1)
	_player.set_meta("zone_generation", 1)
	add_child(_player)
	_player.set_physics_process(false)
	_player.max_hp = 1000000
	_player.current_hp = _player.max_hp
	_player.current_mp = 0
	_player.shield_time = 0.0

	await _case_1_cache_hit()
	await _case_2_position_invalidation()
	await _case_3_map_generation_invalidation()
	await _case_4_projection_authority_invalidation()
	_case_5_non_self_position()
	await _case_6_fail_closed()

	if _failures == 0:
		print("R14_ENEMY_SELF_PROJECTION_CACHE_PASS equivalence fast paths (B1/B2/B3)")
		get_tree().quit(0)
	else:
		push_error("R14_ENEMY_SELF_PROJECTION_CACHE_FAIL failures=" + str(_failures))
		get_tree().quit(1)


## Case 1: repeated self projection after a spatial-index update must hit the
## exact cache and not re-invoke the projection Callable.
func _case_1_cache_hit() -> void:
	var enemy := _make_enemy()
	# Establish the spatial-index projection snapshot (one formal projection).
	enemy.set_combat_position(enemy.global_position, &"r14b_cache_setup")
	_check(enemy.spatial_index_position().is_finite(), "case1 spatial snapshot finite")
	var calls_after_setup := _projection_calls
	for i in range(8):
		var result := enemy._screen_position_px_to_ground_position_gu(
			enemy.global_position
		)
		_check(
			result.is_equal_approx(enemy.spatial_index_position()),
			"case1 self projection value equals spatial-index snapshot",
		)
	_check(
		_projection_calls == calls_after_setup,
		"case1 self projection cache hit: formal projection not re-invoked",
	)
	_check(
		enemy._last_spatial_index_ground_position_gu.is_equal_approx(
			enemy.spatial_index_position()
		),
		"case1 cached ground equals spatial-index ground",
	)
	enemy.free()


## Case 2: moving the enemy invalidates self cache; the next self projection
## performs exactly one formal projection, then subsequent calls hit again.
func _case_2_position_invalidation() -> void:
	var enemy := _make_enemy()
	enemy.set_combat_position(enemy.global_position, &"r14b_cache_setup")
	var calls_before := _projection_calls
	enemy.set_combat_position(
		_ground_to_screen(Vector2(33, 31)),
		&"r14b_position_change",
	)
	var calls_after_move := _projection_calls
	_check(
		calls_after_move == calls_before + 1,
		"case2 moved enemy re-projects once (position invalidation)",
	)
	# Same-position request after the move is cached.
	for i in range(4):
		var result := enemy._screen_position_px_to_ground_position_gu(
			enemy.global_position
		)
		_check(
			result.is_equal_approx(enemy._last_spatial_index_ground_position_gu),
			"case2 post-move self projection cached value",
		)
	_check(
		_projection_calls == calls_after_move,
		"case2 post-move repeated self projection does not re-invoke",
	)
	enemy.free()


## Case 3: map id / zone generation invalidation forces a fresh projection.
func _case_3_map_generation_invalidation() -> void:
	var enemy := _make_enemy()
	enemy.set_combat_position(enemy.global_position, &"r14b_cache_setup")
	var calls_before := _projection_calls
	# Map change at same screen position.
	enemy.configure_runtime_map_projection(
		2,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	enemy.set_combat_position(enemy.global_position, &"r14b_map_change")
	_check(
		_projection_calls == calls_before + 1,
		"case3 map change invalidates cached self projection",
	)
	var ground_after_map := enemy._screen_position_px_to_ground_position_gu(
		enemy.global_position
	)
	_check(
		ground_after_map.is_finite() and ground_after_map.is_equal_approx(
			enemy._last_spatial_index_ground_position_gu
		),
		"case3 post-map self projection cached after map invalidation",
	)
	# Zone generation change.
	calls_before = _projection_calls
	enemy.set_meta("zone_generation", 7)
	enemy.set_combat_position(enemy.global_position, &"r14b_generation_change")
	_check(
		_projection_calls == calls_before + 1,
		"case3 zone generation change invalidates cached self projection",
	)
	enemy.free()


## Case 4: projection authority (Callable) change must use the new Callable and
## never return the old cached value.
func _case_4_projection_authority_invalidation() -> void:
	var enemy := _make_enemy()
	enemy.set_combat_position(enemy.global_position, &"r14b_cache_setup")
	var old_ground := enemy._last_spatial_index_ground_position_gu
	# New authority maps to a shifted ground position.
	var provider := ProjectionProvider.new()
	provider.shift = Vector2(5, -3)
	add_child(provider)
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		Callable(provider, "project"),
	)
	enemy.set_combat_position(enemy.global_position, &"r14b_authority_change")
	_check(
		provider.calls == 1,
		"case4 new projection authority invoked once on setup",
	)
	var ground_after := enemy._screen_position_px_to_ground_position_gu(
		enemy.global_position
	)
	var expected := GU.screen_delta_px_to_ground_delta_gu(
		enemy.global_position
	) + provider.shift
	_check(
		ground_after.is_equal_approx(expected),
		"case4 new projection authority result is used, not old cache",
	)
	_check(
		not ground_after.is_equal_approx(old_ground),
		"case4 old cached ground not returned under new authority",
	)
	provider.queue_free()
	enemy.free()


## Case 5: a non-self point (e.g. target offset) must always run the formal
## projection and never resolve through the self cache.
func _case_5_non_self_position() -> void:
	var enemy := _make_enemy()
	enemy.set_combat_position(enemy.global_position, &"r14b_cache_setup")
	var calls_before := _projection_calls
	var probe := _ground_to_screen(Vector2(28, 28))
	var result := enemy._screen_position_px_to_ground_position_gu(probe)
	_check(
		_projection_calls == calls_before + 1,
		"case5 non-self point always runs formal projection",
	)
	_check(
		result.is_equal_approx(GU.screen_delta_px_to_ground_delta_gu(probe)),
		"case5 non-self point returns the exact projected value",
	)
	# The self cache must not have been rewritten by the non-self request.
	_check(
		enemy._target_ground_cache_target_screen_position_px == Vector2.INF
		or enemy._target_ground_cache_target_screen_position_px != probe,
		"case5 non-self point never written into target cache",
	)
	enemy.free()


## Case 6: fail-closed. Mapped world with an invalid/missing projection
## Callable keeps returning Vector2.INF and preserves the missing-projection
## rejection contract; the fast path must not smuggle an old valid cache into
## the broken authority.
func _case_6_fail_closed() -> void:
	var enemy := _make_enemy()
	enemy.set_combat_position(enemy.global_position, &"r14b_cache_setup")
	var old_valid := enemy._last_spatial_index_ground_position_gu
	_check(old_valid.is_finite(), "case6 setup cache finite")
	# Break the authority: mapped world with an invalid projection Callable.
	enemy.runtime_screen_to_ground_position_px = Callable()
	enemy.set_combat_position(enemy.global_position, &"r14b_authority_removed")
	var result := enemy._screen_position_px_to_ground_position_gu(
		enemy.global_position
	)
	_check(
		result == Vector2.INF,
		"case6 missing projection returns Vector2.INF (fail closed)",
	)
	_check(
		enemy.missing_projection_rejection_count > 0,
		"case6 missing-projection rejection counter recorded",
	)
	_check(
		enemy.projection_rejection_reason
			== GU.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION,
		"case6 rejection reason preserved",
	)
	_check(
		not result.is_equal_approx(old_valid),
		"case6 broken authority never returns stale valid cache",
	)
	enemy.free()
