extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 22
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	game.travel_to_map(218)
	game.player.global_position = Vector2(560, 260)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyActor:
			enemy.apply_control(4.0)
	for _warmup in range(20):
		await get_tree().process_frame
	var start_usec := Time.get_ticks_usec()
	for _sample in range(120):
		await get_tree().process_frame
	var elapsed_seconds := maxf(0.001, float(Time.get_ticks_usec() - start_usec) / 1000000.0)
	var sampled_fps := 120.0 / elapsed_seconds
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var static_memory_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	assert(game.background.get_child_count() < 80, "Boss房环境节点超出垂直切片基线")
	assert(node_count < 500, "垂直切片总节点数异常")
	print("VERTICAL_SLICE_PERF_BASELINE：FPS=%.1f 节点=%d 静态内存=%.1fMB 绘制调用=%d" % [sampled_fps, node_count, static_memory_mb, draw_calls])
	get_tree().quit(0)
