extends Node2D
## Natural engine target acquisition and real polygon/WORLD locomotion.
## No target, cadence, combat clock or attack timer writes.

const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Spatial := preload("res://scripts/runtime_combat_spatial_index.gd")
const WorldRules := preload("res://scripts/world_spatial_rules.gd")

const MAP_ID := 1
const ACTOR_ID := 64
const MAX_FRAMES_PER_CASE := 720
@export_range(0, 2) var case_kind := 0
const START_GROUND := Vector2(4.0, 8.0)
const GOAL_GROUND := Vector2(8.0, 8.0)

var _index := Spatial.new()
var _serial := 100
var _errors: Array[String] = []
var _case_rows: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	match case_kind:
		0: await _case_open_natural_entry()
		1: await _case_short_wall_real_detour_and_damage()
		2: await _case_narrow_polygon_corridor_and_damage()
	F.write_evidence("natural_entry_obstacle_" + str(case_kind), {"rows":_case_rows, "errors":_errors, "case_kind":case_kind})
	if _errors.is_empty():
		print("NATURAL_ENTRY_OBSTACLE_PASS rows=", _case_rows.size())
	else:
		for error: String in _errors:
			push_error(error)
		print("NATURAL_ENTRY_OBSTACLE_FAIL errors=", _errors)
	get_tree().quit(0 if _errors.is_empty() else 1)

func _case_open_natural_entry() -> void:
	var context := F.open_context()
	var player := await _make_player(Vector2(8.0, 8.0))
	var actor := await _make_actor(player, Vector2(4.0, 8.0), context)
	var initial := _ground(actor)
	var target_seen := false
	var moved_after_target := false
	var target_frame := -1
	var first_move_frame := -1
	for frame in range(maxi(0, MAX_FRAMES_PER_CASE - maxi(target_frame, 0))):
		await get_tree().physics_frame
		if is_instance_valid(actor) and actor.target == player:
			if not target_seen:
				target_seen = true
				target_frame = frame
				initial = _ground(actor)
			elif _ground(actor).distance_to(initial) > 0.20:
				if first_move_frame < 0:
					first_move_frame = frame
				moved_after_target = true
		if target_seen and moved_after_target:
			break
	_check(target_seen, "open case acquired player through natural target scan")
	_check(moved_after_target, "open case moved after target acquisition")
	_case_rows.append({"case":"open_natural_entry", "target_frame":target_frame,
		"first_move_frame":first_move_frame,
		"final_ground":_vec2(_ground(actor)) if is_instance_valid(actor) else _vec2(Vector2.INF),
		"actual_body_radius_gu":actor.combat_radius_gu if is_instance_valid(actor) else -1.0,
		"moved_gu":initial.distance_to(_ground(actor)) if is_instance_valid(actor) else 0.0})
	await _dispose(actor, player)

func _case_short_wall_real_detour_and_damage() -> void:
	# Acquire the target in open terrain first. The wall is then installed before
	# the actor reaches it, so a blocked initial LOS cannot masquerade as a
	# target-acquisition failure.
	var player := await _make_player(GOAL_GROUND)
	var actor := await _make_actor(player, START_GROUND, F.open_context())
	var target_frame := await _wait_for_target(actor, player)
	var radius := actor.combat_radius_gu
	var polygons: Array = [[[6.0, 7.4], [6.4, 7.4], [6.4, 8.6], [6.0, 8.6]]]
	var context := F.polygon_context(polygons, radius)
	_check(not context.is_empty() and bool(context.get("valid", false)), "short wall uses formal 16x16 polygon context")
	var fixture := _make_world_polygons(polygons)
	actor.configure_terrain_navigation_context(context)
	var initial := _ground(actor)
	var initial_hp := int(player.current_hp)
	var trace: Array = []
	var detoured := false
	var arrived := false
	var first_move_frame := -1
	for frame in range(maxi(0, MAX_FRAMES_PER_CASE - maxi(target_frame, 0))):
		await get_tree().physics_frame
		if not is_instance_valid(actor):
			break
		var current := _ground(actor)
		if frame % 30 == 0:
			trace.append({"frame":frame,"pos":_vec2(current),"player":_vec2(_ground(player)),"known":str(actor._hc_known_ground),"observed":actor._hc_observed,"reason":actor._hc_last_reason,"target_live":actor.target == player,"step":str(actor._movement_step_target_ground_gu),"path":str(actor._hc_route),"route_index":actor._hc_route_index,"path_status":actor._hc_path_status,"flank":str(actor._hc_flank_waypoint)})
		if first_move_frame < 0 and current.distance_to(initial) > 0.20:
			first_move_frame = frame
		if absf(current.y - initial.y) > 0.45:
			detoured = true
		if actor._hc_access(player) == "CLEAR":
			arrived = true
			if int(player.current_hp) < initial_hp:
				break
	_check(detoured, "short wall required an actual lateral detour")
	_check(arrived, "short wall actor reached an attackable position")
	_check(int(player.current_hp) < initial_hp, "short wall actor produced real player HP damage")
	_case_rows.append({"case":"short_wall_detour_damage", "target_frame":target_frame,
		"first_move_frame":first_move_frame, "detoured":detoured,
		"arrived":arrived, "final_ground":_vec2(_ground(actor)),
		"actual_body_radius_gu":radius, "trace":trace, "hp_delta":initial_hp-int(player.current_hp)})
	await _dispose(actor, player)
	await _dispose_fixture(fixture)

