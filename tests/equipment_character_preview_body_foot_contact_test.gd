extends Node

const PreviewScript := preload("res://scripts/equipment_character_preview.gd")

const BODY_CASES := [
	{
		"professionId": "warrior",
		"itemName": "fixture_body_warrior_62",
		"sourceIndex": 62,
		"path": "res://assets/art/items/client/equipped/062.png",
		"drawOffset": [40, 58],
		"size": [84, 140],
		"footContact": [85, 193],
	},
	{
		"professionId": "warrior",
		"itemName": "fixture_body_warrior_85",
		"sourceIndex": 85,
		"path": "res://assets/art/items/client/equipped/085.png",
		"drawOffset": [46, 43],
		"size": [84, 153],
		"footContact": [85, 191],
	},
	{
		"professionId": "wizard",
		"itemName": "fixture_body_wizard_86",
		"sourceIndex": 86,
		"path": "res://assets/art/items/client/equipped/086.png",
		"drawOffset": [35, 63],
		"size": [104, 129],
		"footContact": [86, 189],
	},
	{
		"professionId": "taoist",
		"itemName": "fixture_body_taoist_87",
		"sourceIndex": 87,
		"path": "res://assets/art/items/client/equipped/087.png",
		"drawOffset": [44, 64],
		"size": [88, 127],
		"footContact": [85.75, 189],
	},
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var classic_document: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(PreviewScript.PAPER_DOLL_MANIFEST)
	)
	var weapon_slot := str(PreviewScript.PAPER_LAYER_SLOTS[1])
	var body_slot := str(PreviewScript.PAPER_LAYER_SLOTS[0])
	var helmet_slot := str(PreviewScript.PAPER_LAYER_SLOTS[2])
	var weapon_name := _mapping_name_for_source_index(classic_document, 55)
	var helmet_name := _mapping_name_for_source_index(classic_document, 344)
	var wide_weapon_name := _widest_mapping_name(classic_document, weapon_slot)
	var wide_helmet_name := _widest_mapping_name(classic_document, helmet_slot)
	assert(not weapon_name.is_empty() and not helmet_name.is_empty())
	assert(not wide_weapon_name.is_empty() and not wide_helmet_name.is_empty())

	var document := _fixture_document(
		classic_document,
		[weapon_name, helmet_name, wide_weapon_name, wide_helmet_name]
	)
	var preview := EquipmentCharacterPreview.new()
	preview.size = Vector2(230, 286)
	preview.configure_source_document(document)
	add_child(preview)
	await get_tree().process_frame

	for body_case: Dictionary in BODY_CASES:
		var profession_name := _profession_name(str(body_case.professionId))
		var baseline_snapshot := {
			body_slot: {"name": str(body_case.itemName)},
			weapon_slot: {"name": weapon_name},
			helmet_slot: {"name": helmet_name},
		}
		preview.configure_profile(profession_name, baseline_snapshot)
		_assert_actual_contact(preview, body_case)
		var baseline_origin := preview.composition_draw_origin()
		var baseline_stage := preview.foot_stage_center()

		var wide_weapon_snapshot := baseline_snapshot.duplicate(true)
		wide_weapon_snapshot[weapon_slot] = {"name": wide_weapon_name}
		preview.configure_profile(profession_name, wide_weapon_snapshot)
		_assert_actual_contact(preview, body_case)
		assert(preview.composition_draw_origin().is_equal_approx(baseline_origin))
		assert(preview.foot_stage_center().is_equal_approx(baseline_stage))

		var wide_helmet_snapshot := baseline_snapshot.duplicate(true)
		wide_helmet_snapshot[helmet_slot] = {"name": wide_helmet_name}
		preview.configure_profile(profession_name, wide_helmet_snapshot)
		_assert_actual_contact(preview, body_case)
		assert(preview.composition_draw_origin().is_equal_approx(baseline_origin))
		assert(preview.foot_stage_center().is_equal_approx(baseline_stage))

	print("EQUIPMENT_CHARACTER_PREVIEW_BODY_FOOT_CONTACT_PASS")
	get_tree().quit(0)


