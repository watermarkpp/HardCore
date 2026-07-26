class_name HelmetCalibrationTool
extends Node

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const ITEM_ID := 146
const PLAYER_VISUAL_ID := "player.male.cloth_002"
const OUTPUT_ROOT := "res://outputs/visual_acceptance/helmet_calibration"
const TEST_OVERRIDE_PATH := OUTPUT_ROOT + "/helmet_146_test_overrides.json"
const DIRECTIONS := HelmetVisualV2.CANONICAL_DIRECTIONS
const ACTIONS := {"idle": 4, "walk": 6, "attack": 6, "hit": 3, "death": 4}
const DIRECTION_VECTORS := [
	Vector2.UP,
	Vector2(0.70710678, -0.70710678),
	Vector2.RIGHT,
	Vector2(0.70710678, 0.70710678),
	Vector2.DOWN,
	Vector2(-0.70710678, 0.70710678),
	Vector2.LEFT,
	Vector2(-0.70710678, -0.70710678),
]
const FRAME_CANVAS := Vector2i(256, 256)
const FOOT_POINT := Vector2i(128, 190)
const HEAD_ZOOM_SOURCE_SIZE := Vector2i(64, 64)

var current_action := "idle"
var current_direction := 0
var current_frame := 0
var head_zoom := 8
var show_face_mask := true
var show_hair_mask := true
var show_helmet_back := true
var show_helmet_front := true
var show_head_occlusion_mask := true
var _session_unlocked: Dictionary = {}
var _game: Node
var _player: PlayerCharacter
var _visual: Node2D
var _formal_override_before := ""


func _ready() -> void:
	_setup_ui()
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.ensure_developer_test_character()
	assert(PlayerState.select_character("developer_warrior_30"))
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState.equipment = {
		"衣服": {"item_id": 116, "name": "布衣(男)", "instance_id": "helmet_v2_cloth"},
		"头盔": {"item_id": ITEM_ID, "name": "精灵头盔", "instance_id": "helmet_v2_146"},
	}
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = _game.player
	_visual = _player.get_node("PlayerVisual")
	assert(_visual != null)
	var is_headless := DisplayServer.get_name() == "headless"
	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	if is_headless:
		_formal_override_before = FileAccess.get_file_as_string(
			HelmetVisualV2.OVERRIDE_PATH
		)
		_write_json(
			ProjectSettings.globalize_path(TEST_OVERRIDE_PATH),
			HelmetVisualV2.calibration_overrides()
		)
		assert(HelmetVisualV2.set_calibration_override_path_for_test(
			TEST_OVERRIDE_PATH
		))
	_render_current_previews()
	assert(get_node("CalibrationUI/Panel/VBox/Previews/FullColumn/FullPersonPreview").texture != null)
	assert(get_node("CalibrationUI/Panel/VBox/Previews/HeadColumn/HeadPreview").texture != null)
	if not is_headless:
		print("HELMET_CALIBRATION_TOOL_INTERACTIVE_READY item=146")
		return
	_generate_idle_outputs(output_dir)
	_generate_all_actions_overview(output_dir)
	var audit := _direction_audit()
	_write_json(output_dir.path_join("helmet_146_direction_audit.json"), audit)
	var validation := _validation_report(audit)
	_write_json(output_dir.path_join("helmet_146_validation_report.json"), validation)
	assert(bool(validation.get("passed", false)))
	HelmetVisualV2.reset_calibration_override_path()
	assert(
		FileAccess.get_file_as_string(HelmetVisualV2.OVERRIDE_PATH)
		== _formal_override_before
	)
	print(
		"HELMET_CALIBRATION_TOOL_PASS "
		+ "item=146 sockets=184 directions=8 golden151_pixel_diff=0"
	)
	get_tree().quit(0)


