extends Node


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
		assert(frame_size.size() == 2 and int(frame_size[0]) == 160 and int(frame_size[1]) == 160, "帧尺寸错误：%s" % monster_name)
		assert(foot_anchor.size() == 2 and int(foot_anchor[0]) == 80 and int(foot_anchor[1]) == 138, "脚底锚点错误：%s" % monster_name)
		for action_name: String in EXPECTED_FRAMES.keys():
			var action: Dictionary = mapping.get("actions", {}).get(action_name, {})
			assert(int(action.get("framesPerDirection", 0)) == EXPECTED_FRAMES[action_name], "%s %s帧数错误" % [monster_name, action_name])
			assert(action.get("missingFrames", []).is_empty(), "%s %s存在缺帧" % [monster_name, action_name])
			assert(ResourceLoader.exists(str(action.get("path", ""))), "%s %s图集不存在" % [monster_name, action_name])

	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(2000, 0)
	for index in range(EXPECTED_NAMES.size()):
		var monster_name: String = EXPECTED_NAMES[index]
		var boss := monster_name in ["骷髅精灵", "尸王"]
		var enemy := EnemyActor.new()
		enemy.setup({"name": monster_name, "hp": 500 if boss else 100, "attackMin": 1, "attackMax": 2}, player, boss)
		enemy.global_position = Vector2(index * 170, 0)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		if boss:
			assert(enemy.name_label.position.y == -116.0, "%s名称未避开大型客户端Boss造型" % monster_name)
		var visual: MonsterVisual = enemy.get_node("MonsterVisual")
		var sprite: Sprite2D = visual.get_node("BodySprite")
		assert(visual.uses_final_art() and visual.frame_size == Vector2i(160, 160), "%s未启用客户端正式资源" % monster_name)
		assert(visual.actor_ground_offset == Vector2i(32, 28), "%s 未采用经典客户端角色原点迁移量" % monster_name)
		assert(sprite.position == Vector2(-112, -166) and sprite.texture.get_size() == Vector2(640, 1280), "%s 待机绘制原点迁移或图集尺寸错误" % monster_name)
		enemy.facing = Vector2.RIGHT
		enemy.movement_facing = Vector2.RIGHT
		enemy.velocity = Vector2.RIGHT * 50.0
		visual._process(0.12)
		assert(visual.current_state == "walk" and visual.current_direction == 2 and sprite.texture.get_size() == Vector2(960, 1280), "%s移动动作错误" % monster_name)
		visual.play_attack()
		visual._process(0.02)
		assert(visual.current_state == "attack" and sprite.texture.get_size() == Vector2(960, 1280), "%s攻击动作错误" % monster_name)
		visual._attack_remaining = 0.0
		visual.play_hit()
		visual._process(0.02)
		assert(visual.current_state == "hit" and sprite.texture.get_size() == Vector2(320, 1280), "%s受击动作错误" % monster_name)
		visual.play_death()
		visual._process(0.02)
		assert(visual.current_state == "death" and sprite.texture.get_size() == Vector2(1600, 1280), "%s死亡动作错误" % monster_name)

	print("BICH_UNDEAD_CLIENT_ART_PASS：11类亡灵五动作、八方向、源帧、锚点和运行切换完整")
	get_tree().quit(0)
