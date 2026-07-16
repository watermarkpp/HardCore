extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: PlayerCharacter = game.player
	player.set_touch_vector(Vector2(1.0, 0.08))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(player.facing.is_equal_approx(Vector2.RIGHT), "人物移动时没有稳定面向移动方向：%s" % player.facing)
	assert(player.actual_motion_facing.is_equal_approx(Vector2.RIGHT), "人物图像方向未使用实际位移方向")
	player.visual._process(0.01)
	assert(player.visual.current_direction == 2, "人物向右移动时没有播放镜像后的东方向行")
	player.visual._process(0.05)
	assert(player.visual.current_direction == 2, "行走动画没有优先使用实际移动方向")
	player.set_touch_vector(Vector2.ZERO)
	game.travel_to_map(217)
	await get_tree().process_frame
	player.global_position = Vector2(900, 700)
	player.defense_min = 0
	player.defense_max = 0
	player.take_damage(999999)
	assert(player._dead and player.global_position == Vector2(900, 700), "死亡动作期间人物被传送到未知世界原点")
	await get_tree().create_timer(0.9).timeout
	assert(game.current_map_id == GameData.service_home_runtime_map_id(false), "人物死亡后没有回到服务端HomeMap")
	assert(player.global_position.is_equal_approx(game._bich_home_world_position()), "人物死亡后复活坐标不是比奇城镇出生点")
	assert(player.current_hp == player.max_hp and not player._dead, "城镇复活后人物状态没有恢复")
	print("PLAYER_MOVEMENT_RESPAWN_PASS：移动朝向稳定、死亡动作和HomeMap复活正常")
	get_tree().quit(0)