func _setup_ui() -> void:
	var action_control := get_node("CalibrationUI/Panel/VBox/Inputs/Action") as OptionButton
	var direction_control := get_node("CalibrationUI/Panel/VBox/Inputs/Direction") as OptionButton
	var zoom_control := get_node("CalibrationUI/Panel/VBox/Inputs/Zoom") as OptionButton
	for action: String in ACTIONS:
		action_control.add_item(action)
	for direction: String in DIRECTIONS:
		direction_control.add_item(direction)
	for zoom_value: int in [1, 8, 10]:
		zoom_control.add_item("%dx" % zoom_value, zoom_value)
	zoom_control.select(1)
	action_control.item_selected.connect(func(index: int) -> void:
		select_action(str(action_control.get_item_text(index)))
		_render_current_previews()
	)
	direction_control.item_selected.connect(func(index: int) -> void:
		select_direction(str(direction_control.get_item_text(index)))
		_render_current_previews()
	)
	var frame_control := get_node("CalibrationUI/Panel/VBox/Inputs/Frame") as SpinBox
	frame_control.value_changed.connect(func(value: float) -> void:
		select_frame(int(value))
		_render_current_previews()
	)
	zoom_control.item_selected.connect(func(index: int) -> void:
		set_head_zoom(int(zoom_control.get_item_id(index)))
		_render_current_previews()
	)
	var layer_controls := {
		"FaceMask": "face_mask",
		"HairMask": "hair_mask",
		"HelmetBack": "helmet_back",
		"HelmetFront": "helmet_front",
		"OcclusionMask": "head_occlusion_mask",
	}
	for control_name: String in layer_controls:
		var control := get_node(
			"CalibrationUI/Panel/VBox/Layers/%s" % control_name
		) as CheckButton
		var layer_name: String = str(layer_controls[control_name])
		control.toggled.connect(func(enabled: bool) -> void:
			set_layer_visible(layer_name, enabled)
			_render_current_previews()
		)
	get_node("CalibrationUI/Panel/VBox/Commands/Save").pressed.connect(
		func() -> void: save_current_direction()
	)
	get_node("CalibrationUI/Panel/VBox/Commands/Lock").pressed.connect(
		func() -> void: lock_current_direction()
	)


func select_action(action: String) -> void:
	assert(ACTIONS.has(action))
	current_action = action
	current_frame = mini(current_frame, int(ACTIONS[action]) - 1)
	var frame_control := get_node("CalibrationUI/Panel/VBox/Inputs/Frame") as SpinBox
	frame_control.max_value = int(ACTIONS[action]) - 1
	frame_control.value = current_frame


func select_direction(direction: String) -> void:
	assert(direction in DIRECTIONS)
	current_direction = DIRECTIONS.find(direction)


func select_frame(frame_index: int) -> void:
	current_frame = clampi(frame_index, 0, int(ACTIONS[current_action]) - 1)


func set_head_zoom(scale_factor: int) -> void:
	assert(scale_factor in [1, 8, 10])
	head_zoom = scale_factor


func set_layer_visible(layer_name: String, enabled: bool) -> void:
	match layer_name:
		"face_mask": show_face_mask = enabled
		"hair_mask": show_hair_mask = enabled
		"helmet_back": show_helmet_back = enabled
		"helmet_front": show_helmet_front = enabled
		"head_occlusion_mask": show_head_occlusion_mask = enabled
		_: assert(false, "unknown calibration layer: %s" % layer_name)


func unlock_current_direction_for_session() -> void:
	_session_unlocked[DIRECTIONS[current_direction]] = true


func nudge_current(delta: Vector2i) -> bool:
	assert(delta in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT])
	var direction: String = str(DIRECTIONS[current_direction])
	if HelmetVisualV2.is_locked(ITEM_ID, current_direction) and not bool(_session_unlocked.get(direction, false)):
		return false
	var record := HelmetVisualV2.direction_record(ITEM_ID, current_direction)
	var nudge_value: Array = record.get("nudge", [0, 0])
	return HelmetVisualV2.set_session_calibration_override(
		ITEM_ID,
		current_direction,
		{"nudge": [int(nudge_value[0]) + delta.x, int(nudge_value[1]) + delta.y]}
	)


func save_current_direction() -> bool:
	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var direction: String = str(DIRECTIONS[current_direction])
	var record := HelmetVisualV2.direction_record(ITEM_ID, current_direction)
	if not HelmetVisualV2.persist_calibration_override(
		ITEM_ID,
		current_direction,
		{
			"nudge": record.get("nudge", [0, 0]),
			"status": record.get("status", "valid"),
			"locked": record.get("locked", false),
		}
	):
		return false
	var payload := {
		"contractId": "equipment.world_helmet.calibration.session.v1",
		"itemId": ITEM_ID,
		"action": current_action,
		"direction": direction,
		"frameIndex": current_frame,
		"headSocket": _vector_array(HelmetVisualV2.body_head_socket(
			PLAYER_VISUAL_ID, current_action, current_direction, current_frame
		)),
		"directionRecord": record,
	}
	_write_json(output_dir.path_join("helmet_146_calibration_working.json"), payload)
	return true


func lock_current_direction() -> bool:
	var record := HelmetVisualV2.direction_record(ITEM_ID, current_direction)
	if not HelmetVisualV2.set_session_calibration_override(
		ITEM_ID, current_direction, {"locked": true, "status": "locked"}
	):
		return false
	record = HelmetVisualV2.direction_record(ITEM_ID, current_direction)
	_session_unlocked.erase(DIRECTIONS[current_direction])
	return HelmetVisualV2.persist_calibration_override(
		ITEM_ID,
		current_direction,
		{
			"nudge": record.get("nudge", [0, 0]),
			"status": "locked",
			"locked": true,
		}
	)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_UP: nudge_current(Vector2i.UP)
		KEY_DOWN: nudge_current(Vector2i.DOWN)
		KEY_LEFT: nudge_current(Vector2i.LEFT)
		KEY_RIGHT: nudge_current(Vector2i.RIGHT)
		KEY_1: set_head_zoom(1)
		KEY_8: set_head_zoom(8)
		KEY_0: set_head_zoom(10)
		KEY_S: save_current_direction()
		KEY_L: lock_current_direction()
	_render_current_previews()


