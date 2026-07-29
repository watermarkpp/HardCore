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
	var default_presentation: Dictionary = (
		editor._default_presentation_calibration()
	)
	assert(int(default_presentation.get(
		"paperDoll", {}
	).get("scale_percent", -1)) == 100)
	var baseline_cutout: Image = editor._authored_source_cutout(4)
	if baseline_cutout.is_empty():
		baseline_cutout = editor.source_row_thumbnail(4)
	assert(is_equal_approx(
		editor._paper_doll_display_size(baseline_cutout, 100).y,
		editor._paper_doll_reference_rect().size.y
	))
	var migrated_legacy: Dictionary = (
		editor._migrate_legacy_paper_doll_defaults({
			"paperDoll": {
				"source_row": 4,
				"offset": [110, 32],
				"scale_percent": 25,
			},
			"inventory": {"source_row": 4},
			"ground": {"source_row": 4},
		})
	)
	assert(int(migrated_legacy.get(
		"paperDoll", {}
	).get("scale_percent", -1)) == 100)
	assert(migrated_legacy.get(
		"paperDoll", {}
	).get("offset", []) != [110, 32])

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
	assert(editor._scale_popup.item_count == 13)
	assert(editor._scale_popup.get_item_text(0) == "整体放大 5%")
	assert(editor._scale_popup.get_item_text(1) == "整体缩小 5%")
	assert(editor._scale_popup.get_item_text(3) == "横向放大 5%")
	assert(editor._scale_popup.get_item_text(4) == "横向缩小 5%")
	assert(editor._scale_popup.get_item_text(5) == "纵向放大 5%")
	assert(editor._scale_popup.get_item_text(6) == "纵向缩小 5%")
	assert(editor._scale_popup.get_item_text(8) == "向左旋转 5°")
	assert(editor._scale_popup.get_item_text(9) == "向右旋转 5°")
	assert(editor._scale_popup.get_item_text(11) == "当前帧旋转归零")

	var n_before := HelmetVisualV2.direction_scale_percent(147, 0)
	var ne_before := HelmetVisualV2.direction_scale_percent(147, 1)
	assert(HelmetVisualV2.WORLD_SCALE_MIN_PERCENT == 5)
	assert(editor.set_direction_scale_percent(0, 50))
	assert(editor.adjust_direction_scale_percent(0, -5))
	assert(HelmetVisualV2.direction_scale_percent(147, 0) == 45)
	assert(editor.set_direction_scale_percent(0, 5))
	assert(editor.adjust_direction_scale_percent(0, -5))
	assert(HelmetVisualV2.direction_scale_percent(147, 0) == 5)
	assert(editor.set_direction_scale_percent(0, n_before))
	assert(editor.adjust_direction_scale_percent(0, 5))
	assert(HelmetVisualV2.direction_scale_percent(147, 0) == n_before + 5)
	assert(HelmetVisualV2.direction_scale_percent(147, 1) == ne_before)
	assert("%d%%" % (n_before + 5) in str(
		(target_grid.get_node("Target_N/Label") as Label).text
	))
	assert(not editor.adjust_direction_scale_percent(0, 3))

	editor.select_action("hit")
	editor.select_target_direction(0)
	editor.select_frame(1)
	var authored_overlay := editor._target_authored_overlays[0] as TextureRect
	assert(authored_overlay.stretch_mode == TextureRect.STRETCH_SCALE)
	assert(editor.adjust_pose_scale_percent(0, "x", -5))
	var horizontal_only_pose: Dictionary = editor.current_pose_transform()
	assert(int(horizontal_only_pose.get("scale_x_percent", -1)) == n_before)
	assert(int(horizontal_only_pose.get(
		"scale_y_percent", -1
	)) == n_before + 5)
	if authored_overlay.visible:
		assert(authored_overlay.size.is_equal_approx(
			editor.authored_world_display_size_xy(
				int(HelmetVisualV2.direction_record(
					147, 0
				).get("source_row", 0)),
				n_before,
				n_before + 5
			)
		))
	assert(editor.adjust_pose_scale_percent(0, "y", 5))
	assert(editor.adjust_pose_rotation(0, -5.0))
	assert(editor.adjust_pose_rotation(0, 5.0))
	assert(float(editor.current_pose_transform().get(
		"rotation_degrees", 1.0
	)) == 0.0)
	assert(editor.adjust_pose_rotation(0, -5.0))
	assert(editor.nudge_current(Vector2i.RIGHT))
	var hit_pose: Dictionary = editor.current_pose_transform()
	assert(int(hit_pose.get("scale_x_percent", -1)) == n_before)
	assert(int(hit_pose.get("scale_y_percent", -1)) == n_before + 10)
	assert(float(hit_pose.get("rotation_degrees", 0.0)) == -5.0)
	assert(Vector2(hit_pose.get("offset", [0, 0])[0], hit_pose.get(
		"offset", [0, 0]
	)[1]) == Vector2(0.5, 0.0))
	if editor._has_authored_source_sheet():
		if authored_overlay.visible:
			assert(is_equal_approx(editor._normalized_rotation_degrees(
				authored_overlay.rotation_degrees
			), -5.0))
			assert(authored_overlay.size.is_equal_approx(
				editor.authored_world_display_size_xy(
				int(HelmetVisualV2.direction_record(147, 0).get("source_row", 0)),
				n_before,
				n_before + 10
				)
			))
	editor.select_frame(2)
	var untouched_hit_pose: Dictionary = editor.current_pose_transform()
	assert(int(untouched_hit_pose.get(
		"scale_x_percent", -1
	)) == n_before + 5)
	assert(int(untouched_hit_pose.get(
		"scale_y_percent", -1
	)) == n_before + 5)
	assert(float(untouched_hit_pose.get(
		"rotation_degrees", 1.0
	)) == 0.0)
	assert(untouched_hit_pose.get("offset", []) == [0.0, 0.0])

	editor.select_action("death")
	assert(editor._frame_buttons.size() == 4)
	assert(editor._frame_buttons[0].text == "0 起始")
	assert(editor._frame_buttons[1].text == "1 后仰")
	assert(editor._frame_buttons[2].text == "2 倒地")
	assert(editor._frame_buttons[3].text == "3 躺地")
	editor._frame_buttons[3].emit_signal("pressed")
	assert(editor.current_frame == 3)
	assert(editor._frame_buttons[3].button_pressed)
	editor.select_action("hit")
	editor.select_frame(1)

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
	assert(editor._image_has_opaque_pixel(resampled_intermediate))
	assert(
		editor.calibration_source_cell("idle", 0, 0).get_data()
		== intermediate.get_data()
	)

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
	assert(
		editor._inventory_preview.texture.get_image().get_size()
		== editor._authored_source_cutout(6).get_size()
	)
	assert(
		editor._ground_preview.texture.get_image().get_size()
		== editor._authored_source_cutout(7).get_size()
	)
	assert(editor._paper_doll_overlay.position == Vector2(91, 27))
	assert(editor._paper_doll_overlay.texture != null)
	assert(editor._paper_doll_preview.has_renderable_assets())
	var world_nudge_before: Array = HelmetVisualV2.direction_record(
		147, editor.current_direction
	).get("nudge", [0, 0]).duplicate()
	editor._set_active_editor_scope("paperDoll")
	var right_key := InputEventKey.new()
	right_key.keycode = KEY_RIGHT
	right_key.pressed = true
	editor._input(right_key)
	assert(editor._paper_doll_overlay.position == Vector2(91.5, 27))
	assert(
		HelmetVisualV2.direction_record(
			147, editor.current_direction
		).get("nudge", [0, 0]) == world_nudge_before,
		"paper-doll arrow key leaked into the world-direction nudge"
	)

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
	assert(bool(draft.get("previewPolicy", {}).get(
		"noPreviewRasterDownsample", false
	)))
	assert(bool(draft.get("finalizePolicy", {}).get(
		"noIntermediateResample", false
	)))
	assert(int(draft.get("directions", {}).get(
		"N", {}
	).get("scale_percent", -1)) == n_before + 5)
	assert(int(draft.get("directions", {}).get(
		"NE", {}
	).get("scale_percent", -1)) == ne_before)
	var saved_hit_pose: Dictionary = draft.get(
		"poseTransforms", {}
	).get("hit", {}).get("N", {}).get("1", {})
	assert(int(saved_hit_pose.get("scale_x_percent", -1)) == n_before)
	assert(int(saved_hit_pose.get(
		"scale_y_percent", -1
	)) == n_before + 10)
	assert(float(saved_hit_pose.get("rotation_degrees", 0.0)) == -5.0)
	assert(saved_hit_pose.get("offset", []) == [0.5, 0.0])
	assert(int(draft.get("presentationCalibration", {}).get(
		"paperDoll", {}
	).get("source_row", -1)) == 2)
	assert(int(draft.get("presentationCalibration", {}).get(
		"inventory", {}
	).get("source_row", -1)) == 6)
	assert(int(draft.get("presentationCalibration", {}).get(
		"ground", {}
	).get("source_row", -1)) == 7)
	editor.reload_formal_data()
	editor.select_action("hit")
	editor.select_target_direction(0)
	editor.select_frame(1)
	var reloaded_hit_pose: Dictionary = editor.current_pose_transform()
	assert(_pose_fields_equal(reloaded_hit_pose, saved_hit_pose))
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
		+ "world_8dir_pose_frame=true axis_scale=true rotation_5deg=true "
		+ "death_frames=4 paper_doll=true inventory=true ground=true "
		+ "draft_only=true original_once=true"
	)
	get_tree().quit()


func _pose_fields_equal(left: Dictionary, right: Dictionary) -> bool:
	return (
		Vector2(left.get("offset", [0, 0])[0], left.get(
			"offset", [0, 0]
		)[1]) == Vector2(right.get("offset", [0, 0])[0], right.get(
			"offset", [0, 0]
		)[1])
		and int(left.get("scale_x_percent", -1))
			== int(right.get("scale_x_percent", -2))
		and int(left.get("scale_y_percent", -1))
			== int(right.get("scale_y_percent", -2))
		and is_equal_approx(
			float(left.get("rotation_degrees", 0.0)),
			float(right.get("rotation_degrees", 1.0))
		)
	)
