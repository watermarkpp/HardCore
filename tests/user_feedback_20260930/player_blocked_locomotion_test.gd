extends Node

const Spatial := preload("res://scripts/world_spatial_rules.gd")
var failures: Array[String] = []
var rows: Array = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	for body_kind in ["wall", "monster"]:
		await _case(body_kind)
	FileAccess.open("res://outputs/test_logs/player_blocked_locomotion.json", FileAccess.WRITE).store_string(JSON.stringify({"rows": rows, "failures": failures}, "  "))
	print("PLAYER_BLOCKED_LOCOMOTION_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _case(body_kind: String) -> void:
	var actor := PlayerCharacter.new()
	add_child(actor)
	var blocker: PhysicsBody2D
	var second_blocker: EnemyActor
	if body_kind == "monster":
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(24), actor, false)
		enemy.global_position = Vector2(170.0, -10.0)
		add_child(enemy)
		enemy._leave_background_deep_sleep()
		enemy.set_physics_process(false)
		blocker = enemy
		# Two non-overlapping native footsoles close the gap. A single curved
		# footsole legitimately permits contact separation around its edge.
		second_blocker = EnemyActor.new()
		second_blocker.setup(GameData.get_monster_by_id(24), actor, false)
		second_blocker.global_position = Vector2(170.0, 10.0)
		add_child(second_blocker)
		second_blocker._leave_background_deep_sleep()
		second_blocker.set_physics_process(false)
	else:
		var wall := StaticBody2D.new()
		wall.collision_layer = Spatial.WORLD_LAYER
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(20.0, 300.0)
		shape.shape = rectangle
		wall.add_child(shape)
		wall.global_position = Vector2(170.0, 0.0)
		add_child(wall)
		blocker = wall
	actor.set_touch_vector(Vector2.RIGHT)
	if body_kind == "monster":
		await _monster_contact(actor, blocker)
		second_blocker.queue_free()
		await get_tree().process_frame
		return
	var stationary := 0
	var prior := actor.global_position
	for _frame in 180:
		await get_tree().physics_frame
		if actor.global_position.distance_squared_to(prior) < 0.000001: stationary += 1
		else: stationary = 0
		prior = actor.global_position
		if stationary >= 8 and actor.locomotion_state == "run": break
	check(stationary >= 8, body_kind + ": never contacted real collision body")
	check(actor.movement_input_active and actor.locomotion_state == "run", body_kind + ": collision cleared run intent")
	var stop := actor.global_position
	var distance := actor.locomotion_distance_gu
	var frame_set := {}
	for _frame in 30:
		await get_tree().physics_frame
		await get_tree().process_frame
		frame_set[actor.visual.current_frame] = true
		check(actor.visual.current_state == "run", body_kind + ": blocked input displayed idle")
	check(actor.global_position.distance_to(stop) < 0.02, body_kind + ": collision allowed continued displacement")
	check(is_equal_approx(actor.locomotion_distance_gu, distance), body_kind + ": blocked pose manufactured run distance")
	check(frame_set.size() > 1, body_kind + ": blocked run animation did not advance")
	rows.append({"body": body_kind, "position": [stop.x, stop.y], "run_distance": distance, "frames": frame_set.keys(), "state": actor.visual.current_state})
	actor.set_touch_vector(Vector2.ZERO)
	for _frame in 2:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(actor.visual.current_state == "idle" and actor.locomotion_state == "walk", body_kind + ": input release did not reset locomotion")
	actor.set_physics_process(false)
	actor.queue_free()
	blocker.queue_free()
	await get_tree().process_frame

func _monster_contact(actor: PlayerCharacter, blocker: PhysicsBody2D) -> void:
	# A closed gap between two native footsoles stops world displacement.
	# Safe-margin separation and the following clipped input can cancel each
	# other; the accepted directional counter is not a net-position counter.
	var blocked := 0
	var frame_set := {}
	var motion_rows: Array = []
	var prior_position := actor.global_position
	var held_position := Vector2.INF
	for frame in 240:
		await get_tree().physics_frame
		await get_tree().process_frame
		if frame % 10 == 0:
			motion_rows.append({"frame": frame, "position": str(actor.global_position), "body_position": str(blocker.global_position), "actual_gu": str(actor.actual_ground_motion_gu), "velocity": str(actor.velocity), "distance": actor.locomotion_distance_gu})
		if actor.locomotion_state == "run" and actor.global_position.distance_to(prior_position) < 0.02:
			blocked += 1
			if not held_position.is_finite(): held_position = actor.global_position
			frame_set[actor.visual.current_frame] = true
			check(actor.movement_input_active and actor.visual.current_state == "run", "monster: blocked input lost run presentation")
			check(actor.global_position.distance_to(held_position) < 0.02, "monster: closed body gap allowed continuing movement")
			motion_rows.append({"frame": frame, "position": str(actor.global_position), "body_position": str(blocker.global_position), "actual_gu": str(actor.actual_ground_motion_gu), "velocity": str(actor.velocity)})
		prior_position = actor.global_position
		if blocked >= 30: break
	check(blocked >= 2, "monster: no native body-blocked frames were observed")
	check(frame_set.size() > 1, "monster: blocked run animation did not advance")
	rows.append({"body": "monster", "layer": blocker.collision_layer, "blocked_frames": blocked, "animation_frames": frame_set.keys(), "samples": motion_rows})
	actor.set_touch_vector(Vector2.ZERO)
	for _frame in 2:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(actor.visual.current_state == "idle" and actor.locomotion_state == "walk", "monster: input release did not reset locomotion")
	actor.set_physics_process(false)
	actor.queue_free()
	blocker.queue_free()
	await get_tree().process_frame
