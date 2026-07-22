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
const RUNTIME_SAMPLES := ["毒蜘蛛", "山洞蝙蝠"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var manifest: Dictionary = GameData.bich_common_art
	assert(int(manifest.get("schemaVersion", 0)) == 2, "比奇客户端怪物清单版本错误")
	assert(manifest.get("clientFormulaEvidence", {}).get("confidence", "") == "A", "客户端公式证据必须为A级")
	assert(manifest.get("rejectedMappings", []).is_empty(), "比奇常见怪仍有被拒绝动作")
	var mappings: Dictionary = manifest.get("runtimeMappings", {})
	assert(int(manifest.get("generatedAtlases", 0)) == mappings.size() * 5, "比奇常见怪图集数量错误")
	assert(mappings.size() >= EXPECTED.size(), "比奇常见怪映射覆盖数量错误")

	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(2000, 0)
	for monster_name: String in EXPECTED:
		var mapping: Dictionary = mappings.get(monster_name, {})
		var expected_confidence := "B" if monster_name in ["半兽人", "毒蜘蛛"] else "A"
		assert(mapping.get("mappingConfidence", "") == expected_confidence, "名称到外观证据等级错误：%s" % monster_name)
		assert(int(mapping.get("directions", 0)) == 8, "%s 方向数错误" % monster_name)
		var frame_size_values: Array = mapping.get("frameSize", [])
		var foot_values: Array = mapping.get("footAnchor", [])
		var health_bar_tops: Array = mapping.get("healthBarTopByDirection", [])
		assert(frame_size_values.size() == 2 and foot_values.size() == 2, "%s 锚点元数据缺失" % monster_name)
		assert(mapping.get("atlasCellIsolation", "") == "per_frame" and health_bar_tops.size() == 8, "%s 缺少逐帧隔离或八方向血条顶边" % monster_name)
		var frame_size := Vector2i(int(frame_size_values[0]), int(frame_size_values[1]))
		var foot_anchor := Vector2i(int(foot_values[0]), int(foot_values[1]))
		for action_name: String in EXPECTED[monster_name]:
			var action: Dictionary = mapping.get("actions", {}).get(action_name, {})
			var frame_count: int = EXPECTED[monster_name][action_name]
			assert(int(action.get("framesPerDirection", 0)) == frame_count, "%s %s 帧数错误" % [monster_name, action_name])
			assert(action.get("missingFrames", []).is_empty(), "%s %s 存在缺帧" % [monster_name, action_name])
			assert(ResourceLoader.exists(str(action.get("path", ""))), "%s %s 图集不存在" % [monster_name, action_name])
			if monster_name == "食人花":
				assert(int(action.get("sourceDirectionStride", -1)) == 0, "食人花 %s 仍把相邻状态段误当成方向" % action_name)
				assert(int(action.get("fixedSourceDirection", -1)) == 0, "食人花 %s 未固定到唯一有效源方向" % action_name)
				_assert_direction_rows_identical(str(action.get("path", "")), frame_size, frame_count, action_name)
		if monster_name == "食人花":
			assert(mapping.get("directionPolicy", "") == "fixed_source_direction", "食人花未声明固定体视觉方向策略")
		if monster_name not in RUNTIME_SAMPLES:
			continue

		var enemy := EnemyActor.new()
		enemy.setup({"name": monster_name, "hp": 100, "attackMin": 1, "attackMax": 2}, player, false)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		player.global_position = enemy.global_position + Vector2(200, 0)
		var visual: MonsterVisual = enemy.get_node("MonsterVisual")
		var sprite: Sprite2D = visual.get_node("BodySprite")
		assert(visual.uses_final_art(), "%s 未启用客户端正式资源" % monster_name)
		assert(visual.frame_size == frame_size, "%s 运行帧尺寸与清单不一致" % monster_name)
		assert(visual.actor_ground_offset == Vector2i(32, 28), "%s 未采用经典客户端角色原点迁移量" % monster_name)
		assert(sprite.position == -Vector2(foot_anchor + visual.actor_ground_offset), "%s 绘制原点未迁移到统一地面原点" % monster_name)
		var expected_bar_y := visual.position.y + sprite.position.y + int(health_bar_tops[visual.current_direction]) - MonsterVisual.HEALTH_BAR_FRAME_MARGIN
		assert(is_equal_approx(enemy.health_bar_anchor_y(), expected_bar_y), "%s 血条未按当前朝向身体顶边定位" % monster_name)
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

	print("BICH_COMMON_CLIENT_ART_PASS：既有比奇常见怪客户端五动作、八方向、源帧、锚点与证据等级完整")
	get_tree().quit(0)


func _assert_direction_rows_identical(path: String, frame_size: Vector2i, frame_count: int, action_name: String) -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert(image != null and not image.is_empty(), "食人花 %s 图集无法读取" % action_name)
	var row_size := Vector2i(frame_size.x * frame_count, frame_size.y)
	var reference := image.get_region(Rect2i(Vector2i.ZERO, row_size)).get_data()
	for direction in range(1, 8):
		var row := image.get_region(Rect2i(Vector2i(0, frame_size.y * direction), row_size)).get_data()
		assert(row == reference, "食人花 %s 第%d方向没有复用固定体源帧" % [action_name, direction])
