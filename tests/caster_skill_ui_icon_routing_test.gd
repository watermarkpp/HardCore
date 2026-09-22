extends Node

const Catalog := preload("res://scripts/hud_skill_icon_catalog.gd")
const EXPECTED_SKILL_COUNT := 33
const GENERATED_ICON_ROOT := (
	"res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_assert_complete_native_icon_catalog()
	await _assert_skill_panel_uses_generated_icons()
	_assert_hud_uses_generated_icons()
	print(
		"SKILL_UI_ICON_ROUTING_PASS: 33/33技能使用独立128x128透明图标；"
		+ "无施法帧或技能书缩略图回退"
	)
	get_tree().quit(0)


func _assert_complete_native_icon_catalog() -> void:
	var skill_ids := SkillDataLoader.skill_ids()
	assert(skill_ids.size() == EXPECTED_SKILL_COUNT, "正式技能清单必须为33项")
	assert(Catalog.SKILL_TEXTURES.size() == EXPECTED_SKILL_COUNT, "技能图标目录必须完整覆盖33项")
	var seen_paths := {}
	for skill_id: String in skill_ids:
		var skill_name := SkillDataLoader.display_name(skill_id)
		var texture := Catalog.texture_for(skill_name)
		var source_id := Catalog.source_id_for(skill_name)
		var source_path := Catalog.source_path_for(skill_name)
		assert(texture != null, "%s缺少专用图标" % skill_id)
		assert(texture.get_width() == 128 and texture.get_height() == 128, "%s图标不是128x128" % skill_id)
		assert(not source_id.is_empty(), "%s缺少稳定图标ID" % skill_id)
		assert(source_path.begins_with(GENERATED_ICON_ROOT), "%s未使用generated_v2专用图标" % skill_id)
		assert(source_path.ends_with("%s.png" % skill_id.replace(".", "_")), "%s图标文件名未绑定稳定ID" % skill_id)
		assert(not seen_paths.has(source_path), "%s与其他技能共用图标文件" % skill_id)
		seen_paths[source_path] = skill_id
		_assert_png_alpha_contract(skill_id, source_path)


func _assert_png_alpha_contract(skill_id: String, source_path: String) -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(source_path))
	assert(not image.is_empty(), "%s图标PNG无法读取" % skill_id)
	assert(image.get_width() == 128 and image.get_height() == 128, "%s源PNG不是128x128" % skill_id)
	for corner: Vector2i in [Vector2i.ZERO, Vector2i(127, 0), Vector2i(0, 127), Vector2i(127, 127)]:
		assert(image.get_pixelv(corner).a == 0.0, "%s图标四角必须透明" % skill_id)
	var has_visible := false
	var has_partial_alpha := false
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha := image.get_pixel(x, y).a
			has_visible = has_visible or alpha > 0.0
			has_partial_alpha = has_partial_alpha or (alpha > 0.0 and alpha < 1.0)
	assert(has_visible, "%s图标没有可见像素" % skill_id)
	assert(has_partial_alpha, "%s图标缺少抗锯齿透明边缘" % skill_id)


func _assert_skill_panel_uses_generated_icons() -> void:
	for profession_id: String in ["warrior", "wizard", "taoist"]:
		PlayerState.profession = ProfessionRules.profession_display_name(profession_id)
		var panel := SkillPanel.new()
		add_child(panel)
		await get_tree().process_frame
		panel.open_for("技能导师")
		for index in range(panel.skill_entries.size()):
			var skill_name := str(panel.skill_entries[index].get("skillName", ""))
			var skill_id := ProfessionRules.skill_id(skill_name)
			panel._on_skill_selected(index)
			assert(panel.skill_icon.texture == Catalog.texture_for(skill_name), "%s技能面板未使用专用图标" % skill_id)
			assert(str(panel.skill_icon.get_meta("skill_icon_id", "")) == Catalog.source_id_for(skill_name), "%s技能面板图标ID错误" % skill_id)
			assert(str(panel.skill_icon.get_meta("skill_icon_path", "")) == Catalog.source_path_for(skill_name), "%s技能面板图标路径错误" % skill_id)
		panel.queue_free()
		await get_tree().process_frame


func _assert_hud_uses_generated_icons() -> void:
	var hud := GameHUD.new()
	add_child(hud)
	for skill_name: String in ["烈火剑法", "雷电术", "灵魂火符"]:
		PlayerState.quick_slots = [skill_name, "", "", ""]
		hud.set_skill_button_assignments({
			"attack": [skill_name],
			"attack_ring": [skill_name, "", "", "", "", ""],
		})
		hud.update_quick_slots()
		for icon: TextureRect in [hud.attack_slot_icon, hud.attack_ring_skill_icons[0]]:
			assert(icon.texture == Catalog.texture_for(skill_name), "%s HUD未使用专用图标" % skill_name)
			assert(str(icon.get_meta("skill_icon_id", "")) == Catalog.source_id_for(skill_name), "%s HUD图标ID错误" % skill_name)
			assert(str(icon.get_meta("skill_icon_path", "")) == Catalog.source_path_for(skill_name), "%s HUD图标路径错误" % skill_name)
	hud.queue_free()
