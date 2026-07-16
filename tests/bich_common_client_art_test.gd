extends Node


const EXPECTED := {
	"森林雪人": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 4},
	"食人花": {"idle": 4, "walk": 8, "attack": 6, "hit": 2, "death": 10},
	"洞蛆": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 4},
	"多钩猫": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 10},
	"钉耙猫": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 10},
	"稻草人": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 10},
	"半兽人": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 10},
	"山洞蝙蝠": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 10},
	"蝎子": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 10},
	"毒蜘蛛": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 10},
	"蛤蟆": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 10},
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var manifest: Dictionary = GameData.bich_common_art
	assert(int(manifest.get("schemaVersion", 0)) == 2, "比奇客户端怪物清单版本错误")
	assert(manifest.get("clientFormulaEvidence", {}).get("confidence", "") == "A", "客户端公式证据必须为A级")
	assert(manifest.get("rejectedMappings", []).is_empty(), "比奇常见怪仍有被拒绝动作")
	assert(int(manifest.get("generatedAtlases", 0)) == EXPECTED.size() * 5, "比奇常见怪图集数量错误")
	var mappings: Dictionary = manifest.get("runtimeMappings", {})
	assert(mappings.size() == EXPECTED.size(), "比奇常见怪映射覆盖数量错误")

	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(2000, 0)
	for monster_name: String in EXPECTED:
		var mapping: Dictionary = mappings.get(monster_name, {})
		assert(mapping.get("mappingConfidence", "") == "A", "本地像素已核定的映射未保持A级：%s" % monster_name)
		assert(int(mapping.get("directions", 0)) == 8, "%s 方向数错误" % monster_name)
		var frame_size_values: Array = mapping.get("frameSize", [])
		var foot_values: Array = mapping.get("footAnchor", [])
		assert(frame_size_values.size() == 2 and foot_values.size() == 2, "%s 锚点元数据缺失" % monster_name)
		var frame_size := Vector2i(int(frame_size_values[0]), int(frame_size_values[1]))
		var foot_anchor := Vector2i(int(foot_values[0]), int(foot_values[1]))
		for action_name: String in EXPECTED[monster_name]:
			var action: Dictionary = mapping.get("actions", {}).get(action_name, {})
			var frame_count: int = EXPECTED[monster_name][action_name]
			assert(int(action.get("framesPerDirection", 0)) == frame_count, "%s %s 帧数错误" % [monster_name, action_name])
			assert(action.get("missingFrames", []).is_empty(), "%s %s 存在缺帧" % [monster_name, action_name])
			assert(ResourceLoader.exists(str(action.get("path", ""))), "%s %s 图集不存在" % [monster_name, action_name])

		var enemy := EnemyActor.new()
		enemy.setup({"name": monster_name, "hp": 100, "attackMin": 1, "attackMax": 2}, player, false)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		var visual: MonsterVisual = enemy.get_node("MonsterVisual")
		var sprite: Sprite2D = visual.get_node("BodySprite")
		assert(visual.uses_final_art(), "%s 未启用客户端正式资源" % monster_name)
		assert(visual.frame_size == frame_size, "%s 运行帧尺寸与清单不一致" % monster_name)
		assert(sprite.position == -Vector2(foot_anchor), "%s 脚底锚点与清单不一致" % monster_name)
		enemy.facing = Vector2.RIGHT
		enemy.movement_facing = Vector2.RIGHT
		enemy.velocity = Vector2.RIGHT * 50.0
		visual._process(0.12)
		assert(visual.current_state == "walk" and visual.current_direction == 2, "%s 移动方向或状态错误" % monster_name)
		assert(sprite.texture.get_size() == Vector2(frame_size.x * EXPECTED[monster_name]["walk"], frame_size.y * 8), "%s 移动图集尺寸错误" % monster_name)
		visual.play_death()
		visual._process(0.02)
		assert(sprite.texture.get_size() == Vector2(frame_size.x * EXPECTED[monster_name]["death"], frame_size.y * 8), "%s 死亡图集尺寸错误" % monster_name)
		enemy.queue_free()

	print("BICH_COMMON_CLIENT_ART_PASS：11类比奇常见怪客户端五动作、八方向、源帧、锚点与运行切换完整")
	get_tree().quit(0)
