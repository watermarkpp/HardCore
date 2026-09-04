extends Node

const PreviewScript := preload("res://scripts/equipment_character_preview.gd")
const LOADOUTS_PATH := "res://assets/data/equipment_test_loadouts.json"
const TEST_DIRECTORY := "user://paper_doll_world_avatar_real_profiles"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOADOUTS_PATH))
	assert(parsed is Dictionary, "测试套装合同必须是字典")
	var loadouts: Array = parsed.get("loadouts", [])
	assert(loadouts.size() == 9, "必须覆盖三职业三套装备")
	var old_equipment: Dictionary = PlayerState.equipment.duplicate(true)
	_prepare_real_profiles(loadouts)
	for loadout: Dictionary in loadouts:
		var saved_equipment := _read_saved_equipment(str(loadout.get("profileId", "")))
		var migrated_equipment := PlayerState.migrate_equipment_slots(saved_equipment)
		var preview := PreviewScript.new()
		preview.size = Vector2(288, 224)
		preview.configure_presentation_mode("world_avatar")
		preview.configure_profile(
			str(loadout.get("profession", "战士")),
			migrated_equipment
		)
		add_child(preview)
		await get_tree().process_frame
		_assert_world_avatar(preview, str(loadout.get("loadoutId", "unknown")))
		_assert_world_layer_pixels(preview, str(loadout.get("loadoutId", "unknown")))
		preview.queue_free()
	await _assert_live_equipment_refresh(loadouts[0], old_equipment)
	PlayerState.equipment = old_equipment
	for loadout: Dictionary in loadouts:
		await _assert_classic_avatar(loadout)
	_cleanup_profiles()
	print("PAPER_DOLL_WORLD_AVATAR_LOADOUTS_PASS")
	get_tree().quit(0)


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
		assert(command.get("texture") is Texture2D, "%s世界装备层没有运行时纹理" % label)


func _assert_world_layer_pixels(preview: EquipmentCharacterPreview, label: String) -> void:
	for command: Dictionary in preview.world_avatar_draw_commands():
		var texture: Texture2D = command.get("texture")
		var cell: Array = command.get("cell", [])
		assert(cell.size() == 2, "%s世界层缺少源单元尺寸" % label)
		var opaque := _cell_opaque_bounds(texture.get_image(), Vector2i(cell[0], cell[1]), int(command.get("directionRow", 4)))
		assert(opaque.has_area(), "%s世界层South帧没有任何可见像素" % label)
		var min_height := 4.0 if str(command.get("layerKind", "")) == "helmet" else 18.0
		assert(opaque.size.y >= min_height, "%s世界层可见高度异常，疑似空白方向帧" % label)
		var anchor := preview._vector_from_value(command.get("footAnchor", [64, 80]), Vector2(64, 80))
		var target := Rect2(preview.foot_stage_center() - anchor * preview.preview_scale, Vector2(cell[0], cell[1]) * preview.preview_scale)
		assert(
			(target.position + anchor * preview.preview_scale).distance_to(preview.foot_stage_center()) <= 0.01,
			"%s世界层没有以脚点落在舞台中心" % label
		)


func _cell_opaque_bounds(image: Image, cell: Vector2i, row: int) -> Rect2:
	var start_y := cell.y * row
	var end_x := mini(image.get_width(), cell.x)
	var end_y := mini(image.get_height(), start_y + cell.y)
	var min_x := end_x
	var min_y := end_y
	var max_x := -1
	var max_y := -1
	for y in range(start_y, end_y):
		for x in range(0, end_x):
			if image.get_pixel(x, y).a <= 0.02:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2()
	return Rect2(Vector2(min_x, min_y - start_y), Vector2(max_x - min_x + 1, max_y - min_y + 1))


func _assert_live_equipment_refresh(loadout: Dictionary, old_equipment: Dictionary) -> void:
	var preview := PreviewScript.new()
	preview.size = Vector2(230, 286)
	preview.configure_presentation_mode("world_avatar")
	PlayerState.equipment = {}
	add_child(preview)
	await get_tree().process_frame
	var naked_revision := preview.render_revision()
	PlayerState.equipment = PlayerState.migrate_equipment_slots(_read_saved_equipment(str(loadout.get("profileId", ""))))
	PlayerState.equipment_changed.emit()
	await get_tree().process_frame
	assert(preview.render_revision() > naked_revision, "装备变化没有刷新玩家UI纸娃娃")
	assert(preview.world_avatar_draw_commands().size() == 3, "实时穿戴没有显示衣服/武器/头盔三层")
	preview.queue_free()
	PlayerState.equipment = old_equipment


func _prepare_real_profiles(loadouts: Array) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	for loadout: Dictionary in loadouts:
		var profile_id := str(loadout.get("profileId", ""))
		var file := FileAccess.open(TEST_DIRECTORY.path_join(profile_id + ".json"), FileAccess.WRITE)
		assert(file != null, "无法写入纸娃娃真实存档夹具")
		file.store_string(JSON.stringify({"equipment": _saved_equipment(loadout.get("equipment", {}))}))
		file.close()


