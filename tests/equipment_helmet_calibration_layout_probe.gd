extends Node


func _ready() -> void:
	var scene := load("res://tools/helmet_calibration_tool.tscn") as PackedScene
	var editor := scene.instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	var preview: EquipmentCharacterPreview = editor._paper_doll_preview
	var canvas: Control = editor._paper_doll_canvas
	assert(canvas.size == Vector2(540.0, 340.0))
	assert(is_equal_approx(preview.preview_scale, 1.22))
	var composition_origin := preview.composition_draw_origin()
	assert(absf(composition_origin.x - 167.519989013672) < 0.001)
	assert(absf(composition_origin.y - 91.2200164794922) < 0.001)
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