func _configure_runtime(action: String, direction_index: int, frame_index: int) -> void:
	_player.facing = DIRECTION_VECTORS[direction_index]
	_player.actual_motion_facing = DIRECTION_VECTORS[direction_index]
	_visual._action_name = action
	if action == "idle":
		_player.velocity = Vector2.ZERO
		_visual._action_remaining = 0.0
		_visual._last_state = "idle"
		_visual._elapsed = float(frame_index) / 6.0 + 0.001
	elif action == "walk":
		_player.velocity = DIRECTION_VECTORS[direction_index] * 80.0
		_visual._action_remaining = 0.0
		_visual._last_state = "walk"
		_visual._elapsed = float(frame_index) / 10.0 + 0.001
	else:
		_player.velocity = Vector2.ZERO
		_visual._action_remaining = float(ACTIONS[action])
		_visual._action_duration = float(ACTIONS[action])
		_visual._last_state = "action"
		_visual._elapsed = float(frame_index) + 0.001
	_visual._process(0.0)
	assert(_visual.current_direction == direction_index)
	assert(_visual.current_frame == frame_index)


func _runtime_frame(
	action: String,
	direction_index: int,
	frame_index: int,
	include_calibration_overlays: bool = false
) -> Image:
	_configure_runtime(action, direction_index, frame_index)
	var frame := Image.create(FRAME_CANVAS.x, FRAME_CANVAS.y, false, Image.FORMAT_RGBA8)
	frame.fill(Color(0, 0, 0, 0))
	var layer_names: Array[String] = []
	if show_helmet_back:
		layer_names.append("ClientHelmetBackLayer")
	layer_names.append("BodySprite")
	if show_helmet_front:
		layer_names.append("ClientHelmetLayer")
	if show_head_occlusion_mask:
		layer_names.append("HeadOcclusionMaskLayer")
	for layer_name: String in layer_names:
		var layer := _visual.get_node(layer_name) as Sprite2D
		if layer == null or not layer.visible or layer.texture == null:
			continue
		assert(layer.scale == Vector2.ONE and not layer.flip_h)
		var source := layer.texture.get_image()
		var cell := source.get_region(Rect2i(layer.region_rect))
		var destination := FOOT_POINT + Vector2i(_visual.position.round()) + Vector2i(layer.position.round())
		frame.blend_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), destination)
	if include_calibration_overlays:
		_draw_calibration_overlays(frame, action, direction_index, frame_index)
	return frame


func _draw_calibration_overlays(
	image: Image,
	action: String,
	direction_index: int,
	frame_index: int
) -> void:
	var record := HelmetVisualV2.direction_record(ITEM_ID, direction_index)
	var overlays: Dictionary = record.get("calibrationOverlays", {})
	var socket := HelmetVisualV2.body_head_socket(
		PLAYER_VISUAL_ID, action, direction_index, frame_index
	)
	var body_top_left := (
		FOOT_POINT
		+ Vector2i(_visual.position.round())
		+ Vector2i(_visual.sprite.position.round())
	)
	if show_face_mask:
		_draw_overlay_rect(
			image,
			body_top_left + socket,
			overlays.get("face_mask", {}),
			Color(1.0, 0.72, 0.12, 0.38)
		)
	if show_hair_mask:
		_draw_overlay_rect(
			image,
			body_top_left + socket,
			overlays.get("hair_mask", {}),
			Color(0.28, 1.0, 0.38, 0.32)
		)


func _draw_overlay_rect(
	image: Image,
	origin: Vector2i,
	overlay: Variant,
	color: Color
) -> void:
	if not overlay is Dictionary or str(overlay.get("shape", "")) != "rect":
		return
	var offset := _array_vector(overlay.get("offset", []))
	var size := _array_vector(overlay.get("size", []))
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	for y: int in size.y:
		for x: int in size.x:
			var point := origin + offset + Vector2i(x, y)
			if bounds.has_point(point):
				image.set_pixelv(point, image.get_pixelv(point).blend(color))


