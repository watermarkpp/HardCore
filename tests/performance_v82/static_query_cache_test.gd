extends Node2D
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const GU := preload("res://scripts/ground_unit_space.gd")
class Provider:
	extends Node2D
	var revision := 0
	var blocked := false
	var calls := 0
	func environment_collision_revision() -> int:
		return revision
	func is_environment_actor_blocked(_point: Vector2, _radius: float) -> bool:
		calls += 1
		return blocked

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var provider := Provider.new()
	add_child(provider)
	var a := EnemyActor.new()
	var b := EnemyActor.new()
	a.setup(GameData.get_monster_by_id(64), null, false)
	b.setup(GameData.get_monster_by_id(64), null, false)
	add_child(a)
	add_child(b)
	var context := _context({}, true)
	for actor in [a, b]:
		actor.set_physics_process(false)
		actor.environment_blocker = provider
		actor.configure_runtime_map_projection(1, _to_screen, _to_ground)
		actor.configure_terrain_navigation_context(context)
		actor.combat_radius_gu = 0.35
		actor.collision_radius_px = 16.0
		actor.set_meta("zone_generation", 1)
	var p := Vector2(10.5, 10.5)
	assert(a._hc_point_walkable(p) and b._hc_point_walkable(p))
	assert(provider.calls == 1, "Same exact authority and footprint share static point work")
	# Same physics frame: revision/footprint/authority changes cannot reuse old results.
	provider.blocked = true
	provider.revision += 1
	assert(not a._hc_point_walkable(p) and not b._hc_point_walkable(p))
	assert(provider.calls == 2)
	provider.blocked = false
	provider.revision += 1
	assert(a._hc_point_walkable(p))
	var calls := provider.calls
	a.collision_radius_px = 17.0
	assert(a._hc_point_walkable(p) and provider.calls == calls + 1)
	a.combat_radius_gu = 0.45
	assert(a._hc_point_walkable(p) and provider.calls == calls + 2)
	a.set_meta("zone_generation", 2)
	assert(a._hc_point_walkable(p) and provider.calls == calls + 3)
	# Distinct float64 radii must not alias after float32 vector conversion.
	a.collision_radius_px = 17.0 + 0.00000001
	assert(a._hc_point_walkable(p) and provider.calls == calls + 4)
	a.combat_radius_gu = 0.45 + 0.000000001
	assert(a._hc_point_walkable(p) and provider.calls == calls + 5)
	a.configure_terrain_navigation_context(_context({Vector2i(10, 10): true}, true))
	assert(not a._hc_point_walkable(p))
	a.configure_terrain_navigation_context(context)
	assert(a._hc_point_walkable(p))
	a.set_meta("safe_zone_context", {"valid": false, "revision": 1, "zones": []})
	assert(not a._hc_point_walkable(p), "Invalid private safe context must remain fail-closed")
	a.set_meta("safe_zone_context", {"valid": true, "revision": 2, "zones": []})
	assert(a._hc_point_walkable(p), "Same-owner safe context revision must invalidate")
	# Mutable authored contexts must bypass the cache and observe in-place edits.
	var mutable := _context({}, false)
	a.configure_terrain_navigation_context(mutable)
	assert(a._hc_point_walkable(p))
	mutable.blocked_cells[Vector2i(10, 10)] = true
	assert(not a._hc_point_walkable(p))
	# Actor bodies remain live, outside the static point cache. Its environment
	# ownership still changes immediately when the provider itself is replaced.
	var other := Provider.new()
	other.blocked = true
	add_child(other)
	b.environment_blocker = other
	assert(not b._hc_point_walkable(p))
	assert(other.calls == 1)
	b.environment_blocker = provider
	var player := PlayerCharacter.new()
	player.set_meta("runtime_map_id", 1)
	add_child(player)
	player.set_physics_process(false)
	player.current_hp = 100
	player.global_position = _to_screen(p)
	a.attack_delivery_rule = {"kind": "test_special"}
	var private_safe := {"valid": true, "revision": 9, "zones": []}
	a.set_meta("safe_zone_context", private_safe)
	assert(a._hc_target_usable(player))
	private_safe.valid = false
	assert(not a._hc_target_usable(player), "Special actors retain the original live player-safe gate")
	provider.blocked = true
	# An unchanged revision may legitimately share this tick, but never the next.
	await get_tree().physics_frame
	await get_tree().process_frame
	assert(not b._hc_point_walkable(p), "All static point results expire at the next physics tick")
	a.queue_free()
	b.queue_free()
	provider.queue_free()
	other.queue_free()
	player.queue_free()
	await get_tree().process_frame
	print("PERFORMANCE_V82_STATIC_QUERY_CACHE_PASS")
	get_tree().quit(0)

func _context(blocked: Dictionary, frozen: bool) -> Dictionary:
	if frozen:
		blocked.make_read_only()
	var value := {"valid": true, "contract_id": Terrain.CONTRACT_ID,
		"runtime_map_id": 1, "build_sha256": "f".repeat(64),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(80, 80), "blocked_cells": blocked}
	if frozen:
		value.make_read_only()
	return value

func _to_screen(p: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(p)

func _to_ground(p: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(p)
