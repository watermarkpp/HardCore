class_name HelmetCalibrationTool
extends Node

@export var auto_run := true

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const EquipmentCharacterPreview := preload(
	"res://scripts/equipment_character_preview.gd"
)
const ITEM_ID := 146
const PLAYER_VISUAL_ID := "player.male.cloth_002"
const OUTPUT_ROOT := "res://outputs/visual_acceptance/helmet_calibration"
const TEST_OVERRIDE_PATH := OUTPUT_ROOT + "/helmet_146_test_overrides.json"
const DRAFT_ROOT := "res://assets/data/helmet_calibration_drafts"
const INTERACTIVE_USER_ARG := "--helmet-calibration-interactive"
const ACTIVE_TARGET_ARG_PREFIX := "--helmet-calibration-target="
const ACTIVE_TARGET_CONTRACT_ID := (
	"equipment.world_helmet.calibration.active_target.v1"
)
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
const SCALE_STEP_PERCENT := 5
const NUDGE_STEP_PX := 0.5
const POPUP_CURSOR_OFFSET := Vector2i(12, 12)
const POPUP_ESTIMATED_SIZE := Vector2i(180, 112)
const PAPER_DOLL_INITIAL_SCALE_PERCENT := 100
const PAPER_DOLL_LEGACY_SCALE_PERCENT := 25
const PAPER_DOLL_LEGACY_OFFSET := [110, 32]
const PAPER_DOLL_FALLBACK_DRAW_OFFSET := Vector2(73, 27)
const PAPER_DOLL_FALLBACK_SIZE := Vector2(32, 41)
const CLASSIC_HEAD_PATCHES_PATH := (
	"res://assets/data/equipment_classic_avatar_head_patches.json"
)

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
var _authored_source_cutout_cache: Dictionary = {}
var _dirty_directions: Dictionary = {}
var _dirty_scales: Dictionary = {}
var _presentation_dirty: Dictionary = {}
var _updating_ui := false
var _interactive_requested := false
var _initialization_error := ""
var _quit_requested := false
var _active_target_enabled := false
var _active_target_manifest_path := ""
var _active_target: Dictionary = {}
var _active_target_load_error := ""
var _scale_popup: PopupMenu
var _scale_popup_direction := -1
var _paper_doll_preview: EquipmentCharacterPreview
var _paper_doll_canvas: Control
var _paper_doll_overlay: TextureRect
var _paper_doll_direction: OptionButton
var _inventory_direction: OptionButton
var _ground_direction: OptionButton
var _inventory_preview: TextureRect
var _ground_preview: TextureRect
var _paper_dragging := false
var _paper_drag_origin := Vector2.ZERO
var _paper_overlay_origin := Vector2.ZERO
var _loaded_draft_items: Dictionary = {}
var _test_draft_session_id := ""
var _active_editor_scope := "world"


func _ready() -> void:
	_configure_active_target(OS.get_cmdline_user_args())
	_setup_ui()
	if auto_run:
		_run.call_deferred()


func _notification(what: int) -> void:
	if what in [
		NOTIFICATION_WM_CLOSE_REQUEST,
		NOTIFICATION_WM_GO_BACK_REQUEST,
	]:
		_request_exit(0)


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
	_prepare_headless_missing_nw_preview()
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
		+ "calibration_assets=11 item_ids=12 sockets=232 "
		+ "directions=8 cast=true source_pixels_frozen=true"
	)
	dispose_runtime_for_test()
	_request_exit(0)


func _prepare_headless_missing_nw_preview() -> void:
	var nw_index := DIRECTIONS.find("NW")
	if (
		current_item_id == 146
		and nw_index >= 0
		and not HelmetVisualV2.saved_direction_override(
			current_item_id, nw_index
		).has("source_row")
		and _source_recipe_id() == "elf_146.user_authorized_nw_mirror.v1"
	):
		HelmetVisualV2.set_session_calibration_override(
			current_item_id,
			nw_index,
			{
				"source_row": 3,
				"source_slot_id": "slot_3",
				"source_direction": "NW",
				"status": "unassigned",
				"locked": false,
			}
		)


func has_interactive_user_arg(user_args: PackedStringArray) -> bool:
	return INTERACTIVE_USER_ARG in user_args


func _configure_active_target(user_args: PackedStringArray) -> bool:
	for argument: String in user_args:
		if argument.begins_with(ACTIVE_TARGET_ARG_PREFIX):
			return _load_active_target_manifest(
				argument.substr(ACTIVE_TARGET_ARG_PREFIX.length())
			)
	return true


func _load_active_target_manifest(path: String) -> bool:
	_active_target_load_error = ""
	if path.is_empty():
		return _fail_active_target("active target manifest path is empty")
	_active_target_manifest_path = path
	if not FileAccess.file_exists(path):
		return _fail_active_target(
			"active target manifest does not exist: %s" % path
		)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _fail_active_target(
			"active target manifest is not a JSON object: %s" % path
		)
	var target := parsed as Dictionary
	if str(target.get("contractId", "")) != ACTIVE_TARGET_CONTRACT_ID:
		return _fail_active_target("active target contractId is invalid")
	var item_id := int(target.get("itemId", -1))
	var item_exists := false
	for item: Variant in HelmetVisualV2.calibration_items():
		if (
			item is Dictionary
			and int(item.get("calibrationItemId", -1)) == item_id
		):
			item_exists = true
			break
	if not item_exists:
		return _fail_active_target(
			"active target item is not calibratable: %d" % item_id
		)
	var expected_asset_id := HelmetVisualV2.visual_asset_id_for_item(item_id)
	if str(target.get("visualAssetId", "")) != expected_asset_id:
		return _fail_active_target(
			"active target visualAssetId does not match item %d" % item_id
		)
	var source_path := str(target.get("sourceSheet", ""))
	if (
		not source_path.begins_with("res://")
		or source_path.get_extension().to_lower() != "png"
		or not FileAccess.file_exists(source_path)
	):
		return _fail_active_target(
			"active target source PNG does not exist: %s" % source_path
		)
	var expected_sha := str(target.get("sourceSheetSha256", "")).to_lower()
	var actual_sha := FileAccess.get_sha256(source_path).to_lower()
	if expected_sha.is_empty() or actual_sha != expected_sha:
		return _fail_active_target(
			"active target source hash mismatch: %s" % source_path
		)
	var grid: Variant = target.get("sourceGrid", [])
	if (
		not grid is Array
		or grid.size() != 2
		or int(grid[0]) != 4
		or int(grid[1]) != 2
	):
		return _fail_active_target("active target sourceGrid must be [4, 2]")
	var direction_order: Variant = target.get("sourceDirectionOrder", [])
	if not direction_order is Array or direction_order.size() != DIRECTIONS.size():
		return _fail_active_target(
			"active target sourceDirectionOrder must contain 8 directions"
		)
	var seen_directions := {}
	for direction_value: Variant in direction_order:
		var direction := str(direction_value)
		if direction not in DIRECTIONS or seen_directions.has(direction):
			return _fail_active_target(
				"active target directions must be one unique N,NE,E,SE,S,SW,W,NW permutation"
			)
		seen_directions[direction] = true
	var prepared_files: Variant = target.get("preparedDirectionFiles", {})
	if prepared_files is Dictionary and not prepared_files.is_empty():
		var prepared_sha: Variant = target.get("preparedDirectionSha256", {})
		if not prepared_sha is Dictionary:
			return _fail_active_target(
				"preparedDirectionSha256 must accompany preparedDirectionFiles"
			)
		for direction: String in DIRECTIONS:
			var prepared_path := str(prepared_files.get(direction, ""))
			var prepared_expected_sha := str(
				prepared_sha.get(direction, "")
			).to_lower()
			if (
				prepared_path.is_empty()
				or prepared_path.get_extension().to_lower() != "png"
				or not FileAccess.file_exists(prepared_path)
				or prepared_expected_sha.is_empty()
				or FileAccess.get_sha256(prepared_path).to_lower()
					!= prepared_expected_sha
			):
				return _fail_active_target(
					"prepared transparent direction is invalid: %s" % direction
				)
	_active_target_enabled = true
	_active_target = target.duplicate(true)
	current_item_id = item_id
	_authored_source_cutout_cache.clear()
	if bool(target.get("initializeSessionDirectionMapping", false)):
		if not _initialize_active_target_session_direction_mapping(
			item_id, direction_order
		):
			return _fail_active_target(
				"active target session direction mapping is invalid"
			)
	return true


func _initialize_active_target_session_direction_mapping(
	item_id: int,
	direction_order: Array
) -> bool:
	for direction_index: int in DIRECTIONS.size():
		var direction: String = DIRECTIONS[direction_index]
		var source_row: int = direction_order.find(direction)
		if source_row < 0:
			return false
		var current: Dictionary = HelmetVisualV2.direction_record(
			item_id, direction_index
		)
		var session: Dictionary = {
			"source_row": source_row,
			"source_slot_id": "slot_%d" % source_row,
			"source_direction": direction,
			"status": "valid",
			"locked": false,
		}
		if current.has("nudge"):
			session["nudge"] = current["nudge"]
		if current.has("scale_percent"):
			session["scale_percent"] = current["scale_percent"]
		if not HelmetVisualV2.set_session_calibration_override(
			item_id, direction_index, session
		):
			return false
	return true


func _fail_active_target(message: String) -> bool:
	_active_target_load_error = message
	_active_target_enabled = false
	_active_target = {}
	push_error(message)
	return false


func active_target_item_id() -> int:
	return (
		int(_active_target.get("itemId", -1))
		if _active_target_enabled
		else -1
	)


func active_target_source_sheet_sha256() -> String:
	return (
		str(_active_target.get("sourceSheetSha256", "")).to_lower()
		if _active_target_enabled
		else ""
	)


func _active_target_applies_to_current_item() -> bool:
	return (
		_active_target_enabled
		and current_item_id == active_target_item_id()
	)


