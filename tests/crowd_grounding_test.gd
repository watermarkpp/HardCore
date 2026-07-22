extends Node2D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	y_sort_enabled = true
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for action in ["move_left", "move_right", "move_up", "move_down", "attack"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var player := PlayerCharacter.new()
	player.name = "CrowdTestPlayer"
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.max_hp = 10000
	player.current_hp = 10000
	assert(player.collision_layer == 2 and player.collision_mask == 5, "玩家碰撞层未隔离为player/world+enemy")

	var enemies: Array[EnemyActor] = []
	var data := GameData.get_monster("稻草人")
	for index in range(8):
		var enemy := EnemyActor.new()
		enemy.setup(data, player, false)
		enemy.global_position = Vector2.from_angle(float(index) / 8.0 * TAU) * 8.0
		add_child(enemy)
		enemies.append(enemy)
	await get_tree().process_frame
	for _frame in range(150):
		await get_tree().physics_frame

	for enemy: EnemyActor in enemies:
		assert(enemy.collision_layer == 4 and enemy.collision_mask == 3, "怪物必须保留world/player硬碰撞并关闭enemy互撞")
		var minimum_player_distance := ArtSpec.PLAYER_COLLISION_RADIUS + enemy.collision_radius + 10.0
		assert(enemy.global_position.distance_to(player.global_position) >= minimum_player_distance, "怪物进入玩家近战安全环")
	for first in range(enemies.size()):
		for second in range(first + 1, enemies.size()):
			var minimum_enemy_distance := enemies[first].collision_radius + enemies[second].collision_radius - 0.75
			assert(enemies[first].global_position.distance_to(enemies[second].global_position) >= minimum_enemy_distance, "怪物之间发生实体重叠")

	var player_shadow_top := 4.0 - 23.0 * 0.36
	var monster_shadow_top := ArtSpec.MONSTER_COLLISION_RADIUS * 0.28 - ArtSpec.MONSTER_COLLISION_RADIUS * 0.36
	assert(player_shadow_top < 0.0 and monster_shadow_top < 0.0, "接地阴影上缘没有覆盖脚底锚点")
	assert(player.visual.position.y == 4.0, "人物视觉层没有压入地面阴影")
	for enemy: EnemyActor in enemies:
		assert(enemy.visual.position.y == 4.0, "普通怪物视觉层没有压入地面阴影")
	assert(y_sort_enabled, "战斗场景没有启用Y轴渲染排序")
	print("CROWD_GROUNDING_PASS：8怪拥挤无穿模、碰撞层隔离、Y轴排序与脚底阴影接地正常")
	get_tree().quit(0)
