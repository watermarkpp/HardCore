extends Node

const OUTPUT_DIRECTORY := "res://outputs/visual_acceptance/paper_doll"
const TEST_DIRECTORY := "user://paper_doll_classic_avatar_capture_profiles"
const TEST_INDEX := "user://paper_doll_classic_avatar_capture_index.json"
const LOADOUTS_PATH := "res://assets/data/equipment_test_loadouts.json"

var _old_directory := ""
var _old_index := ""
var _old_test_mode := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_prepare_equipment_skill_roster()
	assert(PlayerState.select_character("test.character.warrior.chiyue.v1"), "Unable to load warrior Chiyue test profile")
	var character_select: Control = load("res://scenes/character_select.tscn").instantiate()
	character_select.suppress_scene_change_for_test = true
	add_child(character_select)
	await _settle_frames()
	_assert_classic_preview(character_select.preview_visual_root.get_child(0) as EquipmentCharacterPreview, "人物选择")
	_capture("character_select_warrior_saint.png")
	character_select.queue_free()
	await get_tree().process_frame

	assert(PlayerState.select_character("test.character.taoist.chiyue.v1"), "Unable to load taoist Chiyue test profile")
	var inventory := InventoryPanel.new()
	inventory.name = "InventoryPanel"
	add_child(inventory)
	await _settle_frames()
	_assert_classic_preview(inventory.character_preview as EquipmentCharacterPreview, "人物与背包")
	_capture("inventory_taoist_chiyue.png")
	inventory.queue_free()
	await get_tree().process_frame
	await _capture_profession_tier_sheets()
	_restore()
	print("PAPER_DOLL_CLASSIC_AVATAR_PLAYER_UI_CAPTURE_PASS")
	get_tree().quit(0)


func _settle_frames() -> void:
	for frame in range(5):
		await get_tree().process_frame
	# The project test runner uses the dummy headless renderer, which never
	# emits frame_post_draw. The controlled OpenGL console review run still
	# waits for the actual draw before writing PNG evidence.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _assert_classic_preview(preview: EquipmentCharacterPreview, label: String) -> void:
	assert(preview != null, "%s缺少纸娃娃" % label)
	assert(preview.presentation_mode == "classic_avatar", "%s没有使用清晰透明原客户端纸娃娃" % label)
	assert(not preview.uses_world_avatar(), "%s错误使用低清世界图集" % label)
	assert(not preview.uses_original_client_stage(), "%s错误绘制完整装备页背景或槽位" % label)
	for slot: String in ["衣服", "武器", "头盔"]:
		assert(preview.paper_layer_source_index(slot) >= 0, "%s缺少%s真实纸娃娃层" % [label, slot])
	assert(preview.original_stage_draw_commands().is_empty(), "%s出现了完整装备页背景或槽位" % label)


func _prepare_equipment_skill_roster() -> void:
	_old_directory = PlayerState.profile_directory
	_old_index = PlayerState.profile_index_path
	_old_test_mode = PlayerState.test_mode
	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.test_mode = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	PlayerState.ensure_equipment_skill_test_roster()


func _capture_profession_tier_sheets() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOADOUTS_PATH))
	assert(parsed is Dictionary, "Unable to read the nine-loadout paper-doll contract")
	var loadouts: Array = parsed.get("loadouts", [])
	assert(loadouts.size() == 9, "Paper-doll review must cover all three professions and all three tiers")
	for profession in ["warrior", "wizard", "taoist"]:
		var profession_loadouts: Array = []
		for loadout: Dictionary in loadouts:
			if ProfessionRules.profession_id(str(loadout.get("profession", ""))) == profession:
				profession_loadouts.append(loadout)
		assert(profession_loadouts.size() == 3, "%s visual review must include Wooma, Zuma and Chiyue" % profession)
		await _capture_profession_tier_sheet(profession, profession_loadouts)


func _capture_profession_tier_sheet(profession: String, loadouts: Array) -> void:
	var sheet := Control.new()
	sheet.name = "ClassicAvatarTierSheet_%s" % profession
	sheet.size = get_viewport().get_visible_rect().size
	add_child(sheet)
	var cell_width := sheet.size.x / 3.0
	# Keep the original 199px paper-doll canvas at its native presentation scale
	# and give it a compact, fixed-height stage.  A tall Control moves the foot
	# anchor down with it, which was the source of prior screenshots being cut.
	var preview_size := Vector2(minf(460.0, cell_width - 48.0), 390.0)
	for index in loadouts.size():
		var loadout: Dictionary = loadouts[index]
		var tier_id := str(loadout.get("tierId", ""))
		if tier_id == "wooma":
			tier_id = "woma"
		var profile_id := "test.character.%s.%s.v1" % [
			ProfessionRules.profession_id(str(loadout.get("profession", ""))),
			tier_id,
		]
		assert(PlayerState.select_character(profile_id), "Unable to load review profile: %s" % profile_id)
		var preview := EquipmentCharacterPreview.new()
		preview.name = "ClassicAvatar_%s" % profile_id
		preview.configure_presentation_mode("classic_avatar")
		preview.configure_profile(str(loadout.get("profession", "")), PlayerState.equipment.duplicate(true))
		var column := index
		preview.position = Vector2(
			cell_width * column + (cell_width - preview_size.x) * 0.5,
			80.0
		)
		preview.size = preview_size
		sheet.add_child(preview)
		await get_tree().process_frame
		_assert_classic_preview(preview, str(loadout.get("loadoutId", profile_id)))
		var title := Label.new()
		title.text = "%s / %s" % [str(loadout.get("profession", "")), str(loadout.get("tierName", ""))]
		title.position = Vector2(cell_width * column, 498.0)
		title.size = Vector2(cell_width, 46.0)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 26)
		title.add_theme_color_override("font_color", Color(0.94, 0.76, 0.36, 1.0))
		sheet.add_child(title)
	await _settle_frames()
	_capture("classic_avatar_%s_three_tiers.png" % profession)
	sheet.queue_free()
	await get_tree().process_frame


func _capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("PAPER_DOLL_CLASSIC_CAPTURE_SKIPPED_HEADLESS %s" % file_name)
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		# run_godot_tests uses the dummy headless renderer. This capture scene is
		# still deterministic there, while a controlled GL console run writes the
		# exact same two player-facing screens for visual review.
		print("PAPER_DOLL_WORLD_AVATAR_CAPTURE_SKIPPED_HEADLESS %s" % file_name)
		return
	var output_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(output_directory)
	assert(image.save_png(output_directory.path_join(file_name)) == OK, "无法保存纸娃娃UI截图")


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "无法写入纸娃娃UI截图存档")
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


func _restore() -> void:
	PlayerState.profile_directory = _old_directory
	PlayerState.profile_index_path = _old_index
	PlayerState.test_mode = _old_test_mode
	PlayerState.active_profile_id = ""
	var absolute := ProjectSettings.globalize_path(TEST_DIRECTORY)
	var directory := DirAccess.open(TEST_DIRECTORY)
	if directory != null:
		for file_name: String in directory.get_files():
			DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)
	for suffix: String in ["", ".tmp", ".bak"]:
		var index_path := ProjectSettings.globalize_path(TEST_INDEX + suffix)
		if FileAccess.file_exists(TEST_INDEX + suffix):
			DirAccess.remove_absolute(index_path)