func _session_calibration_items() -> Array:
	return HelmetVisualV2.calibration_items()


func _calibration_source_contract() -> Dictionary:
	if _active_target_applies_to_current_item():
		return {
			"calibrationSourceSheet": str(
				_active_target.get("sourceSheet", "")
			),
			"calibrationSourceSheetSha256": str(
				_active_target.get("sourceSheetSha256", "")
			).to_lower(),
			"calibrationSourceGrid": _active_target.get(
				"sourceGrid", [4, 2]
			),
			"sourceSlotDirectionOrder": _active_target.get(
				"sourceDirectionOrder", DIRECTIONS
			),
			"calibrationSourceMatte": str(
				_active_target.get("sourceMatte", "transparent")
			),
			"calibrationResizeFilter": str(
				_active_target.get("sourceResizeFilter", "nearest")
			),
			"calibrationPreparedSourceRows": [],
			"calibrationPreparedDirectionFiles": _active_target.get(
				"preparedDirectionFiles", {}
			),
			"calibrationPreparedDirectionSha256": _active_target.get(
				"preparedDirectionSha256", {}
			),
			"calibrationPreviewPolicy": (
				"single_active_target_direct_png_hash_validated"
			),
		}
	var source: Variant = HelmetVisualV2.visual_asset_for_item(
		current_item_id
	).get("source", {})
	return source if source is Dictionary else {}


func _calibration_source_direction_for_row(source_row: int) -> String:
	if source_row < 0 or source_row >= DIRECTIONS.size():
		return ""
	if _active_target_applies_to_current_item():
		var order: Array = _active_target.get(
			"sourceDirectionOrder", DIRECTIONS
		)
		return str(order[source_row])
	return HelmetVisualV2.source_direction_for_row(
		current_item_id, source_row
	)


func _calibration_pivot_for_source_row(
	action: String,
	source_row: int,
	frame_index: int
) -> Vector2i:
	if _active_target_applies_to_current_item():
		var direction := _calibration_source_direction_for_row(source_row)
		var direction_index := DIRECTIONS.find(direction)
		assert(direction_index >= 0)
		return HelmetVisualV2.pivot_for_frame(
			current_item_id, action, direction_index, frame_index
		)
	return HelmetVisualV2.pivot_for_source_row(
		current_item_id, action, source_row, frame_index
	)


func _placement_source_row(source_row: int) -> int:
	if not _active_target_applies_to_current_item():
		return source_row
	var direction := _calibration_source_direction_for_row(source_row)
	var record: Variant = HelmetVisualV2.visual_asset_for_item(
		current_item_id
	).get("directions", {}).get(direction, {})
	if record is Dictionary:
		return int(record.get("source_row", source_row))
	return source_row


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
	print(
		"HELMET_CALIBRATION_TOOL_INTERACTIVE_READY item=%d single_target=%s"
		% [current_item_id, str(_active_target_enabled)]
	)
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
		"mode": "maximized",
		"dpiSafe": true,
		"manualPhysicalSize": false,
		"manualPosition": false,
		"projectSettingsModified": false,
		"closeRequestHandled": true,
		"closeButton": true,
		"escapeCloses": true,
	}


func _configure_interactive_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Let Windows choose the DPI-aware physical bounds on the active monitor.
	# Manual pixel sizes/positions are scaled twice on some high-DPI desktops.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


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
			"交互编辑器已就绪。保存仅写入正式覆盖合同；可用关闭按钮或 Esc 退出。"
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
			"初始化失败：%s\n仍可关闭编辑器；详情见 outputs/helmet_calibration_interactive.log。"
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
	if not _active_target_load_error.is_empty():
		_show_initialization_error(_active_target_load_error)
		return false
	PlayerState.test_mode = true
	PlayerState.ensure_developer_test_character()
	if not PlayerState.select_character("developer_warrior_30"):
		_show_initialization_error("无法选择 developer_warrior_30 测试角色")
		return false
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState.equipment = {
		"衣服": {"item_id": 116, "name": "布衣(男)", "instance_id": "helmet_v2_cloth"},
		"头盔": {
			"item_id": current_item_id,
			"name": _calibration_item_display_name(current_item_id),
			"instance_id": "helmet_v2_%d" % current_item_id,
		},
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
		_test_draft_session_id = str(get_instance_id())
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
	select_item(current_item_id)
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
	item_control.clear()
	for item: Variant in _session_calibration_items():
		if not item is Dictionary:
			continue
		var calibration_item_id := int(item.get("calibrationItemId", -1))
		var item_ids: Variant = item.get("itemIds", [])
		var id_labels: PackedStringArray = []
		if item_ids is Array:
			for value: Variant in item_ids:
				id_labels.append(str(int(value)))
		var id_label := "/".join(id_labels)
		var label := "%s %s" % [
			id_label,
			str(item.get("displayName", "")),
		]
		if item_ids is Array and item_ids.size() > 1:
			label += "（共用）"
		item_control.add_item(label, calibration_item_id)
	item_control.disabled = false
	for action: String in ACTIONS:
		action_control.add_item(action)
	for direction: String in DIRECTIONS:
		direction_control.add_item(direction)
	for zoom_value: int in [1, 8, 10]:
		zoom_control.add_item("%dx" % zoom_value, zoom_value)
	zoom_control.select(1)
	item_control.item_selected.connect(func(index: int) -> void:
		select_item(int(item_control.get_item_id(index)))
		item_control.release_focus()
	)
	action_control.item_selected.connect(func(index: int) -> void:
		select_action(str(action_control.get_item_text(index)))
		_refresh_mapping_editor_ui()
		action_control.release_focus()
	)
	direction_control.item_selected.connect(func(index: int) -> void:
		select_target_direction(index)
		direction_control.release_focus()
	)
	var frame_control := get_node("CalibrationUI/Panel/VBox/Inputs/Frame") as SpinBox
	frame_control.value_changed.connect(func(value: float) -> void:
		select_frame(int(value))
		_refresh_mapping_editor_ui()
	)
	zoom_control.item_selected.connect(func(index: int) -> void:
		set_head_zoom(int(zoom_control.get_item_id(index)))
		_refresh_mapping_editor_ui()
		zoom_control.release_focus()
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
	get_node("CalibrationUI/Panel/VBox/Inputs/SaveAll").pressed.connect(
		func() -> void:
			save_all_changes()
	)
	get_node("CalibrationUI/Panel/VBox/Inputs/CloseEditor").pressed.connect(
		func() -> void:
			_request_exit(0)
	)
	_build_mapping_buttons()
	_setup_direction_scale_popup()
	_setup_presentation_ui()
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
	_disable_keyboard_focus_for_editor_controls()


func _disable_keyboard_focus_for_editor_controls() -> void:
	var root := get_node("CalibrationUI") as Control
	root.focus_mode = Control.FOCUS_NONE
	for node: Node in root.find_children("*", "Control", true, false):
		(node as Control).focus_mode = Control.FOCUS_NONE
	for spin_path: String in [
		"CalibrationUI/Panel/VBox/Inputs/Frame",
		"CalibrationUI/Panel/VBox/Inputs/Scale",
	]:
		var spin := get_node(spin_path) as SpinBox
		spin.focus_mode = Control.FOCUS_NONE
		spin.get_line_edit().focus_mode = Control.FOCUS_NONE
	get_viewport().gui_release_focus()


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
			_set_active_editor_scope("world")
			select_target_direction(direction_index)
		)
		target_button.gui_input.connect(func(event: InputEvent) -> void:
			if (
				event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_RIGHT
				and event.pressed
			):
				_set_active_editor_scope("world")
				select_target_direction(direction_index)
				_open_direction_scale_popup(direction_index)
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
			_set_active_editor_scope("world")
			map_source_row_to_current_target(source_row)
		)
		source_grid.add_child(source_button)
		_source_buttons.append(source_button)


func _setup_direction_scale_popup() -> void:
	_scale_popup = PopupMenu.new()
	_scale_popup.name = "DirectionScalePopup"
	_scale_popup.add_item("放大 5%", 1)
	_scale_popup.add_item("缩小 5%", 2)
	_scale_popup.add_separator()
	_scale_popup.add_item("恢复 100%", 3)
	_scale_popup.id_pressed.connect(func(id: int) -> void:
		if _scale_popup_direction < 0:
			return
		match id:
			1: adjust_direction_scale_percent(
				_scale_popup_direction, SCALE_STEP_PERCENT
			)
			2: adjust_direction_scale_percent(
				_scale_popup_direction, -SCALE_STEP_PERCENT
			)
			3: set_direction_scale_percent(_scale_popup_direction, 100)
	)
	add_child(_scale_popup)


func _open_direction_scale_popup(direction_index: int) -> void:
	_scale_popup_direction = direction_index
	if _scale_popup == null:
		return
	_popup_near_mouse(_scale_popup)


func popup_position_near_pointer(
	pointer: Vector2,
	popup_size: Vector2i = POPUP_ESTIMATED_SIZE
) -> Vector2i:
	var visible_rect := get_viewport().get_visible_rect()
	var desired := Vector2i(pointer.round()) + POPUP_CURSOR_OFFSET
	var minimum := Vector2i(visible_rect.position.round())
	var maximum := Vector2i((
		visible_rect.end - Vector2(popup_size)
	).round())
	maximum.x = maxi(maximum.x, minimum.x)
	maximum.y = maxi(maximum.y, minimum.y)
	return Vector2i(
		clampi(desired.x, minimum.x, maximum.x),
		clampi(desired.y, minimum.y, maximum.y)
	)


func _popup_near_mouse(popup: PopupMenu) -> void:
	var anchor := popup_position_near_pointer(
		get_viewport().get_mouse_position()
	)
	popup.popup(Rect2i(anchor, Vector2i.ZERO))


func _setup_presentation_ui() -> void:
	var root := get_node(
		"CalibrationUI/Panel/VBox/PresentationCalibration"
	) as HBoxContainer
	var paper_canvas := root.get_node("PaperDoll/Canvas") as Control
	_paper_doll_canvas = paper_canvas
	_paper_doll_canvas.gui_input.connect(_on_paper_canvas_input)
	_paper_doll_preview = EquipmentCharacterPreview.new()
	_paper_doll_preview.name = "WarriorChiyueBase"
	_paper_doll_preview.configure_presentation_mode("classic_avatar")
	_paper_doll_preview.configure_profile("战士", {
		"武器": {"item_id": 113, "name": "怒斩"},
		"衣服": {"item_id": 140, "name": "天魔神甲"},
	})
	paper_canvas.add_child(_paper_doll_preview)
	_paper_doll_preview.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_paper_doll_overlay = TextureRect.new()
	_paper_doll_overlay.name = "HelmetOverlay"
	_paper_doll_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_paper_doll_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_paper_doll_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_paper_doll_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_paper_doll_overlay.gui_input.connect(_on_paper_overlay_input)
	paper_canvas.add_child(_paper_doll_overlay)
	_paper_doll_direction = root.get_node(
		"Selectors/PaperDollDirection"
	) as OptionButton
	_inventory_direction = root.get_node(
		"Selectors/InventoryDirection"
	) as OptionButton
	_ground_direction = root.get_node(
		"Selectors/GroundDirection"
	) as OptionButton
	_inventory_preview = root.get_node(
		"Selectors/SelectionPreviews/InventoryPreview"
	) as TextureRect
	_ground_preview = root.get_node(
		"Selectors/SelectionPreviews/GroundPreview"
	) as TextureRect
	for option: OptionButton in [
		_paper_doll_direction, _inventory_direction, _ground_direction,
	]:
		option.clear()
		for direction_index: int in DIRECTIONS.size():
			option.add_item(str(DIRECTIONS[direction_index]), direction_index)
		option.focus_mode = Control.FOCUS_NONE
	_paper_doll_direction.item_selected.connect(func(index: int) -> void:
		_set_active_editor_scope("paperDoll")
		_update_presentation_selection("paperDoll", index)
	)
	_inventory_direction.item_selected.connect(func(index: int) -> void:
		_update_presentation_selection("inventory", index)
	)
	_ground_direction.item_selected.connect(func(index: int) -> void:
		_update_presentation_selection("ground", index)
	)
	_load_presentation_controls()


func _set_active_editor_scope(scope: String) -> void:
	assert(scope in ["world", "paperDoll"])
	_active_editor_scope = scope


func _on_paper_canvas_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_set_active_editor_scope("paperDoll")


func _on_paper_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			_set_active_editor_scope("paperDoll")
		if event.button_index == MOUSE_BUTTON_LEFT:
			_paper_dragging = event.pressed
			if event.pressed:
				_paper_drag_origin = event.position
				_paper_overlay_origin = _paper_doll_overlay.position
			else:
				_commit_paper_overlay_position()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_scale_popup_direction = -1
			var popup := PopupMenu.new()
			popup.add_item("放大 5%", 1)
			popup.add_item("缩小 5%", 2)
			popup.id_pressed.connect(func(id: int) -> void:
				var presentation := _current_presentation_calibration()
				var paper: Dictionary = presentation.get("paperDoll", {})
				var percent := int(paper.get(
					"scale_percent", PAPER_DOLL_INITIAL_SCALE_PERCENT
				))
				paper["scale_percent"] = clampi(
					percent + (SCALE_STEP_PERCENT if id == 1 else -SCALE_STEP_PERCENT),
					10,
					300
				)
				presentation["paperDoll"] = paper
				_apply_presentation_session(presentation)
				_refresh_presentation_ui()
				popup.queue_free()
			)
			add_child(popup)
			_popup_near_mouse(popup)
	elif event is InputEventMouseMotion and _paper_dragging:
		_paper_doll_overlay.position = (
			_paper_overlay_origin + event.position - _paper_drag_origin
		)


func _commit_paper_overlay_position() -> void:
	var presentation := _current_presentation_calibration()
	var paper: Dictionary = presentation.get("paperDoll", {})
	paper["offset"] = [
		roundi(_paper_doll_overlay.position.x),
		roundi(_paper_doll_overlay.position.y),
	]
	presentation["paperDoll"] = paper
	_apply_presentation_session(presentation)


func _paper_doll_reference_record() -> Dictionary:
	if not FileAccess.file_exists(CLASSIC_HEAD_PATCHES_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CLASSIC_HEAD_PATCHES_PATH)
	)
	if not parsed is Dictionary:
		return {}
	var item: Variant = parsed.get("itemsById", {}).get(
		str(current_item_id), {}
	)
	if not item is Dictionary:
		return {}
	var patch: Variant = item.get("flattenedHeadPatch", {})
	return patch.duplicate(true) if patch is Dictionary else {}


