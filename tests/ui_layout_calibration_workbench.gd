extends Control

const CalibrationOverlayScript := preload("res://scripts/ui_layout_calibration_overlay.gd")
const GothicConfirmationPanelScript := preload("res://scripts/gothic_confirmation_panel.gd")
const LevelUpPreviewScript := preload("res://scripts/ui_level_up_preview.gd")

const DEVICE_PHYSICAL_SIZE := Vector2i(2664, 1200)
const EXPECTED_DEVICE_LOGICAL_SIZE := Vector2(1598, 720)
const DEVICE_SAFE_LEFT_PX := 121.0
const DEVICE_SAFE_RIGHT_PX := 129.0
const INSPECTOR_WINDOW_SIZE := Vector2i(412, 1040)
const INSPECTOR_GAP := 16
const WORLD_BOOTSTRAP_TIMEOUT_MSEC := 30000
const LEVEL_UP_PREVIEW_ARG := "--level-up-preview"
const LEVEL_UP_PREVIEW_CAPTURE_ARG_PREFIX := "--capture-level-up-preview="
const LEVEL_UP_PREVIEW_PEAK_PROGRESS := 0.48
const LEVEL_UP_PREVIEW_RESTART_GAP_SECONDS := 0.65

const PANEL_SPECS := [
	{"id": "skill", "label": "技能", "panel_property": "skill_panel", "open_method": "_toggle_skill_book"},
	{"id": "inventory", "label": "背包与装备", "panel_property": "inventory_panel", "open_method": "_toggle_inventory"},
	{"id": "map", "label": "地图", "panel_property": "map_panel", "open_method": "_toggle_map_panel"},
	{"id": "warehouse", "label": "仓库", "panel_property": "warehouse_panel", "open_method": "open_warehouse"},
	{"id": "shop_sell", "label": "商店出售", "panel_property": "shop_panel", "open_method": "open_shop"},
	{"id": "shop_buy", "label": "商店购买", "panel_property": "shop_panel", "open_method": "open_shop"},
	{"id": "quest", "label": "任务日志", "panel_property": "quest_panel", "open_method": "open_quest"},
	{"id": "system_menu", "label": "系统菜单", "panel_property": "_system_menu_panel", "open_method": "_show_system_menu"},
	{"id": "system_settings", "label": "游戏设置", "panel_property": "_system_menu_panel", "open_method": "_show_system_menu"},
	{"id": "character_hall", "label": "人物殿堂", "panel_property": "_character_hall_instance", "open_method": "_open_character_hall"},
	{"id": "death_revival", "label": "死亡与复活", "panel_property": "death_revival_panel", "open_method": "show_death_screen"},
	{"id": "confirmation_dialog", "label": "稀有物品确认弹窗", "panel_property": "_confirmation_instance", "open_method": "_open_confirmation_dialog"},
]

var inspector_window: Window
var inspector_host: Control
var calibration_canvas: CanvasLayer
var panel_picker: OptionButton
var overlay: Control
var active_panel: Control
var _character_hall_instance: Control
var _confirmation_instance: Control
var game: Node
var hud: Node
# Keep the preview reference dynamic so this workbench remains parse-safe even
# before Godot has imported the new class_name resource in a fresh worktree.
var level_up_preview
var level_up_preview_status: Label
var level_up_preview_toggle_button: Button
var _level_up_preview_requested := false
var _level_up_preview_capture_path := ""
var _level_up_preview_capture_scheduled := false
var _level_up_preview_capture_done := false
var _level_up_preview_auto_active := false
var _level_up_preview_peak_reached := false
var _level_up_preview_restart_remaining := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_level_up_preview_args(OS.get_cmdline_user_args())
	_build_native_inspector_window()
	_build_panel_picker()
	await _build_production_game()
	_freeze_calibration_world()
	_build_calibration_overlay()
	_build_level_up_preview_controls()
	assert(process_mode == Node.PROCESS_MODE_ALWAYS, "calibration workbench must process while the game is paused")
	active_panel = null
	_print_geometry()
	if _level_up_preview_requested:
		_start_requested_level_up_preview.call_deferred()


