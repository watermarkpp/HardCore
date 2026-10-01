extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
var service: Node
@export var case_monster_id := 24
@export var case_count := 2

class Probe extends EnemyActor:
	var moves: Array = []
	var relocations: Array = []
	func set_combat_position(position_px: Vector2, reason: StringName = &"") -> void:
		if relocations.size() < 96 and reason in [&"eight_way_collision_stop", &"environment_revert", &"safe_zone_revert", &"entrapment_boundary_revert"]:
			relocations.append({"tick": Engine.get_physics_frames(), "reason": str(reason),
				"before": str(global_position), "after": str(position_px), "velocity": str(velocity),
				"actual_gu": str(GroundUnitSpace.screen_delta_px_to_ground_delta_gu(global_position - position_px))})
		super.set_combat_position(position_px, reason)
	func _move_with_spatial_rules(delta := 1.0 / 60.0) -> void:
		var start := spatial_index_position()
		var planned := _movement_step_legs.duplicate()
		var requested := velocity
		super._move_with_spatial_rules(delta)
		if moves.size() < 96:
			var collisions: Array = []
			for i in _movement_collision_count():
				var collision := _movement_collision(i)
				var collider := collision.get_collider()
				collisions.append({"body_id": collider.get_instance_id() if is_instance_valid(collider) else 0, "normal": str(collision.get_normal())})
			moves.append({"tick": Engine.get_physics_frames(), "start": str(start), "end": str(spatial_index_position()),
				"legs": str(planned), "requested": str(requested), "collisions": collisions})

func _spawn(mid: int, position: Vector2) -> EnemyActor:
	# Observation-only subclass delegates every sweep to the production method.
	serial += 1
	var actor := Probe.new()
	actor.setup(GameData.get_monster_by_id(mid), player, false)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(MAP_ID, _ground_to_screen, _screen_to_ground)
	actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	actor.configure_spatial_index(index, serial)
	actor.set_combat_position(_ground_to_screen(position), &"d3_fixture_spawn")
	actor.set_meta("spawn_position", actor.global_position)
	add_child(actor)
	actor.set_physics_process(false)
	index.register(serial, MAP_ID, position, actor.combat_radius_gu, serial, actor)
	return actor

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	service = Combat.new()
	add_child(service)
	await _case(case_monster_id, case_count)
	FileAccess.open("res://outputs/test_logs/crowd_recovery_%d_%d.json" % [case_monster_id, case_count], FileAccess.WRITE).store_string(JSON.stringify({"failures": failures, "rows": rows}, "  "))
	service.queue_free()
	await get_tree().process_frame
	print("CROWD_RECOVERY_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _case(mid: int, count: int) -> void:
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	var actors: Array[EnemyActor] = []
	var initial: Array[Vector2] = []
	var samples: Array = []
	var columns := 5 if count == 30 else 2
	var row_count := ceili(float(count) / float(columns))
	for i in count:
		var position := CENTER + Vector2(3.0 + float(i % columns) * 1.1, (float(i / columns) - float(row_count - 1) * 0.5) * 1.1)
		var actor := _spawn(mid, position)
		actor._leave_background_deep_sleep()
		actor.dormant = false
		actor.target = player
		actor._retarget_timer = 999.0
		actor.max_hp = 100000
		actor.current_hp = actor.max_hp
		actors.append(actor)
		initial.append(_screen_to_ground(actor.global_position))
	for actor in actors: actor.set_physics_process(true)
	var starts_before_kite := 0
	# Preserve canonical source speeds. Give the slowest native approach and
	# flank enough time to reach contact before starting the real player kite.
	for frame in 900:
		await get_tree().physics_frame
		if frame == 90:
			for actor in actors:
				var hp_before: int = actor.current_hp
				var outcome: Dictionary = service.apply_enemy_direct_spell_damage(actor, "wizard.fire_wall", 50, player, null, Callable(), 9, {}, Combat.EnemyMagicDeliveryKind.AUTO)
				_check(bool(outcome.get("success", false)) and actor.current_hp < hp_before, str([mid, count]) + ": real AOE damage sink failed")
		if frame == 720:
			for actor in actors: starts_before_kite += actor._hc_starts
			player.set_touch_vector(Vector2.LEFT)
			player.set_physics_process(true)
		if frame % 60 == 0 or frame == 899:
			var actors_snapshot: Array = []
			for actor in actors:
				var ground := _screen_to_ground(actor.global_position)
				actors_snapshot.append({"id": actor.get_instance_id(), "position": [ground.x, ground.y],
					"reason": actor._hc_last_reason, "starts": actor._hc_starts, "clock": actor._combat_action_time_s,
					"step_active": actor._movement_step_active, "leg_target": str(actor._movement_step_target_ground_gu),
					"route_index": actor._hc_route_index, "route": str(actor._hc_route),
					"observed": actor._hc_observed, "known": str(actor._hc_known_ground), "physics": actor.is_physics_processing(),
					"radius": actor.combat_radius_gu, "safe_margin": actor.safe_margin,
					"permission": actor._source176_decision_granted, "pursuit": actor._hc_pursuit_session,
					"motion": str(actor.actual_ground_motion_gu), "cadence": actor._movement_cadence.state_snapshot(),
					"visual": actor.visual.hc_m30_motion_snapshot()})
			samples.append({"frame": frame, "player": str(_screen_to_ground(player.global_position)), "actors": actors_snapshot})
	var moved := 0
	var starts := 0
	for i in count:
		var actor := actors[i]
		if _screen_to_ground(actor.global_position).distance_to(initial[i]) > 1.0: moved += 1
		starts += actor._hc_starts
	_check(starts_before_kite > 0, str([mid, count]) + ": stationary crowd never admitted a real attack")
	_check(moved > 0 and starts > 0, str([mid, count]) + ": crowd stayed deadlocked")
	var sweep_traces: Array = []
	for actor in actors: sweep_traces.append({"id": actor.get_instance_id(), "moves": actor.moves, "relocations": actor.relocations})
	rows.append({"monster_id": mid, "count": count, "moved": moved, "starts": starts, "starts_before_kite": starts_before_kite,
		"player_damage": player.max_hp - player.current_hp, "samples": samples, "sweeps": sweep_traces})
	for actor in actors:
		actor.set_physics_process(false)
		index.unregister(actor.spatial_actor_runtime_id)
		actor.queue_free()
	player.set_physics_process(false)
	player.queue_free()
	await get_tree().process_frame
