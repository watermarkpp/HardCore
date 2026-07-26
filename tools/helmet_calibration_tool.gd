class_name HelmetCalibrationTool
extends Node

@export var auto_run := true

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const ITEM_ID := 146
const PLAYER_VISUAL_ID := "player.male.cloth_002"
const OUTPUT_ROOT := "res://outputs/visual_acceptance/helmet_calibration"
const TEST_OVERRIDE_PATH := OUTPUT_ROOT + "/helmet_146_test_overrides.json"
const INTERACTIVE_USER_ARG := "--helmet-calibration-interactive"
const INTERACTIVE_WINDOW_SIZE := Vector2i(1600, 900)
const DIRECTIONS := HelmetVisualV2.CANONICAL_DIRECTIONS
const ACTIONS := {
	"idle": 4, "walk": 6, "attack": 6, "cast": 6, "hit": 3, "death": 4,
}
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
var current_item_id := ITEM_ID
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
var _game_viewport: SubViewport
var _player: PlayerCharacter
var _visual: Node2D
var _formal_override_before := ""
var _editor_initialized := false
var _target_buttons: Array[TextureButton] = []
var _source_buttons: Array[TextureButton] = []
var _dirty_directions: Dictionary = {}
var _dirty_scale := false
var _updating_ui := false
var _interactive_requested := false
var _initialization_error := ""
var _quit_requested := false


func _ready() -> void:
	_setup_ui()
	if auto_run:
		_run.call_deferred()


func _run() -> void:
	var user_args := OS.get_cmdline_user_args()
	_interactive_requested = has_interactive_user_arg(user_args)
	if (
		_interactive_requested
		or not should_auto_quit_for_context(user_args, DisplayServer.get_name())
	):
		await _start_interactive(false)
		return
	var initialized := await initialize_editor_runtime(true)
	assert(initialized, "headless helmet calibration initialization failed")
	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	_generate_idle_outputs(output_dir)
	_generate_all_actions_overview(output_dir)
	await _save_editor_ui_preview(output_dir)
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
		+ "items=146,151 sockets=232 directions=8 cast=true source_pixels_frozen=true"
	)
	dispose_runtime_for_test()
	_request_exit(0)


func has_interactive_user_arg(user_args: PackedStringArray) -> bool:
	return INTERACTIVE_USER_ARG in user_args


func should_auto_quit_for_context(
	user_args: PackedStringArray,
	display_name: String
) -> bool:
	return (
		not has_interactive_user_arg(user_args)
		and display_name == "headless"
	)


func should_auto_quit_for_display(display_name: String) -> bool:
	# Compatibility wrapper for existing callers. New startup decisions must
	# include the explicit user-argument policy above.
	return should_auto_quit_for_context(PackedStringArray(), display_name)


func _start_interactive(simulate_failure: bool = false) -> bool:
	_interactive_requested = true
	_configure_interactive_window()
	if simulate_failure:
		_show_initialization_error("测试模拟：编辑器初始化失败")
		return false
	var initialized := await initialize_editor_runtime(false)
	if not initialized:
		return false
	_show_interactive_ready()
	print("HELMET_CALIBRATION_TOOL_INTERACTIVE_READY item=146")
	return true


func start_interactive_failure_for_test() -> bool:
	return await _start_interactive(true)


func _request_exit(exit_code: int) -> void:
	_quit_requested = true
	# Defer the engine exit so the current async validation stack can unwind
	# and release its Image/Texture resources before Godot performs leak checks.
	get_tree().quit.call_deferred(exit_code)


func quit_was_requested() -> bool:
	return _quit_requested


func initialization_error() -> String:
	return _initialization_error


func interactive_window_policy() -> Dictionary:
	return {
		"minimumSize": [
			INTERACTIVE_WINDOW_SIZE.x,
			INTERACTIVE_WINDOW_SIZE.y,
		],
		"centered": true,
		"projectSettingsModified": false,
	}


func _configure_interactive_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_min_size(INTERACTIVE_WINDOW_SIZE)
	DisplayServer.window_set_size(INTERACTIVE_WINDOW_SIZE)
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_position(
		usable_rect.position
		+ Vector2i(
			(usable_rect.size.x - INTERACTIVE_WINDOW_SIZE.x) / 2,
			(usable_rect.size.y - INTERACTIVE_WINDOW_SIZE.y) / 2
		)
	)


func game_render_is_isolated() -> bool:
	return (
		is_instance_valid(_game_viewport)
		and is_instance_valid(_game)
		and _game.get_parent() == _game_viewport
		and _game_viewport.render_target_update_mode
			== SubViewport.UPDATE_DISABLED
	)


func dispose_runtime_for_test() -> void:
	_visual = null
	_player = null
	if is_instance_valid(_game_viewport):
		_game_viewport.free()
	elif is_instance_valid(_game):
		_game.free()
	_game = null
	_game_viewport = null


func _show_interactive_ready() -> void:
	var status := get_node_or_null(
		"CalibrationUI/Panel/VBox/StartupStatus"
	) as Label
	if status != null:
		status.visible = true
		status.modulate = Color(0.35, 1.0, 0.62)
		status.text = (
			"交互编辑器已就绪。窗口会保持打开；保存仅写入正式覆盖合同。"
		)


func _show_initialization_error(message: String) -> void:
	_initialization_error = message
	var status := get_node_or_null(
		"CalibrationUI/Panel/VBox/StartupStatus"
	) as Label
	if status != null:
		status.visible = true
		status.modulate = Color(1.0, 0.42, 0.32)
		status.text = (
			"初始化失败：%s\n窗口将保持打开，请查看 outputs/helmet_calibration_interactive.log。"
			% message
		)
	var state := get_node_or_null(
		"CalibrationUI/Panel/VBox/MappingStatus/State"
	) as Label
	if state != null:
		state.text = "初始化失败 / 未退出"
	print("HELMET_CALIBRATION_TOOL_INTERACTIVE_ERROR " + message)


