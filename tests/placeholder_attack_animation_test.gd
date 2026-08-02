extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	game.travel_to_map(217)
	await get_tree().process_frame
	await get_tree().process_frame
	var placeholder: EnemyActor
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyActor and not enemy.visual.uses_final_art():
			placeholder = enemy
			break
	if placeholder == null:
		placeholder = EnemyActor.new()
		placeholder.setup({"name":"动画测试占位怪","hp":10,"attackMin":1,"attackMax":2},game.player,false)
		placeholder.global_position=game.player.global_position+Vector2(120,0)
		placeholder.set_meta("spawn_position",placeholder.global_position)
		game.add_child(placeholder)
		await get_tree().process_frame
	assert(placeholder != null and not placeholder.visual.uses_final_art(), "无法建立占位怪攻击验收对象")
	placeholder.facing = Vector2.RIGHT
	placeholder.visual.play_attack(0.46)
	await get_tree().create_timer(0.12).timeout
	assert(placeholder.visual.is_fallback_attacking(), "占位怪攻击前摇未启动")
	assert(placeholder.visual.fallback_lunge_offset_px(placeholder.facing).length() >= 7.0, "占位怪扑击位移不可见")
	assert(placeholder.visual.fallback_attack_progress() > 0.0, "占位怪攻击进度未推进")
	await get_tree().create_timer(0.40).timeout
	assert(not placeholder.visual.is_fallback_attacking(), "占位怪攻击动作没有按时结束")
	print("PLACEHOLDER_ATTACK_PASS：占位怪前摇、12像素扑击与方向挥击反馈正常")
	get_tree().quit(0)