func _render_current_previews() -> void:
	if _visual == null:
		return
	var full := _runtime_frame(
		current_action, current_direction, current_frame, true
	)
	var full_preview := get_node(
		"CalibrationUI/Panel/VBox/Previews/FullColumn/FullPersonPreview"
	) as TextureRect
	full_preview.texture = ImageTexture.create_from_image(full)
	var head := _head_preview(
		full, current_action, current_direction, current_frame, head_zoom
	)
	var head_preview := get_node(
		"CalibrationUI/Panel/VBox/Previews/HeadColumn/HeadPreview"
	) as TextureRect
	head_preview.texture = ImageTexture.create_from_image(head)


func _head_preview(
	frame: Image,
	action: String,
	direction_index: int,
	frame_index: int,
	zoom: int
) -> Image:
	var socket := HelmetVisualV2.body_head_socket(
		PLAYER_VISUAL_ID, action, direction_index, frame_index
	)
	var pivot := HelmetVisualV2.pivot_for_frame(
		ITEM_ID, action, direction_index, frame_index
	)
	var delta := HelmetVisualV2.final_position_delta(
		ITEM_ID, PLAYER_VISUAL_ID, action, direction_index, frame_index
	)
	var body_top_left := (
		FOOT_POINT
		+ Vector2i(_visual.position.round())
		+ Vector2i(_visual.sprite.position.round())
	)
	var centre := body_top_left + socket
	var crop_rect := Rect2i(centre - HEAD_ZOOM_SOURCE_SIZE / 2, HEAD_ZOOM_SOURCE_SIZE)
	var crop := frame.get_region(crop_rect)
	crop.resize(
		HEAD_ZOOM_SOURCE_SIZE.x * zoom,
		HEAD_ZOOM_SOURCE_SIZE.y * zoom,
		Image.INTERPOLATE_NEAREST
	)
	var crop_origin := crop_rect.position
	var socket_point := (body_top_left + socket - crop_origin) * zoom
	var pivot_point := (body_top_left + delta + pivot - crop_origin) * zoom
	_draw_x_mark(crop, socket_point, Color(0.2, 0.9, 1.0, 0.95), zoom)
	_draw_plus_mark(crop, pivot_point, Color(1.0, 0.2, 0.88, 0.95), zoom)
	return crop


func _generate_idle_outputs(output_dir: String) -> void:
	var one_x := Image.create(FRAME_CANVAS.x * 8, FRAME_CANVAS.y, false, Image.FORMAT_RGBA8)
	one_x.fill(Color(18.0 / 255.0, 27.0 / 255.0, 39.0 / 255.0, 1))
	var head_cells: Array[Image] = []
	for direction_index: int in 8:
		var frame := _runtime_frame("idle", direction_index, 0)
		one_x.blend_rect(
			frame,
			Rect2i(Vector2i.ZERO, frame.get_size()),
			Vector2i(direction_index * FRAME_CANVAS.x, 0)
		)
		head_cells.append(_head_preview(frame, "idle", direction_index, 0, 8))
	assert(one_x.save_png(output_dir.path_join("helmet_146_idle_8dir_1x.png")) == OK)

	var eight_x := Image.create(HEAD_ZOOM_SOURCE_SIZE.x * 8 * 4, HEAD_ZOOM_SOURCE_SIZE.y * 8 * 2, false, Image.FORMAT_RGBA8)
	eight_x.fill(Color(18.0 / 255.0, 27.0 / 255.0, 39.0 / 255.0, 1))
	for index: int in head_cells.size():
		var destination := Vector2i(
			(index % 4) * head_cells[index].get_width(),
			(index / 4) * head_cells[index].get_height()
		)
		eight_x.blend_rect(
			head_cells[index],
			Rect2i(Vector2i.ZERO, head_cells[index].get_size()),
			destination
		)
	assert(eight_x.save_png(output_dir.path_join("helmet_146_idle_8dir_8x.png")) == OK)


func _generate_all_actions_overview(output_dir: String) -> void:
	var max_frames := 6
	var overview := Image.create(
		ArtSpec.WARRIOR_FRAME.x * 8 * max_frames,
		ArtSpec.WARRIOR_FRAME.y * ACTIONS.size(),
		false,
		Image.FORMAT_RGBA8
	)
	overview.fill(Color(18.0 / 255.0, 27.0 / 255.0, 39.0 / 255.0, 1))
	var action_row := 0
	for action: String in ACTIONS:
		for direction_index: int in 8:
			for frame_index: int in int(ACTIONS[action]):
				var frame := _runtime_frame(action, direction_index, frame_index)
				var crop := frame.get_region(Rect2i(
					Vector2i(32, 86),
					ArtSpec.WARRIOR_FRAME
				))
				var destination := Vector2i(
					(direction_index * max_frames + frame_index) * ArtSpec.WARRIOR_FRAME.x,
					action_row * ArtSpec.WARRIOR_FRAME.y
				)
				overview.blend_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), destination)
		action_row += 1
	assert(overview.save_png(output_dir.path_join("helmet_146_all_actions_overview_1x.png")) == OK)