func initialize_editor_runtime(use_test_override: bool = false) -> bool:
	if _editor_initialized:
		return true
	PlayerState.test_mode = true
	PlayerState.ensure_developer_test_character()
	if not PlayerState.select_character("developer_warrior_30"):
		_show_initialization_error("无法选择 developer_warrior_30 测试角色")
		return false
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState.equipment = {
		"衣服": {"item_id": 116, "name": "布衣(男)", "instance_id": "helmet_v2_cloth"},
		"头盔": {"item_id": ITEM_ID, "name": "精灵头盔", "instance_id": "helmet_v2_146"},
	}
	var main_scene: Resource = load("res://scenes/main.tscn")
	if not main_scene is PackedScene:
		_show_initialization_error("无法加载 res://scenes/main.tscn")
		return false
	_game = (main_scene as PackedScene).instantiate()
	if _game == null:
		_show_initialization_error("主场景实例化失败")
		return false
	# The complete GameRoot remains alive as a data/runtime source, but it must
	# never paint its world or HUD into the standalone calibration workspace.
	_game_viewport = SubViewport.new()
	_game_viewport.name = "GameDataViewport"
	_game_viewport.size = Vector2i(1280, 720)
	_game_viewport.disable_3d = true
	_game_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_game_viewport)
	_game_viewport.add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player_candidate: Variant = _game.get("player")
	if not player_candidate is PlayerCharacter:
		_show_initialization_error("主场景未提供可用的 PlayerCharacter")
		return false
	_player = player_candidate as PlayerCharacter
	_visual = _player.get_node_or_null("PlayerVisual")
	if _visual == null:
		_show_initialization_error("PlayerVisual 节点缺失")
		return false
	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	if use_test_override:
		_formal_override_before = FileAccess.get_file_as_string(
			HelmetVisualV2.OVERRIDE_PATH
		)
		_write_json(
			ProjectSettings.globalize_path(TEST_OVERRIDE_PATH),
			HelmetVisualV2.calibration_overrides()
		)
		if not HelmetVisualV2.set_calibration_override_path_for_test(
			TEST_OVERRIDE_PATH
		):
			_show_initialization_error("无法启用测试覆盖文件")
			return false
	_editor_initialized = true
	select_item(ITEM_ID)
	_refresh_mapping_editor_ui()
	var full_preview := get_node_or_null(
		"CalibrationUI/Panel/VBox/Previews/FullColumn/FullPersonPreview"
	) as TextureRect
	var head_preview := get_node_or_null(
		"CalibrationUI/Panel/VBox/Previews/HeadColumn/HeadPreview"
	) as TextureRect
	if (
		full_preview == null
		or head_preview == null
		or full_preview.texture == null
		or head_preview.texture == null
	):
		_editor_initialized = false
		_show_initialization_error("预览纹理初始化失败")
		return false
	return true


func _setup_ui() -> void:
	var item_control := get_node("CalibrationUI/Panel/VBox/Inputs/Item") as OptionButton
	var action_control := get_node("CalibrationUI/Panel/VBox/Inputs/Action") as OptionButton
	var direction_control := get_node("CalibrationUI/Panel/VBox/Inputs/Direction") as OptionButton
	var zoom_control := get_node("CalibrationUI/Panel/VBox/Inputs/Zoom") as OptionButton
	item_control.add_item("146 精灵头盔", 146)
	item_control.add_item("151 黑铁头盔（原始源槽 / 可编辑）", 151)
	for action: String in ACTIONS:
		action_control.add_item(action)
	for direction: String in DIRECTIONS:
		direction_control.add_item(direction)
	for zoom_value: int in [1, 8, 10]:
		zoom_control.add_item("%dx" % zoom_value, zoom_value)
	zoom_control.select(1)
	item_control.item_selected.connect(func(index: int) -> void:
		select_item(int(item_control.get_item_id(index)))
	)
	action_control.item_selected.connect(func(index: int) -> void:
		select_action(str(action_control.get_item_text(index)))
		_refresh_mapping_editor_ui()
	)
	direction_control.item_selected.connect(func(index: int) -> void:
		select_target_direction(index)
	)
	var frame_control := get_node("CalibrationUI/Panel/VBox/Inputs/Frame") as SpinBox
	frame_control.value_changed.connect(func(value: float) -> void:
		select_frame(int(value))
		_refresh_mapping_editor_ui()
	)
	zoom_control.item_selected.connect(func(index: int) -> void:
		set_head_zoom(int(zoom_control.get_item_id(index)))
		_refresh_mapping_editor_ui()
	)
	var scale_control := get_node(
		"CalibrationUI/Panel/VBox/Inputs/Scale"
	) as SpinBox
	scale_control.value_changed.connect(func(value: float) -> void:
		if not _updating_ui:
			set_uniform_scale_percent(int(value))
	)
	get_node("CalibrationUI/Panel/VBox/Inputs/ScaleMinus").pressed.connect(
		func() -> void:
			set_uniform_scale_percent(
				HelmetVisualV2.uniform_scale_percent(current_item_id) - 1
			)
	)
	get_node("CalibrationUI/Panel/VBox/Inputs/ScalePlus").pressed.connect(
		func() -> void:
			set_uniform_scale_percent(
				HelmetVisualV2.uniform_scale_percent(current_item_id) + 1
			)
	)
	_build_mapping_buttons()
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
			_refresh_mapping_editor_ui()
		)
	var nudge_buttons := {
		"NudgeUp": Vector2i.UP,
		"NudgeDown": Vector2i.DOWN,
		"NudgeLeft": Vector2i.LEFT,
		"NudgeRight": Vector2i.RIGHT,
	}
	for control_name: String in nudge_buttons:
		var delta: Vector2i = nudge_buttons[control_name]
		get_node(
			"CalibrationUI/Panel/VBox/Commands/%s" % control_name
		).pressed.connect(func() -> void:
			nudge_current(delta)
			_refresh_mapping_editor_ui()
		)
	get_node("CalibrationUI/Panel/VBox/Commands/Undo").pressed.connect(
		func() -> void: undo_current_direction()
	)
	get_node("CalibrationUI/Panel/VBox/Commands/Reload").pressed.connect(
		func() -> void: reload_formal_data()
	)
	get_node("CalibrationUI/Panel/VBox/Commands/Save").pressed.connect(
		func() -> void:
			save_current_direction()
			_refresh_mapping_editor_ui()
	)
	get_node("CalibrationUI/Panel/VBox/Commands/Lock").pressed.connect(
		func() -> void:
			lock_current_direction()
			_refresh_mapping_editor_ui()
	)
	get_node(
		"CalibrationUI/Panel/VBox/Commands/GenerateAllActions"
	).pressed.connect(func() -> void:
		generate_all_actions_from_idle()
		_refresh_mapping_editor_ui()
	)


