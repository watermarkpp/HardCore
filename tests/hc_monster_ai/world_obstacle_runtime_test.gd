extends "res://tests/hc_monster_ai/test_support.gd"

const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const WorldRules := preload("res://scripts/world_spatial_rules.gd")


class WorldFixture extends Node2D:
	const FixtureGU := preload("res://scripts/ground_unit_space.gd")
	const FixtureWorldRules := preload("res://scripts/world_spatial_rules.gd")
	var blocked_cells: Dictionary = {}
	var revision := 0

	func ground_to_screen(position: Vector2) -> Vector2:
		return FixtureGU.ground_delta_gu_to_screen_delta_px(position)

	func screen_to_ground(position: Vector2) -> Vector2:
		return FixtureGU.screen_delta_px_to_ground_delta_gu(position)

	func environment_collision_revision() -> int:
		return revision

	func is_environment_point_blocked(position_screen_px: Vector2) -> bool:
		return blocked_cells.has(Vector2i(screen_to_ground(position_screen_px).floor()))

	func is_environment_segment_blocked_ground(
		start_ground_gu: Vector2,
		end_ground_gu: Vector2,
		step_gu: float,
	) -> bool:
		var samples := maxi(1,int(ceil(start_ground_gu.distance_to(end_ground_gu)/maxf(0.05,step_gu))))
		for sample_index in range(samples+1):
			var point:=start_ground_gu.lerp(end_ground_gu,float(sample_index)/float(samples))
			if blocked_cells.has(Vector2i(point.floor())):
				return true
		return false

	func set_cells(cells: Array[Vector2i]) -> void:
		for child: Node in get_children():
			child.free()
		blocked_cells.clear()
		for cell: Vector2i in cells:
			blocked_cells[cell]=true
			_add_cell_body(cell)
		revision+=1

	func add_dynamic_barrier(from_screen_px: Vector2,to_screen_px: Vector2,blocked_cell: Vector2i) -> void:
		# Keep the deterministic occupancy fallback clear in this probe: the
		# failure must be produced by the newly inserted WORLD physics body.
		var direction:=(to_screen_px-from_screen_px).normalized()
		var body:=StaticBody2D.new()
		body.name="DynamicWorldBarrier"
		body.collision_layer=FixtureWorldRules.WORLD_LAYER
		body.collision_mask=0
		body.global_position=from_screen_px.lerp(to_screen_px,0.55)
		body.rotation=direction.angle()
		var collision:=CollisionShape2D.new()
		var shape:=RectangleShape2D.new()
		shape.size=Vector2(12.0,192.0)
		collision.shape=shape
		body.add_child(collision)
		add_child(body)
		revision+=1

	func _add_cell_body(cell: Vector2i) -> void:
		var center_ground:=Vector2(cell)+Vector2(0.5,0.5)
		var center_screen:=ground_to_screen(center_ground)
		var points:=PackedVector2Array()
		for corner: Vector2 in [Vector2(cell),Vector2(cell)+Vector2.RIGHT,Vector2(cell)+Vector2.ONE,Vector2(cell)+Vector2.DOWN]:
			points.append(ground_to_screen(corner)-center_screen)
		var body:=StaticBody2D.new()
		body.name="WorldCell_%d_%d"%[cell.x,cell.y]
		body.collision_layer=FixtureWorldRules.WORLD_LAYER
		body.collision_mask=0
		body.global_position=center_screen
		var collision:=CollisionShape2D.new()
		var shape:=ConvexPolygonShape2D.new()
		shape.points=points
		collision.shape=shape
		body.add_child(collision)
		add_child(body)


var index:=Index.new()
var player:PlayerCharacter
var fixture:WorldFixture
var serial:=0


func ground_to_screen(position:Vector2)->Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(position)


func screen_to_ground(position:Vector2)->Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(position)


