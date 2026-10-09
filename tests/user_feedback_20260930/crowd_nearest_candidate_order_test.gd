extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Production chooser regression: local candidates are ordered by actual
## distance, while equal distances retain CrowdAttackPosition's stable order.
## The cases use the real EnemyActor chooser and live world bodies; only the
## test scene's wall is synthetic.
const Positions := preload("res://scripts/monster_crowd_attack_position_policy.gd")
const Reach := preload("res://scripts/monster_source176/source_melee_geometry.gd")
const SourceStepPlan := preload("res://scripts/monster_source176/source_step_plan.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")

class CandidateProbe extends EnemyActor:
	var blocked_point := Vector2.INF
	var point_queries := 0
	func _hc_point_walkable(point: Vector2) -> bool:
		point_queries += 1
		var real_result := super._hc_point_walkable(point)
		return false if real_result and blocked_point.is_finite() and point.is_equal_approx(blocked_point) else real_result

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	var actor := _spawn_probe(24, CENTER + Vector2(1.4, 0.0))
	actor._leave_background_deep_sleep()
	actor.set_physics_process(false)
	actor.target = player
	var first := actor._hc_crowd_position_goal(player)
	_check(first.is_finite(), "baseline chooser produced no legal local goal")
	var first_cost := actor.spatial_index_position().distance_squared_to(first)
	var feasible_cost := INF
	for slot in range(Positions.DIRECTIONS.size()):
		var point := Positions.station(actor, CENTER, actor._target_combat_radius_gu(player), slot)
		if _candidate_is_legal(actor, player, point):
			feasible_cost = minf(feasible_cost, actor.spatial_index_position().distance_squared_to(point))
	_check(is_equal_approx(first_cost, feasible_cost), "chooser did not return the nearest feasible candidate")
	actor.blocked_point = first
	await get_tree().physics_frame
	actor._hc_surround_goal = Vector2.INF
	actor._hc_surround_slot = -1
	actor._hc_surround_scope = []
	var blocked_result := actor._hc_crowd_position_goal(player)
	_check(blocked_result.is_finite(), "blocked nearest candidate did not fall through to a legal candidate")
	_check(blocked_result != first, "blocked nearest candidate was returned")
	actor.blocked_point = Vector2.INF
	await get_tree().physics_frame
	actor.set_combat_position(_ground_to_screen(CENTER), &"crowd_tie_fixture")
	actor._hc_surround_goal = Vector2.INF
	actor._hc_surround_slot = -1
	actor._hc_surround_scope = []
	var stable_a := actor._hc_crowd_position_goal(player)
	var tie_order := Positions.local_slot_order(actor.spatial_actor_runtime_id)
	var expected_slot := _expected_tie_slot(actor, tie_order)
	_check(actor._hc_surround_slot == expected_slot, "equal-distance candidates did not use original stable order")
	var born := _spawn(24, stable_a)
	born._leave_background_deep_sleep()
	born.set_physics_process(false)
	born.target = player
	actor._hc_surround_goal = Vector2.INF
	actor._hc_surround_slot = -1
	actor._hc_surround_scope = []
	var same_frame := actor._hc_crowd_position_goal(player)
	_check(same_frame.is_finite() and same_frame != stable_a, "same-frame newly registered body was not visible to chooser")
	index.unregister(born.spatial_actor_runtime_id)
	born.free()
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	player.free()
	print("CROWD_NEAREST_CANDIDATE_ORDER_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _candidate_is_legal(actor: EnemyActor, target: Node2D, point: Vector2) -> bool:
	if not actor._hc_point_walkable(point) or not actor._hc_world_between(point, CENTER):
		return false
	var first_leg := SourceStepPlan.next_leg(actor.spatial_index_position(), point, 1.0, GroundUnitSpace.EPSILON_GU)
	return first_leg.is_finite() and actor._hc_flank_destination_clear(point) and actor._hc_motion_clear(actor.spatial_index_position(), first_leg)


func _spawn_probe(mid: int, position: Vector2) -> CandidateProbe:
	serial += 1
	var actor := CandidateProbe.new()
	actor.setup(GameData.get_monster_by_id(mid), player, false)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(MAP_ID, _ground_to_screen, _screen_to_ground)
	actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	actor.configure_spatial_index(index, serial)
	actor.set_combat_position(_ground_to_screen(position), &"candidate_probe_spawn")
	actor.set_meta("spawn_position", actor.global_position)
	add_child(actor)
	actor.set_physics_process(false)
	index.register(serial, MAP_ID, position, actor.combat_radius_gu, serial, actor)
	return actor


func _expected_tie_slot(actor: EnemyActor, order: Array[int]) -> int:
	var best_slot := -1
	var best_cost := INF
	for slot: int in order:
		var point := Positions.station(actor, CENTER, actor._target_combat_radius_gu(player), slot)
		var cost := actor.spatial_index_position().distance_squared_to(point)
		if cost < best_cost:
			best_cost = cost
			best_slot = slot
	return best_slot
