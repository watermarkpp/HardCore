extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
@export var prefilled_front := false
@export var case_monster_id := 24
@export var target_phase := Vector2.ZERO
@export var case_body_ids: Array[int] = []
@export var moving_start := false
@export var west_wall := false
@export_range(0, 1) var identity_padding := 0
@export var evidence_suffix := ""
const STANDS := [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1)]

class Probe extends EnemyActor:
	var navigation: Array = []
	func _hc_neighbor(current: Vector2, hit_target: Node2D, direct: Vector2i) -> Vector2i:
		var result := super._hc_neighbor(current, hit_target, direct)
		if _combat_action_time_s >= 20.0 and navigation.size() < 160:
			navigation.append({"time": _combat_action_time_s, "current": str(current), "neighbor": str(result), "waypoint": str(_hc_step_override), "held_flank": str(_hc_flank_waypoint), "first_leg": str(SourceStepPlan.next_leg(current, _hc_step_override)), "reason": _hc_last_reason})
		return result

func _spawn(mid: int, position: Vector2) -> EnemyActor:
	serial += 1
	var actor := Probe.new()
	actor.setup(GameData.get_monster_by_id(mid), player, false)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(MAP_ID, _ground_to_screen, _screen_to_ground)
	actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	actor.configure_spatial_index(index, serial)
	actor.set_combat_position(_ground_to_screen(position), &"surround_fixture_spawn")
	actor.set_meta("spawn_position", actor.global_position)
	add_child(actor)
	actor.set_physics_process(false)
	index.register(serial, MAP_ID, position, actor.combat_radius_gu, serial, actor)
	return actor

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	# A test-owned inert node varies native identity only; geometry, actor order,
	# attacks, cadence and the2700-frame completion assertion stay identical.
	assert(identity_padding >= 0 and identity_padding <= 1)
	for offset in identity_padding:
		var padding := Node.new()
		padding.name = "IdentityPadding" + str(offset)
		add_child(padding)
	var center := CENTER + target_phase
	var initial_center := center
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(center)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	var combat := Combat.new()
	add_child(combat)
	var wall: StaticBody2D
	var provider: CollisionRevision
	if west_wall:
		provider = CollisionRevision.new()
		add_child(provider)
		wall = StaticBody2D.new()
		wall.collision_layer = WorldSpatialRules.WORLD_MASK
		wall.collision_mask = 0
		wall.position = _ground_to_screen(center)
		var shape := ConvexPolygonShape2D.new()
		var points := PackedVector2Array()
		for corner in [Vector2(-0.55, -3), Vector2(-0.45, -3), Vector2(-0.45, 3), Vector2(-0.55, 3)]:
			points.append(_ground_to_screen(corner))
		shape.points = points
		var collision := CollisionShape2D.new()
		collision.shape = shape
		wall.add_child(collision)
		add_child(wall)
		await get_tree().physics_frame
		await get_tree().physics_frame
	var actors: Array[EnemyActor] = []
	for i in 30:
		var position := center + Vector2(3.0 + float(i % 5) * 1.1, (float(i / 5) - 2.5) * 1.1)
		if prefilled_front and i < 3:
			position = center + [Vector2(1, 0), Vector2(1, -1), Vector2(1, 1)][i]
		var mid: int = case_monster_id if case_body_ids.is_empty() else case_body_ids[i % case_body_ids.size()]
		var actor := _spawn(mid, position)
		if west_wall: actor.environment_blocker = provider
		actor._leave_background_deep_sleep()
		actor.dormant = false
		actor.target = player
		actor._retarget_timer = 999.0
		actor.max_hp = 100000
		actor.current_hp = actor.max_hp
		actors.append(actor)
	for actor in actors: actor.set_physics_process(true)
	if moving_start:
		player.set_touch_vector(Vector2.LEFT)
		player.set_physics_process(true)
	var snapshots: Array = []
	var final_stands: Array = []
	for frame in 2700:
		await get_tree().physics_frame
		if moving_start and frame == 60:
			player.set_touch_vector(Vector2.ZERO)
			player.set_physics_process(false)
			center = _screen_to_ground(player.global_position)
			_check(center.distance_to(initial_center) > 1.0, "native player movement did not change the surround anchor")
		if frame == 120:
			for actor in actors:
				var before: int = actor.current_hp
				var result := combat.apply_enemy_direct_spell_damage(actor, "wizard.fire_wall", 50, player, null, Callable(), 9, {}, Combat.EnemyMagicDeliveryKind.AUTO)
				_check(bool(result.get("success", false)) and actor.current_hp < before, "real AOE damage failed")
		if frame % 120 == 0 or frame == 2699:
			var positions: Array = []
			var stands: Array = []
			for offset: Vector2 in STANDS:
				var nearest := INF
				var occupant := 0
				for actor in actors:
					var distance := actor.spatial_index_position().distance_to(center + offset)
					if actor._hc_access(player) == "CLEAR" and distance < nearest:
						nearest = distance
						occupant = actor.spatial_actor_runtime_id
				stands.append({"offset": str(offset), "nearest_clear_distance_gu": nearest, "actor": occupant, "occupied": nearest <= 0.4, "available": not west_wall or offset.x >= 0.0})
			for actor in actors:
				positions.append({"id": actor.spatial_actor_runtime_id, "instance_id": actor.get_instance_id(), "position": str(actor.spatial_index_position()), "access": actor._hc_access(player), "starts": actor._hc_starts, "reason": actor._hc_last_reason,
					"clock": actor._combat_action_time_s, "physics": actor.is_physics_processing(), "target": actor.target.get_instance_id() if is_instance_valid(actor.target) else 0,
					"step_active": actor._movement_step_active, "leg_target": str(actor._movement_step_target_ground_gu), "flank": str(actor._hc_flank_waypoint), "velocity": str(actor.velocity), "pursuit": actor._hc_pursuit_session,
					"focus_ms": actor._target_focus_tick_ms, "now_ms": Time.get_ticks_msec(), "observed": actor._hc_observed, "sleeping": actor._background_deep_sleeping})
				positions[-1]["station_goal"] = str(actor._hc_surround_goal)
				positions[-1]["station_slot"] = actor._hc_surround_slot
			snapshots.append({"frame": frame, "stands": stands, "actors": positions})
			final_stands = stands
	var occupied := 0
	for stand: Dictionary in final_stands:
		if not stand.available:
			_check(not bool(stand.occupied), "real wall incorrectly allowed a blocked west stand")
			continue
		if stand.occupied: occupied += 1
		_check(bool(stand.occupied), "reachable source attack stand left empty: " + str(stand.offset))
	_check(occupied == (5 if west_wall else 8), "available surround count differs from independent geometry")
	_check(player.current_hp < player.max_hp, "surround did not deliver real melee damage")
	var label := ("prefilled" if prefilled_front else "one_side") + "_" + str(case_monster_id)
	if target_phase != Vector2.ZERO: label += "_fractional"
	if not case_body_ids.is_empty(): label += "_mixed"
	if moving_start: label += "_moving"
	if west_wall: label += "_west_wall"
	label += evidence_suffix
	var navigation: Array = []
	for actor in actors: navigation.append({"id": actor.spatial_actor_runtime_id, "decisions": actor.navigation})
	FileAccess.open("res://outputs/test_logs/full_surround_" + label + ".json", FileAccess.WRITE).store_string(JSON.stringify({"monster_id": case_monster_id, "body_ids": case_body_ids, "moving_start": moving_start, "west_wall": west_wall, "target_ground_gu": str(center), "body_radius_gu": actors[0].combat_radius_gu, "occupied": occupied, "failures": failures, "snapshots": snapshots, "navigation": navigation}, "  "))
	for actor in actors:
		actor.set_physics_process(false)
		index.unregister(actor.spatial_actor_runtime_id)
		actor.queue_free()
	combat.queue_free()
	player.queue_free()
	if is_instance_valid(wall): wall.queue_free()
	if is_instance_valid(provider): provider.queue_free()
	await get_tree().process_frame
	print("FULL_SURROUND_NATIVE_", "PASS" if failures.is_empty() else "FAIL", " occupied=", occupied, " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