func _build_mapping_buttons() -> void:
	var target_grid := get_node(
		"CalibrationUI/Panel/VBox/TargetDirections"
	) as GridContainer
	var source_grid := get_node(
		"CalibrationUI/Panel/VBox/SourceDirections"
	) as GridContainer
	for direction_index: int in DIRECTIONS.size():
		var target_button := _direction_texture_button(
			"Target_%s" % DIRECTIONS[direction_index],
			DIRECTIONS[direction_index]
		)
		target_button.set_meta("target_direction", direction_index)
		target_button.pressed.connect(func() -> void:
			select_target_direction(direction_index)
		)
		target_grid.add_child(target_button)
		_target_buttons.append(target_button)
	for source_row: int in DIRECTIONS.size():
		var source_button := _direction_texture_button(
			"Source_Row%d" % source_row,
			"row %d" % source_row
		)
		source_button.set_meta("source_row", source_row)
		source_button.pressed.connect(func() -> void:
			map_source_row_to_current_target(source_row)
		)
		source_grid.add_child(source_button)
		_source_buttons.append(source_button)


func _direction_texture_button(
	node_name: String,
	label_text: String
) -> TextureButton:
	var button := TextureButton.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(104, 82)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.toggle_mode = true
	var label := Label.new()
	label.name = "Label"
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.position.y = -22
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_child(label)
	return button


func select_item(item_id: int) -> void:
	assert(item_id in [146, 151])
	current_item_id = item_id
	if _visual != null:
		var item_name := "精灵头盔" if item_id == 146 else "黑铁头盔"
		PlayerState.equipment["头盔"] = {
			"item_id": item_id,
			"name": item_name,
			"instance_id": "helmet_mapping_editor_%d" % item_id,
		}
		_visual._refresh_equipment_visuals()
	_refresh_mapping_editor_ui()


func select_action(action: String) -> void:
	assert(ACTIONS.has(action))
	current_action = action
	current_frame = mini(current_frame, int(ACTIONS[action]) - 1)
	var frame_control := get_node("CalibrationUI/Panel/VBox/Inputs/Frame") as SpinBox
	frame_control.max_value = int(ACTIONS[action]) - 1
	frame_control.value = current_frame


func select_direction(direction: String) -> void:
	assert(direction in DIRECTIONS)
	select_target_direction(DIRECTIONS.find(direction))


func select_target_direction(direction_index: int) -> void:
	assert(direction_index >= 0 and direction_index < DIRECTIONS.size())
	current_direction = direction_index
	var direction_control := get_node(
		"CalibrationUI/Panel/VBox/Inputs/Direction"
	) as OptionButton
	direction_control.select(direction_index)
	_refresh_mapping_editor_ui()


func select_frame(frame_index: int) -> void:
	current_frame = clampi(frame_index, 0, int(ACTIONS[current_action]) - 1)


func set_head_zoom(scale_factor: int) -> void:
	assert(scale_factor in [1, 8, 10])
	head_zoom = scale_factor


func set_uniform_scale_percent(percent: int) -> bool:
	var safe_percent := clampi(percent, 50, 200)
	if not HelmetVisualV2.set_session_uniform_scale_percent(
		current_item_id, safe_percent
	):
		return false
	_dirty_scale = true
	_refresh_mapping_editor_ui()
	return true


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
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	unlock_current_direction_for_session()
	var record := HelmetVisualV2.direction_record(current_item_id, current_direction)
	var nudge_value: Array = record.get("nudge", [0, 0])
	var changed := HelmetVisualV2.set_session_calibration_override(
		current_item_id,
		current_direction,
		{"nudge": [int(nudge_value[0]) + delta.x, int(nudge_value[1]) + delta.y]}
	)
	if changed:
		_dirty_directions[DIRECTIONS[current_direction]] = true
	return changed


func map_source_row_to_current_target(source_row: int) -> bool:
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	if source_row < 0 or source_row >= DIRECTIONS.size():
		return false
	var source_direction := HelmetVisualV2.source_direction_for_row(
		current_item_id, source_row
	)
	var fields := {
		"source_row": source_row,
		"source_slot_id": HelmetVisualV2.source_slot_id_for_row(
			current_item_id, source_row
		),
		"status": "valid",
	}
	if not source_direction.is_empty():
		fields["source_direction"] = source_direction
	unlock_current_direction_for_session()
	var changed := HelmetVisualV2.set_session_calibration_override(
		current_item_id,
		current_direction,
		fields
	)
	if changed:
		_dirty_directions[DIRECTIONS[current_direction]] = true
		_refresh_mapping_editor_ui()
	return changed


func undo_current_direction() -> void:
	HelmetVisualV2.clear_session_calibration_override(
		current_item_id, current_direction
	)
	_dirty_directions.erase(DIRECTIONS[current_direction])
	_refresh_mapping_editor_ui()


func reload_formal_data() -> void:
	HelmetVisualV2.reload_data()
	_dirty_directions.clear()
	_dirty_scale = false
	if _visual != null:
		_visual._refresh_equipment_visuals()
	_refresh_mapping_editor_ui()


func save_current_direction() -> bool:
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	var asset_override := HelmetVisualV2.visual_asset_override_for_item(
		current_item_id
	)
	if (
		(_dirty_scale or not asset_override.has("uniform_scale_percent"))
		and not _bake_and_persist_uniform_scale()
	):
		return false
	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var direction: String = str(DIRECTIONS[current_direction])
	var record := HelmetVisualV2.direction_record(current_item_id, current_direction)
	if not HelmetVisualV2.persist_calibration_override(
		current_item_id,
		current_direction,
		{
			"source_row": int(record.get("source_row", -1)),
			"source_slot_id": HelmetVisualV2.source_slot_id_for_row(
				current_item_id, int(record.get("source_row", -1))
			),
			"nudge": record.get("nudge", [0, 0]),
			"status": record.get("status", "valid"),
			"locked": record.get("locked", false),
		}
	):
		return false
	var source_direction := str(record.get("source_direction", ""))
	if not source_direction.is_empty():
		# Preserve explicit semantics only for assets whose source contract has
		# them. 151 deliberately exposes opaque source slots.
		HelmetVisualV2.persist_calibration_override(
			current_item_id,
			current_direction,
			{"source_direction": source_direction}
		)
	HelmetVisualV2.clear_session_calibration_override(
		current_item_id, current_direction
	)
	_dirty_directions.erase(direction)
	var payload := {
		"contractId": "equipment.world_helmet.calibration.session.v1",
		"itemId": current_item_id,
		"action": current_action,
		"direction": direction,
		"frameIndex": current_frame,
		"headSocket": _vector_array(HelmetVisualV2.body_head_socket(
			PLAYER_VISUAL_ID, current_action, current_direction, current_frame
		)),
		"directionRecord": record,
	}
	_write_json(output_dir.path_join(
		"helmet_%d_calibration_working.json" % current_item_id
	), payload)
	_refresh_mapping_editor_ui()
	return true