func _paper_doll_reference_rect() -> Rect2:
	var record := _paper_doll_reference_record()
	var source_offset := PAPER_DOLL_FALLBACK_DRAW_OFFSET
	var source_size := PAPER_DOLL_FALLBACK_SIZE
	if not record.is_empty():
		var offset_value: Variant = record.get("drawOffset", [])
		var size_value: Variant = record.get("size", [])
		if offset_value is Array and offset_value.size() == 2:
			source_offset = Vector2(
				float(offset_value[0]), float(offset_value[1])
			)
		if size_value is Array and size_value.size() == 2:
			source_size = Vector2(
				float(size_value[0]), float(size_value[1])
			)
	var preview_scale := (
		_paper_doll_preview.preview_scale
		if _paper_doll_preview != null
		else EquipmentCharacterPreview.DEFAULT_PREVIEW_SCALE
	)
	var origin := (
		_paper_doll_preview.composition_draw_origin()
		if _paper_doll_preview != null
		else Vector2.ZERO
	)
	return Rect2(
		origin + source_offset * preview_scale,
		source_size * preview_scale
	)


func _paper_doll_display_size(
	paper_cutout: Image,
	percent: int
) -> Vector2:
	var reference_size := _paper_doll_reference_rect().size
	var factor := float(percent) / 100.0
	if paper_cutout.is_empty():
		return reference_size * factor
	var source_size := Vector2(paper_cutout.get_size())
	var target_height := reference_size.y * factor
	return Vector2(
		target_height * source_size.x / maxf(1.0, source_size.y),
		target_height
	)


func _paper_doll_default_offset(
	source_row: int = 4,
	percent: int = PAPER_DOLL_INITIAL_SCALE_PERCENT
) -> Array:
	var paper_cutout := _authored_source_cutout(source_row)
	if paper_cutout.is_empty():
		paper_cutout = source_row_thumbnail(source_row)
	var display_size := _paper_doll_display_size(paper_cutout, percent)
	var reference_rect := _paper_doll_reference_rect()
	var position := reference_rect.get_center() - display_size * 0.5
	return [roundi(position.x), roundi(position.y)]


func _migrate_legacy_paper_doll_defaults(
	presentation: Dictionary
) -> Dictionary:
	var migrated := presentation.duplicate(true)
	var paper: Variant = migrated.get("paperDoll", {})
	if not paper is Dictionary:
		return migrated
	var offset: Variant = paper.get("offset", [])
	if (
		int(paper.get("scale_percent", -1))
			!= PAPER_DOLL_LEGACY_SCALE_PERCENT
		or not offset is Array
		or offset.size() != 2
		or int(offset[0]) != int(PAPER_DOLL_LEGACY_OFFSET[0])
		or int(offset[1]) != int(PAPER_DOLL_LEGACY_OFFSET[1])
	):
		return migrated
	var row := int(paper.get("source_row", 4))
	var corrected: Dictionary = paper.duplicate(true)
	corrected["scale_percent"] = PAPER_DOLL_INITIAL_SCALE_PERCENT
	corrected["offset"] = _paper_doll_default_offset(
		row, PAPER_DOLL_INITIAL_SCALE_PERCENT
	)
	migrated["paperDoll"] = corrected
	return migrated


func _default_presentation_calibration() -> Dictionary:
	return {
		"paperDoll": {
			"source_row": 4,
			"offset": _paper_doll_default_offset(),
			"scale_percent": PAPER_DOLL_INITIAL_SCALE_PERCENT,
		},
		"inventory": {"source_row": 4},
		"ground": {"source_row": 4},
	}


func _current_presentation_calibration() -> Dictionary:
	var value := HelmetVisualV2.presentation_calibration(current_item_id)
	return (
		_default_presentation_calibration()
		if value.is_empty()
		else _migrate_legacy_paper_doll_defaults(value)
	)


func _load_presentation_controls() -> void:
	_refresh_presentation_ui()


func _update_presentation_selection(role: String, source_row: int) -> void:
	if _updating_ui:
		return
	var presentation := _current_presentation_calibration()
	var record: Dictionary = presentation.get(role, {})
	record["source_row"] = source_row
	if role == "paperDoll":
		record["offset"] = record.get(
			"offset",
			_paper_doll_default_offset(source_row)
		)
		record["scale_percent"] = record.get(
			"scale_percent", PAPER_DOLL_INITIAL_SCALE_PERCENT
		)
	presentation[role] = record
	_apply_presentation_session(presentation)
	_refresh_presentation_ui()


func _apply_presentation_session(presentation: Dictionary) -> bool:
	if not HelmetVisualV2.set_session_presentation_calibration(
		current_item_id, presentation
	):
		return false
	_presentation_dirty[_scale_dirty_key(current_item_id)] = true
	return true