func context_for(cells:Array[Vector2i])->Dictionary:
	var blocked:Dictionary={}
	for cell:Vector2i in cells:
		blocked[cell]=true
	return {"valid":true,"contract_id":Terrain.CONTRACT_ID,"runtime_map_id":1,
		"build_sha256":"c".repeat(64),"coordinate_contract_id":Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size":Vector2i(80,80),"blocked_cells":blocked}


func make_enemy(position:Vector2,context:Dictionary)->EnemyActor:
	var actor:=EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(64),player,false)
	actor.global_position=ground_to_screen(position)
	actor.set_meta("spawn_position",actor.global_position)
	actor.set_meta("safe_zones",[])
	actor.set_meta("zone_generation",1)
	actor.configure_runtime_map_projection(1,Callable(self,"ground_to_screen"),Callable(self,"screen_to_ground"))
	actor.configure_terrain_navigation_context(context)
	actor.environment_blocker=fixture
	add_child(actor)
	actor.set_physics_process(false)
	actor.target=player
	actor.primary_target=player
	actor._retarget_timer=999.0
	actor._attack_timer=999.0
	serial+=1
	actor.spatial_actor_runtime_id=serial
	actor.combat_spatial_index=index
	index.register(serial,1,position,actor.combat_radius_gu,serial,actor)
	actor.set_combat_position(ground_to_screen(position),&"hc_world_test_setup")
	return actor


func ready_cadence(actor:EnemyActor)->void:
	var cadence=actor._movement_cadence
	var now:=Time.get_ticks_msec()
	cadence.walk_wait_locked=false
	cadence.walk_tick_ms=now-cadence.walk_interval_ms-1
	cadence.walk_wait_tick_ms=now
	cadence.last_evaluated_ms=now-1


func _ready()->void:
	_run.call_deferred()


func _run()->void:
	PlayerState.test_mode=true
	fixture=WorldFixture.new()
	fixture.name="FormalWorldFixture"
	add_child(fixture)
	player=PlayerCharacter.new()
	player.name="WorldObstaclePlayer"
	player.set_meta("runtime_map_id",1)
	player.set_meta("zone_generation",1)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp=1000000
	player.current_hp=player.max_hp
	await get_tree().physics_frame
	await _test_real_world_slide_collision()
	await _test_u_detour_last_known()
	await _test_closed_then_revision_open()
	finish("world_obstacle_runtime")


func _test_real_world_slide_collision()->void:
	fixture.set_cells([])
	player.global_position=ground_to_screen(Vector2(20.5,20.5))
	var actor:=make_enemy(Vector2(24.5,20.5),context_for([]))
	actor._hc_next_observation_ms=0
	actor._hc_refresh_observation()
	ready_cadence(actor)
	actor._physics_process_internal(1.0/60.0)
	check(actor._movement_step_active,"C04-move-start","Production HC movement attempts a real step before the dynamic wall arrives")
	var legal_before:=actor.global_position
	var target_screen:=ground_to_screen(actor._movement_step_target_ground_gu)
	fixture.add_dynamic_barrier(actor.global_position,target_screen,Vector2i(actor._movement_step_target_ground_gu.floor()))
	var attempted_motion:=false
	for frame in range(90):
		await get_tree().physics_frame
		var before:=actor.global_position
		actor._physics_process_internal(1.0/60.0)
		attempted_motion=attempted_motion or actor.global_position!=before or actor._hc_world_collision_count>0
		if actor._hc_world_collision_count>0:
			break
	check(attempted_motion,"C04-attempted","The actor attempted physical movement")
	check(actor._hc_world_collision_count>0,"C04-world-branch","A WORLD-layer slide collision reached the production WORLD_BLOCKED branch")
	check(actor.target==player,"C04-target","WORLD failure preserves the selected target")
	check(not actor._hc_owned_movement_call,"C04-owner","HC movement ownership is restored")
	check(actor.global_position.distance_to(legal_before)<ground_to_screen(Vector2.ONE).length(),"C04-last-legal","Failure retains the latest legal point instead of unrelated rewind")
	await _free_enemy(actor)


