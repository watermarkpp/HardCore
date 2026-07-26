extends Node

const PreviewScript := preload("res://scripts/equipment_character_preview.gd")


func _ready() -> void:
	_run.call_deferred()


func _legacy_opaque_centering_contract_reference() -> void:
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


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var source_document: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(PreviewScript.PAPER_DOLL_MANIFEST)
	)
	var weapon_slot := str(PreviewScript.PAPER_LAYER_SLOTS[1])
	var body_slot := str(PreviewScript.PAPER_LAYER_SLOTS[0])
	var helmet_slot := str(PreviewScript.PAPER_LAYER_SLOTS[2])
	var weapon_name := _mapping_name_for_source_index(source_document, 55)
	var body_name := _mapping_name_for_source_index(source_document, 62)
	var helmet_name := _mapping_name_for_source_index(source_document, 344)
	var wide_weapon_name := _widest_mapping_name(source_document, weapon_slot)
	var wide_helmet_name := _widest_mapping_name(source_document, helmet_slot)
	assert(not weapon_name.is_empty() and not body_name.is_empty() and not helmet_name.is_empty())
	assert(not wide_weapon_name.is_empty() and not wide_helmet_name.is_empty())
	assert(_mapping_width(source_document, wide_weapon_name) > _mapping_width(source_document, weapon_name))
	assert(_mapping_width(source_document, wide_helmet_name) > _mapping_width(source_document, helmet_name))

	var document := _foot_anchor_document(source_document, [
		weapon_name, body_name, helmet_name, wide_weapon_name, wide_helmet_name,
	])
	var baseline_snapshot := {
		weapon_slot: {"name": weapon_name},
		body_slot: {"name": body_name},
		helmet_slot: {"name": helmet_name},
	}
	var preview := EquipmentCharacterPreview.new()
	preview.size = Vector2(230, 286)
	# This fixture injects the transparent classic paper-doll catalog rather
	# than worldBase/worldWear.  Select that explicit presentation mode so the
	# default player-facing world_avatar mode is not asked to resolve it.
	preview.configure_presentation_mode("classic_avatar")
	preview.center_on_opaque_bounds = true # Legacy input must have no effect.
	add_child(preview)
	await get_tree().process_frame

	for profession_name: String in PreviewScript.PROFESSION_IDS:
		preview.configure_source_document(document)
		preview.configure_profile(profession_name, baseline_snapshot)
		_assert_foot_stage_contract(preview, "%s/base" % profession_name)
		var baseline_origin := preview.composition_draw_origin()
		var baseline_stage := preview.foot_stage_center()

		var wide_weapon_snapshot := baseline_snapshot.duplicate(true)
		wide_weapon_snapshot[weapon_slot] = {"name": wide_weapon_name}
		preview.configure_profile(profession_name, wide_weapon_snapshot)
		_assert_foot_stage_contract(preview, "%s/wide_weapon" % profession_name)
		_assert_same_stage_and_origin(preview, baseline_stage, baseline_origin, "%s/wide_weapon" % profession_name)

		var wide_helmet_snapshot := baseline_snapshot.duplicate(true)
		wide_helmet_snapshot[helmet_slot] = {"name": wide_helmet_name}
		preview.configure_profile(profession_name, wide_helmet_snapshot)
		_assert_foot_stage_contract(preview, "%s/wide_helmet" % profession_name)
		_assert_same_stage_and_origin(preview, baseline_stage, baseline_origin, "%s/wide_helmet" % profession_name)

	print("EQUIPMENT_CHARACTER_PREVIEW_FOOT_STAGE_ANCHOR_PASS")
	get_tree().quit(0)


func _foot_anchor_document(source_document: Dictionary, item_names: Array[String]) -> Dictionary:
	var source_mappings: Dictionary = source_document.get("runtimeMappings", {})
	var items_by_id := {}
	for index in range(item_names.size()):
		var item_name := item_names[index]
		items_by_id["fixture_%d" % index] = {
			"itemName": item_name,
			"paperDoll": source_mappings.get(item_name, {}),
		}
	var composition: Dictionary = source_document.get("composition", {})
	var profession_manifests := {}
	for profession_name: String in PreviewScript.PROFESSION_IDS:
		var profession_id := str(PreviewScript.PROFESSION_IDS[profession_name])
		profession_manifests[profession_id] = {
			"professionId": profession_id,
			"base": source_document.get("base", {}),
			"hair": source_document.get("hair", {}),
			"canvasSize": composition.get("canvasSize", [168, 199]),
			"paperDollFootAnchor": [84, 186],
		}
	return {
		"professionManifests": profession_manifests,
		"itemsById": items_by_id,
	}


func _mapping_name_for_source_index(source_document: Dictionary, source_index: int) -> String:
	var mappings: Dictionary = source_document.get("runtimeMappings", {})
	for item_name_value: Variant in mappings:
		var mapping_value: Variant = mappings[item_name_value]
		if mapping_value is Dictionary and int(mapping_value.get("sourceIndex", -1)) == source_index:
			return str(item_name_value)
	return ""


func _widest_mapping_name(source_document: Dictionary, slot: String) -> String:
	var mappings: Dictionary = source_document.get("runtimeMappings", {})
	var result := ""
	var widest := -1
	for item_name_value: Variant in mappings:
		var mapping_value: Variant = mappings[item_name_value]
		if not mapping_value is Dictionary or str(mapping_value.get("slot", "")) != slot:
			continue
		var width := _mapping_width(source_document, str(item_name_value))
		if width > widest:
			widest = width
			result = str(item_name_value)
	return result


func _mapping_width(source_document: Dictionary, item_name: String) -> int:
	var mapping: Dictionary = source_document.get("runtimeMappings", {}).get(item_name, {})
	var dimensions: Array = mapping.get("size", [])
	return int(dimensions[0]) if dimensions.size() >= 2 else 0


func _assert_foot_stage_contract(preview: EquipmentCharacterPreview, label: String) -> void:
	assert(preview.has_renderable_assets(), "%s must load a paper-doll base" % label)
	var stage := preview.foot_stage_center()
	var origin := preview.composition_draw_origin()
	var anchor := preview.paper_doll_foot_anchor()
	assert(is_equal_approx(stage.x, preview.size.x * 0.5), "%s stage must remain horizontally centred" % label)
	assert(
		stage.is_equal_approx(origin + anchor * preview.preview_scale),
		"%s paper-doll foot anchor must coincide with the stage centre" % label
	)
	for layer: Dictionary in preview._paper_layers:
		var expected := origin + preview._mapping_offset(layer) * preview.preview_scale
		assert(
			preview.layer_draw_origin(layer).is_equal_approx(expected),
			"%s layer must use the shared foot transform" % label
		)


func _assert_same_stage_and_origin(
	preview: EquipmentCharacterPreview,
	expected_stage: Vector2,
	expected_origin: Vector2,
	label: String
) -> void:
	assert(preview.foot_stage_center().is_equal_approx(expected_stage), "%s moved the stage" % label)
	assert(preview.composition_draw_origin().is_equal_approx(expected_origin), "%s moved the paper-doll origin" % label)