func _refresh_presentation_ui() -> void:
	if (
		_paper_doll_overlay == null
		or _paper_doll_direction == null
		or not _editor_initialized
	):
		return
	var presentation := _current_presentation_calibration()
	var paper: Dictionary = presentation.get("paperDoll", {})
	var paper_row := int(paper.get("source_row", 4))
	var paper_cutout := _authored_source_cutout(paper_row)
	if paper_cutout.is_empty():
		paper_cutout = source_row_thumbnail(paper_row)
	var percent := int(paper.get(
		"scale_percent", PAPER_DOLL_INITIAL_SCALE_PERCENT
	))
	var display_size := _paper_doll_display_size(paper_cutout, percent)
	_paper_doll_overlay.texture = ImageTexture.create_from_image(paper_cutout)
	_paper_doll_overlay.size = display_size
	var offset: Array = paper.get(
		"offset",
		_paper_doll_default_offset(paper_row, percent)
	)
	_paper_doll_overlay.position = Vector2(float(offset[0]), float(offset[1]))
	var inventory_row := int(
		presentation.get("inventory", {}).get("source_row", 4)
	)
	var ground_row := int(
		presentation.get("ground", {}).get("source_row", 4)
	)
	_updating_ui = true
	_paper_doll_direction.select(paper_row)
	_inventory_direction.select(inventory_row)
	_ground_direction.select(ground_row)
	_updating_ui = false
	_inventory_preview.texture = ImageTexture.create_from_image(
		source_row_thumbnail(inventory_row)
	)
	_ground_preview.texture = ImageTexture.create_from_image(
		source_row_thumbnail(ground_row)
	)


func _direction_texture_button(
	node_name: String,
	label_text: String
) -> TextureButton:
	var button := TextureButton.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(104, 82)
	button.ignore_texture_size = true
	# Keep the 64x64 runtime source crop at 1x. Scaling each thumbnail to the
	# button bounds made its apparent size disagree with the worn preview.
	button.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
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
	var calibration_item_ids: Array[int] = []
	for item: Variant in _session_calibration_items():
		if item is Dictionary:
			calibration_item_ids.append(int(item.get("calibrationItemId", -1)))
	assert(item_id in calibration_item_ids)
	current_item_id = item_id
	_load_saved_draft_for_item(item_id)
	if _visual != null:
		var item_name := _calibration_item_display_name(item_id)
		PlayerState.equipment["头盔"] = {
			"item_id": item_id,
			"name": item_name,
			"instance_id": "helmet_mapping_editor_%d" % item_id,
		}
		_visual._refresh_equipment_visuals()
	_refresh_mapping_editor_ui()


func _calibration_item_display_name(item_id: int) -> String:
	if (
		_active_target_enabled
		and item_id == active_target_item_id()
		and not str(_active_target.get("displayName", "")).is_empty()
	):
		return str(_active_target.get("displayName", ""))
	for item: Variant in _session_calibration_items():
		if item is Dictionary and int(item.get("calibrationItemId", -1)) == item_id:
			return str(item.get("displayName", "Helmet %d" % item_id))
	return "Helmet %d" % item_id


func _direction_dirty_key(item_id: int, direction_index: int) -> String:
	return "%d:%s" % [
		HelmetVisualV2.calibration_item_id_for_item(item_id),
		DIRECTIONS[direction_index],
	]


func _scale_dirty_key(item_id: int) -> String:
	return HelmetVisualV2.visual_asset_id_for_item(item_id)


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
	for direction_index: int in DIRECTIONS.size():
		HelmetVisualV2.set_session_calibration_override(
			current_item_id,
			direction_index,
			{"scale_percent": safe_percent}
		)
	_dirty_scales[_scale_dirty_key(current_item_id)] = true
	_refresh_mapping_editor_ui()
	return true


func set_direction_scale_percent(
	direction_index: int,
	percent: int
) -> bool:
	if (
		direction_index < 0
		or direction_index >= DIRECTIONS.size()
		or HelmetVisualV2.is_read_only(current_item_id)
	):
		return false
	var safe_percent := clampi(
		roundi(float(percent) / float(SCALE_STEP_PERCENT))
			* SCALE_STEP_PERCENT,
		50,
		200
	)
	if not HelmetVisualV2.set_session_calibration_override(
		current_item_id,
		direction_index,
		{"scale_percent": safe_percent}
	):
		return false
	_dirty_directions[
		_direction_dirty_key(current_item_id, direction_index)
	] = true
	_dirty_scales[_scale_dirty_key(current_item_id)] = true
	_refresh_mapping_editor_ui()
	return true


func _draft_path_for_item(item_id: int) -> String:
	if (
		HelmetVisualV2.calibration_override_path().begins_with("res://outputs/")
		or HelmetVisualV2.calibration_override_path().begins_with("user://")
	):
		return "%s/drafts/%s/item_%d.json" % [
			OUTPUT_ROOT,
			_test_draft_session_id if not _test_draft_session_id.is_empty()
				else "default",
			item_id,
		]
	return "%s/item_%d.json" % [DRAFT_ROOT, item_id]


func _load_saved_draft_for_item(item_id: int) -> bool:
	if _loaded_draft_items.has(item_id):
		return true
	_loaded_draft_items[item_id] = true
	var path := _draft_path_for_item(item_id)
	if not FileAccess.file_exists(path):
		return true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if (
		not parsed is Dictionary
		or str(parsed.get("contractId", ""))
			!= "equipment.helmet.calibration_draft.v1"
		or int(parsed.get("itemId", -1)) != item_id
		or str(parsed.get("visualAssetId", ""))
			!= HelmetVisualV2.visual_asset_id_for_item(item_id)
	):
		push_error("invalid helmet calibration draft: %s" % path)
		return false
	var source_sha := str(parsed.get("source", {}).get("sheetSha256", ""))
	if (
		_active_target_applies_to_current_item()
		and not source_sha.is_empty()
		and source_sha != active_target_source_sheet_sha256()
	):
		push_error("helmet calibration draft source hash changed: %s" % path)
		return false
	var direction_records: Variant = parsed.get("directions", {})
	if not direction_records is Dictionary:
		return false
	for direction_index: int in DIRECTIONS.size():
		var direction := str(DIRECTIONS[direction_index])
		var fields: Variant = direction_records.get(direction, {})
		if fields is Dictionary and not fields.is_empty():
			HelmetVisualV2.set_session_calibration_override(
				item_id, direction_index, fields
			)
	var presentation: Variant = parsed.get("presentationCalibration", {})
	if presentation is Dictionary and not presentation.is_empty():
		presentation = _migrate_legacy_paper_doll_defaults(presentation)
		HelmetVisualV2.set_session_presentation_calibration(
			item_id, presentation
		)
	return true


func adjust_direction_scale_percent(
	direction_index: int,
	delta_percent: int
) -> bool:
	if delta_percent % SCALE_STEP_PERCENT != 0:
		return false
	return set_direction_scale_percent(
		direction_index,
		HelmetVisualV2.direction_scale_percent(
			current_item_id, direction_index
		) + delta_percent
	)


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
	var nudge_value := _array_vector2(record.get("nudge", [0, 0]))
	var next_nudge := nudge_value + Vector2(delta) * NUDGE_STEP_PX
	var changed := HelmetVisualV2.set_session_calibration_override(
		current_item_id,
		current_direction,
		{"nudge": _vector2_array(next_nudge)}
	)
	if changed:
		_dirty_directions[
			_direction_dirty_key(current_item_id, current_direction)
		] = true
	return changed


func nudge_paper_doll(delta: Vector2i) -> bool:
	assert(delta in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT])
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	var presentation := _current_presentation_calibration()
	var paper: Dictionary = presentation.get("paperDoll", {})
	var source_row := int(paper.get("source_row", 4))
	var percent := int(paper.get(
		"scale_percent", PAPER_DOLL_INITIAL_SCALE_PERCENT
	))
	var offset: Array = paper.get(
		"offset",
		_paper_doll_default_offset(source_row, percent)
	)
	var current_offset := _array_vector2(offset)
	var next_offset := current_offset + Vector2(delta) * NUDGE_STEP_PX
	paper["offset"] = [
		next_offset.x,
		next_offset.y,
	]
	presentation["paperDoll"] = paper
	if not _apply_presentation_session(presentation):
		return false
	_refresh_presentation_ui()
	return true


func nudge_active_editor(delta: Vector2i) -> bool:
	if _active_editor_scope == "paperDoll":
		return nudge_paper_doll(delta)
	return nudge_current(delta)


func map_source_row_to_current_target(source_row: int) -> bool:
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	if source_row < 0 or source_row >= DIRECTIONS.size():
		return false
	var source_direction := _calibration_source_direction_for_row(source_row)
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
		_dirty_directions[
			_direction_dirty_key(current_item_id, current_direction)
		] = true
		_refresh_mapping_editor_ui()
	return changed


func undo_current_direction() -> void:
	HelmetVisualV2.clear_session_calibration_override(
		current_item_id, current_direction
	)
	_dirty_directions.erase(
		_direction_dirty_key(current_item_id, current_direction)
	)
	_refresh_mapping_editor_ui()


func reload_formal_data() -> void:
	if (
		not _active_target_manifest_path.is_empty()
		and not _load_active_target_manifest(_active_target_manifest_path)
	):
		_show_initialization_error(_active_target_load_error)
		return
	HelmetVisualV2.reload_data()
	_authored_source_cutout_cache.clear()
	_dirty_directions.clear()
	_dirty_scales.clear()
	_presentation_dirty.clear()
	_loaded_draft_items.erase(current_item_id)
	_load_saved_draft_for_item(current_item_id)
	if _visual != null:
		_visual._refresh_equipment_visuals()
	_refresh_mapping_editor_ui()


func save_current_direction() -> bool:
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	if not _save_calibration_draft():
		return false
	if not _legacy_test_finalize([current_direction]):
		return false
	_dirty_directions.erase(
		_direction_dirty_key(current_item_id, current_direction)
	)
	_presentation_dirty.erase(_scale_dirty_key(current_item_id))
	_write_calibration_working_file(output_dir)
	_refresh_mapping_editor_ui()
	return true