func _case_narrow_polygon_corridor_and_damage() -> void:
	var player := await _make_player(Vector2(9.0, 0.875))
	var actor := await _make_actor(player, Vector2(5.125, 0.875), F.open_context())
	var target_frame := await _wait_for_target(actor, player)
	var radius := actor.combat_radius_gu
	# Leave a corridor wider than the actual actor body while retaining two
	# matching formal polygons. The width is derived from the live body profile.
	var corridor_center := 0.875
	var corridor_half_width := radius + 0.18
	var bottom := corridor_center - corridor_half_width
	var top := corridor_center + corridor_half_width
	var polygons: Array = [
		[[0.0, 0.0], [16.0, 0.0], [16.0, bottom], [0.0, bottom]],
		[[0.0, top], [16.0, top], [16.0, 16.0], [0.0, 16.0]],
	]
	var context := F.polygon_context(polygons, radius)
	_check(not context.is_empty() and bool(context.get("valid", false)), "narrow case uses formal 16x16 polygon context")
	var fixture := _make_world_polygons(polygons)
	actor.configure_terrain_navigation_context(context)
	var initial_hp := int(player.current_hp)
	var arrived := false
	var first_move_frame := -1
	var initial := _ground(actor)
	for frame in range(maxi(0, MAX_FRAMES_PER_CASE - maxi(target_frame, 0))):
		await get_tree().physics_frame
		if not is_instance_valid(actor):
			break
		if first_move_frame < 0 and _ground(actor).distance_to(initial) > 0.20:
			first_move_frame = frame
		if actor._hc_access(player) == "CLEAR":
			arrived = true
			if int(player.current_hp) < initial_hp:
				break
	_check(arrived, "narrow corridor actor reached the target side")
	_check(int(player.current_hp) < initial_hp, "narrow corridor actor produced real player HP damage")
	_case_rows.append({"case":"narrow_corridor_damage", "target_frame":target_frame,
		"first_move_frame":first_move_frame, "arrived":arrived,
		"final_ground":_vec2(_ground(actor)), "actual_body_radius_gu":radius,
		"corridor_width_gu":top-bottom, "hp_delta":initial_hp-int(player.current_hp)})
	await _dispose(actor, player)
	await _dispose_fixture(fixture)

func _make_player(ground: Vector2) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.name = "NaturalProbePlayer"
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = GU.ground_delta_gu_to_screen_delta_px(ground)
	add_child(player)
	await get_tree().physics_frame
	player.set_physics_process(false)
	# _ready owns the initial health; configure only after it has run.
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	return player

func _make_actor(player: PlayerCharacter, ground: Vector2, context: Dictionary) -> EnemyActor:
	var actor := EnemyActor.new()
	_serial += 1
	actor.name = "NaturalProbeEnemy_%d" % _serial
	actor.setup(GameData.get_monster_by_id(ACTOR_ID), player, false)
	actor.configure_runtime_map_projection(MAP_ID,
		Callable(GU, "ground_delta_gu_to_screen_delta_px"),
		Callable(GU, "screen_delta_px_to_ground_delta_gu"))
	actor.configure_terrain_navigation_context(context)
	actor.configure_spatial_index(_index, _serial)
	actor.set_meta("runtime_map_id", MAP_ID)
	actor.set_meta("zone_generation", 1)
	actor.set_meta("safe_zones", [])
	actor.global_position = GU.ground_delta_gu_to_screen_delta_px(ground)
	add_child(actor)
	await get_tree().physics_frame
	# Register the post-ready position and leave target/cadence/clock/attack timer
	# untouched so acquisition and movement are produced by the natural loop.
	_index.register(_serial, MAP_ID, _ground(actor), actor.combat_radius_gu, _serial,
		actor, Callable(actor, "spatial_index_position"))
	return actor

func _make_world_polygons(polygons: Array) -> Node2D:
	var fixture := Node2D.new()
	fixture.name = "NaturalProbeWorldFixture"
	add_child(fixture)
	for polygon: Array in polygons:
		var points_ground := PackedVector2Array()
		for raw: Array in polygon:
			points_ground.append(Vector2(float(raw[0]), float(raw[1])))
		var center := Vector2.ZERO
		for point: Vector2 in points_ground:
			center += point
		center /= float(points_ground.size())
		var shape := ConvexPolygonShape2D.new()
		var local_screen := PackedVector2Array()
		for point: Vector2 in points_ground:
			local_screen.append(GU.ground_delta_gu_to_screen_delta_px(point-center))
		shape.points = local_screen
		var body := StaticBody2D.new()
		body.collision_layer = WorldRules.WORLD_LAYER
		body.collision_mask = 0
		body.global_position = GU.ground_delta_gu_to_screen_delta_px(center)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)
		fixture.add_child(body)
	return fixture

func _ground(node: Node2D) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(node.global_position)

func _check(value: bool, label: String) -> void:
	if not value:
		_errors.append(label)

func _wait_for_target(actor: EnemyActor, player: PlayerCharacter) -> int:
	for frame in range(MAX_FRAMES_PER_CASE):
		await get_tree().physics_frame
		if is_instance_valid(actor) and actor.target == player and actor._hc_known_ground.is_finite():
			return frame
	_errors.append("natural target acquisition timed out")
	return -1

func _vec2(value: Vector2) -> Array[float]:
	return [value.x, value.y]

func _dispose(actor: EnemyActor, player: PlayerCharacter) -> void:
	if is_instance_valid(actor):
		_index.unregister(actor.spatial_actor_runtime_id)
		actor.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame

func _dispose_fixture(fixture: Node2D) -> void:
	if is_instance_valid(fixture):
		fixture.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
