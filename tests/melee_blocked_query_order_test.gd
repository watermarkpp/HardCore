extends Node
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")

class Probe extends EnemyActor:
	var body_clear := false
	var terrain_clear := true
	var motion_calls := 0
	var terrain_calls := 0
	var endpoint_calls := 0
	func _hc_sync_navigation() -> void: pass
	func _hc_refresh_observation() -> void: pass
	func _hc_world_between(_a: Vector2, _b: Vector2) -> bool: return true
	func _hc_preferred(_hit_target: Node2D) -> float: return 1.5
	func _hc_motion_clear(_a: Vector2, _b: Vector2) -> bool:
		motion_calls += 1
		return body_clear
	func _hc_polygon_neighbor_clear(_a: Vector2, _b: Vector2, _from: Vector2i, _to: Vector2i) -> bool:
		terrain_calls += 1
		return terrain_clear
	func _hc_point_walkable(_p: Vector2) -> bool:
		endpoint_calls += 1
		return terrain_clear
	func _hc_frontline_at(_a: Vector2, _b: Vector2, _hit_target: Node2D) -> int: return 1

func _ready() -> void:
	var enemy := Probe.new()
	enemy.runtime_map_id = 1
	enemy._terrain_navigation_context = {"valid": true, "contract_id": Terrain.CONTRACT_ID,
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"runtime_map_id": 1, "design_size": Vector2i(80,80), "blocked_cells": {}, "build_sha256": "fixture".sha256_text()}
	enemy._hc_known_ground = Vector2(25.5,20.5)
	enemy._hc_observed = true
	# This is the EXISTING side retry window; it must never delay a newly clear
	# direct route. No cached live-body result is permitted between calls.
	enemy._hc_next_side_retry_ms = Time.get_ticks_msec() + 10000
	var a := Vector2(20.5,20.5)
	for repeat in range(60):
		assert(enemy._hc_neighbor(a, null, Vector2i.RIGHT) == Vector2i.ZERO)
	assert(enemy.motion_calls == 60)
	assert(enemy.terrain_calls == 0 and enemy.endpoint_calls == 0,
		"body-blocked retries must short-circuit unused static geometry")
	enemy.body_clear = true
	assert(enemy._hc_neighbor(a, null, Vector2i.RIGHT) == Vector2i.RIGHT,
		"moving/dead/unregistered blocker must open the path immediately")
	assert(enemy.terrain_calls == 1 and enemy.endpoint_calls == 1)
	assert(enemy._hc_step_override == Vector2(21.5,20.5))
	enemy.terrain_clear = false
	assert(enemy._hc_neighbor(a, null, Vector2i.RIGHT) == Vector2i.ZERO,
		"a clear body lane must never bypass static collision")
	assert(enemy.terrain_calls == 2 and enemy.endpoint_calls == 1)
	enemy.free()
	print("MELEE_BLOCKED_QUERY_ORDER_PASS")
	get_tree().quit(0)