func save_all_changes() -> bool:
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	var pending: Array[int] = []
	for direction_index: int in DIRECTIONS.size():
		if _dirty_directions.has(
			_direction_dirty_key(current_item_id, direction_index)
		):
			pending.append(direction_index)
	if not _save_calibration_draft():
		return false
	if not _legacy_test_finalize(pending):
		return false
	for direction_index: int in pending:
		_dirty_directions.erase(
			_direction_dirty_key(current_item_id, direction_index)
		)
	_dirty_scales.erase(_scale_dirty_key(current_item_id))
	_presentation_dirty.erase(_scale_dirty_key(current_item_id))
	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	_write_calibration_working_file(output_dir)
	_refresh_mapping_editor_ui()
	var state := get_node(
		"CalibrationUI/Panel/VBox/MappingStatus/State"
	) as Label
	state.text = (
		"已保存全部无损校准"
		if not pending.is_empty()
		else "没有未保存改动"
	)
	return true


func _legacy_test_finalize(direction_indices: Array[int]) -> bool:
	# Historical regression tests use an isolated outputs override and still
	# exercise the old runtime writer. Interactive/formal saves never enter
	# this branch; their only output is the lossless draft.
	if not (
		HelmetVisualV2.calibration_override_path().begins_with("res://outputs/")
		or HelmetVisualV2.calibration_override_path().begins_with("user://")
	):
		return true
	for direction_index: int in direction_indices:
		if not _persist_direction(direction_index):
			return false
	var asset_override := HelmetVisualV2.visual_asset_override_for_item(
		current_item_id
	)
	if (
		_scale_bake_required(asset_override)
		and not _bake_and_persist_uniform_scale()
	):
		return false
	return _persist_presentation_if_dirty()


func _save_calibration_draft() -> bool:
	var directions: Dictionary = {}
	for direction_index: int in DIRECTIONS.size():
		var record := HelmetVisualV2.direction_record(
			current_item_id, direction_index
		)
		var saved := {
			"source_row": int(record.get("source_row", direction_index)),
			"source_slot_id": HelmetVisualV2.source_slot_id_for_row(
				current_item_id,
				int(record.get("source_row", direction_index))
			),
			"nudge": record.get("nudge", [0, 0]),
			"scale_percent": HelmetVisualV2.direction_scale_percent(
				current_item_id, direction_index
			),
			"status": record.get("status", "valid"),
			"locked": record.get("locked", false),
		}
		var source_direction := str(record.get("source_direction", ""))
		if not source_direction.is_empty():
			saved["source_direction"] = source_direction
		directions[str(DIRECTIONS[direction_index])] = saved
	var source := _calibration_source_contract()
	var payload := {
		"schemaVersion": 1,
		"contractId": "equipment.helmet.calibration_draft.v1",
		"runtimeReadable": false,
		"finalized": false,
		"itemId": current_item_id,
		"visualAssetId": HelmetVisualV2.visual_asset_id_for_item(
			current_item_id
		),
		"source": {
			"sheet": source.get("calibrationSourceSheet", ""),
			"sheetSha256": source.get(
				"calibrationSourceSheetSha256", ""
			),
			"preparedDirectionFiles": source.get(
				"calibrationPreparedDirectionFiles", {}
			),
			"preparedDirectionSha256": source.get(
				"calibrationPreparedDirectionSha256", {}
			),
			"recipeId": _source_recipe_id(),
			"resolutionPolicy": (
				"retain_original_direction_cutouts_until_one_final_runtime_bake"
			),
		},
		"directions": directions,
		"presentationCalibration": _current_presentation_calibration(),
		"finalizePolicy": {
			"world": "single_high_quality_downsample_from_original_per_direction",
			"paperDoll": "single_high_quality_downsample_from_original_selection",
			"inventory": "single_high_quality_downsample_from_original_selection",
			"ground": "single_high_quality_downsample_from_original_selection",
			"runtimeScale": [1, 1],
			"noIntermediateResample": true,
		},
	}
	var path := _draft_path_for_item(current_item_id)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	_write_json(ProjectSettings.globalize_path(path), payload)
	return FileAccess.file_exists(path)


func _persist_presentation_if_dirty() -> bool:
	var key := _scale_dirty_key(current_item_id)
	if not _presentation_dirty.has(key):
		return true
	if not HelmetVisualV2.persist_presentation_calibration(
		current_item_id, _current_presentation_calibration()
	):
		return false
	_presentation_dirty.erase(key)
	return true


func finalize_saved_calibration_for_runtime() -> bool:
	# This method is intentionally not connected to any editor button. Codex
	# invokes it only after the user has finished every calibration choice.
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	var draft_path := _draft_path_for_item(current_item_id)
	if not FileAccess.file_exists(draft_path):
		return false
	for direction_index: int in DIRECTIONS.size():
		if not _persist_direction(direction_index):
			return false
	if not _bake_and_persist_uniform_scale():
		return false
	if not HelmetVisualV2.persist_presentation_calibration(
		current_item_id, _current_presentation_calibration()
	):
		return false
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(draft_path)
	)
	if parsed is Dictionary:
		parsed["finalized"] = true
		parsed["finalizedSourceRecipeId"] = _source_recipe_id()
		var override := HelmetVisualV2.visual_asset_override_for_item(
			current_item_id
		)
		parsed["runtimeAtlases"] = override.get("derivedAtlases", {})
		parsed["runtimeAtlasSha256"] = override.get(
			"derivedAtlasSha256", {}
		)
		_write_json(ProjectSettings.globalize_path(draft_path), parsed)
	return true


func _persist_direction(direction_index: int) -> bool:
	var direction: String = str(DIRECTIONS[direction_index])
	var record := HelmetVisualV2.direction_record(current_item_id, direction_index)
	if not HelmetVisualV2.persist_calibration_override(
		current_item_id,
		direction_index,
		{
			"source_row": int(record.get("source_row", -1)),
			"source_slot_id": HelmetVisualV2.source_slot_id_for_row(
				current_item_id, int(record.get("source_row", -1))
			),
			"nudge": record.get("nudge", [0, 0]),
			"scale_percent": HelmetVisualV2.direction_scale_percent(
				current_item_id, direction_index
			),
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
			direction_index,
			{"source_direction": source_direction}
		)
	HelmetVisualV2.clear_session_calibration_override(
		current_item_id, direction_index
	)
	_dirty_directions.erase(
		_direction_dirty_key(current_item_id, direction_index)
	)
	return true


func _write_calibration_working_file(output_dir: String) -> void:
	var direction: String = str(DIRECTIONS[current_direction])
	var record := HelmetVisualV2.direction_record(current_item_id, current_direction)
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
		"directionScalePercent": HelmetVisualV2.direction_scale_profile(
			current_item_id
		),
		"presentationCalibration": _current_presentation_calibration(),
	}
	_write_json(output_dir.path_join(
		"helmet_%d_calibration_working.json" % current_item_id
	), payload)


func _bake_and_persist_uniform_scale() -> bool:
	if HelmetVisualV2.is_read_only(current_item_id):
		return false
	var scale_profile := HelmetVisualV2.direction_scale_profile(current_item_id)
	var profile_id := JSON.stringify(scale_profile).sha256_text().substr(0, 12)
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
		"%s/derived/%s/profile_%s" % [OUTPUT_ROOT, asset_id, profile_id]
		if test_destination
		else "res://assets/generated/helmet_v2/%s/profile_%s" % [
			asset_id, profile_id,
		]
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
		var source_image := _image_from_path(source_path)
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
				var percent := _scale_percent_for_source_row(source_row)
				var scaled := calibration_source_cell_scaled(
					action, source_row, frame_index, percent
				)
				# The scaled cell is already composited onto a transparent
				# fixed-size cell. Copy it byte-for-byte into the atlas; a
				# second alpha blend would round semi-transparent edge colors.
				derived.blit_rect(
					scaled,
					Rect2i(Vector2i.ZERO, scaled.get_size()),
					source_rect.position
				)
		var derived_path := "%s/%s_%s_profile_%s.png" % [
			bake_root, asset_id, action, profile_id
		]
		if derived.save_png(ProjectSettings.globalize_path(derived_path)) != OK:
			return false
		derived_paths[action] = derived_path
		source_sha[action] = FileAccess.get_sha256(source_path)
		derived_sha[action] = FileAccess.get_sha256(derived_path)
	if not HelmetVisualV2.persist_directional_scale_bake(
		current_item_id,
		scale_profile,
		derived_paths,
		source_sha,
		derived_sha,
		_source_recipe_id()
	):
		return false
	_dirty_scales.erase(_scale_dirty_key(current_item_id))
	if _visual != null:
		_visual._refresh_equipment_visuals()
	return true


func _scale_percent_for_source_row(source_row: int) -> int:
	var matched_percent := -1
	for direction_index: int in DIRECTIONS.size():
		var record := HelmetVisualV2.direction_record(
			current_item_id, direction_index
		)
		if int(record.get("source_row", direction_index)) != source_row:
			continue
		var percent := HelmetVisualV2.direction_scale_percent(
			current_item_id, direction_index
		)
		if matched_percent < 0:
			matched_percent = percent
		elif matched_percent != percent:
			return matched_percent
	return (
		matched_percent
		if matched_percent >= 0
		else HelmetVisualV2.uniform_scale_percent(current_item_id)
	)


func _scale_bake_required(asset_override: Dictionary) -> bool:
	return (
		_dirty_scales.has(_scale_dirty_key(current_item_id))
		or not asset_override.has("directionScalePercent")
		or not asset_override.has("derivedAtlases")
		or str(asset_override.get("bakePolicy", {}).get(
			"sourceRecipeId", ""
		)) != _source_recipe_id()
	)


