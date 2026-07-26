extends Node

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const ArtSpec := preload("res://scripts/art_spec.gd")
const EDITOR_SCENE := preload("res://tools/helmet_calibration_tool.tscn")
const FORMAL_OVERRIDE := "res://assets/data/equipment_helmet_visual_v2_overrides.json"
const OUTPUT_ROOT := "res://outputs/visual_acceptance/helmet_calibration"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var formal_before := FileAccess.get_file_as_string(FORMAL_OVERRIDE)
	var all_source_hashes_before := {
		"146": _source_hashes(146),
		"151": _source_hashes(151),
	}
	var editor: Node = EDITOR_SCENE.instantiate()
	editor.auto_run = false
	add_child(editor)
	assert(await editor.initialize_editor_runtime(true))
	var interactive_args := PackedStringArray([
		"--helmet-calibration-interactive",
	])
	assert(editor.has_interactive_user_arg(interactive_args))
	assert(not editor.has_interactive_user_arg(PackedStringArray()))
	assert(editor.should_auto_quit_for_context(
		PackedStringArray(), "headless"
	))
	assert(not editor.should_auto_quit_for_context(
		interactive_args, "headless"
	))
	assert(not editor.should_auto_quit_for_context(
		PackedStringArray(), "windows"
	))
	assert(not await editor.start_interactive_failure_for_test())
	assert(not editor.quit_was_requested())
	assert(not editor.initialization_error().is_empty())
	var window_policy: Dictionary = editor.interactive_window_policy()
	assert(window_policy.get("minimumSize", []) == [1600, 900])
	assert(bool(window_policy.get("centered", false)))
	assert(not bool(window_policy.get("projectSettingsModified", true)))
	var startup_status := editor.get_node(
		"CalibrationUI/Panel/VBox/StartupStatus"
	) as Label
	assert(startup_status.visible)
	assert("窗口将保持打开" in startup_status.text)
	var launcher_text := FileAccess.get_file_as_string(
		"res://tools/launch_helmet_calibration_tool.ps1"
	)
	assert("Godot_v4.7-stable_win64.exe" in launcher_text)
	assert("--headless" not in launcher_text)
	assert("--helmet-calibration-interactive" in launcher_text)
	assert(".godot\\helmet_calibration_appdata" in launcher_text)
	assert("Join-Path $OutputDirectory 'helmet_calibration_interactive.log'" in launcher_text)
	assert("--log-file" in launcher_text)

	var target_grid := editor.get_node(
		"CalibrationUI/Panel/VBox/TargetDirections"
	) as GridContainer
	var source_grid := editor.get_node(
		"CalibrationUI/Panel/VBox/SourceDirections"
	) as GridContainer
	var calibration_ui := editor.get_node("CalibrationUI") as Control
	var editor_background := editor.get_node("EditorBackground") as ColorRect
	assert(editor.game_render_is_isolated())
	assert(editor.get_node("GameDataViewport") is SubViewport)
	assert(calibration_ui.custom_minimum_size == Vector2(1600, 900))
	assert(editor_background.custom_minimum_size == Vector2(1600, 900))
	assert(editor_background.color.a == 1.0)
	assert(editor_background.color.r < 0.1)
	assert(calibration_ui.z_index > editor_background.z_index)
	assert(calibration_ui.get_global_rect().encloses(
		editor_background.get_global_rect()
	))
	assert(target_grid.get_child_count() == 8)
	assert(source_grid.get_child_count() == 8)
	assert(target_grid.columns == 8)
	assert(source_grid.columns == 8)
	_assert_editor_layout(editor)

	# Mouse target selection: NE must become the highlighted player target.
	var target_ne := target_grid.get_node("Target_NE") as TextureButton
	target_ne.emit_signal("pressed")
	assert(editor.current_direction == 1)
	assert(target_ne.button_pressed)

	# Every source thumbnail is the actual source atlas row advertised in metadata.
	for row: int in 8:
		var button := source_grid.get_node("Source_Row%d" % row) as TextureButton
		assert(int(button.get_meta("source_row", -1)) == row)
		var expected: Image = editor.source_row_thumbnail(row)
		assert(
			button.texture_normal.get_image().get_data()
			== expected.get_data()
		)

	# Mouse source-row selection maps the current target through explicit semantics.
	var source_row_zero := source_grid.get_node("Source_Row0") as TextureButton
	source_row_zero.emit_signal("pressed")
	var mapped := HelmetVisualV2.direction_record(146, 1)
	assert(int(mapped.get("source_row", -1)) == 0)
	assert(str(mapped.get("source_direction", "")) == "S")
	assert(
		"人物目标 NE <- 头盔源 S(row 0)" in str(editor.get_node(
			"CalibrationUI/Panel/VBox/MappingStatus/Mapping"
		).text)
	)

	# Keyboard and mouse controls each move exactly one integer pixel.
	var right_event := InputEventKey.new()
	right_event.keycode = KEY_RIGHT
	right_event.pressed = true
	editor._unhandled_input(right_event)
	editor.get_node(
		"CalibrationUI/Panel/VBox/Commands/NudgeUp"
	).emit_signal("pressed")
	mapped = HelmetVisualV2.direction_record(146, 1)
	assert(_vector(mapped.get("nudge", [])) == Vector2i(1, -1))
	assert("DIRTY" in str(editor.get_node(
		"CalibrationUI/Panel/VBox/MappingStatus/State"
	).text))

	# Undo discards only the current unsaved direction and restores formal data.
	editor.get_node(
		"CalibrationUI/Panel/VBox/Commands/Undo"
	).emit_signal("pressed")
	mapped = HelmetVisualV2.direction_record(146, 1)
	assert(int(mapped.get("source_row", -1)) == 3)
	assert(_vector(mapped.get("nudge", [])) == Vector2i.ZERO)

	# Reapply, then save through the visible button and verify reload parity.
	source_row_zero.emit_signal("pressed")
	editor._unhandled_input(right_event)
	editor.get_node(
		"CalibrationUI/Panel/VBox/Commands/Save"
	).emit_signal("pressed")
	editor.reload_formal_data()
	mapped = HelmetVisualV2.direction_record(146, 1)
	assert(int(mapped.get("source_row", -1)) == 0)
	assert(str(mapped.get("source_direction", "")) == "S")
	assert(_vector(mapped.get("nudge", [])) == Vector2i.RIGHT)
	assert(str(mapped.get("status", "")) in ["valid", "locked"])
	assert(mapped.has("locked"))

	# An unsaved remap can still be discarded back to the newly saved temp record.
	assert(editor.map_source_row_to_current_target(1))
	assert(int(HelmetVisualV2.direction_record(146, 1).get("source_row", -1)) == 1)
	editor.undo_current_direction()
	assert(int(HelmetVisualV2.direction_record(146, 1).get("source_row", -1)) == 0)

	# Asset-level scale applies once to every direction, bakes all six actions,
	# uses nearest-neighbour around the local pivot, and survives runtime reload.
	var scale_plus := editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/ScalePlus"
	) as Button
	scale_plus.emit_signal("pressed")
	assert(HelmetVisualV2.uniform_scale_percent(146) == 101)
	var keyboard_plus := InputEventKey.new()
	keyboard_plus.keycode = KEY_EQUAL
	keyboard_plus.pressed = true
	editor._unhandled_input(keyboard_plus)
	assert(HelmetVisualV2.uniform_scale_percent(146) == 102)
	var keyboard_minus := InputEventKey.new()
	keyboard_minus.keycode = KEY_MINUS
	keyboard_minus.pressed = true
	editor._unhandled_input(keyboard_minus)
	assert(HelmetVisualV2.uniform_scale_percent(146) == 101)
	for direction_index: int in 8:
		assert(HelmetVisualV2.uniform_scale_percent(146) == 101)
	assert(editor.set_uniform_scale_percent(125))
	var synthetic := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	synthetic.fill(Color(0, 0, 0, 0))
	synthetic.set_pixel(4, 4, Color.WHITE)
	var scaled: Image = editor.scale_cell_around_pivot(
		synthetic, Vector2i(4, 4), 125
	)
	assert(scaled.get_pixel(4, 4).a == 1.0)
	editor.get_node(
		"CalibrationUI/Panel/VBox/Commands/Save"
	).emit_signal("pressed")
	editor.reload_formal_data()
	assert(HelmetVisualV2.uniform_scale_percent(146) == 125)
	var asset_override := HelmetVisualV2.visual_asset_override_for_item(146)
	var derived: Dictionary = asset_override.get("derivedAtlases", {})
	var source_hashes: Dictionary = asset_override.get("sourceAtlasSha256", {})
	var derived_hashes: Dictionary = asset_override.get("derivedAtlasSha256", {})
	for action: String in ["idle", "walk", "attack", "cast", "hit", "death"]:
		assert(derived.has(action))
		assert(str(derived[action]).begins_with("res://outputs/"))
		assert(FileAccess.file_exists(str(derived[action])))
		var source_path := HelmetVisualV2.base_action_texture_path(
			146, action, 0, "helmet_front"
		)
		assert(FileAccess.get_sha256(source_path) == str(source_hashes[action]))
		assert(
			FileAccess.get_sha256(str(derived[action]))
			== str(derived_hashes[action])
		)
		var source_image := (load(source_path) as Texture2D).get_image()
		var derived_image := Image.load_from_file(str(derived[action]))
		assert(source_image.get_size() == derived_image.get_size())
		var frame_count := int(
			source_image.get_width() / ArtSpec.WARRIOR_FRAME.x
		)
		for source_row: int in 8:
			for frame_index: int in frame_count:
				var cell_rect := Rect2i(
					frame_index * ArtSpec.WARRIOR_FRAME.x,
					source_row * ArtSpec.WARRIOR_FRAME.y,
					ArtSpec.WARRIOR_FRAME.x,
					ArtSpec.WARRIOR_FRAME.y
				)
				var expected_cell: Image = editor.scale_cell_around_pivot(
					source_image.get_region(cell_rect),
					HelmetVisualV2.pivot_for_source_row(
						146, action, source_row, frame_index
					),
					125
				)
				assert(
					expected_cell.get_data()
					== derived_image.get_region(cell_rect).get_data(),
					"bake mismatch action=%s source_row=%d frame=%d pivot=%s"
					% [
						action,
						source_row,
						frame_index,
						HelmetVisualV2.pivot_for_source_row(
							146, action, source_row, frame_index
						),
					]
				)
		assert(
			HelmetVisualV2.action_texture_path(146, action, 0, "helmet_front")
			== str(derived[action])
		)
	for direction_index: int in 8:
		assert(
			HelmetVisualV2.direction_record(
				146, direction_index
			).get("runtime_scale", []) == [1.0, 1.0]
		)
	var bake_policy: Dictionary = asset_override.get("bakePolicy", {})
	assert(str(bake_policy.get("filter", "")) == "nearest")
	assert(bool(bake_policy.get("pivotInvariant", false)))
	assert(bool(bake_policy.get("castPivotUsesSameFramePrimaryHairEvidence", false)))

	# Complete the eight saved idle targets. Only then may the explicit
	# "generate all actions" workflow become available.
	for direction_index: int in 8:
		if direction_index == 1:
			continue
		editor.select_target_direction(direction_index)
		var current_record := HelmetVisualV2.direction_record(
			146, direction_index
		)
		assert(editor.map_source_row_to_current_target(
			int(current_record.get("source_row", -1))
		))
		assert(editor.save_current_direction())
	assert(HelmetVisualV2.idle_baseline_complete(146))
	var generate_button := editor.get_node(
		"CalibrationUI/Panel/VBox/Commands/GenerateAllActions"
	) as Button
	assert(not generate_button.disabled)
	var saved_146_before: Variant = HelmetVisualV2.calibration_overrides().get(
		"itemOverrides", {}
	).get("146", {}).duplicate(true)
	assert(editor.generate_all_actions_from_idle())
	assert(
		saved_146_before
		== HelmetVisualV2.calibration_overrides().get(
			"itemOverrides", {}
		).get("146", {})
	)
	var trace_146 := _json(
		"%s/helmet_146_generated_all_actions_trace.json" % OUTPUT_ROOT
	)
	assert(bool(trace_146.get("passed", false)))
	assert(int(trace_146.get("headSocketRecordCount", 0)) == 232)
	assert(trace_146.get("records", []).size() == 232)
	assert(bool(trace_146.get("idleBaselinePreserved", false)))

	# Item 151 exposes opaque original source slots. The editor does not assign
	# N/S semantics, and both mapping/nudge and asset-scale are editable.
	editor.select_item(151)
	assert(not HelmetVisualV2.is_read_only(151))
	assert((editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/Scale"
	) as SpinBox).editable)
	var source_151_hashes: Dictionary = {}
	for action: String in ["idle", "walk", "attack", "cast", "hit", "death"]:
		var evidence: Dictionary = HelmetVisualV2.visual_asset_for_item(
			151
		).get("source", {}).get("actions", {}).get(action, {})
		source_151_hashes[action] = FileAccess.get_sha256(
			str(evidence.get("path", ""))
		)
	for source_row: int in 8:
		var source_button := source_grid.get_node(
			"Source_Row%d" % source_row
		) as TextureButton
		assert(not source_button.disabled)
		assert(
			"源槽 %d" % source_row
			in str((source_button.get_node("Label") as Label).text)
		)
		assert(_has_opaque_pixel(editor.source_row_thumbnail(source_row)))
	assert(editor.set_uniform_scale_percent(110))
	target_ne.emit_signal("pressed")
	(source_grid.get_node("Source_Row3") as TextureButton).emit_signal("pressed")
	assert(editor.nudge_current(Vector2i.LEFT))
	assert(
		"人物目标 NE <- 黑铁原始源槽 3"
		in str(editor.get_node(
			"CalibrationUI/Panel/VBox/MappingStatus/Mapping"
		).text)
	)
	assert(editor.save_current_direction())
	for direction_index: int in 8:
		if direction_index == 1:
			continue
		editor.select_target_direction(direction_index)
		assert(editor.map_source_row_to_current_target((direction_index + 3) % 8))
		assert(editor.save_current_direction())
	# Reusing source slot 3 is a visible warning, never a save blocker.
	editor.select_target_direction(0)
	assert(editor.map_source_row_to_current_target(3))
	assert(editor.save_current_direction())
	assert("警告" in str(editor.get_node(
		"CalibrationUI/Panel/VBox/MappingStatus/State"
	).text))
	assert(HelmetVisualV2.idle_baseline_complete(151))
	assert(not generate_button.disabled)
	var saved_151_before: Variant = HelmetVisualV2.calibration_overrides().get(
		"itemOverrides", {}
	).get("151", {}).duplicate(true)
	assert(editor.generate_all_actions_from_idle())
	assert(
		saved_151_before
		== HelmetVisualV2.calibration_overrides().get(
			"itemOverrides", {}
		).get("151", {})
	)
	editor.reload_formal_data()
	assert(HelmetVisualV2.uniform_scale_percent(151) == 110)
	var saved_151_ne := HelmetVisualV2.direction_record(151, 1)
	assert(int(saved_151_ne.get("source_row", -1)) == 3)
	assert(str(saved_151_ne.get("source_slot_id", "")) == "slot_3")
	assert(_vector(saved_151_ne.get("nudge", [])) == Vector2i.LEFT)
	var trace_151 := _json(
		"%s/helmet_151_generated_all_actions_trace.json" % OUTPUT_ROOT
	)
	assert(bool(trace_151.get("passed", false)))
	assert(trace_151.get("records", []).size() == 232)
	assert(bool(trace_151.get("idleBaselinePreserved", false)))
	assert(not trace_151.get("duplicateTargetSourceRows", []).is_empty())
	for action: String in source_151_hashes:
		var evidence: Dictionary = HelmetVisualV2.visual_asset_for_item(
			151
		).get("source", {}).get("actions", {}).get(action, {})
		assert(
			FileAccess.get_sha256(str(evidence.get("path", "")))
			== str(source_151_hashes[action])
		)
	assert(not HelmetVisualV2.set_session_calibration_override(
		146, 0, {"source_row": 8, "source_slot_id": "slot_8"}
	))

	await editor._save_editor_ui_preview(ProjectSettings.globalize_path(OUTPUT_ROOT))
	assert(FileAccess.get_file_as_string(FORMAL_OVERRIDE) == formal_before)
	assert(all_source_hashes_before == {
		"146": _source_hashes(146),
		"151": _source_hashes(151),
	})
	assert(FileAccess.file_exists(
		"%s/helmet_mapping_editor_ui_preview.png" % OUTPUT_ROOT
	))
	print(
		"EQUIPMENT_HELMET_MAPPING_EDITOR_TEST_PASS "
		+ "items=146,151 editable=true idle_to_all_actions=232 scale_baked=true cast=true"
	)
	HelmetVisualV2.reset_calibration_override_path()
	editor.dispose_runtime_for_test()
	editor.queue_free()
	await get_tree().process_frame
	get_tree().quit.call_deferred(0)