func _direction_audit() -> Dictionary:
	var asset := HelmetVisualV2.visual_asset_for_item(ITEM_ID)
	var directions: Array[Dictionary] = []
	for direction_index: int in 8:
		var direction: String = str(DIRECTIONS[direction_index])
		var record := HelmetVisualV2.direction_record(ITEM_ID, direction_index)
		directions.append({
			"direction": direction,
			"sourceRow": int(record.get("source_row", -1)),
			"texture": str(record.get("texture", "")),
			"pivot": record.get("pivot", []),
			"nudge": record.get("nudge", []),
			"face_policy": str(record.get("face_policy", "")),
			"hair_policy": str(record.get("hair_policy", "")),
			"openingVisibility": str(record.get("openingVisibility", "")),
			"status": str(record.get("status", "")),
			"locked": bool(record.get("locked", false)),
			"artRedrawn": false,
		})
	return {
		"schemaVersion": 1,
		"contractId": "equipment.world_helmet.146.direction_audit.v1",
		"itemId": ITEM_ID,
		"itemName": "精灵头盔",
		"visual_asset_id": str(asset.get("visual_asset_id", "")),
		"canonicalDirections": DIRECTIONS,
		"source_direction_map": asset.get("source_direction_map", {}),
		"directions": directions,
	}


func _validation_report(audit: Dictionary) -> Dictionary:
	var checks: Array[Dictionary] = []
	_add_check(checks, "canonical_direction_order", audit.get("canonicalDirections", []) == DIRECTIONS)
	var source_rows: Array[int] = []
	for record: Dictionary in audit.get("directions", []):
		source_rows.append(int(record.get("sourceRow", -1)))
		_add_check(checks, "integer_%s" % record.direction, _record_uses_integer_coordinates(record))
		_add_check(checks, "no_flip_%s" % record.direction, not bool(
			HelmetVisualV2.direction_record(ITEM_ID, DIRECTIONS.find(record.direction)).get("flip_h", true)
		))
		var scale_value: Variant = HelmetVisualV2.direction_record(
			ITEM_ID, DIRECTIONS.find(record.direction)
		).get("runtime_scale", [])
		_add_check(checks, "scale_one_%s" % record.direction, (
			scale_value is Array
			and scale_value.size() == 2
			and float(scale_value[0]) == 1.0
			and float(scale_value[1]) == 1.0
		))
	_add_check(checks, "source_rows_unique", _unique_ints(source_rows) == 8)
	_add_check(checks, "n_s_not_same", not _helmet_cells_equal("idle", 0, 4))
	_add_check(checks, "ne_se_not_same", not _helmet_cells_equal("idle", 1, 3))
	_add_check(checks, "nw_sw_not_same", not _helmet_cells_equal("idle", 7, 5))
	_add_check(checks, "no_horizontal_mirror_generation", not _has_exact_horizontal_mirror_pair())
	_add_check(checks, "all_head_sockets_present", _head_socket_count() == 184)
	_add_check(checks, "head_sockets_are_per_frame_primary_evidence", _socket_evidence_safe())
	_add_check(checks, "head_sockets_are_not_global_constant", _unique_socket_count() > 100, {
		"uniqueSocketCount": _unique_socket_count(),
	})
	_add_check(checks, "adjacent_socket_jump_matches_primary_source", _adjacent_socket_jump_safe(), {
		"observedByAction": _max_adjacent_socket_jump_by_action(),
	})
	_add_check(checks, "open_helmet_face_window_pixel_overlap_safe", _open_policy_mask_safe())
	_add_check(checks, "rear_opening_pixel_check", _rear_opening_safe())
	_add_check(checks, "cpu_head_occlusion_mask_changes_alpha", _mask_execution_safe())
	_add_check(checks, "runtime_layer_order_unique", _runtime_layer_order_safe())
	_add_check(checks, "calibration_controls_and_previews_live", _calibration_ui_safe())
	_add_check(checks, "face_hair_overlay_toggles_change_preview", _overlay_toggle_safe())
	_add_check(checks, "arrow_nudge_exactly_one_pixel", _nudge_roundtrip_safe())
	_add_check(checks, "formal_runtime_override_save", _formal_override_save_safe())
	_add_check(checks, "headless_save_does_not_modify_tracked_override", (
		FileAccess.get_file_as_string(HelmetVisualV2.OVERRIDE_PATH)
		== _formal_override_before
	))
	var golden_diff := _golden_151_pixel_diff()
	_add_check(checks, "golden_151_pixel_diff_zero", golden_diff == 0, {"pixelDiff": golden_diff})
	var passed := true
	for check: Dictionary in checks:
		passed = passed and bool(check.get("passed", false))
	return {
		"schemaVersion": 1,
		"contractId": "equipment.world_helmet.146.validation.v1",
		"itemId": ITEM_ID,
		"passed": passed,
		"headSocketRecords": _head_socket_count(),
		"golden151PixelDiff": golden_diff,
		"checks": checks,
	}


