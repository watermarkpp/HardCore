extends Node


func _ready() -> void:
	var scene := load("res://tools/helmet_calibration_tool.tscn") as PackedScene
	var editor := scene.instantiate()
	editor.auto_run = false
	add_child(editor)
	assert(await editor.initialize_editor_runtime(true))
	await get_tree().process_frame
	await get_tree().process_frame
	var preview: EquipmentCharacterPreview = editor._paper_doll_preview
	var canvas: Control = editor._paper_doll_canvas
	assert(canvas.size == Vector2(540.0, 340.0))
	assert(is_equal_approx(preview.preview_scale, 1.22))
	var composition_origin := preview.composition_draw_origin()
	assert(absf(composition_origin.x - 167.519989013672) < 0.001)
	assert(absf(composition_origin.y - 91.2200164794922) < 0.001)
	assert(editor._load_active_target_manifest(
		"res://assets/data/helmet_calibration_active_target.json"
	))
	editor.select_item(240)
	var draft: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/data/helmet_calibration_drafts/item_240.json"
	))
	var paper: Dictionary = draft.get(
		"presentationCalibration", {}
	).get("paperDoll", {})
	var paper_cutout: Image = editor._authored_source_cutout(
		int(paper.get("source_row", 4))
	)
	var expected_size: Vector2 = editor._paper_doll_display_size(
		paper_cutout, int(paper.get("scale_percent", 100))
	)
	var expected_offset := Vector2(
		float(paper.get("offset", [0, 0])[0]),
		float(paper.get("offset", [0, 0])[1])
	)
	assert(
		editor._paper_doll_overlay.texture.get_image().get_size()
		== paper_cutout.get_size()
	)
	assert(editor._paper_doll_overlay.size.is_equal_approx(expected_size))
	assert(editor._paper_doll_overlay.position == expected_offset)
	assert(expected_size.is_equal_approx(Vector2(
		41.0 * 1.22 * 0.65 * float(paper_cutout.get_width())
			/ float(paper_cutout.get_height()),
		41.0 * 1.22 * 0.65
	)))
	print(
		"HELMET_CALIBRATION_LAYOUT ",
		JSON.stringify({
			"canvasSize": [canvas.size.x, canvas.size.y],
			"previewScale": preview.preview_scale,
			"compositionOrigin": [
				composition_origin.x,
				composition_origin.y,
			],
			"referenceRect": [
				editor._paper_doll_reference_rect().position.x,
				editor._paper_doll_reference_rect().position.y,
				editor._paper_doll_reference_rect().size.x,
				editor._paper_doll_reference_rect().size.y,
			],
		})
	)
	print("EQUIPMENT_HELMET_CALIBRATION_LAYOUT_PROBE_PASS")
	get_tree().quit()
