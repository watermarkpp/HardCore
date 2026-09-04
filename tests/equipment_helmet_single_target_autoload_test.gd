extends Node

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const EDITOR_SCENE := preload("res://tools/helmet_calibration_tool.tscn")
const FORMAL_OVERRIDE := (
	"res://assets/data/equipment_helmet_visual_v2_overrides.json"
)
const ACTIVE_TARGET := (
	"res://assets/data/helmet_calibration_active_target.json"
)
const TEST_ROOT := "res://outputs/test_helmet_single_target_autoload"
const TEST_SOURCE := TEST_ROOT + "/source.png"
const TEST_TARGET := TEST_ROOT + "/target.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var override_before := FileAccess.get_file_as_string(FORMAL_OVERRIDE)
	var target: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(ACTIVE_TARGET)
	)
	var target_item_id := int(target.get("itemId", -1))
	assert(target_item_id > 0)
	assert(str(target.get("loadPolicy", "")) == (
		"single_target_direct_png_hash_validated"
	))
	var source_path := str(target.get("sourceSheet", ""))
	var expected_sha := str(target.get("sourceSheetSha256", "")).to_lower()
	assert(FileAccess.file_exists(source_path))
	assert(FileAccess.get_sha256(source_path).to_lower() == expected_sha)
	var prepared_presentation: Dictionary = target.get(
		"preparedPresentationFiles", {}
	)
	var prepared_presentation_sha: Dictionary = target.get(
		"preparedPresentationSha256", {}
	)
	for role: String in prepared_presentation:
		var presentation_path := str(prepared_presentation.get(role, ""))
		assert(FileAccess.file_exists(presentation_path))
		assert(
			FileAccess.get_sha256(presentation_path).to_lower()
			== str(prepared_presentation_sha.get(role, "")).to_lower()
		)

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(TEST_ROOT)
	)
	assert(DirAccess.copy_absolute(
		ProjectSettings.globalize_path(source_path),
		ProjectSettings.globalize_path(TEST_SOURCE)
	) == OK)
	target["sourceSheet"] = TEST_SOURCE
	target["sourceSheetSha256"] = FileAccess.get_sha256(TEST_SOURCE).to_lower()
	_write_json(TEST_TARGET, target)

	var editor: Node = EDITOR_SCENE.instantiate()
	editor.auto_run = false
	assert(editor._load_active_target_manifest(TEST_TARGET))
	add_child(editor)
	var item_control := editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/Item"
	) as OptionButton
	assert(
		item_control.item_count
		== HelmetVisualV2.calibration_items().size()
	)
	assert(not item_control.disabled)
	assert(await editor.initialize_editor_runtime(false))
	assert(editor.active_target_item_id() == target_item_id)
	assert(editor.current_item_id == target_item_id)
	assert(editor._active_target_applies_to_current_item())
	assert(
		editor.active_target_source_sheet_sha256()
		== FileAccess.get_sha256(TEST_SOURCE).to_lower()
	)
	if bool(target.get("initializeSessionDirectionMapping", false)):
		for direction_index: int in 8:
			var initialized_record := HelmetVisualV2.direction_record(
				target_item_id, direction_index
			)
			assert(
				int(initialized_record.get("source_row", -1))
				== direction_index
			)
			assert(
				str(initialized_record.get("source_direction", ""))
				== HelmetVisualV2.canonical_direction(direction_index)
			)
	if prepared_presentation.has("inventory"):
		var inventory_control := editor.get_node(
			"CalibrationUI/Panel/VBox/PresentationCalibration/"
			+ "Selectors/InventoryDirection"
		) as OptionButton
		assert(inventory_control.item_count == 9)
		assert(inventory_control.selected == 8)
		assert(inventory_control.get_item_text(8) == "背包专用")
		var presentation: Dictionary = (
			editor._current_presentation_calibration()
		)
		assert(str(presentation.get(
			"inventory", {}
		).get("source_variant", "")) == "dedicated_inventory")
		var dedicated: Image = editor._authored_presentation_cutout(
			"inventory"
		)
		assert(not dedicated.is_empty())
		assert(dedicated.get_used_rect().has_area())
		inventory_control.emit_signal("item_selected", 0)
		presentation = editor._current_presentation_calibration()
		assert(not presentation.get(
			"inventory", {}
		).has("source_variant"))
		assert(int(presentation.get(
			"inventory", {}
		).get("source_row", -1)) == 0)
		inventory_control.emit_signal("item_selected", 8)
		presentation = editor._current_presentation_calibration()
		assert(str(presentation.get(
			"inventory", {}
		).get("source_variant", "")) == "dedicated_inventory")

	for source_row: int in 8:
		var source_cell: Image = editor._authored_source_cutout(source_row)
		assert(not source_cell.is_empty())
		assert(source_cell.get_used_rect().has_area())
	for direction_index: int in 8:
		editor._configure_runtime("idle", direction_index, 0)
		var record := HelmetVisualV2.direction_record(
			target_item_id, direction_index
		)
		var source_row := int(record.get("source_row", direction_index))
		var expected: Image = editor.calibration_source_cell_scaled(
			"idle",
			source_row,
			0,
			HelmetVisualV2.direction_scale_percent(
				target_item_id, direction_index
			)
		)
		var actual: Image = editor._runtime_layer_cell(
			"ClientHelmetLayer", "idle", direction_index, 0
		)
		if actual.get_data() != expected.get_data():
			print(
				(
					"ACTIVE_TARGET_RUNTIME_CELL_MISMATCH "
				+ "direction=%s source_row=%d scale=%d "
				+ "actual_sha=%s expected_sha=%s "
				+ "actual_used=%s expected_used=%s"
				)
				% [
					HelmetVisualV2.canonical_direction(direction_index),
					source_row,
					HelmetVisualV2.direction_scale_percent(
						target_item_id, direction_index
					),
					actual.get_data().hex_encode().sha256_text(),
					expected.get_data().hex_encode().sha256_text(),
					str(actual.get_used_rect()),
					str(expected.get_used_rect()),
				]
			)
		assert(actual.get_data() == expected.get_data())

	editor.select_item(150)
	assert(editor.current_item_id == 150)
	assert(not editor._active_target_applies_to_current_item())
	assert(
		str(editor._calibration_source_contract().get(
			"calibrationSourceSheet", ""
		)) != TEST_SOURCE
	)
	editor.select_item(target_item_id)
	assert(editor.current_item_id == target_item_id)
	assert(editor._active_target_applies_to_current_item())
	assert(
		str(editor._calibration_source_contract().get(
			"calibrationSourceSheet", ""
		)) == TEST_SOURCE
	)

	var source_before: Image = editor._authored_source_cutout(0)
	var changed_sheet := Image.load_from_file(
		ProjectSettings.globalize_path(TEST_SOURCE)
	)
	assert(not changed_sheet.is_empty())
	var changed_pixel := _first_opaque_pixel(changed_sheet)
	assert(changed_pixel.x >= 0)
	var changed_color := changed_sheet.get_pixelv(changed_pixel)
	changed_color.r = 1.0 - changed_color.r
	changed_sheet.set_pixelv(changed_pixel, changed_color)
	assert(changed_sheet.save_png(
		ProjectSettings.globalize_path(TEST_SOURCE)
	) == OK)
	target["sourceSheetSha256"] = FileAccess.get_sha256(TEST_SOURCE).to_lower()
	_write_json(TEST_TARGET, target)
	editor.reload_formal_data()
	assert(
		editor.active_target_source_sheet_sha256()
		== FileAccess.get_sha256(TEST_SOURCE).to_lower()
	)
	var source_after: Image = editor._authored_source_cutout(0)
	if target.get("preparedDirectionFiles", {}).is_empty():
		assert(source_after.get_data() != source_before.get_data())
	else:
		# Prepared full-resolution cuts are the authoritative editor inputs.
		# Replacing only the presentation sheet must not alter those pixels.
		assert(source_after.get_data() == source_before.get_data())

	assert(FileAccess.get_file_as_string(FORMAL_OVERRIDE) == override_before)
	editor.dispose_runtime_for_test()
	editor.queue_free()
	print(
		"EQUIPMENT_HELMET_SINGLE_TARGET_AUTOLOAD_TEST_PASS "
		+ "startup_item=151 menu_switchable=true per_item_source=true "
		+ "direct_png=true cache_refresh=true "
		+ "protected_overrides_unchanged=true"
	)
	get_tree().quit()


func _first_opaque_pixel(image: Image) -> Vector2i:
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.9:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(payload, "\t") + "\n")
	file.close()