func _bake_and_persist_uniform_scale() -> bool:
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	var percent := HelmetVisualV2.uniform_scale_percent(current_item_id)
	var asset_id := HelmetVisualV2.visual_asset_id_for_item(current_item_id)
	var reference_record := HelmetVisualV2.direction_record(
		current_item_id, 0
	)
	var action_paths: Variant = reference_record.get(
		"layers", {}
	).get("helmet_front", {})
	if not action_paths is Dictionary or action_paths.is_empty():
		return false
	var test_destination := HelmetVisualV2.calibration_override_path().begins_with(
		"res://outputs/"
	) or HelmetVisualV2.calibration_override_path().begins_with("user://")
	var bake_root := (
		"%s/derived/%s/scale_%d" % [OUTPUT_ROOT, asset_id, percent]
		if test_destination
		else "res://assets/generated/helmet_v2/%s/scale_%d" % [asset_id, percent]
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bake_root))
	var derived_paths: Dictionary = {}
	var source_sha: Dictionary = {}
	var derived_sha: Dictionary = {}
	for action: String in action_paths:
		var source_path := HelmetVisualV2.base_action_texture_path(
			current_item_id, action, 0, "helmet_front"
		)
		if source_path.is_empty() or not ResourceLoader.exists(source_path):
			return false
		var source_image := (load(source_path) as Texture2D).get_image()
		var frame_count := int(
			source_image.get_width() / ArtSpec.WARRIOR_FRAME.x
		)
		if (
			frame_count <= 0
			or source_image.get_height() != 8 * ArtSpec.WARRIOR_FRAME.y
		):
			return false
		var derived := Image.create(
			source_image.get_width(),
			source_image.get_height(),
			false,
			Image.FORMAT_RGBA8
		)
		derived.fill(Color(0, 0, 0, 0))
		for source_row: int in 8:
			var direction_index := HelmetVisualV2.source_pivot_direction_index(
				current_item_id, source_row
			)
			if direction_index < 0:
				return false
			for frame_index: int in frame_count:
				var source_rect := Rect2i(
					frame_index * ArtSpec.WARRIOR_FRAME.x,
					source_row * ArtSpec.WARRIOR_FRAME.y,
					ArtSpec.WARRIOR_FRAME.x,
					ArtSpec.WARRIOR_FRAME.y
				)
				var cell := source_image.get_region(source_rect)
				var pivot := HelmetVisualV2.pivot_for_source_row(
					current_item_id, action, source_row, frame_index
				)
				if pivot == Vector2i.ZERO:
					return false
				var scaled := scale_cell_around_pivot(cell, pivot, percent)
				# The scaled cell is already composited onto a transparent
				# fixed-size cell. Copy it byte-for-byte into the atlas; a
				# second alpha blend would round semi-transparent edge colors.
				derived.blit_rect(
					scaled,
					Rect2i(Vector2i.ZERO, scaled.get_size()),
					source_rect.position
				)
		var derived_path := "%s/%s_%s_scale_%d.png" % [
			bake_root, asset_id, action, percent
		]
		if derived.save_png(ProjectSettings.globalize_path(derived_path)) != OK:
			return false
		derived_paths[action] = derived_path
		source_sha[action] = FileAccess.get_sha256(source_path)
		derived_sha[action] = FileAccess.get_sha256(derived_path)
	if not HelmetVisualV2.persist_uniform_scale_bake(
		current_item_id,
		percent,
		derived_paths,
		source_sha,
		derived_sha
	):
		return false
	_dirty_scale = false
	if _visual != null:
		_visual._refresh_equipment_visuals()
	return true