func _fixture_document(classic_document: Dictionary, accessory_names: Array[String]) -> Dictionary:
	var classic_mappings: Dictionary = classic_document.get("runtimeMappings", {})
	var items_by_id := {}
	for body_case: Dictionary in BODY_CASES:
		items_by_id[str(body_case.itemName)] = {
			"itemName": str(body_case.itemName),
			"paperDoll": {
				"slot": str(PreviewScript.PAPER_LAYER_SLOTS[0]),
				"sourceIndex": int(body_case.sourceIndex),
				"path": str(body_case.path),
				"drawOffset": body_case.drawOffset,
				"size": body_case.size,
				PreviewScript.BODY_FOOT_CONTACT_FIELD: body_case.footContact,
			},
		}
	for item_name: String in accessory_names:
		items_by_id[item_name] = {
			"itemName": item_name,
			"paperDoll": classic_mappings.get(item_name, {}),
		}
	var composition: Dictionary = classic_document.get("composition", {})
	var manifests := {}
	for profession_name: String in PreviewScript.PROFESSION_IDS:
		var profession_id := str(PreviewScript.PROFESSION_IDS[profession_name])
		manifests[profession_id] = {
			"professionId": profession_id,
			"base": classic_document.get("base", {}),
			"hair": classic_document.get("hair", {}),
			"canvasSize": composition.get("canvasSize", [168, 199]),
			# Deliberately wrong fallback: equipped body footContact must win.
			"paperDollFootAnchor": [84, 186],
		}
	return {
		"professionManifests": manifests,
		"itemsById": items_by_id,
	}


func _assert_actual_contact(preview: EquipmentCharacterPreview, body_case: Dictionary) -> void:
	var actual_contact := _alpha_foot_contact(preview)
	var declared_contact := preview._vector_from_value(body_case.footContact, Vector2.ZERO)
	assert(
		actual_contact.distance_to(declared_contact) <= 0.01,
		"%s alpha contact %s differs from declared %s" % [
			body_case.itemName, actual_contact, declared_contact,
		]
	)
	assert(preview.paper_doll_foot_anchor().is_equal_approx(declared_contact))
	var contact_on_screen := (
		preview.composition_draw_origin()
		+ actual_contact * preview.preview_scale
	)
	assert(
		contact_on_screen.distance_to(preview.foot_stage_center()) <= 1.0,
		"%s feet are not centred on stage" % body_case.itemName
	)


func _alpha_foot_contact(preview: EquipmentCharacterPreview) -> Vector2:
	var image_layers: Array[Dictionary] = []
	image_layers.append({
		"image": preview._base_texture.get_image(),
		"offset": Vector2i.ZERO,
	})
	if not preview._hair_layer.is_empty():
		image_layers.append({
			"image": (preview._hair_layer.get("texture") as Texture2D).get_image(),
			"offset": Vector2i(preview._mapping_offset(preview._hair_layer)),
		})
	image_layers.append({
		"image": (preview._body_layer.get("texture") as Texture2D).get_image(),
		"offset": Vector2i(preview._mapping_offset(preview._body_layer)),
	})
	var canvas_width := int(preview._canvas_size.x)
	var canvas_height := int(preview._canvas_size.y)
	var split_x := canvas_width / 2
	var contact_y := -1
	var left_contact: Array[int] = []
	var right_contact: Array[int] = []
	for y in range(canvas_height):
		var left_pixels: Array[int] = []
		var right_pixels: Array[int] = []
		for x in range(maxi(0, split_x - 44), mini(canvas_width, split_x + 44)):
			if not _has_alpha(image_layers, Vector2i(x, y)):
				continue
			if x < split_x:
				left_pixels.append(x)
			else:
				right_pixels.append(x)
		if left_pixels.size() >= 3 and right_pixels.size() >= 3:
			contact_y = y
			left_contact = left_pixels
			right_contact = right_pixels
	assert(contact_y >= 0, "paper doll has no two-foot alpha contact")
	var left_center := (float(left_contact.front()) + float(left_contact.back())) * 0.5
	var right_center := (float(right_contact.front()) + float(right_contact.back())) * 0.5
	return Vector2((left_center + right_center) * 0.5, float(contact_y))


func _has_alpha(image_layers: Array[Dictionary], canvas_point: Vector2i) -> bool:
	for layer: Dictionary in image_layers:
		var image: Image = layer.image
		var local_point := canvas_point - Vector2i(layer.offset)
		if (
			local_point.x >= 0
			and local_point.y >= 0
			and local_point.x < image.get_width()
			and local_point.y < image.get_height()
			and image.get_pixelv(local_point).a > 0.0
		):
			return true
	return false


func _profession_name(profession_id: String) -> String:
	for profession_name: String in PreviewScript.PROFESSION_IDS:
		if str(PreviewScript.PROFESSION_IDS[profession_name]) == profession_id:
			return profession_name
	return ""


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
		var dimensions: Array = mapping_value.get("size", [])
		var width := int(dimensions[0]) if dimensions.size() >= 2 else 0
		if width > widest:
			widest = width
			result = str(item_name_value)
	return result
