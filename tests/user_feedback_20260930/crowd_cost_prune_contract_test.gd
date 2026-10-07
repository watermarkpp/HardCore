extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Public behavior contract for cost pruning. This test uses real EnemyActor
## queries and counts only the two production query wrappers. It does not
## reproduce choose_with_snapshot internals.
const PositionPolicy := preload("res://scripts/monster_crowd_attack_position_policy.gd")

class CostSpyEnemy extends EnemyActor:
	var point_walkable_calls := 0
	var world_between_calls := 0

	func reset_query_counts() -> void:
		point_walkable_calls = 0
		world_between_calls = 0

	func _hc_point_walkable(point: Vector2) -> bool:
		point_walkable_calls += 1
		return super._hc_point_walkable(point)

	func _hc_world_between(a: Vector2, b: Vector2) -> bool:
		world_between_calls += 1
		return super._hc_world_between(a, b)

func _configure_spawn(actor: EnemyActor, monster_id: int, position: Vector2) -> EnemyActor:
	serial += 1
	actor.setup(GameData.get_monster_by_id(monster_id), player, false)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(MAP_ID, _ground_to_screen, _screen_to_ground)
	actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	actor.configure_spatial_index(index, serial)
	actor.set_combat_position(_ground_to_screen(position), &"cost_prune_contract_spawn")
	add_child(actor)
	actor.set_physics_process(false)
	index.register(serial, MAP_ID, position, actor.combat_radius_gu, serial, actor)
	return actor

func _spawn_spy(monster_id: int, position: Vector2) -> CostSpyEnemy:
	return _configure_spawn(CostSpyEnemy.new(), monster_id, position) as CostSpyEnemy

func _spawn_regular(monster_id: int, position: Vector2) -> EnemyActor:
	return _configure_spawn(EnemyActor.new(), monster_id, position)

func _cleanup(actors: Array) -> void:
	for actor: EnemyActor in actors:
		if is_instance_valid(actor):
			index.unregister(actor.spatial_actor_runtime_id)
			actor.free()
	if is_instance_valid(player):
		player.free()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)

	var actor := _spawn_spy(89, CENTER + Vector2(4, 0))
	actor.target = player
	var actors: Array[EnemyActor] = [actor]
	var target_radius: float = float(actor._target_combat_radius_gu(player))
	var slot0 := PositionPolicy.station(actor, CENTER, target_radius, 0)
	var peers: Array = []

	# Current position is exactly slot 0 and previous slot is 0. The current
	# winner is the only candidate that needs the two real query calls.
	actor.reset_query_counts()
	var selected := PositionPolicy.choose(actor, player, CENTER, slot0, peers, 0)
	_check(selected == 0, "current slot 0 was not retained")
	_check(actor.point_walkable_calls == 1 and actor.world_between_calls == 1, "winner query counts were not exactly one each")

	# A previous opposite slot cannot beat the strictly nearer current slot.
	actor.reset_query_counts()
	selected = PositionPolicy.choose(actor, player, CENTER, slot0, peers, 2)
	_check(selected == 0, "previous opposite slot displaced the nearer current slot")

	# Equal axial distances retain previous-slot epsilon and order.
	var equal_axis_current := CENTER
	actor.reset_query_counts()
	selected = PositionPolicy.choose(actor, player, CENTER, equal_axis_current, peers, 1)
	_check(selected == 1, "equal-distance previous slot did not retain epsilon preference")

	# A live body occupying the nearest station must reject it; the next public
	# result must be a different physically available slot.
	var blocker := _spawn_regular(89, slot0)
	blocker.target = player
	actors.append(blocker)
	var live_peers: Array = [blocker]
	selected = PositionPolicy.choose(actor, player, CENTER, slot0, live_peers, 0)
	_check(selected >= 0 and selected != 0, "live occupied nearest station was selected")
	if selected >= 0:
		var selected_point := PositionPolicy.station(actor, CENTER, target_radius, selected)
		_check(PositionPolicy.available(actor, player, selected_point, live_peers), "selected replacement station was not live-available")

	# NaN cost cannot satisfy strict cost < best_cost and must not fabricate a
	# winner or invoke a fake finite station.
	selected = PositionPolicy.choose(actor, player, CENTER, Vector2(NAN, NAN), peers, -1)
	_check(selected == -1, "invalid NaN cost fabricated a crowd winner")

	_cleanup(actors)
	if not failures.is_empty():
		print("CROWD_COST_PRUNE_CONTRACT_FAIL: ", failures)
		get_tree().quit(1)
		return
	print("CROWD_COST_PRUNE_CONTRACT_PASS")
	get_tree().quit(0)