func _test_u_detour_last_known()->void:
	fixture.set_cells([])
	player.global_position=ground_to_screen(Vector2(20.5,20.5))
	var actor:=make_enemy(Vector2(23.5,20.5),context_for([]))
	actor._hc_next_observation_ms=0
	actor._hc_refresh_observation()
	check(actor._hc_observed,"C05-observe","Target is formally observed before occlusion")
	var known_before:=actor._hc_known_ground
	var u_cells:Array[Vector2i]=[]
	for y in range(18,23):
		u_cells.append(Vector2i(22,y))
	for x in range(18,23):
		u_cells.append(Vector2i(x,18))
		u_cells.append(Vector2i(x,22))
	fixture.set_cells(u_cells)
	var u_context:=context_for(u_cells)
	actor.configure_terrain_navigation_context(u_context)
	player.global_position=ground_to_screen(Vector2(20.25,20.5))
	actor._hc_next_observation_ms=0
	actor._hc_refresh_observation()
	check(not actor._hc_observed and actor._hc_known_ground==known_before,"C05-last-known","Occluded player motion does not update the last-known point")
	actor._attack_timer=0.0
	ready_cadence(actor)
	var initial_distance:=screen_to_ground(actor.global_position).distance_to(screen_to_ground(player.global_position))
	var farthest_distance:=initial_distance
	var clipped:=false
	for frame in range(1200):
		await get_tree().physics_frame
		actor._physics_process_internal(1.0/60.0)
		var ground:=screen_to_ground(actor.global_position)
		farthest_distance=maxf(farthest_distance,ground.distance_to(screen_to_ground(player.global_position)))
		clipped=clipped or not Terrain.cell_walkable(u_context,Vector2i(ground.floor()),actor.combat_radius_gu)
		if actor._hc_starts>0 and ground.distance_to(screen_to_ground(player.global_position))<=actor._hc_preferred(player)+0.05:
			break
	var final_distance:=screen_to_ground(actor.global_position).distance_to(screen_to_ground(player.global_position))
	check(not clipped,"C05-continuous-no-clip","Every sampled footprint remains outside the U/L WORLD cells")
	check(farthest_distance>initial_distance+0.05,"C05-away-first","The valid U detour temporarily moves away from the hidden target")
	check(actor._hc_starts>0 and final_distance<=actor._hc_preferred(player)+0.05,"C05-reach","The open U route reaches a legal live engagement position")
	await _free_enemy(actor)


func _test_closed_then_revision_open()->void:
	fixture.set_cells([])
	player.global_position=ground_to_screen(Vector2(20.5,20.5))
	var actor:=make_enemy(Vector2(26.5,20.5),context_for([]))
	actor._hc_next_observation_ms=0
	actor._hc_refresh_observation()
	var ring:Array[Vector2i]=[]
	for coordinate in range(18,23):
		ring.append(Vector2i(18,coordinate))
		ring.append(Vector2i(22,coordinate))
		ring.append(Vector2i(coordinate,18))
		ring.append(Vector2i(coordinate,22))
	fixture.set_cells(ring)
	var closed_context:=context_for(ring)
	actor.configure_terrain_navigation_context(closed_context)
	actor._hc_next_observation_ms=0
	actor._hc_refresh_observation()
	actor._attack_timer=0.0
	ready_cadence(actor)
	var starts_before:=actor._hc_starts
	var saw_terminal_no_route:=false
	var clipped:=false
	for frame in range(420):
		await get_tree().physics_frame
		actor._physics_process_internal(1.0/60.0)
		var ground:=screen_to_ground(actor.global_position)
		clipped=clipped or not Terrain.cell_walkable(closed_context,Vector2i(ground.floor()),actor.combat_radius_gu)
		saw_terminal_no_route=saw_terminal_no_route or actor._hc_path_status in ["NO_VALID_GOAL_IN_CURRENT_SAMPLE","NO_ROUTE_FOR_CURRENT_GRAPH"]
	check(not clipped and actor._hc_starts==starts_before,"C05-closed-no-clip","Closed target remains unreachable without clipping or attacking")
	check(saw_terminal_no_route,"C06-no-route","Terminal no-route is observed separately from scheduler waiting")
	var opened:Array[Vector2i]=[]
	for cell:Vector2i in ring:
		if cell!=Vector2i(22,20):
			opened.append(cell)
	fixture.set_cells(opened)
	var open_revision_context:=context_for(opened)
	actor.configure_terrain_navigation_context(open_revision_context)
	ready_cadence(actor)
	for frame in range(720):
		await get_tree().physics_frame
		actor._physics_process_internal(1.0/60.0)
		if actor._hc_starts>starts_before:
			break
	check(actor._hc_path_revision==fixture.environment_collision_revision(),"C05-revision","Dynamic wall revision invalidates the stale route")
	check(actor._hc_starts>starts_before,"C05-reopen","Removing one authored wall cell permits a fresh legal engagement")
	await _free_enemy(actor)


func _free_enemy(actor:EnemyActor)->void:
	if actor.spatial_actor_runtime_id>0:
		index.unregister(actor.spatial_actor_runtime_id)
	actor.queue_free()
	await get_tree().physics_frame