func generate_all_actions_from_idle() -> bool:
	if not HelmetVisualV2.idle_baseline_complete(current_item_id):
		get_node("CalibrationUI/Panel/VBox/MappingStatus/State").text = (
			"请先保存 8 个站立方向和统一缩放"
		)
		return false
	var before_items: Variant = HelmetVisualV2.calibration_overrides().get(
		"itemOverrides", {}
	).get(str(current_item_id), {}).duplicate(true)
	var percent := HelmetVisualV2.uniform_scale_percent(current_item_id)
	if not HelmetVisualV2.set_session_uniform_scale_percent(
		current_item_id, percent
	):
		return false
	_dirty_scale = true
	if not _bake_and_persist_uniform_scale():
		return false
	var trace_records: Array[Dictionary] = []
	var failures: Array[Dictionary] = []
	var asset_override := HelmetVisualV2.visual_asset_override_for_item(
		current_item_id
	)
	var derived_paths: Dictionary = asset_override.get("derivedAtlases", {})
	var source_hashes: Dictionary = asset_override.get("sourceAtlasSha256", {})
	var derived_hashes: Dictionary = asset_override.get("derivedAtlasSha256", {})
	var duplicate_idle_rows: Array[Array] = []
	var idle_hashes: Dictionary = {}
	for source_row: int in 8:
		var source_cell := source_row_thumbnail(source_row)
		var cell_hash := source_cell.get_data().hex_encode().hash()
		if idle_hashes.has(cell_hash):
			duplicate_idle_rows.append([int(idle_hashes[cell_hash]), source_row])
		else:
			idle_hashes[cell_hash] = source_row
	for action: String in ACTIONS:
		var source_path := HelmetVisualV2.base_action_texture_path(
			current_item_id, action, 0, "helmet_front"
		)
		var derived_path := str(derived_paths.get(action, ""))
		if (
			source_path.is_empty()
			or derived_path.is_empty()
			or not FileAccess.file_exists(source_path)
			or not FileAccess.file_exists(derived_path)
			or FileAccess.get_sha256(source_path) != str(source_hashes.get(action, ""))
			or FileAccess.get_sha256(derived_path) != str(derived_hashes.get(action, ""))
		):
			failures.append({"action": action, "reason": "atlas_or_sha_invalid"})
			continue
		var source_image := (load(source_path) as Texture2D).get_image()
		var derived_image := Image.load_from_file(derived_path)
		for direction_index: int in 8:
			var record := HelmetVisualV2.direction_record(
				current_item_id, direction_index
			)
			var source_row := int(record.get("source_row", -1))
			var nudge := _array_vector(record.get("nudge", []))
			for frame_index: int in int(ACTIONS[action]):
				var cell_rect := Rect2i(
					frame_index * ArtSpec.WARRIOR_FRAME.x,
					source_row * ArtSpec.WARRIOR_FRAME.y,
					ArtSpec.WARRIOR_FRAME.x,
					ArtSpec.WARRIOR_FRAME.y
				)
				var source_nonempty := _image_has_opaque_pixel(
					source_image.get_region(cell_rect)
				)
				var derived_nonempty := _image_has_opaque_pixel(
					derived_image.get_region(cell_rect)
				)
				var socket := HelmetVisualV2.body_head_socket(
					PLAYER_VISUAL_ID, action, direction_index, frame_index
				)
				var pivot := HelmetVisualV2.pivot_for_frame(
					current_item_id, action, direction_index, frame_index
				)
				var final_position := socket - pivot + nudge
				var frame_ok: bool = (
					source_nonempty
					and derived_nonempty
					and socket != Vector2i.ZERO
					and pivot != Vector2i.ZERO
					and record.get("runtime_scale", []) == [1.0, 1.0]
					and not bool(record.get("flip_h", true))
				)
				var trace := {
					"action": action,
					"targetDirection": DIRECTIONS[direction_index],
					"frameIndex": frame_index,
					"sourceRow": source_row,
					"sourceSlotId": HelmetVisualV2.source_slot_id_for_row(
						current_item_id, source_row
					),
					"bodyHeadSocket": _vector_array(socket),
					"helmetLocalPivot": _vector_array(pivot),
					"savedNudge": _vector_array(nudge),
					"uniformScalePercent": percent,
					"finalPosition": _vector_array(final_position),
					"sourceAtlas": source_path,
					"derivedAtlas": derived_path,
					"sourceNonempty": source_nonempty,
					"derivedNonempty": derived_nonempty,
					"nearest": true,
					"runtimeScale": [1, 1],
					"flip": false,
					"rotationDegrees": 0,
					"passed": frame_ok,
				}
				trace_records.append(trace)
				if not frame_ok:
					failures.append({
						"action": action,
						"direction": DIRECTIONS[direction_index],
						"frame": frame_index,
						"reason": "frame_validation_failed",
					})
	var after_items: Variant = HelmetVisualV2.calibration_overrides().get(
		"itemOverrides", {}
	).get(str(current_item_id), {})
	var idle_preserved: bool = before_items == after_items
	if not idle_preserved:
		failures.append({"reason": "saved_idle_baseline_changed"})
	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	_generate_all_actions_overview(output_dir)
	var report := {
		"schemaVersion": 1,
		"contractId": "equipment.world_helmet.generated_all_actions.v1",
		"itemId": current_item_id,
		"playerVisualId": PLAYER_VISUAL_ID,
		"manualBaseline": "saved_idle_target_to_source_slot_nudge_and_uniform_scale",
		"automaticFormula": (
			"body_head_socket(action,target,frame) - "
			+ "source_helmet_local_pivot(action,source_row,frame) + saved_nudge"
		),
		"actions": ACTIONS.keys(),
		"headSocketRecordCount": _head_socket_count(),
		"uniformScalePercent": percent,
		"nearestBake": true,
		"runtimeScale": [1, 1],
		"sourceAtlasSha256": source_hashes,
		"derivedAtlasSha256": derived_hashes,
		"duplicateIdleSourceRows": duplicate_idle_rows,
		"duplicateTargetSourceRows": _duplicate_saved_source_rows(
			current_item_id
		),
		"idleBaselinePreserved": idle_preserved,
		"passed": failures.is_empty(),
		"failures": failures,
		"records": trace_records,
	}
	_write_json(output_dir.path_join(
		"helmet_%d_generated_all_actions_trace.json" % current_item_id
	), report)
	get_node("CalibrationUI/Panel/VBox/MappingStatus/State").text = (
		"全动作生成完成" if failures.is_empty()
		else "生成失败：请查看逐帧报告"
	)
	return failures.is_empty()


func _image_has_opaque_pixel(image: Image) -> bool:
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				return true
	return false


func lock_current_direction() -> bool:
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	var record := HelmetVisualV2.direction_record(current_item_id, current_direction)
	if not HelmetVisualV2.set_session_calibration_override(
		current_item_id, current_direction, {"locked": true, "status": "locked"}
	):
		return false
	record = HelmetVisualV2.direction_record(current_item_id, current_direction)
	_session_unlocked.erase(DIRECTIONS[current_direction])
	_dirty_directions[DIRECTIONS[current_direction]] = true
	return save_current_direction()


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
		KEY_EQUAL, KEY_KP_ADD:
			set_uniform_scale_percent(
				HelmetVisualV2.uniform_scale_percent(current_item_id) + 1
			)
		KEY_MINUS, KEY_KP_SUBTRACT:
			set_uniform_scale_percent(
				HelmetVisualV2.uniform_scale_percent(current_item_id) - 1
			)
		KEY_S: save_current_direction()
		KEY_L: lock_current_direction()
	_refresh_mapping_editor_ui()


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
		if layer == null or not layer.visible:
			continue
		assert(layer.scale == Vector2.ONE and not layer.flip_h)
		var cell: Image
		var contract_layer: String = str({
			"ClientHelmetBackLayer": "helmet_back",
			"ClientHelmetLayer": "helmet_front",
			"HeadOcclusionMaskLayer": "head_occlusion_mask",
		}.get(layer_name, ""))
		if not contract_layer.is_empty():
			var path := HelmetVisualV2.base_action_texture_path(
				current_item_id,
				action,
				direction_index,
				contract_layer
			)
			if path.is_empty() or not ResourceLoader.exists(path):
				continue
			var source_row := HelmetVisualV2.source_direction_row(
				current_item_id, direction_index
			)
			cell = (load(path) as Texture2D).get_image().get_region(Rect2i(
				frame_index * ArtSpec.WARRIOR_FRAME.x,
				source_row * ArtSpec.WARRIOR_FRAME.y,
				ArtSpec.WARRIOR_FRAME.x,
				ArtSpec.WARRIOR_FRAME.y
			))
			cell = scale_cell_around_pivot(
				cell,
				HelmetVisualV2.pivot_for_frame(
					current_item_id,
					action,
					direction_index,
					frame_index
				),
				HelmetVisualV2.uniform_scale_percent(current_item_id)
			)
		else:
			if layer.texture == null:
				continue
			var source := layer.texture.get_image()
			cell = source.get_region(Rect2i(layer.region_rect))
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
	var record := HelmetVisualV2.direction_record(current_item_id, direction_index)
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