func _source_recipe_id() -> String:
	var source := _calibration_source_contract()
	var authored_sha := str(source.get("calibrationSourceSheetSha256", ""))
	if not authored_sha.is_empty():
		if _active_target_applies_to_current_item():
			var active_resize_filter := str(
				_active_target.get("sourceResizeFilter", "nearest")
			)
			if active_resize_filter == "nearest":
				return (
					"active_target.%s.%s.direct_png_v1"
					% [
						str(_active_target.get(
							"sourceRevision", "unversioned"
						)),
						authored_sha,
					]
				)
			return (
				"active_target.%s.%s.%s.direct_png_v2"
				% [
					str(_active_target.get("sourceRevision", "unversioned")),
					authored_sha,
					active_resize_filter,
				]
			)
		var idle_layout_sha := str(
			source.get("actions", {}).get("idle", {}).get("sha256", "")
		)
		var matte_policy := str(
			source.get("calibrationSourceMatte", "unspecified_matte")
		)
		var resize_filter := str(
			source.get("calibrationResizeFilter", "nearest")
		)
		return (
			"authored_source_sheet.%s.layout.%s.%s.%s"
			% [
				authored_sha,
				idle_layout_sha,
				matte_policy,
				resize_filter,
			]
		)
	return str(HelmetVisualV2.visual_asset_for_item(
		current_item_id
	).get("bakedSourceOverrides", {}).get(
		"recipeId", "primary_source_rows.v1"
	))


func calibration_source_cell(
	action: String,
	source_row: int,
	frame_index: int
) -> Image:
	assert(source_row >= 0 and source_row < DIRECTIONS.size())
	if _has_authored_source_sheet():
		return _authored_source_runtime_cell(action, source_row, frame_index)
	return _generated_atlas_source_cell(action, source_row, frame_index)


func calibration_source_cell_scaled(
	action: String,
	source_row: int,
	frame_index: int,
	percent: int
) -> Image:
	if _has_authored_source_sheet():
		return _authored_source_runtime_cell_scaled(
			action, source_row, frame_index, percent
		)
	var cell := _generated_atlas_source_cell(action, source_row, frame_index)
	var pivot := _calibration_pivot_for_source_row(
		action, source_row, frame_index
	)
	return scale_cell_around_pivot(cell, pivot, percent)


func _generated_atlas_source_cell(
	action: String,
	source_row: int,
	frame_index: int
) -> Image:
	var path := HelmetVisualV2.base_action_texture_path(
		current_item_id, action, 0, "helmet_front"
	)
	if (
		path.is_empty()
		or (
			not ResourceLoader.exists(path)
			and not FileAccess.file_exists(path)
		)
	):
		var empty := Image.create(
			ArtSpec.WARRIOR_FRAME.x,
			ArtSpec.WARRIOR_FRAME.y,
			false,
			Image.FORMAT_RGBA8
		)
		empty.fill(Color(0, 0, 0, 0))
		return empty
	var source_image := _image_from_path(path)
	var recipe: Dictionary = HelmetVisualV2.visual_asset_for_item(
		current_item_id
	).get("bakedSourceOverrides", {})
	var target_recipe: Variant = recipe.get(
		"rows", {}
	).get(str(source_row), {})
	var actual_row := source_row
	if target_recipe is Dictionary:
		actual_row = int(target_recipe.get("sourceRow", source_row))
	var cell := source_image.get_region(Rect2i(
		frame_index * ArtSpec.WARRIOR_FRAME.x,
		actual_row * ArtSpec.WARRIOR_FRAME.y,
		ArtSpec.WARRIOR_FRAME.x,
		ArtSpec.WARRIOR_FRAME.y
	))
	if (
		target_recipe is Dictionary
		and str(target_recipe.get("operation", "")) == "horizontal_mirror"
	):
		return mirror_cell_between_pivots(
			cell,
			_calibration_pivot_for_source_row(
				action, actual_row, frame_index
			),
			_calibration_pivot_for_source_row(
				action, source_row, frame_index
			)
		)
	return cell


func _authored_source_runtime_cell(
	action: String,
	source_row: int,
	frame_index: int
) -> Image:
	if _is_prepared_source_row(source_row):
		return _generated_atlas_source_cell(action, source_row, frame_index)
	var authored_cutout := _authored_source_cutout(source_row)
	if authored_cutout.is_empty():
		assert(
			not _active_target_applies_to_current_item(),
			"active target source row %d failed to load" % source_row
		)
		return _generated_atlas_source_cell(action, source_row, frame_index)
	# The generated atlas remains the placement envelope. Only its pixels are
	# replaced. This preserves every action/frame pivot while guaranteeing the
	# editor previews and later scale bake use the selected authored material.
	var placement_cell := _generated_atlas_source_cell(
		action, _placement_source_row(source_row), frame_index
	)
	var placement_rect := placement_cell.get_used_rect()
	if not placement_rect.has_area():
		return placement_cell
	var fitted := authored_cutout.duplicate()
	var resize_filter := Image.INTERPOLATE_NEAREST
	if "lanczos_downsample" in str(
		_calibration_source_contract().get(
			"calibrationResizeFilter", ""
		)
	):
		resize_filter = Image.INTERPOLATE_LANCZOS
	if resize_filter == Image.INTERPOLATE_LANCZOS:
		fitted = _resize_premultiplied_alpha_lanczos(
			authored_cutout, placement_rect.size
		)
	else:
		fitted.resize(
			placement_rect.size.x,
			placement_rect.size.y,
			resize_filter
		)
	var result := Image.create(
		ArtSpec.WARRIOR_FRAME.x,
		ArtSpec.WARRIOR_FRAME.y,
		false,
		Image.FORMAT_RGBA8
	)
	result.fill(Color(0, 0, 0, 0))
	result.blit_rect(
		fitted,
		Rect2i(Vector2i.ZERO, fitted.get_size()),
		placement_rect.position
	)
	return result


func _authored_source_runtime_cell_scaled(
	action: String,
	source_row: int,
	frame_index: int,
	percent: int
) -> Image:
	if percent == 100:
		return _authored_source_runtime_cell(
			action, source_row, frame_index
		)
	var authored_cutout := _authored_source_cutout(source_row)
	if authored_cutout.is_empty():
		var fallback := _generated_atlas_source_cell(
			action, source_row, frame_index
		)
		return scale_cell_around_pivot(
			fallback,
			_calibration_pivot_for_source_row(
				action, source_row, frame_index
			),
			percent
		)
	var placement_cell := _generated_atlas_source_cell(
		action, _placement_source_row(source_row), frame_index
	)
	var placement_rect := placement_cell.get_used_rect()
	if not placement_rect.has_area():
		return placement_cell
	var pivot := _calibration_pivot_for_source_row(
		action, source_row, frame_index
	)
	var factor := float(percent) / 100.0
	var target_size := Vector2i(
		maxi(1, roundi(float(placement_rect.size.x) * factor)),
		maxi(1, roundi(float(placement_rect.size.y) * factor))
	)
	# Resize exactly once from the original transparent cutout. The interactive
	# preview never becomes the source for a later save/finalize operation.
	var fitted := _resize_premultiplied_alpha_lanczos(
		authored_cutout, target_size
	)
	var scaled_top_left := pivot + Vector2i(
		roundi(float(placement_rect.position.x - pivot.x) * factor),
		roundi(float(placement_rect.position.y - pivot.y) * factor)
	)
	var result := Image.create(
		ArtSpec.WARRIOR_FRAME.x,
		ArtSpec.WARRIOR_FRAME.y,
		false,
		Image.FORMAT_RGBA8
	)
	result.fill(Color(0, 0, 0, 0))
	result.blend_rect(
		fitted,
		Rect2i(Vector2i.ZERO, fitted.get_size()),
		scaled_top_left
	)
	return result


func _resize_premultiplied_alpha_lanczos(
	source: Image,
	target_size: Vector2i
) -> Image:
	var premultiplied := source.duplicate()
	premultiplied.convert(Image.FORMAT_RGBA8)
	for y: int in premultiplied.get_height():
		for x: int in premultiplied.get_width():
			var color: Color = premultiplied.get_pixel(x, y)
			premultiplied.set_pixel(
				x, y, Color(color.r * color.a, color.g * color.a, color.b * color.a, color.a)
			)
	premultiplied.resize(
		target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS
	)
	for y: int in premultiplied.get_height():
		for x: int in premultiplied.get_width():
			var color: Color = premultiplied.get_pixel(x, y)
			if color.a <= 0.004:
				premultiplied.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			premultiplied.set_pixel(
				x,
				y,
				Color(
					clampf(color.r / color.a, 0.0, 1.0),
					clampf(color.g / color.a, 0.0, 1.0),
					clampf(color.b / color.a, 0.0, 1.0),
					color.a
				)
			)
	_sanitize_transparent_downsample(premultiplied)
	return premultiplied


func _sanitize_transparent_downsample(image: Image) -> void:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a <= 0.02:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var non_green := maxf(color.r, color.b)
			color.g = minf(color.g, non_green + 0.025)
			image.set_pixel(x, y, color)


