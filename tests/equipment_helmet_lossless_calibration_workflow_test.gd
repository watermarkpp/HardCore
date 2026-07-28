extends Node

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const EDITOR_SCENE := preload("res://tools/helmet_calibration_tool.tscn")
const FORMAL_OVERRIDE := "res://assets/data/equipment_helmet_visual_v2_overrides.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var formal_before := FileAccess.get_file_as_string(FORMAL_OVERRIDE)
	var editor: Node = EDITOR_SCENE.instantiate()
	editor.auto_run = false
	add_child(editor)
	assert(await editor.initialize_editor_runtime(true))
	editor.select_item(147)
	await get_tree().process_frame

	var target_grid := editor.get_node(
		"CalibrationUI/Panel/VBox/TargetDirections"
	) as GridContainer
	var source_grid := editor.get_node(
		"CalibrationUI/Panel/VBox/SourceDirections"
	) as GridContainer
	assert(target_grid.get_child_count() == 8)
	assert(source_grid.get_child_count() == 8)
	assert(not (editor.get_node(
		"CalibrationUI/Panel/VBox/Previews"
	) as Control).visible)
	assert(not (editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/Scale"
	) as Control).visible)
	assert(editor._scale_popup.item_count == 4)
	assert(editor._scale_popup.get_item_text(0) == "放大 5%")
	assert(editor._scale_popup.get_item_text(1) == "缩小 5%")

	var n_before := HelmetVisualV2.direction_scale_percent(147, 0)
	var ne_before := HelmetVisualV2.direction_scale_percent(147, 1)
	assert(editor.adjust_direction_scale_percent(0, 5))
	assert(HelmetVisualV2.direction_scale_percent(147, 0) == n_before + 5)
	assert(HelmetVisualV2.direction_scale_percent(147, 1) == ne_before)
	assert("%d%%" % (n_before + 5) in str(
		(target_grid.get_node("Target_N/Label") as Label).text
	))
	assert(not editor.adjust_direction_scale_percent(0, 3))

	var original_once: Image = editor.calibration_source_cell_scaled(
		"idle", 0, 0, n_before + 5
	)
	var intermediate: Image = editor.calibration_source_cell("idle", 0, 0)
	var pivot: Vector2i = editor._calibration_pivot_for_source_row(
		"idle", 0, 0
	)
	var resampled_intermediate: Image = editor.scale_cell_around_pivot(
		intermediate, pivot, n_before + 5
	)
	assert(editor._image_has_opaque_pixel(original_once))
	assert(original_once.get_data() != resampled_intermediate.get_data())

	editor._update_presentation_selection("paperDoll", 2)
	editor._update_presentation_selection("inventory", 6)
	editor._update_presentation_selection("ground", 7)
	var presentation: Dictionary = editor._current_presentation_calibration()
	var paper: Dictionary = presentation.get("paperDoll", {})
	paper["offset"] = [91, 27]
	paper["scale_percent"] = 30
	presentation["paperDoll"] = paper
	assert(editor._apply_presentation_session(presentation))
	editor._refresh_presentation_ui()
	assert(editor._paper_doll_direction.selected == 2)
	assert(editor._inventory_direction.selected == 6)
	assert(editor._ground_direction.selected == 7)
	assert(editor._inventory_preview.texture != null)
	assert(editor._ground_preview.texture != null)
	assert(editor._paper_doll_overlay.position == Vector2(91, 27))
	assert(editor._paper_doll_overlay.texture != null)
	assert(editor._paper_doll_preview.has_renderable_assets())

	assert(editor.save_all_changes())
	var draft_path: String = editor._draft_path_for_item(147)
	assert(FileAccess.file_exists(draft_path))
	var draft: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(draft_path)
	)
	assert(draft is Dictionary)
	assert(str(draft.get("contractId", "")) == (
		"equipment.helmet.calibration_draft.v1"
	))
	assert(not bool(draft.get("runtimeReadable", true)))
	assert(not bool(draft.get("finalized", true)))
	assert(bool(draft.get("finalizePolicy", {}).get(
		"noIntermediateResample", false
	)))
	assert(int(draft.get("directions", {}).get(
		"N", {}
	).get("scale_percent", -1)) == n_before + 5)
	assert(int(draft.get("directions", {}).get(
		"NE", {}
	).get("scale_percent", -1)) == ne_before)
	assert(int(draft.get("presentationCalibration", {}).get(
		"paperDoll", {}
	).get("source_row", -1)) == 2)
	assert(int(draft.get("presentationCalibration", {}).get(
		"inventory", {}
	).get("source_row", -1)) == 6)
	assert(int(draft.get("presentationCalibration", {}).get(
		"ground", {}
	).get("source_row", -1)) == 7)
	assert(FileAccess.get_file_as_string(FORMAL_OVERRIDE) == formal_before)

	var preparer := FileAccess.get_file_as_string(
		"res://tools/prepare_helmet_calibration_source.ps1"
	)
	assert("preparedDirectionFiles" in preparer)
	assert("canonical_order_only_no_direction_scan" in preparer)
	assert("GetPixel($X, $Y).A" in preparer)
	assert("ImageFormat]::Png" in preparer)

	editor.dispose_runtime_for_test()
	editor.queue_free()
	HelmetVisualV2.reset_calibration_override_path()
	print(
		"EQUIPMENT_HELMET_LOSSLESS_CALIBRATION_WORKFLOW_PASS "
		+ "world_8dir_5pct=true paper_doll=true inventory=true ground=true "
		+ "draft_only=true original_once=true"
	)
	get_tree().quit()
