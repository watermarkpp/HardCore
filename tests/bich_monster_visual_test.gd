extends Node


const TARGET_NAMES := ["稻草人", "钉耙猫", "半兽人", "森林雪人", "食人花"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var mappings: Dictionary = GameData.bich_common_art.get("runtimeMappings", {})
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO

	for index in range(TARGET_NAMES.size()):
		var monster_name: String = TARGET_NAMES[index]
		var mapping: Dictionary = mappings.get(monster_name, {})
		var size_values: Array = mapping.get("frameSize", [])
		var frame_size := Vector2i(int(size_values[0]), int(size_values[1]))
		var enemy := EnemyActor.new()
		enemy.setup({"name": monster_name, "hp": 10, "attackMin": 1, "attackMax": 2}, player)
		enemy.global_position = Vector2(index * 180, 0)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		var visual: MonsterVisual = enemy.get_node("MonsterVisual")
		var sprite: Sprite2D = visual.get_node("BodySprite")
		assert(visual.uses_final_art(), "%s 未启用原客户端逐帧资源" % monster_name)
		assert(visual.active_resources.get("animation_source", "") == "classic_client_wil", "%s 仍在使用程序变形动画" % monster_name)
		assert(visual.actor_ground_offset == Vector2i(32, 28), "%s 旧名称入口未采用经典客户端角色原点迁移量" % monster_name)
		enemy.set_targeted(true)
		assert(enemy.ground_indicator_center().is_equal_approx(visual.position + visual.visual_foot_offset()), "%s 锁定光圈未使用人工视觉脚点" % monster_name)
		assert(
			enemy.ground_indicator_radii().is_equal_approx(
				WorldSpatialRules.actor_footprint_radii(enemy.collision_radius)
				* EnemyActor.TARGET_RING_FOOTPRINT_SCALE
			),
			"%s 锁定光圈未按怪物物理体积缩放" % monster_name,
		)
		assert(sprite.texture.get_size() == Vector2(frame_size.x * 4, frame_size.y * 8), "%s 待机图集尺寸错误" % monster_name)
		enemy.facing = Vector2.RIGHT
		enemy.movement_facing = Vector2.RIGHT
		if monster_name == "食人花":
			assert(enemy.move_speed == 0.0 and enemy.attack_range == 78.0, "食人花固定怪参数错误")
			visual._process(0.12)
			assert(visual.active_resources.get("direction_policy", "") == "fixed_source_direction", "食人花未加载固定源方向策略")
			assert(visual.current_state == "idle" and visual.current_direction == 0, "食人花仍被玩家方向带偏到相邻状态帧")
		else:
			enemy.velocity = Vector2.RIGHT * 50.0
			visual._process(0.12)
			assert(visual.current_state == "walk" and visual.current_direction == 2, "%s 移动方向错误" % monster_name)
		visual.play_attack()
		visual._process(0.05)
		assert(visual.current_state == "attack", "%s 攻击状态错误" % monster_name)
		visual._attack_remaining = 0.0
		visual.play_hit()
		visual._process(0.02)
		assert(visual.current_state == "hit", "%s 受击状态错误" % monster_name)
		visual.play_death()
		visual._process(0.02)
		assert(visual.current_state == "death", "%s 死亡状态错误" % monster_name)
		enemy.queue_free()

	var catalog_file := FileAccess.open("res://assets/data/runtime/monster_animation_catalog.json", FileAccess.READ)
	var catalog: Dictionary = JSON.parse_string(catalog_file.get_as_text()) if catalog_file != null else {}
	var rows: Dictionary = {}
	for value: Variant in catalog.get("monsters", []):
		if value is Dictionary:
			rows[str(value.get("name", ""))] = value
	for monster_name: String in TARGET_NAMES:
		assert(rows.get(monster_name, {}).get("status", "") == "formal", "%s 未进入正式客户端动画目录" % monster_name)
	for zombie_name: String in ["僵尸1", "僵尸2", "僵尸3", "僵尸4", "僵尸5"]:
		assert(rows.get(zombie_name, {}).get("status", "") == "formal", "%s 仍被目录错误漏登记" % zombie_name)

	print("BICH_MONSTER_VISUAL_PASS：五种原占位怪已切换为客户端原始逐帧动画，僵尸目录漏登记已修复")
	get_tree().quit(0)
