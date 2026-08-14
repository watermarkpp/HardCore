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
	var gold_after_first_death := PlayerState.gold
	assert(not player.can_start_attack(), "死亡期间普通攻击预检必须关闭")
	assert(not player.request_attack(), "死亡期间普通攻击请求必须拒绝")
	player.take_damage(999999)
	assert(
		player._dead and player.current_hp == 0,
		"重复伤害不得改变死亡状态 dead=%s hp=%s"
		% [str(player._dead), str(player.current_hp)]
	)
	assert(
		PlayerState.gold == gold_after_first_death,
		"重复死亡伤害不得再次扣除金币"
	)
	await get_tree().create_timer(0.9).timeout
	assert(game.hud.death_revival_panel.visible, "死亡动作结束后没有显示死亡复活界面")
	assert(game.current_map_id == 217, "玩家未选择复活方式时提前回城")
	assert(player.current_hp == 0 and player._dead, "死亡界面显示时人物被提前复活")
	game.hud.death_revival_panel.town_button.pressed.emit()
	var revival_deadline := Time.get_ticks_msec() + 3000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < revival_deadline:
		await get_tree().process_frame
	assert(not game._map_transition_in_progress, "城镇复活过渡没有完成")
	assert(game.current_map_id == GameData.service_home_runtime_map_id(false), "人物死亡后没有回到服务端HomeMap")
	assert(player.global_position.is_equal_approx(game._bich_home_screen_position_px()), "人物死亡后复活坐标不是比奇城镇出生点")
	assert(player.current_hp == player.max_hp and not player._dead, "城镇复活后人物状态没有恢复")
	print("PLAYER_MOVEMENT_RESPAWN_PASS：移动朝向稳定、死亡动作和HomeMap复活正常")
	get_tree().quit(0)
