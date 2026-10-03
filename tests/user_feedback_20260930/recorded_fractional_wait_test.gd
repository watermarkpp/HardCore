extends "res://tests/user_feedback_20260930/full_surround_native_test.gd"
const Neighbor := preload("res://scripts/monster_neighbor_step_policy.gd")
const CorePolicy := preload("res://scripts/monster_ai_package/policy.gd")

class MotionProbe extends EnemyActor:
    var pose_writes: Array = []
    var moves: Array = []
    func _move_with_spatial_rules(delta := 1.0/60.0) -> void:
        var before := global_position
        var motion := velocity*get_physics_process_delta_time()
        var result := KinematicCollision2D.new()
        var hit := test_move(global_transform,motion,result,safe_margin,true)
        var sample := {"before":str(before),"motion":str(motion),"physics_delta":get_physics_process_delta_time(),
            "test_hit":hit,"test_travel":str(result.get_travel())}
        if hit:
            var collider := result.get_collider()
            sample["test_collider"] = collider.spatial_actor_runtime_id if collider is EnemyActor else 0
        super._move_with_spatial_rules(delta)
        sample["after"] = str(global_position)
        moves.append(sample)
    func set_combat_position(screen_px: Vector2, reason: StringName = &"unspecified") -> void:
        if pose_writes.size()<64:
            pose_writes.append({"reason":str(reason),"before":str(global_position),"after":str(screen_px),"velocity":str(velocity)})
        super.set_combat_position(screen_px,reason)

func _spawn(mid: int, position: Vector2) -> EnemyActor:
    serial += 1
    var actor := MotionProbe.new()
    actor.setup(GameData.get_monster_by_id(mid),player,false)
    actor.set_meta("safe_zones",[])
    actor.set_meta("zone_generation",1)
    actor.configure_runtime_map_projection(MAP_ID,_ground_to_screen,_screen_to_ground)
    actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
    actor.configure_spatial_index(index,serial)
    actor.set_combat_position(_ground_to_screen(position),&"recorded_wait_spawn")
    actor.set_meta("spawn_position",actor.global_position)
    add_child(actor)
    actor.set_physics_process(false)
    index.register(serial,MAP_ID,position,actor.combat_radius_gu,serial,actor)
    return actor

func point(value: Array) -> Vector2:
    return Vector2(float(value[0]), float(value[1]))

func _run() -> void:
    PlayerState.test_mode = true
    PlayerState.reset_progress(false)
    var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/user_feedback_20260930/recorded_fractional_wait_fixture.json"))
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
    await get_tree().physics_frame
    await get_tree().physics_frame
    var actor := actors[11]
    var goal := actor._hc_surround_goal
    var origin := actor.spatial_index_position()
    var observations: Array = []
    _check(not actor._hc_flank_destination_clear(goal),"recorded waiting goal is actually inside a live rear body")
    var first_leg := actor.SourceStepPlan.next_leg(origin,goal,1.0,GU.EPSILON_GU)
    _check(actor._hc_motion_clear(origin,first_leg),"recorded tiny first prefix remains core-clear")
    actor._hc_pursuit_session = true
    for frame in 12:
        await get_tree().physics_frame
        var current := actor.spatial_index_position()
        actor._hc_owned_movement_call = true
        var admitted := actor._movement_step_active or actor._begin_autonomous_step_without_cadence(goal-current,1.0,false,&"pursuit",player)
        var proposed := actor._movement_step_target_ground_gu
        if frame == 0:
            _check(admitted and actor._hc_flank_waypoint.is_finite(),"occupied wait endpoint must select a complete legal detour instead of repeating its tiny prefix")
            _check(actor._hc_flank_waypoint.is_finite() and actor._hc_flank_destination_clear(actor._hc_flank_waypoint),"the selected wait detour ends outside all live peer cores")
        actor._advance_autonomous_step(1.0/60.0,1.0/60.0)
        actor._hc_owned_movement_call = false
        var collision_id := 0
        if actor._directional_collision != null:
            var collider := actor._directional_collision.get_collider()
            if collider is EnemyActor: collision_id = collider.spatial_actor_runtime_id
        observations.append({"frame":frame,"before":str(current),"admitted":admitted,"proposed":str(proposed),
            "after":str(actor.spatial_index_position()),"collision_id":collision_id,"reason":actor._hc_last_reason})
    print("RECORDED_WAIT_OBSERVATION "+JSON.stringify({"origin":str(origin),"goal":str(goal),"samples":observations,"pose_writes":actor.pose_writes,"moves":actor.moves}))
    _check(actor.spatial_index_position().distance_to(origin)>actor.CrowdAttackPosition.margin_gu(actor),"real physics must make body-margin-sized escape progress from the recorded wait jam")
    for item: EnemyActor in actors:
        index.unregister(item.spatial_actor_runtime_id)
        item.queue_free()
    player.queue_free()
    await get_tree().process_frame
    print("RECORDED_WAIT_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
    get_tree().quit(0 if failures.is_empty() else 1)
