extends Node

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const EDITOR_SCENE := preload("res://tools/helmet_calibration_tool.tscn")
const FORMAL_OVERRIDE := "res://assets/data/equipment_helmet_visual_v2_overrides.json"
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var formal_before := FileAccess.get_file_as_string(FORMAL_OVERRIDE)
	var editor: Node = EDITOR_SCENE.instantiate()
	editor.auto_run = false
	add_child(editor)
	assert(await editor.initialize_editor_runtime(true))

	var sheet := (
		"res://assets/art/items/client/world_wear/helmet/male/source/"
		+ "elf_146_helmet_8dir_transparent.png"
	)
	var prepared_files: Dictionary = {}
	var prepared_hashes: Dictionary = {}
	var direction_records: Dictionary = {}
	for direction: String in DIRECTIONS:
		var path := (
			"res://assets/art/items/client/world_wear/helmet/male/source/"
			+ "elf_146_directions/%s.png" % direction.to_lower()
		)
		prepared_files[direction] = path
		prepared_hashes[direction] = FileAccess.get_sha256(path)
		var source_row := DIRECTIONS.find(direction)
		direction_records[direction] = {
			"source_row": source_row,
			"source_slot_id": "slot_%d" % source_row,
			"source_direction": direction,
			"nudge": [0, 0],
			"scale_percent": 100,
			"status": "valid",
			"locked": false,
		}
	var draft := {
		"schemaVersion": 1,
		"contractId": "equipment.helmet.calibration_draft.v1",
		"runtimeReadable": false,
		"finalized": false,
		"itemId": 146,
		"visualAssetId": "elf_146",
		"source": {
			"sheet": sheet,
			"sheetSha256": FileAccess.get_sha256(sheet),
			"preparedDirectionFiles": prepared_files,
			"preparedDirectionSha256": prepared_hashes,
			"preparedPresentationFiles": {},
			"preparedPresentationSha256": {},
		},
		"directions": direction_records,
		"presentationCalibration": {},
	}
	var draft_path: String = editor._draft_path_for_item(146)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(draft_path.get_base_dir())
	)
	editor._write_json(ProjectSettings.globalize_path(draft_path), draft)
	editor._loaded_draft_items.erase(146)
	editor._draft_source_contracts.erase("146")
	editor.select_item(146)
	await get_tree().process_frame

	var source_grid := editor.get_node(
		"CalibrationUI/Panel/VBox/SourceDirections"
	) as GridContainer
	for source_row: int in DIRECTIONS.size():
		var raw := Image.load_from_file(ProjectSettings.globalize_path(
			str(prepared_files[DIRECTIONS[source_row]])
		))
		raw.convert(Image.FORMAT_RGBA8)
		var loaded: Image = editor._authored_source_cutout(source_row)
		assert(loaded.get_size() == raw.get_size())
		assert(loaded.get_data() == raw.get_data())
		var source_button := source_grid.get_node(
			"Source_Row%d" % source_row
		) as TextureButton
		assert(source_button.texture_normal.get_image().get_size() == raw.get_size())
		assert(source_button.texture_normal.get_image().get_data() == raw.get_data())
		var overlay: TextureRect = editor._target_authored_overlays[source_row]
		assert(overlay.texture.get_image().get_size() == raw.get_size())
		var display_size: Vector2 = editor.authored_world_display_size(
			source_row,
			HelmetVisualV2.direction_scale_percent(146, source_row)
		)
		assert(overlay.size.is_equal_approx(display_size))
		assert(is_equal_approx(
			display_size.x / display_size.y,
			float(raw.get_width()) / float(raw.get_height())
		))

	assert(FileAccess.get_file_as_string(FORMAL_OVERRIDE) == formal_before)
	print(
		"EQUIPMENT_HELMET_DRAFT_SOURCE_RESOLUTION_TEST_PASS "
		+ "item=146 original_rgba=8 preview_resample=false"
	)
	editor.dispose_runtime_for_test()
	editor.queue_free()
	await get_tree().process_frame
	get_tree().quit.call_deferred(0)