func _refresh_mapping_editor_ui() -> void:
	if not _editor_initialized or _visual == null:
		return
	var read_only := HelmetVisualV2.is_read_only(current_item_id)
	var direction := str(DIRECTIONS[current_direction])
	var record := HelmetVisualV2.direction_record(
		current_item_id, current_direction
	)
	var source_row := int(record.get("source_row", -1))
	var source_direction := str(record.get(
		"source_direction",
		HelmetVisualV2.source_direction_for_row(current_item_id, source_row)
	))
	var nudge := _array_vector(record.get("nudge", []))
	if current_item_id == 151:
		get_node("CalibrationUI/Panel/VBox/MappingStatus/Mapping").text = (
			"人物目标 %s <- 黑铁原始源槽 %d"
			% [direction, source_row]
		)
	else:
		get_node("CalibrationUI/Panel/VBox/MappingStatus/Mapping").text = (
			"人物目标 %s <- 头盔源 %s(row %d)"
			% [direction, source_direction, source_row]
		)
	get_node("CalibrationUI/Panel/VBox/MappingStatus/Nudge").text = (
		"nudge x=%d y=%d | action=%s frame=%d | scale=%d%%"
		% [
			nudge.x,
			nudge.y,
			current_action,
			current_frame,
			HelmetVisualV2.uniform_scale_percent(current_item_id),
		]
	)
	var direction_dirty := bool(_dirty_directions.get(direction, false))
	var state_text := ""
	if read_only:
		state_text = "READ ONLY"
	else:
		state_text = "%s / %s" % [
			"LOCKED" if bool(record.get("locked", false)) else "UNLOCKED",
			"DIRTY" if direction_dirty or _dirty_scale else "CLEAN",
		]
		if not _duplicate_saved_source_rows(current_item_id).is_empty():
			state_text += " / 警告：多个人物方向使用同一源槽"
	get_node("CalibrationUI/Panel/VBox/MappingStatus/State").text = state_text
	_updating_ui = true
	var scale_control := get_node(
		"CalibrationUI/Panel/VBox/Inputs/Scale"
	) as SpinBox
	scale_control.value = HelmetVisualV2.uniform_scale_percent(current_item_id)
	scale_control.editable = not read_only
	get_node("CalibrationUI/Panel/VBox/Inputs/ScaleMinus").disabled = read_only
	get_node("CalibrationUI/Panel/VBox/Inputs/ScalePlus").disabled = read_only
	var item_control := get_node(
		"CalibrationUI/Panel/VBox/Inputs/Item"
	) as OptionButton
	item_control.select(0 if current_item_id == 146 else 1)
	_updating_ui = false
	for direction_index: int in _target_buttons.size():
		var target_button := _target_buttons[direction_index]
		var target_frame := _runtime_frame(
			current_action, direction_index, current_frame, false
		)
		target_button.texture_normal = ImageTexture.create_from_image(target_frame)
		target_button.button_pressed = direction_index == current_direction
		target_button.modulate = (
			Color(1.0, 0.82, 0.25)
			if direction_index == current_direction
			else Color.WHITE
		)
	for row: int in _source_buttons.size():
		var source_button := _source_buttons[row]
		var source_image := source_row_thumbnail(row)
		source_button.texture_normal = ImageTexture.create_from_image(source_image)
		var real_direction := HelmetVisualV2.source_direction_for_row(
			current_item_id, row
		)
		(source_button.get_node("Label") as Label).text = (
			"源槽 %d" % row
			if current_item_id == 151
			else "%s (row %d)" % [real_direction, row]
		)
		source_button.set_meta(
			"source_cell_hash",
			source_image.get_data().hex_encode().hash()
		)
		source_button.disabled = read_only
		source_button.button_pressed = row == source_row
		source_button.modulate = (
			Color(0.35, 1.0, 0.72)
			if row == source_row
			else Color.WHITE
		)
	for control_name: String in [
		"NudgeUp", "NudgeDown", "NudgeLeft", "NudgeRight",
		"Save", "Lock",
	]:
		get_node(
			"CalibrationUI/Panel/VBox/Commands/%s" % control_name
		).disabled = read_only
	get_node(
		"CalibrationUI/Panel/VBox/Commands/GenerateAllActions"
	).disabled = not HelmetVisualV2.idle_baseline_complete(current_item_id)
	_render_current_previews()


func _duplicate_saved_source_rows(item_id: int) -> Array[Dictionary]:
	var first_target_by_row: Dictionary = {}
	var duplicates: Array[Dictionary] = []
	for direction_index: int in 8:
		var saved := HelmetVisualV2.saved_direction_override(
			item_id, direction_index
		)
		if not saved.has("source_row"):
			continue
		var source_row := int(saved.get("source_row", -1))
		if first_target_by_row.has(source_row):
			duplicates.append({
				"sourceRow": source_row,
				"firstTarget": DIRECTIONS[int(first_target_by_row[source_row])],
				"repeatedTarget": DIRECTIONS[direction_index],
				"warningOnly": true,
			})
		else:
			first_target_by_row[source_row] = direction_index
	return duplicates


func source_row_thumbnail(source_row: int) -> Image:
	assert(source_row >= 0 and source_row < DIRECTIONS.size())
	var path := HelmetVisualV2.base_action_texture_path(
		current_item_id, current_action, current_direction, "helmet_front"
	)
	var empty := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	empty.fill(Color(0, 0, 0, 0))
	if path.is_empty() or not ResourceLoader.exists(path):
		return empty
	var cell := (load(path) as Texture2D).get_image().get_region(Rect2i(
		current_frame * ArtSpec.WARRIOR_FRAME.x,
		source_row * ArtSpec.WARRIOR_FRAME.y,
		ArtSpec.WARRIOR_FRAME.x,
		ArtSpec.WARRIOR_FRAME.y
	))
	var pivot := HelmetVisualV2.pivot_for_source_row(
		current_item_id, current_action, source_row, current_frame
	)
	cell = scale_cell_around_pivot(
		cell,
		pivot,
		HelmetVisualV2.uniform_scale_percent(current_item_id)
	)
	return cell.get_region(Rect2i(
		pivot - HEAD_ZOOM_SOURCE_SIZE / 2,
		HEAD_ZOOM_SOURCE_SIZE
	))