func mirror_cell_between_pivots(
	cell: Image,
	source_pivot: Vector2i,
	target_pivot: Vector2i
) -> Image:
	var mirrored := Image.create(
		cell.get_width(), cell.get_height(), false, Image.FORMAT_RGBA8
	)
	mirrored.fill(Color(0, 0, 0, 0))
	for y: int in cell.get_height():
		for x: int in cell.get_width():
			var destination := Vector2i(
				target_pivot.x + source_pivot.x - x,
				target_pivot.y + y - source_pivot.y
			)
			if (
				destination.x >= 0
				and destination.x < mirrored.get_width()
				and destination.y >= 0
				and destination.y < mirrored.get_height()
			):
				mirrored.set_pixelv(destination, cell.get_pixel(x, y))
	return mirrored


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
	_dirty_scales[_scale_dirty_key(current_item_id)] = true
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
		var source_image := _image_from_path(source_path)
		var derived_image := Image.load_from_file(derived_path)
		for direction_index: int in 8:
			var record := HelmetVisualV2.direction_record(
				current_item_id, direction_index
			)
			var source_row := int(record.get("source_row", -1))
			var nudge := _array_vector2(record.get("nudge", []))
			for frame_index: int in int(ACTIONS[action]):
				var cell_rect := Rect2i(
					frame_index * ArtSpec.WARRIOR_FRAME.x,
					source_row * ArtSpec.WARRIOR_FRAME.y,
					ArtSpec.WARRIOR_FRAME.x,
					ArtSpec.WARRIOR_FRAME.y
				)
				var source_nonempty := _image_has_opaque_pixel(
					calibration_source_cell(
						action, source_row, frame_index
					)
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
				var final_position := Vector2(socket - pivot) + nudge
				var frame_ok: bool = (
					source_nonempty == derived_nonempty
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
					"savedNudge": _vector2_array(nudge),
					"uniformScalePercent": percent,
					"finalPosition": _vector2_array(final_position),
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


func _image_from_path(path: String) -> Image:
	if FileAccess.file_exists(path) and path.get_extension().to_lower() == "png":
		var raw_image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if not raw_image.is_empty():
			return raw_image
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null:
			return texture.get_image()
	var empty := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	empty.fill(Color(0, 0, 0, 0))
	return empty


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
	_dirty_directions[
		_direction_dirty_key(current_item_id, current_direction)
	] = true
	return save_current_direction()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if key_event.pressed and not key_event.echo:
			_request_exit(0)
		return
	var nudge_delta := Vector2i.ZERO
	match key_event.keycode:
		KEY_UP: nudge_delta = Vector2i.UP
		KEY_DOWN: nudge_delta = Vector2i.DOWN
		KEY_LEFT: nudge_delta = Vector2i.LEFT
		KEY_RIGHT: nudge_delta = Vector2i.RIGHT
	if nudge_delta != Vector2i.ZERO:
		# Handle both press (including echo for held-key repetition) and release
		# before Control/PopupMenu keyboard navigation can see the arrows.
		get_viewport().set_input_as_handled()
		if key_event.pressed:
			nudge_active_editor(nudge_delta)
			_refresh_mapping_editor_ui()
		return
	if key_event.keycode not in [
		KEY_1, KEY_8, KEY_0,
		KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT,
		KEY_S, KEY_L,
	]:
		return
	# These editor shortcuts also bypass focused menu type-ahead/navigation.
	get_viewport().set_input_as_handled()
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_1: set_head_zoom(1)
		KEY_8: set_head_zoom(8)
		KEY_0: set_head_zoom(10)
		KEY_EQUAL, KEY_KP_ADD:
			adjust_direction_scale_percent(
				current_direction, SCALE_STEP_PERCENT
			)
		KEY_MINUS, KEY_KP_SUBTRACT:
			adjust_direction_scale_percent(
				current_direction, -SCALE_STEP_PERCENT
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
		var cell := _runtime_layer_cell(
			layer_name, action, direction_index, frame_index
		)
		if cell.is_empty():
			continue
		var destination := FOOT_POINT + Vector2i(_visual.position.round()) + Vector2i(layer.position.round())
		frame.blend_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), destination)
	if include_calibration_overlays:
		_draw_calibration_overlays(frame, action, direction_index, frame_index)
	return frame


func _runtime_layer_cell(
	layer_name: String,
	action: String = "",
	direction_index: int = -1,
	frame_index: int = -1
) -> Image:
	var layer := _visual.get_node(layer_name) as Sprite2D
	if layer == null or not layer.visible or layer.texture == null:
		return Image.new()
	if (
		layer_name == "ClientHelmetLayer"
		and not action.is_empty()
		and direction_index >= 0
		and frame_index >= 0
	):
		var record := HelmetVisualV2.direction_record(
			current_item_id, direction_index
		)
		var source_row := int(record.get("source_row", direction_index))
		return calibration_source_cell_scaled(
			action,
			source_row,
			frame_index,
			HelmetVisualV2.direction_scale_percent(
				current_item_id, direction_index
			)
		)
	if (
		layer_name == "ClientHelmetLayer"
		and not layer.texture.resource_path.is_empty()
	):
		var direct_runtime_atlas := _image_from_path(
			layer.texture.resource_path
		)
		return direct_runtime_atlas.get_region(Rect2i(layer.region_rect))
	# Body and non-helmet layers still come from PlayerVisual. The helmet layer
	# deliberately uses the same direct PNG path as the source buttons so a
	# stale Godot .ctex import can never make the worn preview show old pixels.
	return layer.texture.get_image().get_region(Rect2i(layer.region_rect))


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
	get_node("CalibrationUI/Panel/VBox/Title").text = (
		"PlayerVisual Helmet V2 — Item %d %s"
		% [current_item_id, _calibration_item_display_name(current_item_id)]
	)
	var read_only := HelmetVisualV2.is_read_only(current_item_id)
	var direction := str(DIRECTIONS[current_direction])
	var record := HelmetVisualV2.direction_record(
		current_item_id, current_direction
	)
	var source_row := int(record.get("source_row", -1))
	var source_direction := str(record.get(
		"source_direction",
		_calibration_source_direction_for_row(source_row)
	))
	var nudge := _array_vector2(record.get("nudge", []))
	if current_item_id == 151 and not _active_target_applies_to_current_item():
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
		"nudge x=%.1f y=%.1f | action=%s frame=%d | direction scale=%d%%"
		% [
			nudge.x,
			nudge.y,
			current_action,
			current_frame,
			HelmetVisualV2.direction_scale_percent(
				current_item_id, current_direction
			),
		]
	)
	var direction_dirty := _dirty_directions.has(
		_direction_dirty_key(current_item_id, current_direction)
	)
	var scale_dirty := _dirty_scales.has(_scale_dirty_key(current_item_id))
	var presentation_dirty := _presentation_dirty.has(
		_scale_dirty_key(current_item_id)
	)
	var state_text := ""
	if read_only:
		state_text = "READ ONLY"
	else:
		state_text = "%s / %s" % [
			"LOCKED" if bool(record.get("locked", false)) else "UNLOCKED",
			"DIRTY" if direction_dirty or scale_dirty or presentation_dirty else "CLEAN",
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
	for item_index: int in item_control.item_count:
		if int(item_control.get_item_id(item_index)) == current_item_id:
			item_control.select(item_index)
			break
	_updating_ui = false
	for direction_index: int in _target_buttons.size():
		var target_button := _target_buttons[direction_index]
		var target_frame := _runtime_frame(
			current_action, direction_index, current_frame, false
		)
		target_button.texture_normal = ImageTexture.create_from_image(target_frame)
		target_button.button_pressed = direction_index == current_direction
		(target_button.get_node("Label") as Label).text = "%s  %d%%" % [
			DIRECTIONS[direction_index],
			HelmetVisualV2.direction_scale_percent(
				current_item_id, direction_index
			),
		]
		target_button.modulate = (
			Color(1.0, 0.82, 0.25)
			if direction_index == current_direction
			else Color.WHITE
		)
	for row: int in _source_buttons.size():
		var source_button := _source_buttons[row]
		var source_image := source_row_thumbnail(row)
		source_button.texture_normal = ImageTexture.create_from_image(source_image)
		var real_direction := _calibration_source_direction_for_row(row)
		var authored_source := not str(
			_calibration_source_contract().get(
				"calibrationSourceSheet", ""
			)
		).is_empty()
		if (
			current_item_id == 151
			and not _active_target_applies_to_current_item()
		):
			(source_button.get_node("Label") as Label).text = "源槽 %d" % row
		elif authored_source:
			(source_button.get_node("Label") as Label).text = (
				"原图 %s (%d)" % [real_direction, row]
			)
		else:
			(source_button.get_node("Label") as Label).text = (
				"%s (row %d)" % [real_direction, row]
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
		"CalibrationUI/Panel/VBox/Inputs/SaveAll"
	).disabled = read_only
	get_node(
		"CalibrationUI/Panel/VBox/Commands/GenerateAllActions"
	).disabled = not HelmetVisualV2.idle_baseline_complete(current_item_id)
	_render_current_previews()
	_refresh_presentation_ui()


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
	var authored_thumbnail := _authored_source_sheet_thumbnail(source_row)
	if not authored_thumbnail.is_empty():
		return authored_thumbnail
	var cell := calibration_source_cell(
		current_action, source_row, current_frame
	)
	var pivot := _calibration_pivot_for_source_row(
		current_action, source_row, current_frame
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


func _authored_source_sheet_thumbnail(source_row: int) -> Image:
	var cell := _authored_source_cutout(source_row)
	if cell.is_empty():
		return Image.new()
	var available := HEAD_ZOOM_SOURCE_SIZE - Vector2i(4, 4)
	var fit_scale := minf(
		float(available.x) / float(cell.get_width()),
		float(available.y) / float(cell.get_height())
	)
	var fitted_size := Vector2i(
		maxi(1, roundi(float(cell.get_width()) * fit_scale)),
		maxi(1, roundi(float(cell.get_height()) * fit_scale))
	)
	cell.resize(fitted_size.x, fitted_size.y, Image.INTERPOLATE_NEAREST)
	var thumbnail := Image.create(
		HEAD_ZOOM_SOURCE_SIZE.x,
		HEAD_ZOOM_SOURCE_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	thumbnail.fill(Color(0, 0, 0, 0))
	thumbnail.blit_rect(
		cell,
		Rect2i(Vector2i.ZERO, fitted_size),
		(HEAD_ZOOM_SOURCE_SIZE - fitted_size) / 2
	)
	return thumbnail


func _has_authored_source_sheet() -> bool:
	return not str(_calibration_source_contract().get(
		"calibrationSourceSheet", ""
	)).is_empty()


func _is_prepared_source_row(source_row: int) -> bool:
	var prepared_rows: Array = _calibration_source_contract().get(
		"calibrationPreparedSourceRows", []
	)
	for prepared_row: Variant in prepared_rows:
		if int(prepared_row) == source_row:
			return true
	return false


func _authored_source_cutout(source_row: int) -> Image:
	var source := _calibration_source_contract()
	var prepared_files: Variant = source.get(
		"calibrationPreparedDirectionFiles", {}
	)
	if prepared_files is Dictionary and not prepared_files.is_empty():
		var direction := _calibration_source_direction_for_row(source_row)
		var prepared_path := str(prepared_files.get(direction, ""))
		var prepared_sha: Variant = source.get(
			"calibrationPreparedDirectionSha256", {}
		)
		var expected_prepared_sha := (
			str(prepared_sha.get(direction, "")).to_lower()
			if prepared_sha is Dictionary
			else ""
		)
		if (
			not prepared_path.is_empty()
			and FileAccess.file_exists(prepared_path)
			and (
				expected_prepared_sha.is_empty()
				or FileAccess.get_sha256(prepared_path).to_lower()
					== expected_prepared_sha
			)
		):
			var prepared := Image.load_from_file(
				ProjectSettings.globalize_path(prepared_path)
			)
			if not prepared.is_empty():
				prepared.convert(Image.FORMAT_RGBA8)
				return prepared
	if _is_prepared_source_row(source_row):
		var prepared_cell := _generated_atlas_source_cell(
			"idle", source_row, 0
		)
		var prepared_rect := prepared_cell.get_used_rect()
		if prepared_rect.has_area():
			return prepared_cell.get_region(prepared_rect)
	var path := str(source.get("calibrationSourceSheet", ""))
	var grid: Array = source.get("calibrationSourceGrid", [])
	if path.is_empty() or grid.size() != 2:
		return Image.new()
	var expected_sha := str(
		source.get("calibrationSourceSheetSha256", "")
	).to_lower()
	var matte_policy := str(source.get("calibrationSourceMatte", ""))
	var cache_key := "%d:%s:%s:%s:%d" % [
		current_item_id,
		path,
		expected_sha,
		matte_policy,
		source_row,
	]
	if _authored_source_cutout_cache.has(cache_key):
		return (
			_authored_source_cutout_cache[cache_key] as Image
		).duplicate()
	var absolute_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		return Image.new()
	if not expected_sha.is_empty():
		assert(
			FileAccess.get_sha256(absolute_path).to_lower() == expected_sha,
			"calibration source sheet changed: %s" % path
		)
	var sheet := Image.load_from_file(absolute_path)
	if sheet.is_empty():
		return Image.new()
	sheet.convert(Image.FORMAT_RGBA8)
	var columns := int(grid[0])
	var rows := int(grid[1])
	assert(columns > 0 and rows > 0)
	assert(source_row < columns * rows)
	var column := source_row % columns
	var row := source_row / columns
	var x0 := roundi(float(column * sheet.get_width()) / float(columns))
	var x1 := roundi(float((column + 1) * sheet.get_width()) / float(columns))
	var y0 := roundi(float(row * sheet.get_height()) / float(rows))
	var y1 := roundi(float((row + 1) * sheet.get_height()) / float(rows))
	var cell := sheet.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
	if not matte_policy.begins_with("transparent_"):
		for y: int in cell.get_height():
			for x: int in cell.get_width():
				var color := cell.get_pixel(x, y)
				var non_green := maxf(color.r, color.b)
				var green_spill := maxf(0.0, color.g - non_green)
				if green_spill > 0.0:
					# Legacy green concepts still require chroma-key removal.
					# Approved transparent sheets skip this destructive pass.
					color.a *= clampf(
						1.0 - green_spill / 0.45, 0.0, 1.0
					)
					color.g = minf(color.g, non_green + 0.025)
				if color.a <= 0.02:
					color = Color(0, 0, 0, 0)
				cell.set_pixel(x, y, color)
	var used_rect := cell.get_used_rect()
	if not used_rect.has_area():
		return Image.new()
	cell = cell.get_region(used_rect)
	_authored_source_cutout_cache[cache_key] = cell
	return cell.duplicate()


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
	var pivot_point := Vector2i(
		((Vector2(body_top_left + pivot - crop_origin) + delta) * zoom).round()
	)
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
	# Mouse nudge controls. Direction scale is shown on the eight world cards;
	# the removed global scale strip must not imply a second resample stage.
	for button_index: int in 4:
		_cpu_panel(
			canvas,
			Rect2i(42 + button_index * 62, 402, 48, 48),
			Color(0.14, 0.2, 0.28),
			Color(0.55, 0.65, 0.76)
		)
	# The lower area now contains only the three requested presentation
	# selectors. There is deliberately no enlarged world mannequin/head.
	var presentation := _current_presentation_calibration()
	var paper_row := int(
		presentation.get("paperDoll", {}).get("source_row", 4)
	)
	var inventory_row := int(
		presentation.get("inventory", {}).get("source_row", 4)
	)
	var ground_row := int(
		presentation.get("ground", {}).get("source_row", 4)
	)
	var card_rects := [
		Rect2i(42, 510, 360, 344),
		Rect2i(430, 510, 360, 344),
		Rect2i(818, 510, 360, 344),
	]
	var card_colors := [
		Color(0.7, 0.45, 0.9),
		Color(0.35, 0.72, 0.95),
		Color(0.9, 0.58, 0.24),
	]
	var selected_rows := [paper_row, inventory_row, ground_row]
	for card_index: int in card_rects.size():
		var card: Rect2i = card_rects[card_index]
		_cpu_border(canvas, card, card_colors[card_index], 3)
		var cutout := _authored_source_cutout(
			int(selected_rows[card_index])
		)
		if cutout.is_empty():
			cutout = source_row_thumbnail(
				int(selected_rows[card_index])
			)
		var available := card.size - Vector2i(80, 100)
		var factor := minf(
			float(available.x) / float(cutout.get_width()),
			float(available.y) / float(cutout.get_height())
		)
		var fitted_size := Vector2i(
			maxi(1, roundi(float(cutout.get_width()) * factor)),
			maxi(1, roundi(float(cutout.get_height()) * factor))
		)
		cutout.resize(
			fitted_size.x, fitted_size.y, Image.INTERPOLATE_LANCZOS
		)
		canvas.blend_rect(
			cutout,
			Rect2i(Vector2i.ZERO, cutout.get_size()),
			card.position + (card.size - fitted_size) / 2
		)
		_cpu_draw_number(
			canvas,
			int(selected_rows[card_index]),
			card.position + Vector2i(24, 20),
			5,
			card_colors[card_index]
		)
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
		_add_check(
			checks,
			"calibration_coordinate_step_%s" % record.direction,
			_record_uses_calibration_coordinates(record)
		)
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
	_add_check(checks, "two_world_rows_and_presentation_controls_live", _calibration_ui_safe())
	_add_check(checks, "face_hair_overlay_toggles_change_preview", _overlay_toggle_safe())
	_add_check(checks, "arrow_nudge_exactly_one_pixel", _nudge_roundtrip_safe())
	_add_check(checks, "lossless_draft_save", _calibration_draft_save_safe())
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
				var mask := _image_from_path(path)
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
		var image := _image_from_path(texture_path)
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
	var action_control := get_node(
		"CalibrationUI/Panel/VBox/Inputs/Action"
	) as OptionButton
	var direction_control := get_node(
		"CalibrationUI/Panel/VBox/Inputs/Direction"
	) as OptionButton
	return (
		_target_buttons.size() == 8
		and _source_buttons.size() == 8
		and _target_buttons[0].texture_normal != null
		and _source_buttons[0].texture_normal != null
		and not get_node("CalibrationUI/Panel/VBox/Previews").visible
		and _paper_doll_overlay != null
		and _paper_doll_direction.item_count == 8
		and _inventory_direction.item_count == 8
		and _ground_direction.item_count == 8
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


func _calibration_draft_save_safe() -> bool:
	var expected_nudge: Array = HelmetVisualV2.direction_record(
		ITEM_ID, current_direction
	).get("nudge", []).duplicate()
	if not save_current_direction():
		return false
	var draft_path := _draft_path_for_item(ITEM_ID)
	var draft: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(draft_path)
	)
	if not draft is Dictionary:
		return false
	var saved: Variant = draft.get("directions", {}).get(
		DIRECTIONS[current_direction], {}
	)
	return (
		saved is Dictionary
		and _array_vector2(saved.get("nudge", []))
		== _array_vector2(expected_nudge)
		and not bool(draft.get("runtimeReadable", true))
		and not bool(draft.get("finalized", true))
		and bool(draft.get("finalizePolicy", {}).get(
			"noIntermediateResample", false
		))
	)


func _nudge_roundtrip_safe() -> bool:
	unlock_current_direction_for_session()
	var before := _array_vector2(
		HelmetVisualV2.direction_record(ITEM_ID, current_direction).get("nudge", [])
	)
	if not nudge_current(Vector2i.RIGHT):
		return false
	var after_right := _array_vector2(
		HelmetVisualV2.direction_record(ITEM_ID, current_direction).get("nudge", [])
	)
	if not nudge_current(Vector2i.LEFT):
		return false
	var after_left := _array_vector2(
		HelmetVisualV2.direction_record(ITEM_ID, current_direction).get("nudge", [])
	)
	return (
		after_right == before + Vector2.RIGHT * NUDGE_STEP_PX
		and after_left == before
	)


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
		var image := _image_from_path(path)
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


func _record_uses_calibration_coordinates(record: Dictionary) -> bool:
	var pivot: Variant = record.get("pivot", [])
	if not pivot is Array or pivot.size() != 2:
		return false
	for value: Variant in pivot:
		if not (value is int or value is float) or float(value) != floorf(float(value)):
			return false
	var nudge: Variant = record.get("nudge", [])
	if not nudge is Array or nudge.size() != 2:
		return false
	for value: Variant in nudge:
		if not (value is int or value is float):
			return false
		var doubled := float(value) * 2.0
		if not is_finite(float(value)) or not is_equal_approx(
			doubled, roundf(doubled)
		):
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


func _vector2_array(value: Vector2) -> Array[float]:
	return [snappedf(value.x, NUDGE_STEP_PX), snappedf(value.y, NUDGE_STEP_PX)]


func _array_vector(value: Variant) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


func _array_vector2(value: Variant) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