func _helmet_cells_equal(action: String, direction_a: int, direction_b: int) -> bool:
	var texture := _visual._helmet_action_textures.get(action, null) as Texture2D
	var image := texture.get_image()
	var frame := 0
	var row_a := HelmetVisualV2.source_direction_row(ITEM_ID, direction_a)
	var row_b := HelmetVisualV2.source_direction_row(ITEM_ID, direction_b)
	var rect_a := Rect2i(frame * 192, row_a * 160, 192, 160)
	var rect_b := Rect2i(frame * 192, row_b * 160, 192, 160)
	return image.get_region(rect_a).get_data() == image.get_region(rect_b).get_data()


func _has_exact_horizontal_mirror_pair() -> bool:
	var texture := _visual._helmet_action_textures.get("idle", null) as Texture2D
	var image := texture.get_image()
	for pair: Array in [[1, 7], [2, 6], [3, 5]]:
		var left_row := HelmetVisualV2.source_direction_row(ITEM_ID, int(pair[0]))
		var right_row := HelmetVisualV2.source_direction_row(ITEM_ID, int(pair[1]))
		var left := image.get_region(Rect2i(0, left_row * 160, 192, 160))
		var right := image.get_region(Rect2i(0, right_row * 160, 192, 160))
		left.flip_x()
		if left.get_data() == right.get_data():
			return true
	return false


func _head_socket_count() -> int:
	var total := 0
	var visual: Dictionary = HelmetVisualV2.head_socket_database().get("playerVisuals", {}).get(
		PLAYER_VISUAL_ID, {}
	)
	for action: String in ACTIONS:
		for direction: String in DIRECTIONS:
			total += visual.get("actions", {}).get(action, {}).get(
				"directions", {}
			).get(direction, []).size()
	return total


func _max_adjacent_socket_jump_by_action() -> Dictionary:
	var result: Dictionary = {}
	for action: String in ACTIONS:
		var maximum := 0
		for direction_index: int in 8:
			var previous := Vector2i.ZERO
			for frame_index: int in int(ACTIONS[action]):
				var socket := HelmetVisualV2.body_head_socket(
					PLAYER_VISUAL_ID, action, direction_index, frame_index
				)
				if frame_index > 0:
					maximum = maxi(maximum, absi(socket.x - previous.x) + absi(socket.y - previous.y))
				previous = socket
		result[action] = maximum
	return result


func _adjacent_socket_jump_safe() -> bool:
	var expected: Dictionary = HelmetVisualV2.head_socket_database().get(
		"coordinatePolicy", {}
	).get("maxAdjacentJumpByAction", {})
	var observed := _max_adjacent_socket_jump_by_action()
	for action: String in ACTIONS:
		if int(observed.get(action, -1)) > int(expected.get(action, -1)):
			return false
	return true


func _unique_socket_count() -> int:
	var seen: Dictionary = {}
	for action: String in ACTIONS:
		for direction_index: int in 8:
			for frame_index: int in int(ACTIONS[action]):
				var socket := HelmetVisualV2.body_head_socket(
					PLAYER_VISUAL_ID, action, direction_index, frame_index
				)
				seen["%d,%d" % [socket.x, socket.y]] = true
	return seen.size()


func _socket_evidence_safe() -> bool:
	var visual: Dictionary = HelmetVisualV2.head_socket_database().get(
		"playerVisuals", {}
	).get(PLAYER_VISUAL_ID, {})
	for action: String in ACTIONS:
		for direction: String in DIRECTIONS:
			var frames: Array = visual.get("actions", {}).get(action, {}).get(
				"directions", {}
			).get(direction, [])
			for frame: Variant in frames:
				if not frame is Dictionary:
					return false
				var evidence: Variant = frame.get("evidence", {})
				if not evidence is Dictionary:
					return false
				if str(evidence.get("derivation", "")) != "round_same_frame_hair_alpha_centroid":
					return false
				if str(evidence.get("hairSourceRgbaSha256", "")).length() != 64:
					return false
				var centroid: Variant = evidence.get("hairAnchorCentroid", [])
				if not centroid is Array or centroid.size() != 2:
					return false
				if _array_vector(frame.get("head_socket", [])) != Vector2i(
					roundi(float(centroid[0])), roundi(float(centroid[1]))
				):
					return false
	return true


