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
	await get_tree().process_frame
	assert(not editor.quit_was_requested())
	assert(not editor.initialization_error().is_empty())
	var window_policy: Dictionary = editor.interactive_window_policy()
	assert(str(window_policy.get("mode", "")) == "maximized")
	assert(bool(window_policy.get("dpiSafe", false)))
	assert(not bool(window_policy.get("manualPhysicalSize", true)))
	assert(not bool(window_policy.get("manualPosition", true)))
	assert(not bool(window_policy.get("projectSettingsModified", true)))
	var tool_text := FileAccess.get_file_as_string(
		"res://tools/helmet_calibration_tool.gd"
	)
	assert("window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)" in tool_text)
	assert("window_set_size(" not in tool_text)
	assert("window_set_min_size(" not in tool_text)
	assert("window_set_position(" not in tool_text)
	assert("screen_get_usable_rect(" not in tool_text)
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
	var calibration_ui := editor.get_node("CalibrationUI") as ScrollContainer
	var editor_background := editor.get_node("EditorBackground") as ColorRect
	var content_panel := editor.get_node(
		"CalibrationUI/Panel"
	) as PanelContainer
	assert(editor.game_render_is_isolated())
	assert(editor.get_node("GameDataViewport") is SubViewport)
	assert(calibration_ui.get_child_count() == 1)
	assert(calibration_ui.get_child(0) == content_panel)
	assert(
		calibration_ui.horizontal_scroll_mode
		== ScrollContainer.SCROLL_MODE_AUTO
	)
	assert(
		calibration_ui.vertical_scroll_mode
		== ScrollContainer.SCROLL_MODE_AUTO
	)
	assert(content_panel.custom_minimum_size == Vector2(1600, 900))
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
	# Reproduce the user's high-DPI effective client area. The 1600x900
	# workspace must remain reachable through both scroll axes at 802x480.
	calibration_ui.size = Vector2(802, 480)
	await get_tree().process_frame
	assert(calibration_ui.get_h_scroll_bar().visible)
	assert(calibration_ui.get_v_scroll_bar().visible)
	_assert_mouse_only_focus(editor, target_grid, source_grid)

	# Reproduce the real bug with menu controls deliberately made focusable.
	# Root _input must consume arrows before OptionButton GUI navigation.
	var item_menu := editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/Item"
	) as OptionButton
	var action_menu := editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/Action"
	) as OptionButton
	var direction_menu := editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/Direction"
	) as OptionButton
	var zoom_menu := editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/Zoom"
	) as OptionButton
	var frame_spin := editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/Frame"
	) as SpinBox
	var scale_spin := editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/Scale"
	) as SpinBox
	var save_all := editor.get_node(
		"CalibrationUI/Panel/VBox/Inputs/SaveAll"
	) as Button
	assert(save_all.text == "保存全部改动")
	assert(save_all.focus_mode == Control.FOCUS_NONE)
	var expected_calibration_items := [
		146, 147, 149, 150, 151, 218, 224, 228, 232, 236, 240,
	]
	assert(item_menu.item_count == expected_calibration_items.size())
	for item_index: int in item_menu.item_count:
		assert(
			int(item_menu.get_item_id(item_index))
			== expected_calibration_items[item_index]
		)
		editor.select_item(expected_calibration_items[item_index])
		editor._configure_runtime("idle", 0, 0)
		var helmet_layer := editor._visual.get_node(
			"ClientHelmetLayer"
		) as Sprite2D
		assert(helmet_layer.texture != null)
	editor.select_item(146)
	var menu_state_before := {
		"item": item_menu.selected,
		"action": action_menu.selected,
		"direction": direction_menu.selected,
		"zoom": zoom_menu.selected,
		"frame": frame_spin.value,
		"scale": scale_spin.value,
		"currentDirection": editor.current_direction,
		"currentFrame": editor.current_frame,
	}
	var nudge_before := _vector(
		HelmetVisualV2.direction_record(146, 0).get("nudge", [])
	)
	action_menu.focus_mode = Control.FOCUS_ALL
	action_menu.grab_focus()
	await _dispatch_key(KEY_UP, true, false)
	await _dispatch_key(KEY_UP, true, true)
	await _dispatch_key(KEY_UP, false, false)
	await _dispatch_key(KEY_DOWN, true, false)
	direction_menu.focus_mode = Control.FOCUS_ALL
	direction_menu.grab_focus()
	await _dispatch_key(KEY_LEFT, true, false)
	await _dispatch_key(KEY_LEFT, false, false)
	await _dispatch_key(KEY_RIGHT, true, false)
	await _dispatch_key(KEY_RIGHT, false, false)
	assert(
		_vector(HelmetVisualV2.direction_record(146, 0).get("nudge", []))
		== nudge_before + Vector2i.UP
	)
	assert(item_menu.selected == int(menu_state_before.item))
	assert(action_menu.selected == int(menu_state_before.action))
	assert(direction_menu.selected == int(menu_state_before.direction))
	assert(zoom_menu.selected == int(menu_state_before.zoom))
	assert(frame_spin.value == float(menu_state_before.frame))
	assert(scale_spin.value == float(menu_state_before.scale))
	assert(editor.current_direction == int(menu_state_before.currentDirection))
	assert(editor.current_frame == int(menu_state_before.currentFrame))
	editor._disable_keyboard_focus_for_editor_controls()
	_assert_mouse_only_focus(editor, target_grid, source_grid)
	editor.undo_current_direction()

	# Mouse target selection: NE must become the highlighted player target.
	var target_ne := target_grid.get_node("Target_NE") as TextureButton
	target_ne.emit_signal("pressed")
	assert(editor.current_direction == 1)
	assert(target_ne.button_pressed)
	var formal_ne_before := HelmetVisualV2.saved_direction_override(146, 1)

	# Every source thumbnail is the actual source atlas row advertised in metadata.
	for row: int in 8:
		var button := source_grid.get_node("Source_Row%d" % row) as TextureButton
		assert(int(button.get_meta("source_row", -1)) == row)
		var expected: Image = editor.source_row_thumbnail(row)
		assert(
			button.texture_normal.get_image().get_data()
			== expected.get_data()
		)
	assert(HelmetVisualV2.source_direction_for_row(146, 3) == "NW")
	assert(HelmetVisualV2.source_direction_for_row(146, 5) == "NE")
	var recipe: Dictionary = HelmetVisualV2.visual_asset_for_item(146).get(
		"bakedSourceOverrides", {}
	)
	assert(str(recipe.get("recipeId", "")) == (
		"elf_146.user_authorized_nw_mirror.v1"
	))
	assert(not bool(recipe.get("runtimeFlip", true)))
	var raw_idle := (load(
		HelmetVisualV2.base_action_texture_path(
			146, "idle", 0, "helmet_front"
		)
	) as Texture2D).get_image()
	var raw_row_3 := raw_idle.get_region(Rect2i(
		0,
		3 * ArtSpec.WARRIOR_FRAME.y,
		ArtSpec.WARRIOR_FRAME.x,
		ArtSpec.WARRIOR_FRAME.y
	))
	var raw_row_5 := raw_idle.get_region(Rect2i(
		0,
		5 * ArtSpec.WARRIOR_FRAME.y,
		ArtSpec.WARRIOR_FRAME.x,
		ArtSpec.WARRIOR_FRAME.y
	))
	var baked_nw: Image = editor.calibration_source_cell("idle", 3, 0)
	assert(baked_nw.get_data() != raw_row_3.get_data())
	assert(baked_nw.get_data() != raw_row_5.get_data())
	var expected_nw: Image = editor.mirror_cell_between_pivots(
		raw_row_5,
		HelmetVisualV2.pivot_for_source_row(146, "idle", 5, 0),
		HelmetVisualV2.pivot_for_source_row(146, "idle", 3, 0)
	)
	assert(baked_nw.get_data() == expected_nw.get_data())

	# The full-person and enlarged-head previews must use the same baked row 3
	# as the source thumbnail, never the unchanged row 3 in the primary atlas.
	editor._configure_runtime("idle", 7, 0)
	var runtime_nw: Image = editor._runtime_layer_cell("ClientHelmetLayer")
	var derived_idle_path := HelmetVisualV2.action_texture_path(
		146, "idle", 7, "helmet_front"
	)
	assert(FileAccess.file_exists(derived_idle_path))
	var derived_idle: Image = Image.load_from_file(derived_idle_path)
	var derived_nw: Image = derived_idle.get_region(Rect2i(
		0,
		3 * ArtSpec.WARRIOR_FRAME.y,
		ArtSpec.WARRIOR_FRAME.x,
		ArtSpec.WARRIOR_FRAME.y
	))
	assert(runtime_nw.get_data() == derived_nw.get_data())
	assert(runtime_nw.get_data() != raw_row_3.get_data())

	# Mouse source-row selection maps the current target through explicit semantics.
	var source_row_zero := source_grid.get_node("Source_Row0") as TextureButton
	source_row_zero.emit_signal("pressed")
	var mapped_nudge_before := _vector(
		HelmetVisualV2.direction_record(146, 1).get("nudge", [])
	)
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
	editor._input(right_event)
	editor.get_node(
		"CalibrationUI/Panel/VBox/Commands/NudgeUp"
	).emit_signal("pressed")
	mapped = HelmetVisualV2.direction_record(146, 1)
	assert(
		_vector(mapped.get("nudge", []))
		== mapped_nudge_before + Vector2i(1, -1)
	)
	assert("DIRTY" in str(editor.get_node(
		"CalibrationUI/Panel/VBox/MappingStatus/State"
	).text))

	# Undo discards only the current unsaved direction and restores formal data.
	editor.get_node(
		"CalibrationUI/Panel/VBox/Commands/Undo"
	).emit_signal("pressed")
	mapped = HelmetVisualV2.direction_record(146, 1)
	assert(
		int(mapped.get("source_row", -1))
		== int(formal_ne_before.get("source_row", 3))
	)
	assert(
		_vector(mapped.get("nudge", []))
		== _vector(formal_ne_before.get("nudge", [0, 0]))
	)

	# Reapply, then save through the visible button and verify reload parity.
	source_row_zero.emit_signal("pressed")
	editor._input(right_event)
	editor.get_node(
		"CalibrationUI/Panel/VBox/Commands/Save"
	).emit_signal("pressed")
	editor.reload_formal_data()
	mapped = HelmetVisualV2.direction_record(146, 1)
	assert(int(mapped.get("source_row", -1)) == 0)
	assert(str(mapped.get("source_direction", "")) == "S")
	assert(
		_vector(mapped.get("nudge", []))
		== _vector(formal_ne_before.get("nudge", [0, 0])) + Vector2i.RIGHT
	)
	assert(str(mapped.get("status", "")) in ["valid", "locked"])
	assert(mapped.has("locked"))

	# An unsaved remap can still be discarded back to the newly saved temp record.
	assert(editor.map_source_row_to_current_target(1))
	assert(int(HelmetVisualV2.direction_record(146, 1).get("source_row", -1)) == 1)
	editor.undo_current_direction()
	assert(int(HelmetVisualV2.direction_record(146, 1).get("source_row", -1)) == 0)

	# The always-visible save button persists every dirty direction in one click
	# without falsely marking an untouched direction as complete.
	var nw_saved_before := HelmetVisualV2.saved_direction_override(146, 7)
	editor.select_target_direction(2)
	var batch_e_before := _vector(
		HelmetVisualV2.direction_record(146, 2).get("nudge", [])
	)
	assert(editor.map_source_row_to_current_target(6))
	assert(editor.nudge_current(Vector2i.DOWN))
	editor.select_target_direction(3)
	var batch_se_before := _vector(
		HelmetVisualV2.direction_record(146, 3).get("nudge", [])
	)
	assert(editor.map_source_row_to_current_target(1))
	assert(editor.nudge_current(Vector2i.LEFT))
	save_all.emit_signal("pressed")
	assert("已保存全部改动" in str(editor.get_node(
		"CalibrationUI/Panel/VBox/MappingStatus/State"
	).text))
	editor.reload_formal_data()
	var batch_e := HelmetVisualV2.direction_record(146, 2)
	var batch_se := HelmetVisualV2.direction_record(146, 3)
	assert(int(batch_e.get("source_row", -1)) == 6)
	assert(
		_vector(batch_e.get("nudge", []))
		== batch_e_before + Vector2i.DOWN
	)
	assert(int(batch_se.get("source_row", -1)) == 1)
	assert(
		_vector(batch_se.get("nudge", []))
		== batch_se_before + Vector2i.LEFT
	)
	assert(HelmetVisualV2.saved_direction_override(146, 7) == nw_saved_before)

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
	editor._input(keyboard_plus)
	assert(HelmetVisualV2.uniform_scale_percent(146) == 102)
	var keyboard_minus := InputEventKey.new()
	keyboard_minus.keycode = KEY_MINUS
	keyboard_minus.pressed = true
	editor._input(keyboard_minus)
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
					editor.calibration_source_cell(
						action, source_row, frame_index
					),
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
		var runtime_path := HelmetVisualV2.action_texture_path(
			146, action, 0, "helmet_front"
		)
		assert(runtime_path == str(derived[action]))
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
	assert(str(bake_policy.get("sourceRecipeId", "")) == (
		"elf_146.user_authorized_nw_mirror.v1"
	))

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
	var black_recipe: Dictionary = HelmetVisualV2.visual_asset_for_item(151).get(
		"bakedSourceOverrides", {}
	)
	assert(str(black_recipe.get("recipeId", "")) == (
		"black_iron_151.user_authorized_nw_from_ne_mirror.v2"
	))
	assert(not bool(black_recipe.get("runtimeFlip", true)))
	var black_action_frames := {
		"idle": 4, "walk": 6, "attack": 6,
		"cast": 6, "hit": 3, "death": 4,
	}
	for black_action: String in black_action_frames:
		var black_raw := (load(
			HelmetVisualV2.base_action_texture_path(
				151, black_action, 0, "helmet_front"
			)
		) as Texture2D).get_image()
		for black_frame: int in int(black_action_frames[black_action]):
			var raw_black_ne := black_raw.get_region(Rect2i(
				black_frame * ArtSpec.WARRIOR_FRAME.x,
				1 * ArtSpec.WARRIOR_FRAME.y,
				ArtSpec.WARRIOR_FRAME.x,
				ArtSpec.WARRIOR_FRAME.y
			))
			assert(
				editor.calibration_source_cell(
					black_action, 5, black_frame
				).get_data()
				== editor.mirror_cell_between_pivots(
					raw_black_ne,
					HelmetVisualV2.pivot_for_source_row(
						151, black_action, 1, black_frame
					),
					HelmetVisualV2.pivot_for_source_row(
						151, black_action, 5, black_frame
					)
				).get_data()
			)
	assert(editor.set_uniform_scale_percent(110))
	target_ne.emit_signal("pressed")
	var initial_151_ne_nudge := _vector(
		HelmetVisualV2.direction_record(151, 1).get("nudge", [])
	)
	(source_grid.get_node("Source_Row0") as TextureButton).emit_signal("pressed")
	assert(editor.nudge_current(Vector2i.LEFT))
	assert(
		"人物目标 NE <- 黑铁原始源槽 0"
		in str(editor.get_node(
			"CalibrationUI/Panel/VBox/MappingStatus/Mapping"
		).text)
	)
	assert(editor.save_current_direction())
	for direction_index: int in 8:
		if direction_index == 1:
			continue
		editor.select_target_direction(direction_index)
		var source_row := HelmetVisualV2.source_direction_row(
			151, direction_index
		)
		assert(editor.map_source_row_to_current_target(source_row))
		assert(editor.save_current_direction())
	# Reusing source slot 0 is a visible warning, never a save blocker.
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
	assert(int(saved_151_ne.get("source_row", -1)) == 0)
	assert(str(saved_151_ne.get("source_slot_id", "")) == "slot_0")
	assert(
		_vector(saved_151_ne.get("nudge", []))
		== initial_151_ne_nudge + Vector2i.LEFT
	)
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
	# S/L remain root-level shortcuts even if a menu becomes a focus
	# candidate, and must not alter any menu, frame, or scale selection.
	var shortcut_state_before := {
		"item": item_menu.selected,
		"action": action_menu.selected,
		"direction": direction_menu.selected,
		"zoom": zoom_menu.selected,
		"frame": frame_spin.value,
		"scale": scale_spin.value,
	}
	action_menu.focus_mode = Control.FOCUS_ALL
	action_menu.grab_focus()
	await _dispatch_key(KEY_S, true, false)
	await _dispatch_key(KEY_S, false, false)
	assert(not HelmetVisualV2.saved_direction_override(
		151, editor.current_direction
	).is_empty())
	await _dispatch_key(KEY_L, true, false)
	await _dispatch_key(KEY_L, false, false)
	assert(bool(HelmetVisualV2.direction_record(
		151, editor.current_direction
	).get("locked", false)))
	assert(item_menu.selected == int(shortcut_state_before.item))
	assert(action_menu.selected == int(shortcut_state_before.action))
	assert(direction_menu.selected == int(shortcut_state_before.direction))
	assert(zoom_menu.selected == int(shortcut_state_before.zoom))
	assert(frame_spin.value == float(shortcut_state_before.frame))
	assert(scale_spin.value == float(shortcut_state_before.scale))
	editor._disable_keyboard_focus_for_editor_controls()
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
		"Title",
		"StartupStatus",
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
	var content_panel := editor.get_node("CalibrationUI/Panel") as Control
	var content_rect := content_panel.get_global_rect()
	var previous_end := -INF
	for path: String in ordered_paths:
		var control := editor.get_node(base + path) as Control
		var rect := control.get_global_rect()
		assert(rect.size.x > 0.0 and rect.size.y > 0.0, path)
		assert(content_rect.encloses(rect), path)
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