func _vector(value: Variant) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary)
	return parsed


func _has_opaque_pixel(image: Image) -> bool:
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				return true
	return false


func _source_hashes(item_id: int) -> Dictionary:
	var result: Dictionary = {}
	for action: String in ["idle", "walk", "attack", "cast", "hit", "death"]:
		var path := HelmetVisualV2.base_action_texture_path(
			item_id, action, 0, "helmet_front"
		)
		result[action] = FileAccess.get_sha256(path)
	return result


func _assert_editor_layout(editor: Node) -> void:
	var base := "CalibrationUI/Panel/VBox/"
	var ordered_paths := [
		"Inputs",
		"MappingStatus",
		"TargetLabel",
		"TargetDirections",
		"SourceLabel",
		"SourceDirections",
		"Previews",
		"Layers",
		"Commands",
		"Legend",
	]
	var previous_end := -INF
	for path: String in ordered_paths:
		var control := editor.get_node(base + path) as Control
		var rect := control.get_global_rect()
		assert(rect.size.x > 0.0 and rect.size.y > 0.0, path)
		assert(rect.position.y >= previous_end - 0.5, path)
		previous_end = rect.end.y
	var full_column := editor.get_node(
		base + "Previews/FullColumn"
	) as Control
	var head_column := editor.get_node(
		base + "Previews/HeadColumn"
	) as Control
	assert(not full_column.get_global_rect().intersects(
		head_column.get_global_rect()
	))
	for grid_name: String in ["TargetDirections", "SourceDirections"]:
		var grid := editor.get_node(base + grid_name) as GridContainer
		var grid_rect := grid.get_global_rect()
		for child: Control in grid.get_children():
			assert(
				grid_rect.encloses(child.get_global_rect()),
				str(child.name)
			)