func scale_cell_around_pivot(
	cell: Image,
	pivot: Vector2i,
	percent: int
) -> Image:
	assert(percent >= 50 and percent <= 200)
	if percent == 100:
		return cell.duplicate()
	var factor := float(percent) / 100.0
	var scaled := cell.duplicate()
	scaled.resize(
		maxi(1, roundi(cell.get_width() * factor)),
		maxi(1, roundi(cell.get_height() * factor)),
		Image.INTERPOLATE_NEAREST
	)
	var result := Image.create(
		cell.get_width(), cell.get_height(), false, Image.FORMAT_RGBA8
	)
	result.fill(Color(0, 0, 0, 0))
	var scaled_pivot := Vector2i(
		roundi(pivot.x * factor),
		roundi(pivot.y * factor)
	)
	result.blend_rect(
		scaled,
		Rect2i(Vector2i.ZERO, scaled.get_size()),
		pivot - scaled_pivot
	)
	return result


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
		current_item_id, action, direction_index, frame_index
	)
	var delta := HelmetVisualV2.final_position_delta(
		current_item_id, PLAYER_VISUAL_ID, action, direction_index, frame_index
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


func _save_editor_ui_preview(output_dir: String) -> void:
	_refresh_mapping_editor_ui()
	var screenshot: Image
	if DisplayServer.get_name() == "headless":
		# The headless/dummy renderer has no backing viewport texture. Reading
		# it emits a RenderingServer error before the CPU fallback can run.
		screenshot = _mapping_editor_cpu_preview()
	else:
		await get_tree().process_frame
		RenderingServer.force_draw()
		screenshot = get_viewport().get_texture().get_image()
		if screenshot == null or screenshot.is_empty():
			screenshot = _mapping_editor_cpu_preview()
	assert(screenshot.save_png(
		output_dir.path_join("helmet_mapping_editor_ui_preview.png")
	) == OK)


func _mapping_editor_cpu_preview() -> Image:
	var canvas := Image.create(1280, 900, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(18.0 / 255.0, 27.0 / 255.0, 39.0 / 255.0, 1))
	_cpu_panel(canvas, Rect2i(20, 20, 1240, 56), Color(0.12, 0.22, 0.34), Color(0.25, 0.75, 1.0))
	_cpu_panel(canvas, Rect2i(20, 92, 1240, 130), Color(0.08, 0.13, 0.2), Color(0.25, 0.55, 0.85))
	_cpu_panel(canvas, Rect2i(20, 238, 1240, 130), Color(0.08, 0.13, 0.2), Color(0.38, 0.85, 0.62))
	_cpu_panel(canvas, Rect2i(20, 384, 1240, 86), Color(0.08, 0.13, 0.2), Color(0.85, 0.7, 0.25))
	_cpu_panel(canvas, Rect2i(20, 486, 1240, 394), Color(0.08, 0.13, 0.2), Color(0.55, 0.45, 0.85))
	# Header iconography: eight target nodes flowing into eight source nodes.
	for index: int in 8:
		var header_x := 50 + index * 46
		canvas.fill_rect(Rect2i(header_x, 38, 20, 20), Color(0.25, 0.6, 0.95))
		canvas.fill_rect(Rect2i(860 + index * 46, 38, 20, 20), Color(0.35, 0.9, 0.62))
	canvas.fill_rect(Rect2i(450, 46, 350, 4), Color(0.85, 0.7, 0.25))
	canvas.fill_rect(Rect2i(790, 40, 12, 16), Color(0.85, 0.7, 0.25))
	var target_selected := current_direction
	var source_selected := HelmetVisualV2.source_direction_row(
		current_item_id, current_direction
	)
	for index: int in 8:
		for row: int in 2:
			var texture := (
				_target_buttons[index].texture_normal
				if row == 0
				else _source_buttons[index].texture_normal
			)
			var image := texture.get_image()
			image.resize(116, 92, Image.INTERPOLATE_NEAREST)
			var destination := Vector2i(38 + index * 152, 110 + row * 146)
			var selected := (
				index == target_selected if row == 0 else index == source_selected
			)
			_cpu_border(
				canvas,
				Rect2i(destination - Vector2i(4, 4), Vector2i(124, 100)),
				Color(1.0, 0.78, 0.2) if selected else (
					Color(0.25, 0.55, 0.85)
					if row == 0
					else Color(0.38, 0.85, 0.62)
				),
				4 if selected else 2
			)
			canvas.blend_rect(
				image,
				Rect2i(Vector2i.ZERO, image.get_size()),
				destination
			)
			# Row/direction index encoded as a visible tick count.
			for tick: int in index + 1:
				canvas.fill_rect(
					Rect2i(destination.x + tick * 10, destination.y + 82, 6, 5),
					Color.WHITE
				)
	# Mouse nudge controls and uniform-scale control strip.
	for button_index: int in 4:
		_cpu_panel(
			canvas,
			Rect2i(42 + button_index * 62, 402, 48, 48),
			Color(0.14, 0.2, 0.28),
			Color(0.55, 0.65, 0.76)
		)
	var scale_percent := HelmetVisualV2.uniform_scale_percent(current_item_id)
	var scale_rect := Rect2i(350, 410, 600, 24)
	canvas.fill_rect(scale_rect, Color(0.05, 0.08, 0.12))
	var scale_fill := roundi(
		float(scale_percent - 50) / 150.0 * float(scale_rect.size.x)
	)
	canvas.fill_rect(
		Rect2i(scale_rect.position, Vector2i(scale_fill, scale_rect.size.y)),
		Color(0.25, 0.78, 0.48)
	)
	_cpu_border(canvas, scale_rect, Color(0.8, 0.88, 0.95), 2)
	var baseline_x := scale_rect.position.x + roundi(scale_rect.size.x / 3.0)
	canvas.fill_rect(Rect2i(baseline_x - 2, 402, 4, 40), Color(0.3, 0.7, 1.0))
	var current_x := scale_rect.position.x + scale_fill
	canvas.fill_rect(Rect2i(current_x - 2, 400, 4, 44), Color(1.0, 0.78, 0.2))
	_cpu_draw_number(canvas, scale_percent, Vector2i(1000, 397), 6, Color(1.0, 0.85, 0.35))
	_cpu_draw_percent(canvas, Vector2i(1090, 405), Color(1.0, 0.85, 0.35))
	var full := (
		get_node(
			"CalibrationUI/Panel/VBox/Previews/FullColumn/FullPersonPreview"
		) as TextureRect
	).texture.get_image()
	var head := (
		get_node(
			"CalibrationUI/Panel/VBox/Previews/HeadColumn/HeadPreview"
		) as TextureRect
	).texture.get_image()
	_cpu_border(canvas, Rect2i(42, 510, 276, 344), Color(0.35, 0.58, 0.9), 3)
	canvas.blend_rect(
		full,
		Rect2i(Vector2i.ZERO, full.get_size()),
		Vector2i(52, 520)
	)
	head.resize(344, 344, Image.INTERPOLATE_NEAREST)
	_cpu_border(canvas, Rect2i(356, 510, 364, 364), Color(0.7, 0.45, 0.9), 3)
	canvas.blend_rect(
		head,
		Rect2i(Vector2i.ZERO, head.get_size()),
		Vector2i(366, 520)
	)
	# A compact eight-direction compass makes the active target unambiguous.
	var compass_center := Vector2i(990, 680)
	for index: int in 8:
		var angle := -PI / 2.0 + float(index) * PI / 4.0
		var point := compass_center + Vector2i(
			roundi(cos(angle) * 115.0), roundi(sin(angle) * 115.0)
		)
		var color := (
			Color(1.0, 0.78, 0.2)
			if index == target_selected
			else Color(0.25, 0.55, 0.85)
		)
		canvas.fill_rect(Rect2i(point - Vector2i(15, 15), Vector2i(30, 30)), color)
	canvas.fill_rect(Rect2i(compass_center - Vector2i(6, 6), Vector2i(12, 12)), Color.WHITE)
	return canvas


func _cpu_panel(
	image: Image,
	rect: Rect2i,
	fill: Color,
	border: Color
) -> void:
	image.fill_rect(rect, fill)
	_cpu_border(image, rect, border, 2)


func _cpu_border(
	image: Image,
	rect: Rect2i,
	color: Color,
	thickness: int
) -> void:
	image.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, thickness)), color)
	image.fill_rect(Rect2i(
		rect.position + Vector2i(0, rect.size.y - thickness),
		Vector2i(rect.size.x, thickness)
	), color)
	image.fill_rect(Rect2i(rect.position, Vector2i(thickness, rect.size.y)), color)
	image.fill_rect(Rect2i(
		rect.position + Vector2i(rect.size.x - thickness, 0),
		Vector2i(thickness, rect.size.y)
	), color)