func _assert_mouse_only_focus(
	editor: Node,
	target_grid: GridContainer,
	source_grid: GridContainer
) -> void:
	var base := "CalibrationUI/Panel/VBox/"
	for path: String in [
		"Inputs/Item",
		"Inputs/Action",
		"Inputs/Direction",
		"Inputs/Frame",
		"Inputs/Zoom",
		"Inputs/ScaleMinus",
		"Inputs/Scale",
		"Inputs/ScalePlus",
	]:
		assert((editor.get_node(base + path) as Control).focus_mode == Control.FOCUS_NONE, path)
	for spin_name: String in ["Frame", "Scale"]:
		var spin := editor.get_node(base + "Inputs/" + spin_name) as SpinBox
		assert(spin.get_line_edit().focus_mode == Control.FOCUS_NONE)
	for grid: GridContainer in [target_grid, source_grid]:
		for child: Control in grid.get_children():
			assert(child.focus_mode == Control.FOCUS_NONE, str(child.name))
	for container_name: String in ["Layers", "Commands"]:
		var container := editor.get_node(base + container_name) as Container
		for child: Control in container.get_children():
			assert(child.focus_mode == Control.FOCUS_NONE, str(child.name))


func _dispatch_key(keycode: Key, pressed: bool, echo: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	await get_tree().process_frame
