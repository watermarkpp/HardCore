extends Node

const PreviewScript := preload("res://scripts/equipment_character_preview.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	PlayerState.equipment = {
		"武器": {"name": "裁决之杖"},
		"衣服": {"name": "战神盔甲(男)"},
		"头盔": {"name": "黑铁头盔"},
		"项链": {},
		"左手镯": {},
		"右手镯": {},
		"左戒指": {},
		"右戒指": {},
	}
	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame

	var preview: EquipmentCharacterPreview = panel.character_preview
	assert(preview.center_on_opaque_bounds, "背包装备纸娃娃没有启用alpha边界自动居中")
	assert(
		preview.get_meta("horizontal_alignment_contract", "") == PreviewScript.OPAQUE_CENTER_CONTRACT_ID,
		"背包装备纸娃娃没有声明稳定自动居中契约"
	)
	var bounds := preview.composition_opaque_bounds()
	assert(bounds.has_area(), "战士祖玛装备合成后没有得到真实非透明像素边界")
	var origin := preview.composition_draw_origin()
	var visible_center_x := origin.x + bounds.get_center().x * preview.preview_scale
	assert(
		is_equal_approx(visible_center_x, preview.size.x * 0.5),
		"战士装备合成后的alpha边界没有居中于装备展示框：%s" % visible_center_x
	)
	var legacy_canvas_origin_x := (preview.size.x - PreviewScript.ORIGINAL_CANVAS_SIZE.x * preview.preview_scale) * 0.5
	assert(origin.x > legacy_canvas_origin_x, "战士纸娃娃没有依据真实alpha边界完成轻微向右校正")
	assert(preview._body_texture != null and preview._weapon_texture != null and preview._helmet_texture != null, "战士衣服、武器或头盔层发生退化")

	var source_document: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(PreviewScript.PAPER_DOLL_MANIFEST)
	)
	var profession_manifest := {
		"professionManifests": {
			"warrior": {
				"professionId": "warrior",
				"professionName": "战士",
				"base": source_document.base,
				"hair": source_document.hair,
				"canvasSize": source_document.composition.canvasSize,
				"footAnchor": [84, 186],
			},
			"wizard": {
				"professionId": "wizard",
				"professionName": "法师",
				"base": source_document.base,
				"hair": source_document.hair,
				"canvasSize": source_document.composition.canvasSize,
				"footAnchor": [84, 186],
			},
			"taoist": {
				"professionId": "taoist",
				"professionName": "道士",
				"base": source_document.base,
				"hair": source_document.hair,
				"canvasSize": source_document.composition.canvasSize,
				"footAnchor": [84, 186],
			},
		},
		"itemsById": {
			"weapon": {
				"itemName": "裁决之杖",
				"paperDoll": source_document.runtimeMappings["裁决之杖"],
			},
			"armor": {
				"itemName": "战神盔甲(男)",
				"paperDoll": source_document.runtimeMappings["战神盔甲(男)"],
			},
			"helmet": {
				"itemName": "黑铁头盔",
				"paperDoll": source_document.runtimeMappings["黑铁头盔"],
			},
		},
	}
	for profession_name: String in ["战士", "法师", "道士"]:
		preview.configure_source_document(profession_manifest)
		preview.configure_profile(profession_name, PlayerState.equipment)
		var profession_bounds := preview.composition_opaque_bounds()
		var profession_origin := preview.composition_draw_origin()
		assert(preview.has_renderable_assets(), "%s没有通过统一professionManifests入口加载正式纸娃娃" % profession_name)
		assert(
			is_equal_approx(
				profession_origin.x + profession_bounds.get_center().x * preview.preview_scale,
				preview.size.x * 0.5
			),
			"%s没有复用统一alpha边界居中契约" % profession_name
		)

	print("EQUIPMENT_CHARACTER_PREVIEW_CENTERING_PASS：背包战士右校正、三职业目录注入和全装备alpha边界居中正常")
	get_tree().quit(0)
