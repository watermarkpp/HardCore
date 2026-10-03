extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"
const Neighbor := preload("res://scripts/monster_neighbor_step_policy.gd")

class CountedActor extends EnemyActor:
    var batches := 0
    var lanes := 0
    var direct_lanes := 0
    func _hc_prepare_flank_batch(current: Vector2, anchor: Vector2, cell: Vector2i) -> bool:
        batches += 1
        return super._hc_prepare_flank_batch(current,anchor,cell)
    func _hc_frontline_candidates(a: Vector2,b: Vector2,hit_target: Node2D,candidates: Array) -> int:
        lanes += 1
        return super._hc_frontline_candidates(a,b,hit_target,candidates)
    func _hc_frontline_at(a: Vector2,b: Vector2,hit_target: Node2D) -> int:
        direct_lanes += 1
        return super._hc_frontline_at(a,b,hit_target)

func spawn(position: Vector2) -> CountedActor:
    serial += 1
    var actor := CountedActor.new()
    actor.setup(GameData.get_monster_by_id(89),player,false)
    actor.set_meta("safe_zones",[])
    actor.set_meta("zone_generation",1)
    actor.configure_runtime_map_projection(MAP_ID,_ground_to_screen,_screen_to_ground)
    actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
    actor.configure_spatial_index(index,serial)
    actor.set_combat_position(_ground_to_screen(position),&"layered_approach_fixture")
    add_child(actor)
    actor._leave_background_deep_sleep()
    actor.set_physics_process(false)
    actor.target = player
    actor._hc_owned_movement_call = true
    index.register(serial,MAP_ID,position,actor.combat_radius_gu,serial,actor)
    return actor

func _run() -> void:
    PlayerState.test_mode = true
    PlayerState.reset_progress(false)
    player = PlayerCharacter.new()
    player.set_meta("runtime_map_id",MAP_ID)
    player.set_meta("zone_generation",1)
    player.global_position = _ground_to_screen(CENTER)
    add_child(player)
    player.set_physics_process(false)
    var far := spawn(CENTER+Vector2(6.35,0.25))
    var blocker := spawn(CENTER+Vector2(5.35,0.25))
    var origin := far.spatial_index_position()
    var selected := far._hc_neighbor(origin,player,Neighbor.neighbor_for_desired_ground_direction(CENTER-origin))
    var held := far._hc_flank_waypoint
    _check(selected != Vector2i.ZERO and held.is_finite(),"blocked far approach selects a complete lawful local direction")
    _check(far._hc_motion_clear(origin,far._hc_step_override),"far selected prefix remains live-body clear")
    _check(far._hc_flank_destination_clear(held),"far retained endpoint avoids live bodies")
    _check(held == Vector2(Neighbor.temporary_cell(held))+Vector2(0.5,0.5),"far detour reuses a bounded neighboring cell centre rather than a private fractional destination")
    _check(far.batches == 0 and far.lanes == 0 and far.direct_lanes == 0,"far approach does not rank all attack lanes or build the sixteen-envelope near batch")
    var counts := {"batches":far.batches,"lanes":far.lanes,"direct_lanes":far.direct_lanes}
    player.global_position = _ground_to_screen(CENTER+Vector2(0.25,0.0))
    await get_tree().create_timer(0.3).timeout
    var wall_deadline := Time.get_ticks_msec()+2000
    while Time.get_ticks_msec() <= far._hc_next_observation_ms and Time.get_ticks_msec()<wall_deadline:
        await get_tree().physics_frame
    far._hc_neighbor(origin,player,Neighbor.neighbor_for_desired_ground_direction(CENTER+Vector2(0.25,0)-origin))
    _check(far._hc_known_ground.distance_to(CENTER+Vector2(0.25,0.0))<=GU.EPSILON_GU,"retention is tested after the real observation owner sees the changed player position")
    _check(far._hc_flank_waypoint == held,"small player motion keeps the same usable far detour until arrival")
    _check(far.batches == int(counts.batches),"retaining a far detour does not create another near candidate batch")
    _check(far._hc_starts == 0 and blocker._hc_starts == 0,"selector observation creates no attack permission or damage")
    print("LAYERED_APPROACH_OBSERVATION "+JSON.stringify({"origin":str(origin),"held":str(held),"after":str(far._hc_flank_waypoint),"initial_counts":counts,"final_batches":far.batches,"observed_target":str(far._hc_known_ground)}))
    for actor in [far,blocker]:
        index.unregister(actor.spatial_actor_runtime_id)
        actor.queue_free()
    await get_tree().process_frame
    # Fractional origin: the whole waypoint chord and the motor's first
    # canonical eight-way leg differ. A peer outside the chord can block that
    # actual first leg; geometry selection must describe what the owner moves.
    var probe_actor := spawn(Vector2(22.35,16.25))
    var probe_origin := probe_actor.spatial_index_position()
    var prefix_blocker := spawn(Vector2(22.675036,15.174964))
    var wrong_chord := Vector2(21.5,15.5)
    var actual_prefix := probe_actor._hc_flank_leg_endpoint(probe_origin,wrong_chord)
    _check(probe_actor._hc_motion_clear(probe_origin,wrong_chord),"recorded far waypoint chord clears the peer")
    _check(probe_actor._hc_flank_destination_clear(wrong_chord),"recorded retained waypoint remains unoccupied")
    _check(not probe_actor._hc_motion_clear(probe_origin,actual_prefix),"real canonical first leg is blocked despite the clear waypoint chord")
    var lawful_point := probe_actor._hc_far_approach_waypoint(probe_origin,CENTER,Neighbor.temporary_cell(probe_origin),1.0)
    var lawful_leg := probe_actor._hc_flank_leg_endpoint(probe_origin,lawful_point)
    _check(lawful_point.is_finite() and lawful_point != wrong_chord and probe_actor._hc_motion_clear(probe_origin,lawful_leg),"far first-legal selector validates the canonical first leg rather than accepting the clear wrong chord")
    for actor in [probe_actor,prefix_blocker]:
        index.unregister(actor.spatial_actor_runtime_id)
        actor.queue_free()
    player.queue_free()
    await get_tree().process_frame
    print("LAYERED_APPROACH_", "PASS" if failures.is_empty() else "FAIL"," ",failures)
    get_tree().quit(0 if failures.is_empty() else 1)