func _cpu_draw_number(
	image: Image,
	value: int,
	origin: Vector2i,
	scale: int,
	color: Color
) -> void:
	var text := "%03d" % value
	for index: int in text.length():
		_cpu_draw_digit(
			image,
			int(text.substr(index, 1)),
			origin + Vector2i(index * scale * 5, 0),
			scale,
			color
		)


func _cpu_draw_digit(
	image: Image,
	digit: int,
	origin: Vector2i,
	scale: int,
	color: Color
) -> void:
	var segments_by_digit := [
		[0, 1, 2, 3, 4, 5],
		[1, 2],
		[0, 1, 6, 4, 3],
		[0, 1, 6, 2, 3],
		[5, 6, 1, 2],
		[0, 5, 6, 2, 3],
		[0, 5, 6, 4, 2, 3],
		[0, 1, 2],
		[0, 1, 2, 3, 4, 5, 6],
		[0, 1, 2, 3, 5, 6],
	]
	var horizontal := Vector2i(scale * 3, scale)
	var vertical := Vector2i(scale, scale * 3)
	var segment_rects := [
		Rect2i(origin + Vector2i(scale, 0), horizontal),
		Rect2i(origin + Vector2i(scale * 4, scale), vertical),
		Rect2i(origin + Vector2i(scale * 4, scale * 5), vertical),
		Rect2i(origin + Vector2i(scale, scale * 8), horizontal),
		Rect2i(origin + Vector2i(0, scale * 5), vertical),
		Rect2i(origin + Vector2i(0, scale), vertical),
		Rect2i(origin + Vector2i(scale, scale * 4), horizontal),
	]
	for segment: int in segments_by_digit[clampi(digit, 0, 9)]:
		image.fill_rect(segment_rects[segment], color)


func _cpu_draw_percent(image: Image, origin: Vector2i, color: Color) -> void:
	image.fill_rect(Rect2i(origin, Vector2i(7, 7)), color)
	image.fill_rect(Rect2i(origin + Vector2i(24, 30), Vector2i(7, 7)), color)
	for offset: int in 6:
		image.fill_rect(
			Rect2i(origin + Vector2i(5 + offset * 4, 28 - offset * 4), Vector2i(5, 5)),
			color
		)


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
	assert(overview.save_png(output_dir.path_join(
		"helmet_%d_all_actions_overview_1x.png" % current_item_id
	)) == OK)


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
	_add_check(checks, "all_head_sockets_present", _head_socket_count() == 232)
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
	var source_151 := _raw_151_source_slots_safe()
	_add_check(
		checks,
		"item_151_all_six_action_eight_source_rows_nonempty_and_sha_frozen",
		bool(source_151.get("passed", false)),
		source_151
	)
	_add_check(
		checks,
		"historical_151_golden_mapping_rejected_by_user",
		true,
		{"historicalBaselineRejectedByUser": true, "runtimeGate": false}
	)
	var passed := true
	for check: Dictionary in checks:
		passed = passed and bool(check.get("passed", false))
	return {
		"schemaVersion": 1,
		"contractId": "equipment.world_helmet.146.validation.v1",
		"itemId": ITEM_ID,
		"passed": passed,
		"headSocketRecords": _head_socket_count(),
		"source151": source_151,
		"historicalBaselineRejectedByUser": true,
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
		and HelmetVisualV2.persist_calibration_override(
			151, 0, {
				"source_row": 0,
				"source_slot_id": "slot_0",
				"nudge": [1, 0],
				"status": "valid",
				"locked": false,
			}
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


func _raw_151_source_slots_safe() -> Dictionary:
	var asset := HelmetVisualV2.visual_asset_for_item(151)
	var source_actions: Dictionary = asset.get("source", {}).get("actions", {})
	var failures: Array[Dictionary] = []
	var duplicates: Dictionary = {}
	for action: String in ACTIONS:
		var evidence: Dictionary = source_actions.get(action, {})
		var path := str(evidence.get("path", ""))
		if (
			path.is_empty()
			or not FileAccess.file_exists(path)
			or FileAccess.get_sha256(path) != str(evidence.get("sha256", ""))
		):
			failures.append({"action": action, "reason": "source_sha_mismatch"})
			continue
		var image := (load(path) as Texture2D).get_image()
		var seen: Dictionary = {}
		for source_row: int in 8:
			var cell := image.get_region(Rect2i(
				0,
				source_row * ArtSpec.WARRIOR_FRAME.y,
				ArtSpec.WARRIOR_FRAME.x,
				ArtSpec.WARRIOR_FRAME.y
			))
			if not _image_has_opaque_pixel(cell):
				failures.append({
					"action": action,
					"sourceRow": source_row,
					"reason": "source_row_empty",
				})
			var hash := cell.get_data().hex_encode().hash()
			if seen.has(hash):
				var action_duplicates: Array = duplicates.get(action, [])
				action_duplicates.append([int(seen[hash]), source_row])
				duplicates[action] = action_duplicates
			else:
				seen[hash] = source_row
	return {
		"passed": failures.is_empty(),
		"actionsChecked": ACTIONS.keys(),
		"sourceRowsPerAction": 8,
		"stateItemIndex": int(asset.get("source", {}).get("stateItemIndex", -1)),
		"originalPixelsModified": false,
		"flip": false,
		"rotationDegrees": 0,
		"duplicateSourceRows": duplicates,
		"failures": failures,
	}


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
