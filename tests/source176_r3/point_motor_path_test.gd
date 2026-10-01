extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const O := preload("res://tests/source176_r3/helpers/case_oracle.gd")
const Step := preload("res://scripts/monster_source176/source_step_plan.gd")
class PointMotor:
	extends EnemyActor
	var point_goal: Node2D
	var reached := false
	var rejected := false
	var committed: Array = []
	# A point waypoint is not an occupied combat target. This structural
	# motor fixture bypasses engagement only; real body radii/shapes, speed,
	# terrain and native move_and_slide remain production values.
	func _contact_distance_gu_to_target(node: Node2D) -> float:
		return 0.0 if node==point_goal else super._contact_distance_gu_to_target(node)
	func _movement_step_engagement_ready() -> bool:
		return false
	func _terrain_neighbor_for_pursuit(current: Vector2, _node: Node2D, _direction: Vector2i) -> Vector2i:
		_hc_step_override = Step.next_leg(current,F.to_ground(point_goal.global_position))
		var leg := _hc_step_override-current
		return Vector2i(int(signf(leg.x)),int(signf(leg.y)))
	func _physics_process(delta: float) -> void:
		var current := F.to_ground(global_position)
		var goal := F.to_ground(point_goal.global_position)
		if current.distance_to(goal)<.0001:
			reached = true
			return
		_hc_owned_movement_call = true
		if not _movement_step_active:
			if not _begin_autonomous_step_without_cadence(goal-current,1.0,false,&"pursuit",point_goal):
				rejected = true
				return
			committed.append({"from":current,"to":_movement_step_target_ground_gu})
		_advance_autonomous_step(delta)
var errors: Array[String] = []
var rows: Array = []
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var victim := F.player(self,Vector2(50,50))
	var goal := Node2D.new()
	goal.global_position = F.to_screen(Vector2(27.125,20.875))
	add_child(goal)
	var actor := PointMotor.new()
	actor.setup(GameData.get_monster_by_id(64),victim,false)
	actor.point_goal = goal
	actor.global_position = F.to_screen(Vector2(15.125,15.875))
	actor.set_meta("safe_zones",[])
	actor.set_meta("zone_generation",1)
	actor.configure_runtime_map_projection(1,Callable(F.GU,"ground_delta_gu_to_screen_delta_px"),Callable(F.GU,"screen_delta_px_to_ground_delta_gu"))
	actor.configure_terrain_navigation_context(F.open_context())
	add_child(actor)
	actor.combat_spatial_index = F.Spatial.new()
	actor.spatial_actor_runtime_id = actor.get_instance_id()
	actor.combat_spatial_index.register(actor.spatial_actor_runtime_id,1,F.to_ground(actor.global_position),actor.combat_radius_gu,1,actor)
	var distance := 0.0
	var previous := F.to_ground(actor.global_position)
	for n in range(3000):
		await get_tree().physics_frame
		var now := F.to_ground(actor.global_position)
		distance += previous.distance_to(now)
		previous = now
		if actor.reached or actor.rejected:
			break
	actor.set_physics_process(false)
	var turns := 0
	var previous_leg := Vector2.ZERO
	for record: Dictionary in actor.committed:
		var leg: Vector2 = record.to-record.from
		if record.to.distance_to(O.next_leg(record.from,F.to_ground(goal.global_position)))>.0001:
			errors.append("committed leg differs from independent oracle")
		if previous_leg!=Vector2.ZERO and not O.parallel_forward(leg,previous_leg):
			turns += 1
		previous_leg = leg
	if not actor.reached or actor.rejected or absf(distance-(7+5*sqrt(2.0)))>.001 or turns!=1:
		errors.append("complete native motor path failed")
	rows = actor.committed
	F.write_evidence("point_motor_path",{"errors":errors,"distance_gu":distance,"expected_gu":7+5*sqrt(2.0),"turns":turns,"legs":rows,"scope":"point-to-point structural motor, native physics; occupied-player pursuit separately stops in legal attack domain"})
	goal.free()
	F.dispose(actor,victim)
	print(("R3_POINT_MOTOR_PASS" if errors.is_empty() else "R3_POINT_MOTOR_FAIL")+" distance="+str(distance)+" turns="+str(turns)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