func _process(delta: float) -> void:
	if not _level_up_preview_auto_active or level_up_preview == null:
		return
	var delta_seconds := maxf(delta, 0.0)
	if _level_up_preview_restart_remaining >= 0.0:
		_level_up_preview_restart_remaining = maxf(
			0.0,
			_level_up_preview_restart_remaining - delta_seconds,
		)
		if _level_up_preview_restart_remaining <= 0.0:
			_start_level_up_preview_auto_cycle()
		return
	if level_up_preview.is_playing():
		if (
			not _level_up_preview_peak_reached
			and level_up_preview.progress() >= LEVEL_UP_PREVIEW_PEAK_PROGRESS
		):
			_level_up_preview_peak_reached = true
			_schedule_level_up_preview_capture()
		return
	if level_up_preview.progress() >= 1.0:
		_level_up_preview_restart_remaining = LEVEL_UP_PREVIEW_RESTART_GAP_SECONDS


func _parse_level_up_preview_args(user_args: PackedStringArray) -> void:
	for argument: String in user_args:
		if argument == LEVEL_UP_PREVIEW_ARG:
			_level_up_preview_requested = true
		elif argument.begins_with(LEVEL_UP_PREVIEW_CAPTURE_ARG_PREFIX):
			var raw_path := argument.trim_prefix(LEVEL_UP_PREVIEW_CAPTURE_ARG_PREFIX).strip_edges()
			var capture_path := _resolve_project_local_capture_path(raw_path)
			if capture_path.is_empty():
				push_error("level-up preview capture path must be a project-local PNG: %s" % raw_path)
				continue
			_level_up_preview_capture_path = capture_path
			_level_up_preview_requested = true


func _resolve_project_local_capture_path(raw_path: String) -> String:
	if raw_path.is_empty():
		return ""
	var project_root := ProjectSettings.globalize_path("res://").simplify_path()
	var project_path := raw_path.replace("\\", "/")
	if not project_path.begins_with("res://"):
		project_path = "res://" + project_path.trim_prefix("/")
	var absolute_path := ProjectSettings.globalize_path(project_path).simplify_path()
	var normalized_root := project_root.replace("\\", "/").trim_suffix("/")
	var normalized_path := absolute_path.replace("\\", "/")
	var project_prefix := normalized_root + "/"
	if (
		not normalized_path.to_lower().begins_with(project_prefix.to_lower())
		or normalized_path.get_extension().to_lower() != "png"
	):
		return ""
	return absolute_path


func _start_requested_level_up_preview() -> void:
	if level_up_preview == null:
		return
	# This is a frozen, non-saving calibration fixture. Move only its actor to
	# open foreground ground: the service-home well otherwise hides the body
	# and makes a correct foot effect impossible to judge.
	var preview_player := game.get("player") as Node2D
	if preview_player != null:
		var preview_offset := Vector2(-150.0, 110.0)
		preview_player.position += preview_offset
		var preview_anchor: Variant = (
			preview_player.call("approved_ground_footpoint_local_px")
			if preview_player.has_method("approved_ground_footpoint_local_px")
			else Vector2.ZERO
		)
		level_up_preview.set_anchor(preview_anchor if preview_anchor is Vector2 else Vector2.ZERO)
	_level_up_preview_auto_active = true
	_start_level_up_preview_auto_cycle()


func _start_level_up_preview_auto_cycle() -> void:
	if level_up_preview == null or not _level_up_preview_auto_active:
		return
	_level_up_preview_peak_reached = false
	_level_up_preview_restart_remaining = -1.0
	level_up_preview.replay()


func _schedule_level_up_preview_capture() -> void:
	if (
		_level_up_preview_capture_path.is_empty()
		or _level_up_preview_capture_scheduled
		or _level_up_preview_capture_done
	):
		return
	_level_up_preview_capture_scheduled = true
	_capture_level_up_preview_peak.call_deferred()


func _capture_level_up_preview_peak() -> void:
	await RenderingServer.frame_post_draw
	if level_up_preview == null or _level_up_preview_capture_path.is_empty():
		return
	var capture_directory := _level_up_preview_capture_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(capture_directory)
	var image := get_viewport().get_texture().get_image()
	var save_error := image.save_png(_level_up_preview_capture_path) if image != null else ERR_UNCONFIGURED
	if save_error != OK:
		push_error("level-up preview capture failed: %s (%s)" % [_level_up_preview_capture_path, save_error])
		return
	_level_up_preview_capture_done = true
	print(
		"UI_LEVEL_UP_PREVIEW_CAPTURE_PASS path=%s progress=%.3f anchor=%s" % [
			_level_up_preview_capture_path,
			level_up_preview.progress(),
			level_up_preview.global_position,
		]
	)


func _shortcut_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var requested_index := -1
	match key.keycode:
		KEY_F1: requested_index = 0
		KEY_F2: requested_index = 1
		KEY_F3: requested_index = 2
		KEY_F4: requested_index = 3
		KEY_F5: requested_index = 4
		KEY_F6: requested_index = 5
		KEY_F7: requested_index = 6
		KEY_F8: requested_index = 7
		KEY_F9: requested_index = 8
		KEY_F10: requested_index = 9
		KEY_F11: requested_index = 10
		KEY_F12: requested_index = 11
	if requested_index < 0:
		return
	panel_picker.select(requested_index)
	_show_panel(requested_index)
	get_viewport().set_input_as_handled()


func _build_native_inspector_window() -> void:
	inspector_window = Window.new()
	inspector_window.process_mode = Node.PROCESS_MODE_ALWAYS
	inspector_window.visible = false
	inspector_window.name = "UILayoutInspectorWindow"
	inspector_window.title = "HardCore UI 校准控制台"
	inspector_window.size = INSPECTOR_WINDOW_SIZE
	inspector_window.min_size = INSPECTOR_WINDOW_SIZE
	inspector_window.unresizable = true
	inspector_window.force_native = true
	inspector_window.transient = false
	inspector_window.always_on_top = true
	inspector_window.close_requested.connect(inspector_window.hide)
	add_child(inspector_window)
	inspector_host = Control.new()
	inspector_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspector_window.add_child(inspector_host)
	inspector_window.show()
	_position_inspector_window()


func _position_inspector_window() -> void:
	var main_window := get_window()
	var main_position := main_window.position
	var screen_rect := DisplayServer.screen_get_usable_rect(main_window.current_screen)
	var left_position := Vector2i(main_position.x - INSPECTOR_WINDOW_SIZE.x - INSPECTOR_GAP, main_position.y)
	var right_position := Vector2i(main_position.x + DEVICE_PHYSICAL_SIZE.x + INSPECTOR_GAP, main_position.y)
	if left_position.x >= screen_rect.position.x:
		inspector_window.position = left_position
	elif right_position.x + INSPECTOR_WINDOW_SIZE.x <= screen_rect.end.x:
		inspector_window.position = right_position
	else:
		inspector_window.position = screen_rect.position + Vector2i(8, 8)


func _build_panel_picker() -> void:
	panel_picker = OptionButton.new()
	panel_picker.position = Vector2.ZERO
	panel_picker.size = Vector2(250, 46)
	for spec in PANEL_SPECS:
		panel_picker.add_item(spec["label"])
	panel_picker.item_selected.connect(_show_panel)
	inspector_host.add_child(panel_picker)


func _build_production_game() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.inventory = []
	PlayerState.add_item("强效太阳水", 82)
	PlayerState.add_item("魔法药(中量)", 94)
	PlayerState.add_item("金创药(小量)", 25)
	PlayerState.warehouse_inventory = [{"name": "魔法药(小量)", "count": 23}]
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	hud = game.get("hud") as Node
	assert(hud != null, "calibrator did not create the production GameHUD")
	await _wait_for_production_world_ready()
	var logical_size := get_viewport().get_visible_rect().size
	assert(logical_size.is_equal_approx(EXPECTED_DEVICE_LOGICAL_SIZE), "game logical viewport mismatch: %s" % logical_size)
	var safe_root := hud.get_node_or_null("MobileSafeRoot") as Control
	assert(safe_root != null, "production GameHUD is missing MobileSafeRoot")
	var safe_left := DEVICE_SAFE_LEFT_PX / float(DEVICE_PHYSICAL_SIZE.x) * logical_size.x
	var safe_right := DEVICE_SAFE_RIGHT_PX / float(DEVICE_PHYSICAL_SIZE.x) * logical_size.x
	safe_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	safe_root.position = Vector2(safe_left, 0.0)
	safe_root.size = logical_size - Vector2(safe_left + safe_right, 0.0)
	await get_tree().process_frame
	_build_level_up_preview()


func _wait_for_production_world_ready() -> void:
	var deadline := Time.get_ticks_msec() + WORLD_BOOTSTRAP_TIMEOUT_MSEC
	while (
		bool(game.get("_world_bootstrap_in_progress"))
		or bool(game.get("_map_transition_in_progress"))
	):
		assert(
			Time.get_ticks_msec() < deadline,
			"calibrator timed out waiting for production world bootstrap"
		)
		await get_tree().process_frame
	var loading_overlay := hud.get("loading_transition_overlay") as Control
	assert(loading_overlay != null, "calibrator production Loading overlay is missing")
	assert(
		not loading_overlay.visible,
		"calibrator cannot freeze the production world while Loading is visible"
	)


func _build_level_up_preview() -> void:
	var player := game.get("player") as Node2D
	assert(player != null, "calibrator production player is unavailable for level-up preview")
	level_up_preview = LevelUpPreviewScript.new()
	level_up_preview.name = "CalibrationLevelUpPreview"
	# Match the formal runtime mount: the owner is a player child on actor z=0,
	# allowing the component's back pass to use show_behind_parent while the
	# foreground pass remains after the actor body. The anchor is player-local so
	# moving the calibration actor does not apply the preview offset twice.
	level_up_preview.z_index = 0
	level_up_preview.z_as_relative = true
	level_up_preview.set_meta("render_domain", "actor_y_sort")
	level_up_preview.set_meta("draw_order", "after_player_footpoint")
	level_up_preview.set_meta("preview_only", true)
	level_up_preview.set_meta("gameplay_event_source", "none")
	player.add_child(level_up_preview)
	var anchor_local: Variant = (
		player.call("approved_ground_footpoint_local_px")
		if player.has_method("approved_ground_footpoint_local_px")
		else Vector2.ZERO
	)
	level_up_preview.set_anchor(anchor_local if anchor_local is Vector2 else Vector2.ZERO)
	level_up_preview.reset()


func _build_level_up_preview_controls() -> void:
	assert(level_up_preview != null, "calibrator level-up preview was not created")
	var panel := PanelContainer.new()
	panel.name = "LevelUpPreviewControls"
	panel.position = Vector2(12, 918)
	panel.size = Vector2(388, 108)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	inspector_host.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var title := Label.new()
	title.text = "升级脚下光环（仅校准预览）"
	title.add_theme_font_size_override("font_size", 14)
	column.add_child(title)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	column.add_child(actions)
	var replay_button := Button.new()
	replay_button.text = "重播"
	replay_button.custom_minimum_size = Vector2(82, 36)
	replay_button.pressed.connect(_replay_level_up_preview)
	actions.add_child(replay_button)
	level_up_preview_toggle_button = Button.new()
	level_up_preview_toggle_button.text = "播放"
	level_up_preview_toggle_button.custom_minimum_size = Vector2(82, 36)
	level_up_preview_toggle_button.pressed.connect(_toggle_level_up_preview)
	actions.add_child(level_up_preview_toggle_button)
	var hide_button := Button.new()
	hide_button.text = "隐藏"
	hide_button.custom_minimum_size = Vector2(82, 36)
	hide_button.pressed.connect(_hide_level_up_preview)
	actions.add_child(hide_button)
	level_up_preview_status = Label.new()
	level_up_preview_status.text = "待播放 · 不连接升级事件"
	level_up_preview_status.add_theme_font_size_override("font_size", 11)
	level_up_preview_status.modulate = Color("e6c179")
	column.add_child(level_up_preview_status)
	level_up_preview.playback_started.connect(_on_level_up_preview_started)
	level_up_preview.playback_paused.connect(_on_level_up_preview_paused)
	level_up_preview.playback_finished.connect(_on_level_up_preview_finished)


func _replay_level_up_preview() -> void:
	if level_up_preview == null:
		return
	_level_up_preview_auto_active = false
	_level_up_preview_restart_remaining = -1.0
	level_up_preview.replay()
	level_up_preview_toggle_button.text = "暂停"


func _toggle_level_up_preview() -> void:
	if level_up_preview == null:
		return
	_level_up_preview_auto_active = false
	_level_up_preview_restart_remaining = -1.0
	if level_up_preview.is_playing():
		level_up_preview.pause()
	else:
		level_up_preview.play()


func _hide_level_up_preview() -> void:
	if level_up_preview == null:
		return
	_level_up_preview_auto_active = false
	_level_up_preview_restart_remaining = -1.0
	level_up_preview.reset()
	level_up_preview_toggle_button.text = "播放"
	level_up_preview_status.text = "已隐藏 · 待用户确认"


func _on_level_up_preview_started() -> void:
	if level_up_preview_toggle_button != null:
		level_up_preview_toggle_button.text = "暂停"
	if level_up_preview_status != null:
		level_up_preview_status.text = (
			"自动播放中 · 仅校准预览"
			if _level_up_preview_auto_active
			else "播放中 · 仅校准预览"
		)


func _on_level_up_preview_paused() -> void:
	if level_up_preview_toggle_button != null:
		level_up_preview_toggle_button.text = "继续"
	if level_up_preview_status != null:
		level_up_preview_status.text = "已暂停 · 仅校准预览"


func _on_level_up_preview_finished() -> void:
	if level_up_preview_toggle_button != null:
		level_up_preview_toggle_button.text = "重播"
	if level_up_preview_status != null:
		level_up_preview_status.text = (
			"自动循环 · 即将重播"
			if _level_up_preview_auto_active
			else "播放完成 · 点击重播"
		)


func _freeze_calibration_world() -> void:
	_freeze_gameplay_branch(game, hud)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is CanvasItem:
			(enemy as CanvasItem).visible = false
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	# _freeze_gameplay_branch disables callbacks on every child, including this
	# calibration-only node. Re-enable only its idle callback so Play/Replay can
	# advance while the production world remains frozen.
	if level_up_preview != null:
		level_up_preview.process_mode = Node.PROCESS_MODE_ALWAYS
		level_up_preview.set_process(true)


func _freeze_gameplay_branch(node: Node, excluded_branch: Node) -> void:
	if node == excluded_branch or excluded_branch.is_ancestor_of(node):
		return
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child: Node in node.get_children():
		_freeze_gameplay_branch(child, excluded_branch)


func _build_calibration_overlay() -> void:
	calibration_canvas = CanvasLayer.new()
	calibration_canvas.name = "CalibrationTopLayer"
	calibration_canvas.layer = 1000
	calibration_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(calibration_canvas)
	overlay = CalibrationOverlayScript.new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	calibration_canvas.add_child(overlay)
	overlay.call("dock_inspector_to", inspector_host)
	overlay.call("dock_panel_selector", panel_picker)
	overlay.call("set_device_coordinate_space", Vector2(DEVICE_PHYSICAL_SIZE))


func _show_panel(index: int) -> void:
	if hud == null or index < 0 or index >= PANEL_SPECS.size():
		return
	var spec: Dictionary = PANEL_SPECS[index]
	hud.call("_close_modal_panels")
	var system_menu := game.get("_system_menu_panel") as Control
	if system_menu != null and system_menu.visible:
		get_tree().paused = false
		game.call("_hide_system_menu")
	var profile_id := str(spec["id"])
	var death_panel := hud.get("death_revival_panel") as Control
	if profile_id != "death_revival" and death_panel != null and death_panel.visible:
		hud.call("close_death_screen")
	if profile_id != "confirmation_dialog" and is_instance_valid(_confirmation_instance):
		_confirmation_instance.queue_free()
		await get_tree().process_frame
		_confirmation_instance = null
	if profile_id != "character_hall" and is_instance_valid(_character_hall_instance):
		_character_hall_instance.queue_free()
		await get_tree().process_frame
		_character_hall_instance = null
	await get_tree().process_frame
	if profile_id in ["shop_sell", "shop_buy"]:
		var purchase_stock: Array = game.call("_starter_gear_stock")
		assert(not purchase_stock.is_empty(), "calibrator shop buy stock is empty")
		hud.call("open_shop", "比奇武器店", purchase_stock)
		await get_tree().process_frame
		var shop := hud.get("shop_panel") as Node
		if profile_id == "shop_sell":
			var quote_items: Array = []
			for inventory_index in range(PlayerState.inventory.size()):
				var record: Dictionary = PlayerState.inventory[inventory_index]
				quote_items.append({
					"quote_key": shop.call("sell_quote_key", inventory_index, record),
					"inventory_index": inventory_index,
					"instance_id": str(record.get("instance_id", "")),
					"item_name": str(record.get("name", "")),
					"count": int(record.get("count", 1)),
				})
			shop.call("set_sell_quotes", PlayerState.shop_sell_quotes(quote_items))
			shop.get("sell_tab_button").pressed.emit()
		else:
			shop.get("buy_tab_button").pressed.emit()
			shop.call("_select_shop_item", 0)
	elif profile_id == "quest":
		hud.call("open_quest", "老兵")
	elif profile_id == "system_menu":
		game.call("_show_system_menu")
	elif profile_id == "system_settings":
		game.call("_show_system_menu")
		await get_tree().process_frame
		system_menu = game.get("_system_menu_panel") as Control
		assert(system_menu != null, "system menu panel missing for settings profile")
		system_menu.call("show_settings_page")
	elif profile_id == "character_hall":
		get_tree().paused = false
		_open_character_hall()
	elif profile_id == "death_revival":
		get_tree().paused = false
		hud.call("show_death_screen", {
			"death_id": "death:calibration:001",
			"message": "角色已经倒下",
			"loss_text": "死亡损失：当前等级经验 10%",
			"revival_options": [
				{
					"option_slot": "town",
					"method_id": "revive.nearest_town",
					"label": "最近城镇复活",
					"enabled": true,
					"countdown_seconds": 0,
					"hint": "当前可以使用",
				},
				{
					"option_slot": "special",
					"method_id": "revive.special.scroll",
					"label": "特殊复活",
					"enabled": false,
					"countdown_seconds": 0,
					"reason": "特殊复活暂不可用",
				},
			],
		})
	elif profile_id == "confirmation_dialog":
		get_tree().paused = false
		_open_confirmation_dialog()
	else:
		hud.call(str(spec["open_method"]))
	await get_tree().process_frame
	await get_tree().process_frame
	if str(spec["panel_property"]) == "_character_hall_instance":
		active_panel = _character_hall_instance
	elif str(spec["panel_property"]) == "_confirmation_instance":
		active_panel = _confirmation_instance
	elif str(spec["panel_property"]).begins_with("_"):
		active_panel = game.get(str(spec["panel_property"])) as Control
	else:
		active_panel = hud.get(str(spec["panel_property"])) as Control
	assert(active_panel != null and active_panel.visible, "production panel did not open: %s" % str(spec["id"]))
	# Keep freshly constructed production controls off-screen until the saved
	# profile has retired/hidden stale layers. This prevents a one-frame flash
	# of controls that the user already deleted in the calibration data.
	active_panel.hide()
	overlay.edit_panel(active_panel, str(spec["id"]))
	await overlay.profile_loaded
	active_panel.show()
	if str(spec["id"]) == "skill":
		var loaded_title := active_panel.get_node_or_null("SkillDetailPanel/DescriptionTitle") as Label
		var loaded_description := active_panel.get_node_or_null("SkillDetailPanel/SkillDescription") as RichTextLabel
		assert(loaded_title != null and loaded_title.text == "技能说明", "calibration overlay restored stale skill title")
		assert(loaded_description != null and not ("技能ID" in loaded_description.text or "来源" in loaded_description.text or "可信度" in loaded_description.text), "calibration overlay restored stale skill provenance")
		print("UI_CALIBRATOR_SKILL_AFTER_LOAD title=%s description_has_internal=%s" % [loaded_title.text, loaded_description.text.contains("技能ID") or loaded_description.text.contains("来源") or loaded_description.text.contains("可信度")])
		var detail := active_panel.get_node_or_null("SkillDetailPanel") as Control
		var decoration := active_panel.get_node_or_null("SkillDetailPanel/SkillDetailPanelDecoration") as Control
		var title := active_panel.get_node_or_null("SkillDetailPanel/DescriptionTitle") as Label
		var description := active_panel.get_node_or_null("SkillDetailPanel/SkillDescription") as RichTextLabel
		assert(detail != null and decoration != null, "skill detail semantic decoration is missing")
		assert(active_panel.get_node_or_null("SkillDetailPanel/SkillDetailV3Frame") == null, "retired duplicate skill detail frame was recreated")
		assert(active_panel.get_node_or_null("SkillDetailPanel/LearnButton") == null, "retired skill learn button was recreated")
		print("UI_CALIBRATOR_SKILL_MARKER SkillDetailPanelDecoration=%s duplicate_frame=false learn_button=false title=%s description_has_internal=%s" % [decoration != null, title.text if title != null else "<missing>", description != null and ("技能ID" in description.text or "来源" in description.text or "可信度" in description.text)])
		var expected_skill_rect := Rect2(195, 35, 1208, 650)
		assert(
			active_panel.get_global_rect().is_equal_approx(expected_skill_rect),
			"skill panel does not match the accepted device profile: %s / %s" % [active_panel.get_global_rect(), expected_skill_rect],
		)
	print("UI_CALIBRATOR_PANEL_OPEN profile=%s panel=%s" % [str(spec["id"]), active_panel.get_global_rect()])


func _open_character_hall() -> void:
	get_tree().paused = false
	if is_instance_valid(_character_hall_instance):
		_character_hall_instance.show()
		return
	var scene := load("res://scenes/character_select.tscn") as PackedScene
	assert(scene != null, "character hall scene is unavailable")
	_character_hall_instance = scene.instantiate() as Control
	assert(_character_hall_instance != null, "character hall scene did not instantiate a Control")
	_character_hall_instance.name = "CharacterHall"
	_character_hall_instance.process_mode = Node.PROCESS_MODE_ALWAYS
	# HUD is the production CanvasLayer whose children receive the game's
	# logical-to-physical stretch. A direct workbench child would render in the
	# physical shell canvas and drift away from the overlay/HUD coordinate space.
	hud.add_child(_character_hall_instance)
	# The workbench host is a physical-size shell. Keep the formal hall root in
	# the game's logical coordinate space before its centered content is used.
	_character_hall_instance.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_character_hall_instance.position = Vector2.ZERO
	_character_hall_instance.size = EXPECTED_DEVICE_LOGICAL_SIZE
	var content_root := _character_hall_instance.get_node_or_null("CenteredContent") as Control
	assert(content_root != null, "character hall centered content is missing")
	var expected_content_rect := Rect2(
		(EXPECTED_DEVICE_LOGICAL_SIZE.x - content_root.size.x) * 0.5,
		0.0,
		content_root.size.x,
		content_root.size.y,
	)
	assert(
		_character_hall_instance.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, EXPECTED_DEVICE_LOGICAL_SIZE)),
		"character hall root must use the logical viewport: %s" % _character_hall_instance.get_global_rect(),
	)
	assert(
		content_root.get_global_rect().is_equal_approx(expected_content_rect),
		"character hall centered content must be centered in the logical viewport: %s / %s" % [content_root.get_global_rect(), expected_content_rect],
	)
	_print_character_hall_diagnostics(content_root)


func _print_character_hall_diagnostics(content_root: Control) -> void:
	var background := _character_hall_instance.get_node_or_null("CharacterHallBackground") as Control
	var shade := _character_hall_instance.get_node_or_null("HallShade") as Control
	var viewport := get_viewport()
	print(
		"UI_CALIBRATOR_CHARACTER_HALL_DIAGNOSTICS root_rect=%s root_global=%s root_canvas=%s content_rect=%s content_global=%s content_canvas=%s background_global=%s shade_global=%s viewport=%s canvas_transform=%s workbench=%s overlay_target=%s physical_scale=%s" % [
			_character_hall_instance.get_rect(),
			_character_hall_instance.get_global_rect(),
			_character_hall_instance.get_global_transform_with_canvas(),
			content_root.get_rect(),
			content_root.get_global_rect(),
			content_root.get_global_transform_with_canvas(),
			background.get_global_rect() if background != null else Rect2(),
			shade.get_global_rect() if shade != null else Rect2(),
			viewport.get_visible_rect().size,
			viewport.get_canvas_transform(),
			get_rect(),
			content_root.get_global_rect(),
			Vector2(DEVICE_PHYSICAL_SIZE) / viewport.get_visible_rect().size,
		]
	)


func _open_confirmation_dialog() -> void:
	get_tree().paused = false
	if not is_instance_valid(_confirmation_instance):
		_confirmation_instance = GothicConfirmationPanelScript.new()
		_confirmation_instance.name = "CalibrationConfirmationDialog"
		_confirmation_instance.process_mode = Node.PROCESS_MODE_ALWAYS
		hud.add_child(_confirmation_instance)
		_confirmation_instance.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_confirmation_instance.position = Vector2.ZERO
		_confirmation_instance.size = EXPECTED_DEVICE_LOGICAL_SIZE
	_confirmation_instance.call("open_confirmation", {
		"action_id": "shop.sell.dangerous_item",
		"tone": "danger",
		"title": "稀有物品出售确认",
		"message": "确定要出售这件稀有物品吗？此操作不可撤销。",
		"cancel_label": "取消",
		"confirm_label": "确认出售",
		"context": {"item_id": "calibration_danger_item", "count": 1},
	})


func _print_geometry() -> void:
	if not is_instance_valid(active_panel):
		print("UI_CALIBRATOR_GEOMETRY physical=%s safe_root=%s panel=<none>" % [DEVICE_PHYSICAL_SIZE, hud.get_node("MobileSafeRoot").get_rect()])
		return
	print(
		"UI_CALIBRATOR_GEOMETRY physical=%s safe_root=%s panel=%s" % [
			DEVICE_PHYSICAL_SIZE,
			hud.get_node("MobileSafeRoot").get_rect(),
			active_panel.get_global_rect(),
		]
	)
