extends Node

const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var rows: Array = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.learned_skills = {"刺杀剑术": 3, "半月弯刀": 3, "烈火剑法": 3}
	PlayerState.attack_ring_slots = ["刺杀剑术", "半月弯刀", "烈火剑法", "", "", ""]
	PlayerState.recalculate_stats()
	var root := "user://warrior_toggle_camera_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("profiles.json")
	PlayerState.active_profile_id = "owner"
	PlayerState.test_mode = false
	assert(PlayerState.save_game(false))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await Fixture.wait_for_formal_world(self, game, "warrior_toggle_camera_native_test")
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5)))
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			value.set_physics_process(false)
	# This test isolates native input, camera and disk ownership. Collision
	# invariants are exercised by the separate real body/wall tests.
	game.player.collision_mask = 0
	game.player.environment_blocker = null
	game.hud.movement_changed.emit(Vector2.RIGHT)
	for _frame in 90:
		await get_tree().physics_frame
		await get_tree().process_frame
	assert(game.player.locomotion_state == "run")
	var refreshes: Array = []
	PlayerState.profile_changed.connect(func() -> void: refreshes.append(true))
	var path: String = PlayerState._profile_path("owner")
	var previous_camera: Vector2 = game._world_camera.get_screen_center_position()
	var previous_position: Vector2 = game.player.global_position
	for frame in 180:
		if frame % 30 == 0:
			var index := int(frame / 30) % 3
			var button: Node = game.hud.find_child("AttackRingSkill%d" % [index + 1], true, false)
			assert(button != null)
			var bytes_before := FileAccess.get_file_as_bytes(path)
			var motion_before: Vector2 = game.player.touch_vector
			var position_before: Vector2 = game.player.global_position
			var distance_before: float = game.player.locomotion_distance_gu
			var mp_before: int = game.player.current_mp
			var action_before: float = game.player._attack_action_timer
			var before: Dictionary = game.player.warrior_state_snapshot()
			button.input_started.emit(9000 + frame, 2, &"touch")
			button.input_ended.emit(9000 + frame, 2, &"touch")
			assert(game.player.warrior_state_snapshot() != before, "real HUD toggle did not change warrior state")
			assert(game.player.touch_vector == motion_before and game.player.movement_input_active)
			assert(game.player.global_position == position_before and game.player.locomotion_distance_gu == distance_before)
			assert(game.player.locomotion_state == "run" and game.player.current_mp == mp_before)
			assert(game.player._attack_action_timer == action_before, "toggle created a body action")
			assert(FileAccess.get_file_as_bytes(path) == bytes_before, "real HUD toggle wrote the profile synchronously")
			assert(refreshes.is_empty(), "real HUD toggle broadcast a full profile refresh")
			rows.append({"frame": frame, "slot": index, "state": game.player.warrior_state_snapshot(), "camera": str(previous_camera)})
		await get_tree().physics_frame
		await get_tree().process_frame
		var position: Vector2 = game.player.global_position
		var camera: Vector2 = game._world_camera.get_screen_center_position()
		assert(position.x > previous_position.x, "toggle interrupted native continuous movement")
		assert(camera.x >= previous_camera.x - 0.001, "camera moved backward while player ran forward")
		previous_position = position
		previous_camera = camera
	game.hud.movement_changed.emit(Vector2.ZERO)
	assert(PlayerState.save_game(false))
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(saved.warrior_runtime_state == game.player.warrior_runtime_state_for_save())
	FileAccess.open("res://outputs/test_logs/warrior_toggle_camera_native.json", FileAccess.WRITE).store_string(JSON.stringify({"status": "PASS", "rows": rows}, "  "))
	game.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = true
	print("WARRIOR_TOGGLE_CAMERA_NATIVE_PASS")
	get_tree().quit(0)