func _read_saved_equipment(profile_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_DIRECTORY.path_join(profile_id + ".json")))
	assert(parsed is Dictionary, "纸娃娃真实存档无法解析")
	var equipment: Variant = parsed.get("equipment", {})
	assert(equipment is Dictionary, "纸娃娃真实存档缺少装备字段")
	return equipment


func _saved_equipment(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for slot: Variant in value:
		var source: Variant = value[slot]
		if not source is Dictionary:
			continue
		result[str(slot)] = {
			"itemId": int(source.get("itemId", -1)),
			"item_id": int(source.get("itemId", -1)),
			"name": str(source.get("itemName", "")),
		}
	return result


func _cleanup_profiles() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_DIRECTORY)
	var directory := DirAccess.open(TEST_DIRECTORY)
	if directory != null:
		for file_name: String in directory.get_files():
			DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)


func _assert_classic_avatar(loadout: Dictionary) -> void:
	var preview := PreviewScript.new()
	preview.size = Vector2(230, 286)
	preview.configure_presentation_mode("classic_avatar")
	preview.configure_profile(
		str(loadout.get("profession", "战士")),
		PlayerState.migrate_equipment_slots(_saved_equipment(loadout.get("equipment", {})))
	)
	add_child(preview)
	await get_tree().process_frame
	assert(not preview.uses_world_avatar(), "classic_avatar不能走世界人物管线")
	assert(not preview.uses_original_client_stage(), "classic_avatar不得绘制完整Prguse装备页")
	assert(preview.has_renderable_assets(), "classic_avatar缺少透明人物基底")
	assert(preview.original_stage_draw_commands().is_empty(), "classic_avatar不应有完整背景/槽位绘制命令")
	for slot: String in ["衣服", "武器", "头盔"]:
		assert(preview.paper_layer_source_index(slot) >= 0, "%s classic layer missing: %s" % [str(loadout.get("loadoutId", "unknown")), slot])
	_assert_classic_transparent_helmet(preview, str(loadout.get("loadoutId", "unknown")))
	var helmet_slot := str(PreviewScript.PAPER_LAYER_SLOTS[2])
	var loadout_equipment: Dictionary = loadout.get("equipment", {})
	var loadout_helmet: Dictionary = loadout_equipment.get(helmet_slot, {})
	var helmet_name := str(loadout_helmet.get("itemName", ""))
	assert(not helmet_name.is_empty(), "%s lacks a formal helmet name" % str(loadout.get("loadoutId", "unknown")))
	var name_only := {helmet_slot: {"name": helmet_name}}
	assert(not preview._formal_item_id_for_equipped(name_only[helmet_slot]).is_empty(), "%s name-only helmet did not resolve through the formal catalog" % str(loadout.get("loadoutId", "unknown")))
	assert(not preview._classic_head_patch_for_equipped(name_only[helmet_slot]).is_empty(), "%s name-only helmet did not resolve to a formal head patch" % str(loadout.get("loadoutId", "unknown")))
	preview.configure_profile(str(loadout.get("profession", "")), name_only)
	await get_tree().process_frame
	_assert_classic_transparent_helmet(preview, "%s name-only" % str(loadout.get("loadoutId", "unknown")))
	preview.queue_free()


func _assert_classic_transparent_helmet(preview: EquipmentCharacterPreview, label: String) -> void:
	var helmet_slot := str(PreviewScript.PAPER_LAYER_SLOTS[2])
	var helmet_layer := preview.paper_layer_source_record(helmet_slot)
	assert(
		str(helmet_layer.get("layerAssetKind", "")) == "classic_flattened_head_patch",
		"%s classic helmet must use the transparent primary head patch" % label
	)
	var helmet_texture: Texture2D = helmet_layer.get("texture")
	assert(helmet_texture != null, "classic helmet patch texture missing")
	var helmet_image := helmet_texture.get_image()
	assert(helmet_image != null and not helmet_image.is_empty(), "classic helmet patch image missing")
	for point: Vector2i in [
		Vector2i(0, 0),
		Vector2i(helmet_image.get_width() - 1, 0),
		Vector2i(0, helmet_image.get_height() - 1),
		Vector2i(helmet_image.get_width() - 1, helmet_image.get_height() - 1),
	]:
		assert(helmet_image.get_pixelv(point).a <= 0.001, "%s retained a rectangular helmet background corner" % label)
	var mask_path := str(helmet_layer.get("eraseMaskPath", ""))
	var mask_image := Image.load_from_file(ProjectSettings.globalize_path(mask_path))
	assert(mask_image != null and not mask_image.is_empty(), "%s erase mask is missing" % label)
	var base_image := preview._base_texture.get_image()
	var offset := preview._mapping_offset(helmet_layer)
	for y: int in mask_image.get_height():
		for x: int in mask_image.get_width():
			if mask_image.get_pixel(x, y).a <= 0.001:
				continue
			var base_x := int(offset.x) + x
			var base_y := int(offset.y) + y
			assert(base_image.get_pixel(base_x, base_y).a <= 0.001, "%s erase mask did not clear the original head pixel" % label)
