extends Control

const CalibrationOverlayScript := preload("res://scripts/ui_layout_calibration_overlay.gd")
const GothicConfirmationPanelScript := preload("res://scripts/gothic_confirmation_panel.gd")

const DEVICE_PHYSICAL_SIZE := Vector2i(2664, 1200)
const EXPECTED_DEVICE_LOGICAL_SIZE := Vector2(1598, 720)
const DEVICE_SAFE_LEFT_PX := 121.0
const DEVICE_SAFE_RIGHT_PX := 129.0
const INSPECTOR_WINDOW_SIZE := Vector2i(412, 1040)
const INSPECTOR_GAP := 16

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_native_inspector_window()
	_build_panel_picker()
	await _build_production_game()
	_freeze_calibration_world()
	_build_calibration_overlay()
	assert(process_mode == Node.PROCESS_MODE_ALWAYS, "calibration workbench must process while the game is paused")
	await _show_panel(0)
	_print_geometry()


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


func _freeze_calibration_world() -> void:
	_freeze_gameplay_branch(game, hud)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is CanvasItem:
			(enemy as CanvasItem).visible = false
		enemy.process_mode = Node.PROCESS_MODE_DISABLED


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
		hud.call("open_quest", "比奇老兵")
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
			"message": "校准用：角色已经倒下",
			"loss_text": "校准用：经验损失说明（不会实际扣除）",
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
					"reason": "校准用：特殊复活暂不可用",
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
	if str(spec["id"]) == "skill":
		var loaded_title := active_panel.get_node_or_null("SkillDetailPanel/DescriptionTitle") as Label
		var loaded_description := active_panel.get_node_or_null("SkillDetailPanel/SkillDescription") as RichTextLabel
		assert(loaded_title != null and loaded_title.text == "技能说明", "calibration overlay restored stale skill title")
		assert(loaded_description != null and not ("技能ID" in loaded_description.text or "来源" in loaded_description.text or "可信度" in loaded_description.text), "calibration overlay restored stale skill provenance")
		print("UI_CALIBRATOR_SKILL_AFTER_LOAD title=%s description_has_internal=%s" % [loaded_title.text, loaded_description.text.contains("技能ID") or loaded_description.text.contains("来源") or loaded_description.text.contains("可信度")])
		var detail := active_panel.get_node_or_null("SkillDetailPanel") as Control
		var v3 := active_panel.get_node_or_null("SkillDetailPanel/SkillDetailV3Frame") as Control
		var title := active_panel.get_node_or_null("SkillDetailPanel/DescriptionTitle") as Label
		var description := active_panel.get_node_or_null("SkillDetailPanel/SkillDescription") as RichTextLabel
		print("UI_CALIBRATOR_SKILL_MARKER SkillDetailV3Frame=%s child0=%s title=%s description_has_internal=%s" % [v3 != null, detail != null and detail.get_child_count() > 0 and detail.get_child(0) == v3, title.text if title != null else "<missing>", description != null and ("技能ID" in description.text or "来源" in description.text or "可信度" in description.text)])
		var expected_skill_rect := Rect2(195, 35, 1208, 650)
		assert(
			active_panel.get_global_rect().is_equal_approx(expected_skill_rect),
			"skill panel does not match the accepted device profile: %s / %s" % [active_panel.get_global_rect(), expected_skill_rect],
		)
	overlay.edit_panel(active_panel, str(spec["id"]))
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
	print(
		"UI_CALIBRATOR_GEOMETRY physical=%s safe_root=%s panel=%s" % [
			DEVICE_PHYSICAL_SIZE,
			hud.get_node("MobileSafeRoot").get_rect(),
			active_panel.get_global_rect(),
		]
	)