func _open_policy_mask_safe() -> bool:
	for direction_index: int in 8:
		var record := HelmetVisualV2.direction_record(ITEM_ID, direction_index)
		if str(record.get("face_policy", "")) in ["open_crown", "half_open"]:
			for action: String in ACTIONS:
				var path := HelmetVisualV2.action_texture_path(
					ITEM_ID, action, direction_index, "head_occlusion_mask"
				)
				if path.is_empty():
					continue
				var mask := (load(path) as Texture2D).get_image()
				for frame_index: int in int(ACTIONS[action]):
					var rect := _face_window_rect(
						record, action, direction_index, frame_index
					)
					var source_row := HelmetVisualV2.source_direction_row(
						ITEM_ID, direction_index
					)
					var cell := mask.get_region(Rect2i(
						frame_index * 192, source_row * 160, 192, 160
					))
					if _opaque_pixels(cell, rect) > 0:
						return false
	return true


func _rear_opening_safe() -> bool:
	for direction: String in ["N", "NE", "NW"]:
		var direction_index := DIRECTIONS.find(direction)
		var record := HelmetVisualV2.direction_record(ITEM_ID, direction_index)
		var texture_path := HelmetVisualV2.action_texture_path(
			ITEM_ID, "idle", direction_index, "helmet_front"
		)
		var image := (load(texture_path) as Texture2D).get_image()
		var source_row := HelmetVisualV2.source_direction_row(ITEM_ID, direction_index)
		var cell := image.get_region(Rect2i(0, source_row * 160, 192, 160))
		var face_window := _face_window_rect(record, "idle", direction_index, 0)
		# A full rear opening would leave the entire calibrated face window empty.
		if _opaque_pixels(cell, face_window) == 0:
			return false
	return true


func _face_window_rect(
	record: Dictionary,
	action: String,
	direction_index: int,
	frame_index: int
) -> Rect2i:
	var overlay: Dictionary = record.get("calibrationOverlays", {}).get("face_mask", {})
	var pivot := HelmetVisualV2.pivot_for_frame(
		ITEM_ID, action, direction_index, frame_index
	)
	return Rect2i(
		pivot + _array_vector(overlay.get("offset", [])),
		_array_vector(overlay.get("size", []))
	)


func _opaque_pixels(image: Image, rect: Rect2i) -> int:
	var count := 0
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y: int in range(clipped.position.y, clipped.end.y):
		for x: int in range(clipped.position.x, clipped.end.x):
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _mask_execution_safe() -> bool:
	var destination := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	destination.fill(Color(0.4, 0.5, 0.6, 1.0))
	var mask := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	mask.fill(Color(1, 1, 1, 1))
	var result := HelmetVisualV2.apply_alpha_mask(destination, mask, Vector2i(1, 1))
	return (
		result.get_pixel(0, 0).a == 1.0
		and result.get_pixel(1, 1).a == 0.0
		and result.get_pixel(2, 2).a == 0.0
	)


func _runtime_layer_order_safe() -> bool:
	for direction_index: int in 8:
		_configure_runtime("idle", direction_index, 0)
		var indices := [
			_visual.get_node("ClientHelmetBackLayer").get_index(),
			_visual.get_node("BodySprite").get_index(),
			_visual.get_node("ClientHelmetLayer").get_index(),
			_visual.get_node("HeadOcclusionMaskLayer").get_index(),
		]
		if not (indices[0] < indices[1] and indices[1] < indices[2] and indices[2] < indices[3]):
			return false
	return true


func _calibration_ui_safe() -> bool:
	var full := get_node(
		"CalibrationUI/Panel/VBox/Previews/FullColumn/FullPersonPreview"
	) as TextureRect
	var head_preview := get_node(
		"CalibrationUI/Panel/VBox/Previews/HeadColumn/HeadPreview"
	) as TextureRect
	var action_control := get_node(
		"CalibrationUI/Panel/VBox/Inputs/Action"
	) as OptionButton
	var direction_control := get_node(
		"CalibrationUI/Panel/VBox/Inputs/Direction"
	) as OptionButton
	return (
		full.texture != null
		and head_preview.texture != null
		and action_control.item_count == ACTIONS.size()
		and direction_control.item_count == DIRECTIONS.size()
	)


func _overlay_toggle_safe() -> bool:
	var old_face := show_face_mask
	var old_hair := show_hair_mask
	show_face_mask = true
	show_hair_mask = true
	var with_overlays := _runtime_frame("idle", 4, 0, true)
	show_face_mask = false
	show_hair_mask = false
	var without_overlays := _runtime_frame("idle", 4, 0, true)
	show_face_mask = old_face
	show_hair_mask = old_hair
	return with_overlays.get_data() != without_overlays.get_data()


func _formal_override_save_safe() -> bool:
	if not save_current_direction():
		return false
	HelmetVisualV2.reload_data()
	var override: Dictionary = HelmetVisualV2.calibration_overrides()
	var saved: Variant = override.get("itemOverrides", {}).get(
		str(ITEM_ID), {}
	).get("directions", {}).get(DIRECTIONS[current_direction], {})
	return (
		saved is Dictionary
		and saved.get("nudge", []) == [0.0, 0.0]
		and not HelmetVisualV2.persist_calibration_override(
			151, 0, {"nudge": [1, 0]}
		)
	)


