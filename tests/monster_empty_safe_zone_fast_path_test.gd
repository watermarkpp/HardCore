extends Node

const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const GU := preload("res://scripts/ground_unit_space.gd")

class ProbeEnemy extends EnemyActor:
	var scoped_queries := 0
	var melee_policy_queries := 0
	func _hc_standard_melee() -> bool:
		melee_policy_queries += 1
		return super._hc_standard_melee()
	func _hc_static_query_scope(include_owner: bool) -> Array:
		scoped_queries += 1
		return super._hc_static_query_scope(include_owner)

class TestEnvironment extends Node2D:
	var blocked := false
	func is_environment_actor_blocked(_point: Vector2, _radius: float) -> bool:
		return blocked

func _ready() -> void:
	var enemy := ProbeEnemy.new()
	enemy.setup(GameData.get_monster_by_id(120), null, false)
	var context := {"valid": true, "zones": [], "revision": 1}
	enemy.set_meta("safe_zone_context", context)
	for i in range(100):
		assert(not enemy._point_inside_safe_zone(Vector2(i, i)))
	assert(enemy.scoped_queries == 0, "empty authoritative zones must not build per-point cache scopes")
	# Same-tick edits remain visible; an invalid context must fail closed.
	context.valid = false
	assert(enemy._point_inside_safe_zone(Vector2.ZERO))
	context.valid = true
	context.zones.append({"shape": "circle", "center_ground_gu": Vector2.ZERO, "radius_gu": 4.0})
	assert(enemy._point_inside_safe_zone(Vector2.ZERO))
	assert(not enemy._point_inside_safe_zone(Vector2(6400, 3200)))
	context.zones.clear()
	assert(not enemy._point_inside_safe_zone(Vector2.ZERO))
	enemy.remove_meta("safe_zone_context")
	enemy.set_meta("safe_zones", [])
	assert(not enemy._point_inside_safe_zone(Vector2.ZERO), "uncompiled scenes retain legacy safe-zone behavior without engine errors")
	enemy.free()
	_test_hc_entry_paths()
	print("MONSTER_EMPTY_SAFE_ZONE_FAST_PATH_PASS")
	get_tree().quit()


func _test_hc_entry_paths() -> void:
	var enemy := ProbeEnemy.new()
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.setup(GameData.get_monster_by_id(64), null, false)
	add_child(enemy)
	assert(enemy._hc_standard_melee())
	var target := Node2D.new()
	target.set_meta("runtime_map_id", 1)
	add_child(target)
	var environment := TestEnvironment.new()
	add_child(environment)
	enemy.environment_blocker = environment
	enemy.configure_runtime_map_projection(1, _to_screen, _to_ground)
	enemy.configure_terrain_navigation_context({"valid": true, "contract_id": Terrain.CONTRACT_ID,
		"runtime_map_id": 1, "build_sha256": "f".repeat(64),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(80, 80), "blocked_cells": {}})
	var point := Vector2(10.5, 10.5)
	target.position = _to_screen(point)
	var context := {"valid": true, "zones": [], "revision": 1}
	enemy.set_meta("safe_zone_context", context)
	for index in range(100):
		assert(enemy._hc_target_usable(target))
	assert(enemy.scoped_queries == 0, "HC target checks must use the authoritative empty-zone fast path")
	for index in range(100):
		assert(enemy._hc_point_walkable_uncached(point))
	assert(enemy.scoped_queries == 0, "HC movement candidates must use the same empty-zone fast path")
	# The shortcut only resolves safe-zone membership, never world blocking.
	environment.blocked = true
	assert(not enemy._hc_point_walkable_uncached(point))
	environment.blocked = false
	context.valid = false
	assert(not enemy._hc_target_usable(target))
	assert(not enemy._hc_point_walkable_uncached(point))
	context.valid = true
	context.revision += 1
	context.zones.append({"shape": "circle", "center_ground_gu": point, "radius_gu": 4.0})
	assert(not enemy._hc_target_usable(target))
	assert(not enemy._hc_point_walkable_uncached(point))
	context.zones.clear()
	context.revision += 1
	assert(enemy._hc_target_usable(target))
	assert(enemy._hc_point_walkable_uncached(point))
	# A known HC caller should reuse its selected cache lane. The generic
	# entry must not ask for the same melee policy a second time for each
	# nontrivial/legacy safety query (the common original M30 fixture path).
	enemy.remove_meta("safe_zone_context")
	enemy.set_meta("safe_zones", [])
	enemy.melee_policy_queries = 0
	for index in range(100):
		assert(enemy._hc_target_usable(target))
	assert(enemy.melee_policy_queries == 100,
		"HC target safety repeats lane selection: %d policy calls for 100 targets" % enemy.melee_policy_queries)
	enemy.free()
	target.free()
	environment.free()


func _to_screen(point: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(point)


func _to_ground(point: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(point)
