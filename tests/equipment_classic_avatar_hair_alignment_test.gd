extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var preview := EquipmentCharacterPreview.new()
	preview.size = Vector2(300, 340)
	preview.configure_presentation_mode("classic_avatar")
	preview.configure_profile("战士", {
		"武器": {"item_id": 113, "name": "怒斩"},
		"衣服": {"item_id": 140, "name": "天魔神甲"},
	})
	add_child(preview)
	await get_tree().process_frame

	assert(preview.has_renderable_assets())
	assert(not preview._hair_layer.is_empty())
	var expected_hair_position := Vector2(80, 44)
	assert(
		preview._mapping_offset(preview._hair_layer).is_equal_approx(
			expected_hair_position
		),
		"classic avatar hair ignored avatarOnly.stagePosition"
	)
	assert(
		preview.layer_draw_origin(preview._hair_layer).is_equal_approx(
			preview.composition_draw_origin()
			+ expected_hair_position * preview.preview_scale
		),
		"classic avatar hair is not aligned to the shared head canvas"
	)

	print("EQUIPMENT_CLASSIC_AVATAR_HAIR_ALIGNMENT_PASS")
	get_tree().quit(0)
