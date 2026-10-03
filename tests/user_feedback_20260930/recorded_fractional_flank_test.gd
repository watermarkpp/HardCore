extends "res://tests/user_feedback_20260930/full_surround_native_test.gd"
const Neighbor := preload("res://scripts/monster_neighbor_step_policy.gd")
const CorePolicy := preload("res://scripts/monster_ai_package/policy.gd")

func point(value: Array) -> Vector2:
    return Vector2(float(value[0]), float(value[1]))

func _run() -> void:
    PlayerState.test_mode = true
    PlayerState.reset_progress(false)
    var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/user_feedback_20260930/recorded_fractional_surround_fixture.json"))
    var anchor := point(fixture.target)
    player = PlayerCharacter.new()
    player.set_meta("runtime_map_id", MAP_ID)
    player.set_meta("zone_generation", 1)
    player.global_position = _ground_to_screen(anchor)
    add_child(player)
    player.set_physics_process(false)
    var actors: Array[EnemyActor] = []
    for row: Dictionary in fixture.bodies:
        var actor := _spawn(89, point(row.position))
        actor._leave_background_deep_sleep()
        actor.set_physics_process(false)
        _check(not actor.is_physics_processing(),"recorded pose replay owns its only movement calls")
        actor.target = player
        actor._hc_surround_anchor = anchor
        actor._hc_surround_scope = [MAP_ID, 1, actor._hc_life(actor), player.get_instance_id(), actor._hc_life(player)]
        actor._hc_surround_slot = int(row.slot)
        actor._hc_surround_goal = Vector2.INF if row.goal == null else point(row.goal)
        actor._hc_known_ground = anchor
        actor._hc_known_target_id = player.get_instance_id()
        actor._hc_observed = true
        actors.append(actor)
    var actor := actors[15]
    actor._hc_owned_movement_call = true
    var current := actor.spatial_index_position()
    var direction := Neighbor.neighbor_for_desired_ground_direction(actor._hc_surround_goal - current)
    var neighbor := actor._hc_neighbor(current, player, direction)
    _check(neighbor != Vector2i.ZERO and actor._hc_step_override.is_finite(), "recorded crowded corner has a lawful proposed escape leg")
    var overlaps: Array = []
    if actor._hc_flank_waypoint.is_finite():
        for other: EnemyActor in actors:
            if other == actor: continue
            var radius := actor.combat_radius_gu + other.combat_radius_gu
            if actor._hc_flank_waypoint.distance_squared_to(other.spatial_index_position()) < radius * radius - CorePolicy.EPS:
                overlaps.append(other.spatial_actor_runtime_id)
    _check(actor._hc_flank_waypoint.is_finite(), "recorded corner retains a complete flank destination")
    _check(overlaps.is_empty(), "a clear prefix must not retain a destination inside live peer bodies: " + str(overlaps))
    print("RECORDED_FLANK_OBSERVATION " + JSON.stringify({"origin":str(current), "neighbor":str(neighbor),
        "prefix":str(actor._hc_step_override), "destination":str(actor._hc_flank_waypoint), "overlaps":overlaps}))
    var blocked_destination := Vector2(17.5, 18.5)
    var blocker := actors[21]
    var retained_candidates: Array = [blocker]
    _check(not actor._hc_flank_destination_candidates_clear(blocked_destination, retained_candidates), "recorded rear body rejects the occupied retained destination")
    var before := blocker.spatial_index_position()
    blocker.set_combat_position(_ground_to_screen(before + Vector2(0.03, 0.0)), &"recorded_endpoint_occupant_leaves")
    _check(actor._hc_flank_destination_candidates_clear(blocked_destination, retained_candidates), "same retained candidate identity reads its current clear pose immediately")
    _check(actor._hc_flank_destination_clear(blocked_destination), "fresh real-index query observes the newly clear destination")
    var saved_index := actor.combat_spatial_index
    actor.combat_spatial_index = null
    _check(not actor._hc_flank_destination_clear(blocked_destination), "missing body-query ownership cannot admit a retained destination")
    actor.combat_spatial_index = saved_index
    for item: EnemyActor in actors:
        index.unregister(item.spatial_actor_runtime_id)
        item.queue_free()
    player.queue_free()
    await get_tree().process_frame
    print("RECORDED_FLANK_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
    get_tree().quit(0 if failures.is_empty() else 1)
