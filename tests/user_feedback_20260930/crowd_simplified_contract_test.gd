extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Public API regression for the user-approved simplified crowd contract.
## It deliberately does not inspect snapshot internals or require new helpers.
const PositionPolicy := preload("res://scripts/monster_crowd_attack_position_policy.gd")

func _spawn_probe(mid: int, position: Vector2) -> EnemyActor:
	serial += 1
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(mid), player, false)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(MAP_ID, _ground_to_screen, _screen_to_ground)
	actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	actor.configure_spatial_index(index, serial)
	actor.set_combat_position(_ground_to_screen(position), &"crowd_simplified_contract")
	add_child(actor)
	actor.set_physics_process(false)
	index.register(serial, MAP_ID, position, actor.combat_radius_gu, serial, actor)
	return actor

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)

	var actor := _spawn_probe(89, CENTER + Vector2(4, 0))
	var far_owner := _spawn_probe(89, CENTER + Vector2(8, 8))
	var peers: Array = [actor, far_owner]
	actor.target = player
	far_owner.target = player
	far_owner._hc_surround_scope = [MAP_ID, 1, far_owner._hc_life(far_owner), player.get_instance_id(), far_owner._hc_life(player)]
	far_owner._hc_surround_anchor = CENTER
	far_owner._hc_surround_slot = 0
	far_owner._hc_surround_goal = PositionPolicy.station(far_owner, CENTER, actor._target_combat_radius_gu(player), 0)
	var free_point := PositionPolicy.station(actor, CENTER, actor._target_combat_radius_gu(player), 0)
	_check(PositionPolicy.available(actor, player, free_point, peers), "far old station claim denied a physically free point")

	far_owner.set_combat_position(_ground_to_screen(free_point), &"crowd_contract_cover")
	_check(not PositionPolicy.available(actor, player, free_point, peers), "live body overlap was not rejected")

	far_owner.set_combat_position(_ground_to_screen(CENTER + Vector2(8, 8)), &"crowd_contract_corner")
	far_owner._hc_surround_slot = 0
	var corner := PositionPolicy.station(actor, CENTER, actor._target_combat_radius_gu(player), 4)
	_check(PositionPolicy.goal(actor, player, CENTER, 4, peers) == corner, "corner goal still contains retired axis wait extension")

	var fillers: Array[EnemyActor] = []
	for slot: int in PositionPolicy.DIRECTIONS.size():
		var filler := _spawn_probe(89, PositionPolicy.station(actor, CENTER, actor._target_combat_radius_gu(player), slot))
		filler.target = player
		fillers.append(filler)
	var no_slot := PositionPolicy.choose(actor, player, CENTER, CENTER + Vector2(4, 0), peers + fillers, -1)
	_check(no_slot == -1, "fully occupied ring did not release to ordinary pursuit")
	actor._hc_surround_goal = free_point
	actor._hc_surround_slot = 0
	actor._hc_surround_anchor = CENTER
	actor._hc_surround_scope = [MAP_ID, 1, actor._hc_life(actor), player.get_instance_id(), actor._hc_life(player)]
	actor._hc_crowd_position_goal(player)
	_check(not actor._hc_surround_goal.is_finite(), "no candidate retained a stale actor crowd goal")

	for item in fillers:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
	for item in [actor, far_owner]:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
	player.free()
	if not failures.is_empty():
		print("CROWD_SIMPLIFIED_CONTRACT_FAIL: " + str(failures))
		get_tree().quit(1)
		return
	print("CROWD_SIMPLIFIED_CONTRACT_PASS")
	get_tree().quit(0)
