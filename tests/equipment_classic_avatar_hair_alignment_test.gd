extends Node

const PreviewScript := preload("res://scripts/equipment_character_preview.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var preview := EquipmentCharacterPreview.new()
	preview.size = Vector2(300, 340)
	preview.configure_presentation_mode("classic_avatar")
	preview.configure_profile("战士", {
		"武器": {"item_id": 113, "name": "怒斩"},
		"衣服": {"item_id": 140, "name": "天魔神甲"},
		str(PreviewScript.PAPER_LAYER_SLOTS[2]): {
			"item_id": 240,
			"name": "天尊头盔",
		},
	})
	add_child(preview)
	await get_tree().process_frame

	assert(preview.has_renderable_assets())
	assert(not preview._hair_layer.is_empty())
	assert(preview._helmet_texture != null, "user-final helmet paper doll did not load")
	var draw_layers := preview._classic_avatar_draw_layers()
	assert(not draw_layers.is_empty())
	assert(
		draw_layers[0].get("texture") == preview._hair_layer.get("texture"),
		"male hair must remain the first classic-avatar overlay with a helmet equipped"
	)
	var helmet_layer_index := -1
	for layer_index: int in draw_layers.size():
		if str(draw_layers[layer_index].get("layerKind", "")) == "helmet":
			helmet_layer_index = layer_index
			break
	assert(
		helmet_layer_index > 0,
		"user-final helmet must be drawn above the retained male hair"
	)
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
