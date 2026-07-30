extends Node


const MonsterOverheadScript := preload("res://scripts/monster_overhead.gd")
const EXPECTED_NAMES := ["骷髅", "掷斧骷髅", "骷髅战士", "骷髅战将", "僵尸1", "僵尸2", "僵尸3", "僵尸4", "僵尸5", "骷髅精灵", "尸王"]
const EXPECTED_FRAMES := {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 10}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var manifest: Dictionary = GameData.bich_undead_art
	assert(int(manifest.get("schemaVersion", 0)) == 1, "亡灵客户端资源表版本错误")
	assert(manifest.get("clientFormulaEvidence", {}).get("confidence", "") == "A", "客户端库/偏移/动作公式必须保持A源")
	assert(manifest.get("rejectedMappings", []).is_empty(), "目标亡灵仍有被拒绝的客户端动作")
	assert(int(manifest.get("generatedAtlases", 0)) == 55, "五动作图集数量错误")
	var mappings: Dictionary = manifest.get("runtimeMappings", {})
	assert(mappings.size() == EXPECTED_NAMES.size(), "亡灵映射覆盖数量错误")
	for monster_name: String in EXPECTED_NAMES:
		var mapping: Dictionary = mappings.get(monster_name, {})
		assert(mapping.get("mappingConfidence", "") == "B", "名称到Appearance不得冒充客户端A源")
		var frame_size: Array = mapping.get("frameSize", [])
		var foot_anchor: Array = mapping.get("footAnchor", [])
		var content_bounds: Array = mapping.get("contentBounds", [])
		var content_padding := int(mapping.get("contentPadding", 0))
		var health_bar_tops: Array = mapping.get("healthBarTopByDirection", [])
		assert(frame_size.size() == 2 and int(frame_size[0]) > 0 and int(frame_size[1]) > 0, "帧尺寸错误：%s" % monster_name)
		assert(foot_anchor.size() == 2 and content_bounds.size() == 4, "脚底锚点或可见边界缺失：%s" % monster_name)
		assert(content_padding >= 8 and mapping.get("atlasCellIsolation", "") == "per_frame", "图集没有逐帧隔离：%s" % monster_name)
		assert(health_bar_tops.size() == 8, "血条没有八方向身体顶边：%s" % monster_name)
		for top: Variant in health_bar_tops:
			assert(int(top) >= content_padding and int(top) < int(frame_size[1]) - content_padding, "血条身体顶边越界：%s" % monster_name)
		for action_name: String in EXPECTED_FRAMES.keys():
			var action: Dictionary = mapping.get("actions", {}).get(action_name, {})
			assert(int(action.get("framesPerDirection", 0)) == EXPECTED_FRAMES[action_name], "%s %s帧数错误" % [monster_name, action_name])
			assert(action.get("missingFrames", []).is_empty(), "%s %s存在缺帧" % [monster_name, action_name])
			assert(ResourceLoader.exists(str(action.get("path", ""))), "%s %s图集不存在" % [monster_name, action_name])

	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO
	for index in range(EXPECTED_NAMES.size()):
		var monster_name: String = EXPECTED_NAMES[index]
		var boss := monster_name in ["骷髅精灵", "尸王"]
		var enemy := EnemyActor.new()
		enemy.setup({"name": monster_name, "hp": 500 if boss else 100, "attackMin": 1, "attackMax": 2}, player, boss)
		enemy.global_position = Vector2(index * 170, 0)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		player.global_position = enemy.global_position + Vector2(200, 0)
		if boss:
			assert(is_equal_approx(enemy.overhead.position.y, enemy.health_bar_anchor_y()), "%s头顶层未按固定动画帧锚点定位" % monster_name)
			assert(enemy.overhead.name_global_bottom_y() < enemy.overhead.bar_global_top_y(), "%s名称没有固定在大型客户端Boss血条上方" % monster_name)
		var visual: MonsterVisual = enemy.get_node("MonsterVisual")
		var sprite: Sprite2D = visual.get_node("BodySprite")
		var mapping: Dictionary = mappings[monster_name]
		var expected_frame := Vector2i(int(mapping.frameSize[0]), int(mapping.frameSize[1]))
		var expected_foot := Vector2i(int(mapping.footAnchor[0]), int(mapping.footAnchor[1]))
		assert(visual.uses_final_art() and visual.frame_size == expected_frame, "%s未启用客户端正式资源" % monster_name)
		assert(visual.actor_ground_offset == Vector2i(32, 28), "%s 未采用经典客户端角色原点迁移量" % monster_name)
		assert(sprite.position == -Vector2(expected_foot + visual.actor_ground_offset), "%s 待机绘制原点迁移错误" % monster_name)
		assert(sprite.texture.get_size() == Vector2(expected_frame.x * 4, expected_frame.y * 8), "%s 待机图集尺寸错误" % monster_name)
		var expected_bar_y := (
			visual.position.y
			+ sprite.position.y
			+ visual.stable_body_top()
			- MonsterOverheadScript.HEALTH_BAR_HEIGHT
			- MonsterVisual.HEALTH_BAR_BODY_GAP
		)
		assert(is_equal_approx(enemy.health_bar_anchor_y(), expected_bar_y), "%s 血条未固定在完整动画帧单元上方" % monster_name)
		assert(enemy.ground_indicator_center().is_equal_approx(visual.position + visual.visual_foot_offset()), "%s 脚底光圈未采用人工视觉脚点" % monster_name)
		enemy.facing = Vector2.RIGHT
		enemy.movement_facing = Vector2.RIGHT
		enemy.velocity = Vector2.RIGHT * 50.0
		visual._process(0.12)
		assert(visual.current_state == "walk" and visual.current_direction == 2 and sprite.texture.get_size() == Vector2(expected_frame.x * 6, expected_frame.y * 8), "%s移动动作错误" % monster_name)
		visual.play_attack()
		visual._process(0.02)
		assert(visual.current_state == "attack" and sprite.texture.get_size() == Vector2(expected_frame.x * 6, expected_frame.y * 8), "%s攻击动作错误" % monster_name)
		visual._attack_remaining = 0.0
		visual.play_hit()
		visual._process(0.02)
		assert(visual.current_state == "hit" and sprite.texture.get_size() == Vector2(expected_frame.x * 2, expected_frame.y * 8), "%s受击动作错误" % monster_name)
		visual.play_death()
		visual._process(0.02)
		assert(visual.current_state == "death" and sprite.texture.get_size() == Vector2(expected_frame.x * 10, expected_frame.y * 8), "%s死亡动作错误" % monster_name)

	print("BICH_UNDEAD_CLIENT_ART_PASS：11类亡灵五动作、八方向、源帧、锚点和运行切换完整")
	get_tree().quit(0)