func _nudge_roundtrip_safe() -> bool:
	unlock_current_direction_for_session()
	var before := _array_vector(
		HelmetVisualV2.direction_record(ITEM_ID, current_direction).get("nudge", [])
	)
	if not nudge_current(Vector2i.RIGHT):
		return false
	var after_right := _array_vector(
		HelmetVisualV2.direction_record(ITEM_ID, current_direction).get("nudge", [])
	)
	if not nudge_current(Vector2i.LEFT):
		return false
	var after_left := _array_vector(
		HelmetVisualV2.direction_record(ITEM_ID, current_direction).get("nudge", [])
	)
	return after_right == before + Vector2i.RIGHT and after_left == before


func _golden_151_pixel_diff() -> int:
	var differences := 0
	for action: String in ACTIONS:
		var body := load(
			"res://assets/art/items/client/world_wear/dress/male/dress_002_%s.png" % action
		) as Texture2D
		var helmet := load(
			"res://assets/art/characters/warrior/wear/helmet/black_iron_helmet_%s.png" % action
		) as Texture2D
		var body_image := body.get_image()
		var helmet_image := helmet.get_image()
		for direction_index: int in 8:
			var v2_row := HelmetVisualV2.source_direction_row(151, direction_index)
			for frame_index: int in int(ACTIONS[action]):
				var delta := HelmetVisualV2.final_position_delta(
					151, PLAYER_VISUAL_ID, action, direction_index, frame_index
				)
				var body_cell := body_image.get_region(Rect2i(frame_index * 192, direction_index * 160, 192, 160))
				var legacy := body_cell.duplicate()
				var helmet_legacy := helmet_image.get_region(Rect2i(frame_index * 192, direction_index * 160, 192, 160))
				legacy.blend_rect(helmet_legacy, Rect2i(0, 0, 192, 160), Vector2i.ZERO)
				var v2 := body_cell.duplicate()
				var helmet_v2 := helmet_image.get_region(Rect2i(frame_index * 192, v2_row * 160, 192, 160))
				v2.blend_rect(helmet_v2, Rect2i(0, 0, 192, 160), delta)
				if legacy.get_data() != v2.get_data():
					differences += _pixel_difference_count(legacy, v2)
	return differences


func _pixel_difference_count(left: Image, right: Image) -> int:
	var count := 0
	for y: int in left.get_height():
		for x: int in left.get_width():
			if left.get_pixel(x, y) != right.get_pixel(x, y):
				count += 1
	return count


func _record_uses_integer_coordinates(record: Dictionary) -> bool:
	for field: String in ["pivot", "nudge"]:
		var values: Variant = record.get(field, [])
		if not values is Array or values.size() != 2:
			return false
		for value: Variant in values:
			if not (value is int or value is float) or float(value) != floorf(float(value)):
				return false
	return true


func _unique_ints(values: Array[int]) -> int:
	var seen: Dictionary = {}
	for value: int in values:
		seen[value] = true
	return seen.size()


func _add_check(
	checks: Array[Dictionary],
	check_id: String,
	passed: bool,
	details: Dictionary = {}
) -> void:
	var check := {"id": check_id, "passed": passed}
	check.merge(details)
	checks.append(check)


func _draw_x_mark(image: Image, centre: Vector2i, color: Color, scale_factor: int) -> void:
	var radius := maxi(4, 3 * scale_factor)
	var thickness := maxi(1, scale_factor / 3)
	for offset: int in range(-radius, radius + 1):
		for width: int in range(-thickness, thickness + 1):
			for point: Vector2i in [
				centre + Vector2i(offset, offset + width),
				centre + Vector2i(offset, -offset + width),
			]:
				if Rect2i(Vector2i.ZERO, image.get_size()).has_point(point):
					image.set_pixelv(point, color)


func _draw_plus_mark(image: Image, centre: Vector2i, color: Color, scale_factor: int) -> void:
	var radius := maxi(3, 2 * scale_factor)
	var thickness := maxi(1, scale_factor / 4)
	for offset: int in range(-radius, radius + 1):
		for width: int in range(-thickness, thickness + 1):
			for point: Vector2i in [
				centre + Vector2i(offset, width),
				centre + Vector2i(width, offset),
			]:
				if Rect2i(Vector2i.ZERO, image.get_size()).has_point(point):
					image.set_pixelv(point, color)


func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write %s" % path)
	file.store_string(JSON.stringify(payload, "\t", false))
	file.close()


func _vector_array(value: Vector2i) -> Array[int]:
	return [value.x, value.y]


func _array_vector(value: Variant) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO
