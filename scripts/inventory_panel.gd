class_name InventoryPanel
extends Panel

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const PreviewScript = preload("res://scripts/equipment_character_preview.gd")
const GothicUIThemeScript = preload("res://scripts/gothic_ui_theme.gd")
const UIItemTextureCacheScript = preload("res://scripts/ui_item_texture_cache.gd")
const TouchScrollSupportScript = preload("res://scripts/touch_scroll_support.gd")

signal closed

const PANEL_SIZE := Vector2(1220, 660)
const MODAL_SURFACE_INSET := Vector4(32, 38, 32, 34)
const SECTION_VERTICAL_SHIFT := 24.0
const BAG_COLUMNS := 8
const BAG_VISIBLE_CAPACITY := 40
const BAG_CAPACITY := 100
const BAG_CELL_SIZE := Vector2(56, 64)
const LONG_PRESS_SECONDS := 0.48
const CONTEXT_MENU_POLICY_ID := "ui.inventory.context_menu_policy.v1"
const CONTEXT_MENU_ENABLED := false

var item_grid: GridContainer
var detail_label: RichTextLabel
var equipment_stats_label: RichTextLabel
var bag_summary_label: Label
var character_preview: Control
var equipment_buttons: Dictionary = {}
var equipment_slot_labels: Dictionary = {}
var selected_inventory_index := -1
var selected_equipment_slot := ""

# Compatibility mirrors retained for save/UI regression tests. The user-facing
# interface uses the eight direct slots and the long-press menu.
var equipment_label: Label
var equipment_slot_picker: OptionButton
var action_button: Button
var unequip_button: Button

var context_menu: PopupMenu
var _context_actions: Dictionary = {}
var _press_timer: Timer
var _press_context: Dictionary = {}
var _press_button: Button
var _press_origin := Vector2.ZERO
var _long_press_opened := false
var _refresh_pending := false
var _refresh_execution_count := 0
# Production policy: the long-press context menu is intentionally suppressed.
# The PopupMenu builder/action helpers remain for special items enabled later
# through _context_menu_policy (enabled + optional enabled_kinds whitelist).
var _context_menu_policy: Dictionary = {
	"enabled": CONTEXT_MENU_ENABLED,
	"enabled_kinds": [],
}
var _press_cancelled := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_bottom = PANEL_SIZE.y * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	theme = GothicUIThemeScript.build()
	theme_type_variation = "GothicModalFrame"
	_build_modal_surface()
	_build_header()
	_build_attribute_panel()
	_build_equipment_panel()
	_build_bag_panel()
	_build_context_menu()
	visibility_changed.connect(_on_visibility_changed)
	PlayerState.inventory_changed.connect(_on_panel_data_changed)
	PlayerState.equipment_changed.connect(_on_panel_data_changed)
	PlayerState.profile_changed.connect(_refresh_character_stats)
	refresh()


