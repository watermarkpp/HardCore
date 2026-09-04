extends Node


const ITEM_NAME := "天魔神甲"
const ITEM_ID := 140
const EXPECTED_FEATURE := 12
const EXPECTED_ACTIONS := ["idle", "walk", "attack", "cast", "hit", "death"]
const PROFILE_ID := "test.character.warrior.chiyue.v1"


func _ready() -> void:
	_run.call_deferred()


func _opaque_pixel_count(texture: Texture2D, frame_size: Vector2i, frame_index: int, direction: int) -> int:
	var image := texture.get_image()
	assert(image != null and not image.is_empty(), "天魔神甲导入纹理必须可读")
	var origin := Vector2i(frame_index * frame_size.x, direction * frame_size.y)
	var count := 0
	for y: int in range(origin.y, origin.y + frame_size.y):
		for x: int in range(origin.x, origin.x + frame_size.x):
			if image.get_pixel(x, y).a > 0.99:
				count += 1
	return count


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var sandbox_id := str(Time.get_ticks_usec())
	PlayerState.profile_directory = "user://equipment_warrior_chiyue_world_dress_test/%s/characters" % sandbox_id
	PlayerState.profile_index_path = "user://equipment_warrior_chiyue_world_dress_test/%s/character_profiles.json" % sandbox_id
	var roster_result := PlayerState.ensure_equipment_skill_test_roster()
	assert(int(roster_result.get("created", 0)) == 9, "真实测试角色入口必须生成九个职业套装档案")
	assert(PlayerState.select_character(PROFILE_ID), "必须能通过稳定 profileId 选择战士赤月测试角色")
	assert(PlayerState.profession == "战士")
	assert(PlayerState.gender == "男")
	var saved_armor: Dictionary = PlayerState.equipment.get("衣服", {})
	assert(str(saved_armor.get("name", "")) == ITEM_NAME, "真实赤月测试角色必须穿天魔神甲")

	var item := GameData.get_item(ITEM_NAME)
	assert(not item.is_empty(), "运行时主装备表必须能按名称解析天魔神甲")
	assert(int(item.get("itemId", -1)) == ITEM_ID, "天魔神甲运行时记录必须保留 itemId=140")
	var resolved := GameData.item_world_appearance(int(item.get("itemId", -1)), PlayerState.gender)
	assert(str(resolved.get("appearanceType", "")) == "dressAppearance")
	var appearance: Dictionary = resolved.get("appearance", {})
	assert(int(appearance.get("feature", -1)) == EXPECTED_FEATURE)

	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	var visual: Node = player.visual
	assert(visual != null and visual.visible, "赤月战士世界人物必须可见")
	assert(visual._dress_action_textures.size() == EXPECTED_ACTIONS.size(), "天魔神甲必须加载六套世界动作")
	assert(visual._body_frame_size == Vector2i(192, 160))
	assert(visual._body_source_anchor == Vector2i(64, 80))
	assert(visual.sprite != null and visual.sprite.visible, "天魔神甲身体 Sprite 必须可见")
	assert(is_equal_approx(visual.sprite.modulate.a, 1.0))
	assert(is_equal_approx(visual.sprite.self_modulate.a, 1.0))

	for action: String in EXPECTED_ACTIONS:
		var texture: Texture2D = visual._dress_action_textures.get(action, null)
		assert(texture != null, "天魔神甲缺少世界动作：%s" % action)
		var action_record: Dictionary = appearance.get("actions", {}).get(action, {})
		assert(texture.resource_path == str(action_record.get("path", "")), "运行时必须使用正式天魔神甲动作资源")
		var frame_count := int(action_record.get("framesPerDirection", 0))
		assert(frame_count > 0)
		for direction: int in 8:
			for frame: int in frame_count:
				assert(
					_opaque_pixel_count(texture, Vector2i(192, 160), frame, direction) > 0,
					"天魔神甲不得出现透明空帧：%s direction=%d frame=%d" % [action, direction, frame]
				)

	visual.current_state = "idle"
	visual.current_direction = 0
	visual.current_frame = 0
	visual._process(0.0)
	assert(visual.sprite.texture == visual._dress_action_textures["idle"], "世界角色身体必须由天魔神甲替换基础裸体")
	assert(_opaque_pixel_count(visual.sprite.texture, Vector2i(192, 160), 0, 0) > 0)

	player.queue_free()
	await get_tree().process_frame

	# Device/legacy saves do not all carry the same visible-name field. The
	# world renderer must accept the same stable instance keys as the UI preview.
	var compatibility_records := [
		{"label": "item_id_only", "record": {"item_id": ITEM_ID, "durability": 35}},
		{"label": "itemId_only", "record": {"itemId": ITEM_ID, "durability": 35}},
		{"label": "itemName_only", "record": {"itemName": ITEM_NAME, "durability": 35}},
	]
	for fixture: Dictionary in compatibility_records:
		PlayerState.equipment["衣服"] = fixture.record
		var compatibility_player := PlayerCharacter.new()
		add_child(compatibility_player)
		await get_tree().process_frame
		await get_tree().process_frame
		var compatibility_visual: Node = compatibility_player.visual
		assert(
			compatibility_visual._stable_item_id_for_equipped(fixture.record, {}) == ITEM_ID,
			"%s 必须精确解析为 itemId=140" % fixture.label
		)
		assert(
			compatibility_visual._dress_action_textures.size() == EXPECTED_ACTIONS.size(),
			"%s 必须加载天魔神甲六动作" % fixture.label
		)
		assert(
			compatibility_visual.sprite.texture == compatibility_visual._dress_action_textures["idle"],
			"%s 不得退回裸体基础人物" % fixture.label
		)
		compatibility_player.queue_free()
		await get_tree().process_frame

	print("EQUIPMENT_WARRIOR_CHIYUE_WORLD_DRESS_PASS itemId=140 feature=12 actions=6 save_variants=3")
	get_tree().quit(0)
