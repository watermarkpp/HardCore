extends Node

const PreviewScript := preload("res://scripts/equipment_character_preview.gd")
const LOADOUTS_PATH := "res://assets/data/equipment_test_loadouts.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOADOUTS_PATH))
	assert(parsed is Dictionary, "测试套装合同必须是字典")
	var loadouts: Array = parsed.get("loadouts", [])
	assert(loadouts.size() == 9, "必须覆盖三职业三套装备")
	for loadout: Dictionary in loadouts:
		var preview := PreviewScript.new()
		preview.size = Vector2(288, 224)
		preview.configure_presentation_mode("world_avatar")
		preview.configure_profile(
			str(loadout.get("profession", "战士")),
			_equipment_snapshot(loadout.get("equipment", {}))
		)
		add_child(preview)
		await get_tree().process_frame
		_assert_world_avatar(preview, str(loadout.get("loadoutId", "unknown")))
		preview.queue_free()
	await _assert_classic_avatar(loadouts[0])
	print("PAPER_DOLL_WORLD_AVATAR_LOADOUTS_PASS")
	get_tree().quit(0)


func _equipment_snapshot(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for slot: Variant in value:
		var record: Variant = value[slot]
		if record is Dictionary:
			result[str(slot)] = {
				"itemId": int(record.get("itemId", -1)),
				"item_id": int(record.get("itemId", -1)),
				"name": str(record.get("itemName", "")),
			}
	return result


func _assert_world_avatar(preview: EquipmentCharacterPreview, label: String) -> void:
	assert(preview.presentation_mode == "world_avatar", "%s模式错误" % label)
	assert(preview.uses_world_avatar(), "%s未加载世界人物预览" % label)
	assert(not preview.uses_original_client_stage(), "%s错误加载完整装备页" % label)
	var commands := preview.world_avatar_draw_commands()
	assert(commands.size() == 3, "%s必须含衣服、武器和头盔三个世界外观层" % label)
	var expected_kinds := ["dress", "weapon", "helmet"]
	for index: int in commands.size():
		assert(str(commands[index].get("layerKind", "")) == expected_kinds[index], "%s世界外观层级顺序错误" % label)
	for command: Dictionary in commands:
		var path := str(command.get("path", ""))
		assert(
			path.contains("/world_wear/") or path.contains("/characters/warrior/wear/"),
			"%s错误使用了非世界外观资源：%s" % [label, path]
		)
		assert(not path.contains("/equipped/"), "%s错误使用StateItem装备页贴图" % label)


func _assert_classic_avatar(loadout: Dictionary) -> void:
	var preview := PreviewScript.new()
	preview.size = Vector2(230, 286)
	preview.configure_presentation_mode("classic_avatar")
	preview.configure_profile(
		str(loadout.get("profession", "战士")),
		_equipment_snapshot(loadout.get("equipment", {}))
	)
	add_child(preview)
	await get_tree().process_frame
	assert(not preview.uses_world_avatar(), "classic_avatar不能走世界人物管线")
	assert(not preview.uses_original_client_stage(), "classic_avatar不得绘制完整Prguse装备页")
	assert(preview.has_renderable_assets(), "classic_avatar缺少透明人物基底")
	assert(preview.original_stage_draw_commands().is_empty(), "classic_avatar不应有完整背景/槽位绘制命令")
	preview.queue_free()