func _build_modal_surface() -> void:
	var surface := Panel.new()
	surface.name = "ModalSurface"
	surface.position = Vector2(MODAL_SURFACE_INSET.x, MODAL_SURFACE_INSET.y)
	surface.size = PANEL_SIZE - Vector2(MODAL_SURFACE_INSET.x + MODAL_SURFACE_INSET.z, MODAL_SURFACE_INSET.y + MODAL_SURFACE_INSET.w)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(380, 4)
	title_frame.size = Vector2(460, 64)
	title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_frame.theme_type_variation = "GothicTitleBar"
	add_child(title_frame)
	var title := Label.new()
	title.name = "Title"
	title.text = "人物与背包"
	title.position = Vector2(30, 15)
	title.size = Vector2(400, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f1cc88"))
	title_frame.add_child(title)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.position = Vector2(1138, 8)
	close_button.size = Vector2(56, 56)
	close_button.theme_type_variation = "GothicComponentCloseButton"
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(_close)
	add_child(close_button)


func _build_attribute_panel() -> void:
	var panel := _section_panel("AttributePanel", Vector2(32, 72), Vector2(250, 566))
	add_child(panel)
	var title := _section_title("人物属性", 250)
	panel.add_child(title)
	equipment_stats_label = RichTextLabel.new()
	equipment_stats_label.name = "CharacterStats"
	equipment_stats_label.position = Vector2(16, 44)
	equipment_stats_label.size = Vector2(218, 220)
	equipment_stats_label.fit_content = false
	equipment_stats_label.scroll_active = true
	equipment_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_stats_label.theme_type_variation = "GothicDetailText"
	equipment_stats_label.add_theme_font_size_override("normal_font_size", 16)
	equipment_stats_label.add_theme_color_override("font_color", Color("ddc9a9"))
	panel.add_child(equipment_stats_label)
	var divider := HSeparator.new()
	divider.position = Vector2(16, 270)
	divider.size = Vector2(218, 8)
	panel.add_child(divider)
	var item_title := Label.new()
	item_title.text = "物品属性"
	item_title.position = Vector2(16, 278)
	item_title.size = Vector2(218, 30)
	item_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_title.theme_type_variation = "GothicSectionTitle"
	panel.add_child(item_title)
	detail_label = RichTextLabel.new()
	detail_label.name = "ItemDetail"
	detail_label.position = Vector2(16, 312)
	detail_label.size = Vector2(218, 220)
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.theme_type_variation = "GothicDetailText"
	panel.add_child(detail_label)


func _build_equipment_panel() -> void:
	var panel := _section_panel("EquipmentPanel", Vector2(294, 72), Vector2(390, 566))
	add_child(panel)
	panel.add_child(_section_title("人物装备", 390))
	character_preview = PreviewScript.new()
	character_preview.name = "CharacterPreview"
	character_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Every paper-doll layer is placed relative to the manifest foot anchor;
	# alpha bounds remain diagnostic data and cannot move the stage.
	character_preview.center_on_opaque_bounds = false
	character_preview.set_meta("horizontal_alignment_contract", PreviewScript.FOOT_STAGE_ANCHOR_CONTRACT_ID)
	character_preview.configure_presentation_mode("classic_avatar")
	character_preview.set_meta("paper_doll_render_contract", PreviewScript.PRESENTATION_MODES_CONTRACT_ID)
	character_preview.set_meta("paper_doll_presentation_mode", "classic_avatar")
	character_preview.set_meta(
		"coordinate_space_policy",
		"transparent classic avatar; touch regions remain external equipment slots"
	)
	character_preview.set_meta("input_policy", "visual_only_mouse_filter_ignore")
	# Reserve the lower half of the equipment panel for the client paper-doll;
	# the previous top placement left a visibly unused block under the figure.
	character_preview.position = Vector2(80, 139)
	character_preview.size = Vector2(230, 286)
	panel.add_child(character_preview)

	var positions := {
		"头盔": Vector2(153, 44), "项链": Vector2(296, 44),
		"武器": Vector2(10, 144), "衣服": Vector2(296, 144),
		"左手镯": Vector2(10, 244), "右手镯": Vector2(296, 244),
		"左戒指": Vector2(10, 344), "右戒指": Vector2(296, 344),
	}
	for slot: String in PlayerState.EQUIPMENT_SLOTS:
		_create_equipment_slot(panel, slot, positions.get(slot, Vector2.ZERO))
	# Reserved for a future medal / belt / boots row. Keeping this anchor empty
	# avoids another paper-doll re-layout when those stable equipment slots land.
	var future_row := Control.new()
	future_row.name = "FutureEquipmentRow"
	future_row.position = Vector2(12, 444)
	future_row.size = Vector2(366, 102)
	future_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	future_row.set_meta("reserved_slots", ["勋章", "腰带", "鞋子"])
	panel.add_child(future_row)

	equipment_label = Label.new()
	equipment_label.visible = false
	panel.add_child(equipment_label)
	equipment_slot_picker = OptionButton.new()
	equipment_slot_picker.visible = false
	for slot: String in PlayerState.EQUIPMENT_SLOTS:
		equipment_slot_picker.add_item(slot)
	panel.add_child(equipment_slot_picker)
	action_button = Button.new()
	action_button.visible = false
	panel.add_child(action_button)
	unequip_button = Button.new()
	unequip_button.visible = false
	panel.add_child(unequip_button)


func _build_bag_panel() -> void:
	var panel := _section_panel("BagPanel", Vector2(696, 72), Vector2(492, 566))
	add_child(panel)
	panel.add_child(_section_title("综合背包", 492))
	bag_summary_label = Label.new()
	bag_summary_label.name = "BagSummary"
	bag_summary_label.position = Vector2(246, 19)
	bag_summary_label.size = Vector2(218, 26)
	bag_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bag_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bag_summary_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(bag_summary_label)
	var scroll := ScrollContainer.new()
	scroll.name = "InventoryScroll"
	scroll.position = Vector2(10, 50)
	scroll.size = Vector2(472, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	item_grid = GridContainer.new()
	item_grid.name = "ItemGrid"
	item_grid.columns = BAG_COLUMNS
	item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_grid.add_theme_constant_override("h_separation", 1)
	item_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(item_grid)
	var paging_hint := Label.new()
	paging_hint.name = "BagPagingHint"
	paging_hint.text = "首屏 1–%d 格　·　拖动右侧滚条查看 %d–%d 格" % [BAG_VISIBLE_CAPACITY, BAG_VISIBLE_CAPACITY + 1, BAG_CAPACITY]
	paging_hint.position = Vector2(18, 402)
	paging_hint.size = Vector2(456, 28)
	paging_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paging_hint.theme_type_variation = "GothicMutedLabel"
	panel.add_child(paging_hint)


func _build_context_menu() -> void:
	context_menu = PopupMenu.new()
	context_menu.name = "ItemContextMenu"
	context_menu.add_theme_font_size_override("font_size", 20)
	context_menu.id_pressed.connect(_on_context_action)
	add_child(context_menu)
	_press_timer = Timer.new()
	_press_timer.one_shot = true
	_press_timer.wait_time = LONG_PRESS_SECONDS
	_press_timer.timeout.connect(_on_long_press_timer_timeout)
	add_child(_press_timer)


func _create_equipment_slot(parent: Control, slot: String, position_value: Vector2) -> void:
	var holder := Control.new()
	holder.name = "EquipmentHolder_%s" % slot
	holder.position = position_value
	holder.size = Vector2(84, 98)
	parent.add_child(holder)
	var button := Button.new()
	button.name = "EquipmentSlot_%s" % slot
	button.position = Vector2(2, 0)
	button.size = Vector2(80, 80)
	button.expand_icon = true
	button.toggle_mode = true
	button.tooltip_text = "%s：空" % slot
	button.theme_type_variation = "GothicEquipmentSlotButton"
	button.pressed.connect(_select_equipment_slot.bind(slot))
	button.gui_input.connect(_equipment_input.bind(slot, button))
	holder.add_child(button)
	var caption_plate := Panel.new()
	caption_plate.name = "SlotCaptionPlate"
	caption_plate.position = Vector2(8, 68)
	caption_plate.size = Vector2(68, 24)
	caption_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_plate.theme_type_variation = "GothicEquipmentSlotCaption"
	holder.add_child(caption_plate)
	var slot_label := Label.new()
	slot_label.name = "SlotLabel"
	slot_label.text = slot
	slot_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_label.add_theme_font_size_override("font_size", 13)
	slot_label.add_theme_color_override("font_color", Color("e1bd7d"))
	caption_plate.add_child(slot_label)
	equipment_buttons[slot] = button
	equipment_slot_labels[slot] = slot_label


func _on_panel_data_changed() -> void:
	if not visible:
		_refresh_pending = true
		return
	refresh()


func _on_visibility_changed() -> void:
	if visible and _refresh_pending:
		refresh()


func refresh() -> void:
	if item_grid == null:
		return
	_refresh_pending = false
	_refresh_execution_count += 1
	_refresh_equipment_slots()
	_refresh_character_stats()
	_refresh_bag_grid()
	if character_preview != null:
		character_preview.refresh()


func _refresh_equipment_slots() -> void:
	var compatibility_lines: Array[String] = []
	for slot: String in PlayerState.EQUIPMENT_SLOTS:
		var button: Button = equipment_buttons.get(slot)
		var record: Variant = PlayerState.equipment.get(slot, {})
		var name := str(record.get("name", "")) if record is Dictionary else str(record)
		button.icon = null
		button.text = ""
		button.tooltip_text = "%s：空" % slot
		if not name.is_empty():
			_set_button_texture(button, _item_texture(GameData.get_item_record(name), "inventoryIcon"))
			button.tooltip_text = _equipment_tooltip(slot, record)
		else:
			_set_button_texture(button, null)
		button.set_pressed_no_signal(slot == selected_equipment_slot)
		button.theme_type_variation = "GothicSelectedEquipmentSlotButton" if slot == selected_equipment_slot else "GothicEquipmentSlotButton"
		compatibility_lines.append(_compatibility_equipment_text(slot, record))
	equipment_label.text = "　".join(compatibility_lines)


func _refresh_character_stats() -> void:
	if equipment_stats_label == null:
		return
	equipment_stats_label.text = _character_stats_text(PlayerState.computed_stats)


func _character_stats_text(stats: Dictionary) -> String:
	return "%s　等级 %d\n生命 %d　魔法 %d\n攻击 %d-%d\n魔法 %d-%d　道术 %d-%d\n防御 %d-%d　魔防 %d-%d\n准确 %d　敏捷 %d　幸运 %d\n魔法躲避 %d%%　攻击速度 %+d\n暴击 %.1f%%\n穿戴重量 %d/%d" % [
		PlayerState.profession, PlayerState.level,
		int(stats.get("max_hp", 0)), int(stats.get("max_mp", 0)),
		int(stats.get("attack_min", 0)), int(stats.get("attack_max", 0)),
		int(stats.get("magic_min", 0)), int(stats.get("magic_max", 0)),
		int(stats.get("tao_min", 0)), int(stats.get("tao_max", 0)),
		int(stats.get("defense_min", 0)), int(stats.get("defense_max", 0)),
		int(stats.get("magic_defense_min", 0)), int(stats.get("magic_defense_max", 0)),
		int(stats.get("accuracy", 0)), int(stats.get("agility", 0)), int(stats.get("luck", 0)),
		int(stats.get("magic_evasion_percent", 0)), int(stats.get("attack_speed_tier", 0)),
		float(stats.get("critical_chance", 0.0)) * 100.0,
		int(stats.get("wear_weight", 0)), int(stats.get("max_wear_weight", 0)),
	]


func _refresh_bag_grid() -> void:
	for child: Node in item_grid.get_children():
		child.queue_free()
	if selected_inventory_index >= PlayerState.inventory.size():
		selected_inventory_index = -1
	for inventory_index in range(PlayerState.inventory.size()):
		var stack: Variant = PlayerState.inventory[inventory_index]
		if stack is Dictionary:
			item_grid.add_child(_create_bag_cell(inventory_index, stack))
	for empty_index in range(PlayerState.inventory.size(), BAG_CAPACITY):
		item_grid.add_child(_create_empty_bag_cell(empty_index))
	bag_summary_label.text = "金币 %d　%d/%d格" % [PlayerState.gold, PlayerState.inventory.size(), BAG_CAPACITY]
	if selected_inventory_index >= 0:
		_show_inventory_detail(selected_inventory_index)
	elif selected_equipment_slot.is_empty():
		detail_label.text = "[color=#d9c09a]单击物品查看属性，双击使用或装备。[/color]"


func _create_bag_cell(index: int, stack: Dictionary) -> Control:
	var cell := Control.new()
	cell.name = "InventoryCell_%d" % index
	cell.custom_minimum_size = BAG_CELL_SIZE
	var button := Button.new()
	button.name = "ItemButton"
	button.position = Vector2.ZERO
	button.size = BAG_CELL_SIZE
	button.tooltip_text = str(stack.get("name", "未知物品"))
	button.theme_type_variation = "GothicComponentSelectedSlotButton" if index == selected_inventory_index else "GothicComponentSlotButton"
	button.pressed.connect(_select_inventory_item.bind(index))
	button.gui_input.connect(_inventory_input.bind(index, button))
	cell.add_child(button)
	_set_button_texture(button, _item_texture(GameData.get_item_record(str(stack.get("name", ""))), "inventoryIcon"))
	var count := int(stack.get("count", 1))
	if count > 1:
		var count_label := Label.new()
		count_label.name = "StackCount"
		count_label.text = str(count)
		count_label.position = Vector2(BAG_CELL_SIZE.x - 34, BAG_CELL_SIZE.y - 23)
		count_label.size = Vector2(30, 20)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.add_theme_font_size_override("font_size", 14)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		count_label.add_theme_constant_override("shadow_offset_x", 2)
		count_label.add_theme_constant_override("shadow_offset_y", 2)
		cell.add_child(count_label)
	if stack.has("durability"):
		var durability_label := Label.new()
		durability_label.name = "Durability"
		durability_label.text = "%d/%d" % [int(stack.get("durability", 0)), int(stack.get("max_durability", 1))]
		durability_label.position = Vector2(3, BAG_CELL_SIZE.y - 19)
		durability_label.size = Vector2(BAG_CELL_SIZE.x - 6, 16)
		durability_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		durability_label.add_theme_font_size_override("font_size", 10)
		durability_label.add_theme_color_override("font_color", Color(0.96, 0.83, 0.52))
		cell.add_child(durability_label)
	return cell


func _create_empty_bag_cell(index: int) -> Control:
	var cell := Control.new()
	cell.name = "EmptyCell_%d" % index
	cell.custom_minimum_size = BAG_CELL_SIZE
	var background := Button.new()
	background.name = "EmptySlotBackground"
	background.position = Vector2.ZERO
	background.size = BAG_CELL_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.theme_type_variation = "GothicComponentSlotButton"
	background.disabled = true
	cell.add_child(background)
	return cell


func _select_inventory_item(index: int) -> void:
	if _press_cancelled or TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	if index < 0 or index >= PlayerState.inventory.size():
		return
	selected_inventory_index = index
	selected_equipment_slot = ""
	_show_inventory_detail(index)
	_refresh_equipment_slots()
	_refresh_bag_grid.call_deferred()


func _select_equipment_slot(slot: String) -> void:
	if _press_cancelled or TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	selected_equipment_slot = slot
	selected_inventory_index = -1
	var equipped: Variant = PlayerState.equipment.get(slot, {})
	if equipped is Dictionary and not equipped.is_empty():
		detail_label.text = _equipment_detail(slot, equipped)
	else:
		detail_label.text = "[color=#e0bd83][font_size=18]%s[/font_size][/color]\n当前为空。按住背包中的对应装备可选择穿戴位置。" % slot
	_refresh_equipment_slots()
	_refresh_bag_grid.call_deferred()


func _show_inventory_detail(index: int) -> void:
	if index < 0 or index >= PlayerState.inventory.size():
		return
	var stack: Dictionary = PlayerState.inventory[index]
	var item := GameData.get_item_record(str(stack.get("name", "")))
	if item.is_empty():
		detail_label.text = "[color=#f2c783]%s[/color]\n物品目录缺少此记录。" % stack.get("name", "未知物品")
		return
	if str(item.get("kind", "")) == "equipment":
		detail_label.text = _item_equipment_detail(stack, item)
	else:
		detail_label.text = "[color=#f2c783][font_size=18]%s[/font_size][/color]\n类别：%s\n数量：%d\n%s" % [stack.get("name", ""), _kind_label(str(item.get("kind", ""))), int(stack.get("count", 1)), str(item.get("description", ""))]


func _inventory_input(event: InputEvent, index: int, button: Button) -> void:
	if _is_double_activation_event(event):
		_cancel_long_press()
		_activate_inventory_index(index)
		return
	_handle_press_event(event, {"source": "inventory", "index": index}, button)


func _is_double_activation_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.device == InputEvent.DEVICE_ID_EMULATION:
			return false
		return mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.double_click
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		return touch.pressed and touch.double_tap
	return false


func _equipment_input(event: InputEvent, slot: String, button: Button) -> void:
	_handle_press_event(event, {"source": "equipment", "slot": slot}, button)


func _handle_press_event(event: InputEvent, context: Dictionary, button: Button) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_long_press(context, button, event.position)
		else:
			_end_long_press()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_long_press(context, button, event.position)
		else:
			_end_long_press()
	elif event is InputEventScreenDrag:
		if event.position.distance_to(_press_origin) > 12.0:
			_cancel_long_press()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if event.position.distance_to(_press_origin) > 12.0:
			_cancel_long_press()


func _begin_long_press(context: Dictionary, button: Button, local_position: Vector2) -> void:
	_press_context = context.duplicate(true)
	_press_button = button
	_press_origin = local_position
	_long_press_opened = false
	_press_cancelled = false
	_press_timer.start()


func _end_long_press() -> void:
	if not _press_timer.is_stopped():
		_press_timer.stop()
	_press_context = {}
	_press_button = null


func _cancel_long_press() -> void:
	if not _press_timer.is_stopped():
		_press_timer.stop()
	_press_context = {}
	_press_button = null
	_press_cancelled = true


func _on_long_press_timer_timeout() -> void:
	if not _context_menu_allowed() or TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	_open_long_press_menu()


func _context_menu_allowed() -> bool:
	if not bool(_context_menu_policy.get("enabled", false)):
		return false
	var allowed_kinds: Array = _context_menu_policy.get("enabled_kinds", [])
	if allowed_kinds is Array and not allowed_kinds.is_empty():
		var item_name := ""
		if str(_press_context.get("source", "")) == "inventory":
			var index := int(_press_context.get("index", -1))
			if index >= 0 and index < PlayerState.inventory.size():
				item_name = str(PlayerState.inventory[index].get("name", ""))
		elif str(_press_context.get("source", "")) == "equipment":
			var slot := str(_press_context.get("slot", ""))
			var equipped: Variant = PlayerState.equipment.get(slot, {})
			if equipped is Dictionary:
				item_name = str(equipped.get("name", ""))
		return str(GameData.get_item_kind(item_name)) in allowed_kinds
	return true


func _open_long_press_menu() -> void:
	if _press_context.is_empty() or not is_instance_valid(_press_button):
		return
	_long_press_opened = true
	context_menu.clear()
	_context_actions.clear()
	if str(_press_context.get("source", "")) == "equipment":
		var slot := str(_press_context.get("slot", ""))
		var equipped: Variant = PlayerState.equipment.get(slot, {})
		if equipped is Dictionary and not equipped.is_empty():
			_add_context_action("卸下", {"action": "unequip", "slot": slot})
	else:
		var index := int(_press_context.get("index", -1))
		if index >= 0 and index < PlayerState.inventory.size():
			_add_inventory_context_actions(index)
	if context_menu.item_count == 0:
		_add_context_action("无可用操作", {"action": "none"}, true)
	var popup_position := _press_button.get_screen_position() + _press_button.size * 0.5
	context_menu.position = Vector2i(popup_position)
	context_menu.popup()


func _add_inventory_context_actions(index: int) -> void:
	var stack: Dictionary = PlayerState.inventory[index]
	var item := GameData.get_item_record(str(stack.get("name", "")))
	var kind := str(item.get("kind", ""))
	if kind == "equipment":
		var slots := _slots_for_category(str(item.get("category", "")))
		if slots.size() == 2:
			_add_context_action("装备到%s" % slots[0], {"action": "equip", "index": index, "slot": slots[0]})
			_add_context_action("装备到%s" % slots[1], {"action": "equip", "index": index, "slot": slots[1]})
		elif slots.size() == 1:
			_add_context_action("装备", {"action": "equip", "index": index, "slot": slots[0]})
	elif kind in ["consumable", "scroll"]:
		_add_context_action("使用", {"action": "use", "index": index})


func _add_context_action(label: String, action: Dictionary, disabled := false) -> void:
	var id := _context_actions.size() + 1
	context_menu.add_item(label, id)
	context_menu.set_item_disabled(context_menu.item_count - 1, disabled)
	_context_actions[id] = action


func _on_context_action(id: int) -> void:
	var action: Dictionary = _context_actions.get(id, {})
	var result := ""
	match str(action.get("action", "none")):
		"equip":
			result = PlayerState.equip_inventory_index(int(action.get("index", -1)), str(action.get("slot", "")))
		"unequip":
			result = PlayerState.unequip_slot(str(action.get("slot", "")))
		"use":
			result = PlayerState.use_inventory_index(int(action.get("index", -1)))
		_:
			return
	selected_inventory_index = -1
	selected_equipment_slot = ""
	refresh()
	detail_label.text = "[color=#e8c277]%s[/color]" % result


# Direct action helpers remain available for automated tests and accessibility.
func _activate_selected_item(preferred_slot := "") -> void:
	if selected_inventory_index < 0 or selected_inventory_index >= PlayerState.inventory.size():
		return
	_activate_inventory_index(selected_inventory_index, preferred_slot)


func _activate_inventory_index(index: int, preferred_slot := "") -> void:
	# preferred_slot stays empty for direct double-click activation: PlayerState
	# is the authoritative equipment-slot resolver, so the UI never hardcodes a side.
	if index < 0 or index >= PlayerState.inventory.size():
		return
	_cancel_long_press()
	selected_inventory_index = index
	selected_equipment_slot = ""
	var item := GameData.get_item_record(str(PlayerState.inventory[index].get("name", "")))
	var result := PlayerState.equip_inventory_index(index, preferred_slot) if str(item.get("kind", "")) == "equipment" else PlayerState.use_inventory_index(index)
	selected_inventory_index = -1
	refresh()
	detail_label.text = "[color=#e8c277]%s[/color]" % result


func _unequip_selected() -> void:
	if selected_equipment_slot.is_empty():
		return
	var result := PlayerState.unequip_slot(selected_equipment_slot)
	selected_equipment_slot = ""
	refresh()
	detail_label.text = "[color=#e8c277]%s[/color]" % result


func _item_equipment_detail(stack: Dictionary, item: Dictionary) -> String:
	var category := str(item.get("category", ""))
	var current_durability := int(stack.get("durability", item.get("maxDurability", 1)))
	var maximum_durability := int(stack.get("max_durability", item.get("maxDurability", 1)))
	return "[color=#f2c783][font_size=18]%s[/font_size][/color]\n%s　重量 %d\n耐久 %d/%d\n%s\n%s\n穿戴要求：%s%s" % [
		stack.get("name", ""), category, int(item.get("weight", 0)), current_durability, maximum_durability,
		_stat_line(item), _advanced_stat_line(item), EquipmentRulesScript.requirement_label(item), _comparison_text(item, _comparison_slot(category)),
	]


func _equipment_detail(slot: String, record: Dictionary) -> String:
	var item := GameData.get_item_record(str(record.get("name", "")))
	var durability := int(record.get("durability", 0))
	var maximum := int(record.get("max_durability", 1))
	var state_parts: Array[String] = []
	if slot == "武器":
		state_parts.append(EquipmentRulesScript.weapon_luck_label(record))
	var special := EquipmentRulesScript.special_effect_for(item)
	if not special.is_empty():
		state_parts.append("%s（%s）" % [special.get("label", "特殊效果"), "生效" if durability > 0 and bool(special.get("runtime", false)) else "未生效"])
	var disabled_text := "\n[color=#ef5f55]耐久为0，外观保留，属性失效[/color]" if durability <= 0 else ""
	var state_text := "\n" + "　".join(state_parts) if not state_parts.is_empty() else ""
	return "[color=#f2c783][font_size=18]%s[/font_size][/color]\n槽位：%s　耐久 %d/%d%s%s\n%s\n%s" % [record.get("name", ""), slot, durability, maximum, state_text, disabled_text, _stat_line(item), _advanced_stat_line(item)]


func _stat_line(item: Dictionary) -> String:
	return "攻击 %s-%s　魔法 %s-%s\n道术 %s-%s　防御 %s-%s\n魔防 %s-%s" % [
		_value(item.get("attackMin")), _value(item.get("attackMax")), _value(item.get("magicMin")), _value(item.get("magicMax")),
		_value(item.get("taoMin")), _value(item.get("taoMax")), _value(item.get("defenseMin")), _value(item.get("defenseMax")),
		_value(item.get("mdefMin")), _value(item.get("mdefMax")),
	]


func _advanced_stat_line(item: Dictionary) -> String:
	var parts: Array[String] = []
	for pair: Array in [["accuracy", "准确"], ["agility", "敏捷"], ["luck", "幸运"], ["hpBonus", "生命"], ["mpBonus", "魔法值"]]:
		if item.get(pair[0], null) != null and float(item.get(pair[0], 0)) != 0.0:
			parts.append("%s %+d" % [pair[1], int(item.get(pair[0], 0))])
	if item.get("magicEvasionPercent", null) != null and int(item.get("magicEvasionPercent", 0)) != 0:
		parts.append("魔法躲避 %+d%%" % int(item.get("magicEvasionPercent", 0)))
	if item.get("attackSpeedTier", null) != null and int(item.get("attackSpeedTier", 0)) != 0:
		parts.append("攻击速度 %+d" % int(item.get("attackSpeedTier", 0)))
	var modifiers: Variant = item.get("modifiers", {})
	if modifiers is Dictionary:
		if float(modifiers.get("criticalChance", 0.0)) != 0.0:
			parts.append("暴击 +%.1f%%" % (float(modifiers.get("criticalChance", 0.0)) * 100.0))
	return "　".join(parts) if not parts.is_empty() else "无额外属性"


func _comparison_text(item: Dictionary, slot: String) -> String:
	if slot.is_empty() or _slot_is_empty(slot):
		return ""
	var current := GameData.get_item_record(str(PlayerState.equipment.get(slot, {}).get("name", "")))
	var delta := _simple_power(item) - _simple_power(current)
	var color := "#65d67d" if delta > 0 else ("#ef6e63" if delta < 0 else "#c9bda8")
	return "\n对比%s：[color=%s]%+d综合基础值[/color]" % [slot, color, delta]


func _simple_power(item: Dictionary) -> int:
	var result := 0
	for key: String in ["attackMin", "attackMax", "magicMin", "magicMax", "taoMin", "taoMax", "defenseMin", "defenseMax", "mdefMin", "mdefMax", "hpBonus", "mpBonus"]:
		if item.get(key, null) != null:
			result += int(item.get(key, 0))
	return result


func _comparison_slot(category: String) -> String:
	var slots := _slots_for_category(category)
	for slot: String in slots:
		if not _slot_is_empty(slot):
			return slot
	return slots[0] if not slots.is_empty() else ""


func _slots_for_category(category: String) -> Array[String]:
	match category:
		"武器": return ["武器"]
		"盔甲": return ["衣服"]
		"衣服": return ["衣服"]
		"头盔": return ["头盔"]
		"项链": return ["项链"]
		"手镯": return ["左手镯", "右手镯"]
		"戒指": return ["左戒指", "右戒指"]
	return []


func _slot_is_empty(slot: String) -> bool:
	var value: Variant = PlayerState.equipment.get(slot, {})
	return not value is Dictionary or value.is_empty()


func _compatibility_equipment_text(slot: String, record: Variant) -> String:
	var name := str(record.get("name", "")) if record is Dictionary else str(record)
	if name.is_empty():
		return "%s：—" % slot
	var text := "%s：%s" % [slot, name]
	if record is Dictionary:
		text += " %d/%d" % [int(record.get("durability", 0)), int(record.get("max_durability", 1))]
		if slot == "武器":
			text += " %s" % EquipmentRulesScript.weapon_luck_label(record)
		var special := EquipmentRulesScript.special_effect_for(GameData.get_item(name))
		if not special.is_empty():
			text += " [%s%s]" % [special.get("label", "特殊效果"), "生效" if int(record.get("durability", 0)) > 0 and bool(special.get("runtime", false)) else "登记"]
	return text


func _equipment_tooltip(slot: String, record: Dictionary) -> String:
	return "%s：%s　耐久%d/%d" % [slot, record.get("name", ""), int(record.get("durability", 0)), int(record.get("max_durability", 1))]


func _kind_label(kind: String) -> String:
	match kind:
		"consumable": return "消耗品"
		"skill_book": return "技能书"
		"scroll": return "卷轴"
		"material": return "材料"
		"quest", "quest_item": return "任务物品"
		_: return "物品"


func _item_texture(record: Dictionary, field: String) -> Texture2D:
	return UIItemTextureCacheScript.texture_for(record, field)


func _set_button_texture(button: Button, texture: Texture2D) -> void:
	var old_icon := button.get_node_or_null("CenteredPixelIcon")
	if old_icon != null:
		old_icon.free()
	button.icon = null
	if texture == null:
		return
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	# The original client inventory art stays at its native 1:1 pixel size.
	# Only its position changes; scaling it to fill the slot makes it look soft.
	var display_size := source_size
	var icon_rect := TextureRect.new()
	icon_rect.name = "CenteredPixelIcon"
	icon_rect.texture = texture
	icon_rect.position = (button.size - display_size) * 0.5
	icon_rect.size = display_size
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon_rect)


func _value(value: Variant) -> String:
	return "—" if value == null else str(value)


func _section_panel(node_name: String, at: Vector2, panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = at + Vector2(0, -SECTION_VERTICAL_SHIFT)
	panel.size = panel_size
	panel.theme_type_variation = "GothicInsetFrame"
	var surface := Panel.new()
	surface.name = "SectionSurface"
	surface.position = Vector2(12, 14)
	surface.size = panel_size - Vector2(24, 28)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	panel.add_child(surface)
	return panel


func _section_title(text_value: String, section_width: float) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = Vector2(14, 10)
	label.size = Vector2(section_width - 28.0, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicSectionTitle"
	return label


func _close() -> void:
	_cancel_long_press()
	context_menu.hide()
	hide()
	closed.emit()
