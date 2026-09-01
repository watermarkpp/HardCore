class_name InventoryPanel
extends Panel

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const PreviewScript = preload("res://scripts/equipment_character_preview.gd")
const GothicUIThemeScript = preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript = preload("res://scripts/gothic_frame_factory.gd")
const UIItemTextureCacheScript = preload("res://scripts/ui_item_texture_cache.gd")
const TouchScrollSupportScript = preload("res://scripts/touch_scroll_support.gd")
const UIRuntimeLayoutOverridesScript = preload("res://scripts/ui_runtime_layout_overrides.gd")

signal closed

const PANEL_SIZE := Vector2(1220, 660)
const MODAL_SURFACE_INSET := Vector4(32, 38, 32, 34)
const SECTION_VERTICAL_SHIFT := 24.0
## Two fewer columns than the former eight-column layout; capacity remains 100.
const BAG_COLUMNS := 6
## Six columns x five 64px rows (with 4px separation) fit the 340px viewport.
const BAG_VISIBLE_CAPACITY := 30
const BAG_CAPACITY := 100
const EQUIPMENT_SLOT_LAYOUT_REVISION := 1
const ITEM_DETAIL_LAYOUT_REVISION := 1
const BAG_CELL_SIZE := Vector2(56, 64)
const BAG_HORIZONTAL_SEPARATION := 1
const BAG_VERTICAL_SEPARATION := 4
## The manually accepted viewport leaves this much breathing room before the
## first cell.  It belongs to the ScrollContainer's existing panel style, not
## to any of the 100 transient cells.
const BAG_VIEWPORT_CONTENT_INSET := Vector2(14, 10)
const RETIRED_CALIBRATION_PATHS := [
	"BagPanel/InventoryGridFrame",
	"BagPanel/InventoryGridFrame/InventoryGridFrameDecoration",
]
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
var selected_inventory_indices: Dictionary = {}
var selected_equipment_slot := ""
var _suppress_next_pressed_index := -1
var auto_sort_button: Button
var discard_button: Button

# Compatibility mirrors retained for save/UI regression tests. The user-facing
# interface uses the ten direct slots and the long-press menu.
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
var _refresh_scheduled := false
var _layout_initialized := false
var _layout_apply_count := 0
var _bag_cells: Array[Control] = []
var _bag_cell_creation_count := 0
var _bag_cell_update_count := 0
var _selection_cell_update_count := 0
var _action_feedback_serial := 0
# Production policy: the long-press context menu is intentionally suppressed.
# The PopupMenu builder/action helpers remain for special items enabled later
# through _context_menu_policy (enabled + optional enabled_kinds whitelist).
var _context_menu_policy: Dictionary = {
	"enabled": CONTEXT_MENU_ENABLED,
	"enabled_kinds": [],
}
var _press_cancelled := false


func _ready() -> void:
	# This source-created frame duplicated the user's calibrated BagPanel frame.
	# Keep both its root and generated decoration retired so an older saved
	# calibration profile cannot bind them if that profile is loaded again.
	set_meta("calibration_retired_paths", RETIRED_CALIBRATION_PATHS.duplicate())
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
	GothicFrameFactoryScript.seal_modal_rings(self)
	visibility_changed.connect(_on_visibility_changed)
	PlayerState.inventory_changed.connect(_on_inventory_data_changed)
	PlayerState.equipment_changed.connect(_on_equipment_data_changed)
	PlayerState.profile_changed.connect(_refresh_character_stats)
	_initialize_bag_cells()
	refresh()


func _build_modal_surface() -> void:
	GothicFrameFactoryScript.add_modal_fill(self, PANEL_SIZE)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(380, 10)
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
	var title := _section_title("人物属性", 250)
	title.name = "AttributeTitle"
	panel.add_child(title)
	equipment_stats_label = RichTextLabel.new()
	equipment_stats_label.name = "CharacterStats"
	equipment_stats_label.set_meta("calibration_runtime_text", true)
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
	item_title.name = "ItemDetailTitle"
	item_title.text = "物品属性"
	item_title.position = Vector2(16, 278)
	item_title.size = Vector2(218, 30)
	item_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_title.theme_type_variation = "GothicSectionTitle"
	panel.add_child(item_title)
	detail_label = RichTextLabel.new()
	detail_label.name = "ItemDetail"
	detail_label.set_meta("calibration_runtime_text", true)
	detail_label.set_meta("calibration_layout_revision", ITEM_DETAIL_LAYOUT_REVISION)
	detail_label.position = Vector2(16, 312)
	detail_label.size = Vector2(218, 204)
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.theme_type_variation = "GothicDetailText"
	panel.add_child(detail_label)


func _build_equipment_panel() -> void:
	var panel := _section_panel("EquipmentPanel", Vector2(294, 72), Vector2(390, 566))
	var title := _section_title("人物装备", 390)
	title.name = "EquipmentTitle"
	panel.add_child(title)
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
		"圣物": Vector2(10, 44), "徽章": Vector2(10, 444),
	}
	for slot: String in PlayerState.EQUIPMENT_SLOTS:
		_create_equipment_slot(panel, slot, positions.get(slot, Vector2.ZERO))
	# Keep the legacy reserved anchor for calibration compatibility.
	var future_row := Control.new()
	future_row.name = "FutureEquipmentRow"
	future_row.position = Vector2(12, 550)
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
	var title := _section_title("综合背包", 492)
	title.name = "BagTitle"
	panel.add_child(title)
	bag_summary_label = Label.new()
	bag_summary_label.name = "BagSummary"
	bag_summary_label.set_meta("calibration_runtime_text", true)
	bag_summary_label.position = Vector2(246, 19)
	bag_summary_label.size = Vector2(218, 26)
	bag_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bag_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bag_summary_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(bag_summary_label)
	var scroll := ScrollContainer.new()
	scroll.name = "InventoryScroll"
	# The shared ScrollContainer theme draws a one-pixel panel border.  This
	# inventory viewport sits flush around the complete six-column grid, so that
	# border reads as an unintended outer grid frame.  Suppress it only here;
	# individual occupied and empty slot button frames remain unchanged.
	var viewport_style := StyleBoxEmpty.new()
	viewport_style.content_margin_left = BAG_VIEWPORT_CONTENT_INSET.x
	viewport_style.content_margin_top = BAG_VIEWPORT_CONTENT_INSET.y
	scroll.add_theme_stylebox_override("panel", viewport_style)
	scroll.position = Vector2(10, 50)
	scroll.size = Vector2(472, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	item_grid = GridContainer.new()
	item_grid.name = "ItemGrid"
	item_grid.columns = BAG_COLUMNS
	item_grid.custom_minimum_size = _bag_grid_minimum_size()
	item_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	item_grid.add_theme_constant_override("h_separation", BAG_HORIZONTAL_SEPARATION)
	item_grid.add_theme_constant_override("v_separation", BAG_VERTICAL_SEPARATION)
	scroll.add_child(item_grid)
	var paging_hint := Label.new()
	paging_hint.name = "BagPagingHint"
	paging_hint.set_meta("calibration_runtime_text", true)
	paging_hint.text = "首屏 1–%d 格　·　拖动右侧滚条查看 %d–%d 格" % [BAG_VISIBLE_CAPACITY, BAG_VISIBLE_CAPACITY + 1, BAG_CAPACITY]
	paging_hint.position = Vector2(18, 402)
	paging_hint.size = Vector2(456, 28)
	paging_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paging_hint.theme_type_variation = "GothicMutedLabel"
	panel.add_child(paging_hint)
	var actions := Control.new()
	actions.name = "InventoryActions"
	actions.position = Vector2(16, 452)
	actions.size = Vector2(460, 48)
	actions.add_theme_constant_override("separation", 10)
	panel.add_child(actions)
	auto_sort_button = Button.new()
	auto_sort_button.name = "AutoSortButton"
	auto_sort_button.text = "自动整理"
	auto_sort_button.position = Vector2(0, 0)
	auto_sort_button.size = Vector2(215, 48)
	auto_sort_button.pressed.connect(_on_auto_sort_pressed)
	auto_sort_button.theme_type_variation = "GothicComponentButton"
	actions.add_child(auto_sort_button)
	discard_button = Button.new()
	discard_button.name = "DiscardButton"
	discard_button.text = "丢弃"
	discard_button.position = Vector2(225, 0)
	discard_button.size = Vector2(215, 48)
	discard_button.pressed.connect(_on_discard_pressed)
	discard_button.theme_type_variation = "GothicComponentButton"
	actions.add_child(discard_button)


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
	holder.size = Vector2(72, 84)
	parent.add_child(holder)
	var button := Button.new()
	button.name = "EquipmentSlot_%s" % slot
	button.position = Vector2(2, 0)
	button.size = Vector2(68, 68)
	button.set_meta("calibration_layout_revision", EQUIPMENT_SLOT_LAYOUT_REVISION)
	holder.set_meta("calibration_layout_revision", EQUIPMENT_SLOT_LAYOUT_REVISION)
	button.expand_icon = true
	button.toggle_mode = true
	button.tooltip_text = "%s：空" % slot
	button.theme_type_variation = "GothicEquipmentSlotButton"
	button.pressed.connect(_select_equipment_slot.bind(slot))
	button.gui_input.connect(_equipment_input.bind(slot, button))
	holder.add_child(button)
	var caption_plate := Panel.new()
	caption_plate.name = "SlotCaptionPlate"
	caption_plate.position = Vector2(6, 64)
	caption_plate.size = Vector2(60, 20)
	caption_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_plate.theme_type_variation = "GothicEquipmentSlotCaption"
	holder.add_child(caption_plate)
	var slot_label := Label.new()
	slot_label.name = "SlotLabel"
	slot_label.text = slot
	slot_label.set_meta("calibration_layout_revision", EQUIPMENT_SLOT_LAYOUT_REVISION)
	slot_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_label.add_theme_font_size_override("font_size", 13)
	slot_label.add_theme_color_override("font_color", Color("e1bd7d"))
	caption_plate.add_child(slot_label)
	equipment_buttons[slot] = button
	equipment_slot_labels[slot] = slot_label


func _on_inventory_data_changed() -> void:
	# PlayerState emits inventory_changed without an index remap contract.  A
	# removal/sort can therefore make the previous numeric selection refer to a
	# different item.  Drop it before rebuilding so details never describe the
	# wrong stack; callers that intentionally select/equip will set the new
	# semantic selection after their mutation completes.
	selected_inventory_index = -1
	selected_inventory_indices.clear()
	if not visible:
		_refresh_pending = true
		return
	_queue_refresh()


func _on_equipment_data_changed() -> void:
	# Durability ticks emit equipment_changed while the player is inspecting a
	# bag item. They do not change inventory indices, so preserve the semantic
	# bag selection and its detail instead of treating the tick as a removal or
	# sort. Equip/unequip mutations also emit inventory_changed and still take
	# the fail-closed path above.
	if not visible:
		_refresh_pending = true
		return
	_queue_refresh()


func _on_visibility_changed() -> void:
	if not visible:
		return
	if _refresh_pending:
		refresh()
	# A panel can be kept alive while HUD toggles it.  Action feedback (for
	# example, "丢弃 1 个物品格") is intentionally transient; a later open must
	# not expose that result as if it were the currently selected item detail.
	if selected_inventory_index < 0 and selected_inventory_indices.is_empty() and selected_equipment_slot.is_empty():
		detail_label.text = "[color=#d9c09a]单击物品查看属性，双击使用或装备。[/color]"


func refresh() -> void:
	if item_grid == null:
		return
	_refresh_pending = false
	_refresh_scheduled = false
	_refresh_execution_count += 1
	_refresh_equipment_slots()
	_refresh_character_stats()
	_refresh_bag_grid()
	if character_preview != null:
		character_preview.refresh()
	if not _layout_initialized:
		_layout_initialized = true
		_layout_apply_count += 1
		UIRuntimeLayoutOverridesScript.apply_profile(self, "inventory")
	_stabilize_bag_layout()


func _queue_refresh() -> void:
	_refresh_pending = true
	if _refresh_scheduled:
		return
	_refresh_scheduled = true
	call_deferred("_flush_queued_refresh")


func _flush_queued_refresh() -> void:
	_refresh_scheduled = false
	if not _refresh_pending or not visible:
		return
	refresh()


func _on_runtime_layout_profile_applied(profile_id: String) -> void:
	if profile_id == "inventory":
		_stabilize_bag_layout()
		call_deferred("_stabilize_bag_layout")


func _stabilize_bag_layout() -> void:
	if item_grid == null or not is_instance_valid(item_grid) or not item_grid.is_inside_tree():
		return
	# GridContainer can inherit an expanded width while the asynchronous runtime
	# calibration profile is settling.  Reassert the complete mathematical
	# contract after every rebuild and again after the profile callback so first
	# open and later refreshes have identical six-column geometry.
	item_grid.columns = BAG_COLUMNS
	item_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	item_grid.custom_minimum_size = _bag_grid_minimum_size()
	item_grid.queue_sort()
	var scroll := get_node_or_null("BagPanel/InventoryScroll") as ScrollContainer
	if scroll != null:
		scroll.queue_redraw()


func _bag_grid_minimum_size() -> Vector2:
	var rows := ceili(float(BAG_CAPACITY) / float(BAG_COLUMNS))
	return Vector2(
		float(BAG_COLUMNS) * BAG_CELL_SIZE.x + float(maxi(BAG_COLUMNS - 1, 0)) * BAG_HORIZONTAL_SEPARATION,
		float(rows) * BAG_CELL_SIZE.y + float(maxi(rows - 1, 0)) * BAG_VERTICAL_SEPARATION
	)


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
	_initialize_bag_cells()
	if selected_inventory_index >= PlayerState.inventory.size() or _inventory_record(selected_inventory_index).is_empty():
		selected_inventory_index = -1
	var stale_selection_indices: Array = []
	for selected_index: Variant in selected_inventory_indices.keys():
		if _inventory_record(int(selected_index)).is_empty():
			stale_selection_indices.append(selected_index)
	for selected_index: Variant in stale_selection_indices:
		selected_inventory_indices.erase(selected_index)
	for inventory_index in range(BAG_CAPACITY):
		_update_bag_cell(inventory_index, _inventory_record(inventory_index))
	_stabilize_bag_layout()
	bag_summary_label.text = "金币 %d　%d/%d格" % [PlayerState.gold, PlayerState.inventory_occupied_count(), BAG_CAPACITY]
	if selected_inventory_index >= 0:
		_show_inventory_detail(selected_inventory_index)
	elif selected_equipment_slot.is_empty():
		detail_label.text = "[color=#d9c09a]单击物品查看属性，双击使用或装备。[/color]"


func _initialize_bag_cells() -> void:
	if not _bag_cells.is_empty():
		return
	for index in range(BAG_CAPACITY):
		var cell := _create_bag_cell(index, {})
		item_grid.add_child(cell)
		_bag_cells.append(cell)
		_bag_cell_creation_count += 1


func _create_bag_cell(index: int, stack: Dictionary) -> Control:
	var cell := Control.new()
	cell.name = "InventoryCell_%03d" % index
	cell.custom_minimum_size = BAG_CELL_SIZE
	var button := Button.new()
	button.name = "EmptySlotBackground"
	button.position = Vector2.ZERO
	button.size = BAG_CELL_SIZE
	button.tooltip_text = "空物品格"
	button.disabled = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.theme_type_variation = "GothicComponentSlotButton"
	button.pressed.connect(_select_inventory_item.bind(index))
	button.gui_input.connect(_inventory_input.bind(index, button))
	cell.add_child(button)
	var count_label := Label.new()
	count_label.name = "StackCount"
	count_label.position = Vector2(BAG_CELL_SIZE.x - 34, BAG_CELL_SIZE.y - 23)
	count_label.size = Vector2(30, 20)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.add_theme_color_override("font_color", Color.WHITE)
	count_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	count_label.add_theme_constant_override("shadow_offset_x", 2)
	count_label.add_theme_constant_override("shadow_offset_y", 2)
	count_label.hide()
	cell.add_child(count_label)
	var durability_label := Label.new()
	durability_label.name = "Durability"
	durability_label.position = Vector2(3, BAG_CELL_SIZE.y - 19)
	durability_label.size = Vector2(BAG_CELL_SIZE.x - 6, 16)
	durability_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	durability_label.add_theme_font_size_override("font_size", 10)
	durability_label.add_theme_color_override("font_color", Color(0.96, 0.83, 0.52))
	durability_label.hide()
	cell.add_child(durability_label)
	return cell


func _update_bag_cell(index: int, stack: Dictionary) -> void:
	if index < 0 or index >= _bag_cells.size():
		return
	_bag_cell_update_count += 1
	var cell := _bag_cells[index]
	var button := cell.get_child(0) as Button
	var occupied := not stack.is_empty()
	button.name = "ItemButton" if occupied else "EmptySlotBackground"
	button.disabled = not occupied
	button.mouse_filter = Control.MOUSE_FILTER_STOP if occupied else Control.MOUSE_FILTER_IGNORE
	button.tooltip_text = str(stack.get("name", "未知物品")) if occupied else "空物品格"
	button.theme_type_variation = "GothicComponentSelectedSlotButton" if occupied and selected_inventory_indices.has(index) else "GothicComponentSlotButton"
	_set_button_texture(button, _item_texture(GameData.get_item_record(str(stack.get("name", ""))), "inventoryIcon") if occupied else null)
	var count_label := cell.get_node("StackCount") as Label
	var count := int(stack.get("count", 1))
	count_label.text = str(count)
	count_label.visible = occupied and count > 1
	var durability_label := cell.get_node("Durability") as Label
	durability_label.text = "%d/%d" % [int(stack.get("durability", 0)), int(stack.get("max_durability", 1))]
	durability_label.visible = occupied and stack.has("durability")


func _inventory_record(index: int) -> Dictionary:
	if index < 0 or index >= PlayerState.inventory.size():
		return {}
	var record: Variant = PlayerState.inventory[index]
	return record if record is Dictionary and not (record as Dictionary).is_empty() else {}


func _select_inventory_item(index: int) -> void:
	if _press_cancelled or TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	if _inventory_record(index).is_empty():
		return
	if _suppress_next_pressed_index == index:
		_suppress_next_pressed_index = -1
		return
	var old_selected_index := selected_inventory_index
	if selected_inventory_indices.has(index):
		selected_inventory_indices.erase(index)
	else:
		selected_inventory_indices[index] = true
	selected_inventory_index = index if selected_inventory_indices.has(index) else (-1 if selected_inventory_indices.is_empty() else int(selected_inventory_indices.keys().back()))
	selected_equipment_slot = ""
	if selected_inventory_index >= 0:
		_show_inventory_detail(selected_inventory_index)
	else:
		detail_label.text = "[color=#d9c09a]单击物品查看属性，双击使用或装备。[/color]"
	_refresh_equipment_slots()
	for cell_index: int in [old_selected_index, index]:
		_refresh_bag_cell_selection(cell_index)


func _refresh_bag_cell_selection(index: int) -> void:
	if index < 0 or index >= _bag_cells.size():
		return
	_selection_cell_update_count += 1
	var button := (_bag_cells[index] as Control).get_child(0) as Button
	button.theme_type_variation = "GothicComponentSelectedSlotButton" if selected_inventory_indices.has(index) else "GothicComponentSlotButton"


func _clear_inventory_selection_styles() -> void:
	var changed_indices: Array = selected_inventory_indices.keys()
	if selected_inventory_index >= 0 and not changed_indices.has(selected_inventory_index):
		changed_indices.append(selected_inventory_index)
	selected_inventory_index = -1
	selected_inventory_indices.clear()
	for raw_index: Variant in changed_indices:
		_refresh_bag_cell_selection(int(raw_index))


func _select_equipment_slot(slot: String) -> void:
	if _press_cancelled or TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	if selected_inventory_index >= 0 and not _inventory_record(selected_inventory_index).is_empty():
		var item := GameData.get_item_record(str(_inventory_record(selected_inventory_index).get("name", "")))
		if str(item.get("kind", "")) == "equipment":
			var allowed: Array = _slots_for_category(str(item.get("category", "")))
			if not allowed.has(slot):
				detail_label.text = "[color=#d96f5f]该装备不能放入此槽位。[/color]"
				return
			var result := PlayerState.equip_inventory_index(selected_inventory_index, slot)
			selected_equipment_slot = slot
			selected_inventory_index = -1
			selected_inventory_indices.clear()
			refresh()
			detail_label.text = "[color=#e8c277]%s[/color]" % result
			return
	selected_equipment_slot = slot
	_clear_inventory_selection_styles()
	var equipped: Variant = PlayerState.equipment.get(slot, {})
	if equipped is Dictionary and not equipped.is_empty():
		detail_label.text = _equipment_detail(slot, equipped)
	else:
		detail_label.text = "[color=#e0bd83][font_size=18]%s[/font_size][/color]\n当前为空。按住背包中的对应装备可选择穿戴位置。" % slot
	_refresh_equipment_slots()


func _show_inventory_detail(index: int) -> void:
	var stack := _inventory_record(index)
	if stack.is_empty():
		return
	var item := GameData.get_item_record(str(stack.get("name", "")))
	if item.is_empty():
		detail_label.text = "[color=#f2c783]%s[/color]\n物品目录缺少此记录。" % stack.get("name", "未知物品")
		return
	if str(item.get("kind", "")) == "equipment":
		detail_label.text = _item_equipment_detail(stack, item)
	else:
		detail_label.text = "[color=#f2c783][font_size=18]%s[/font_size][/color]\n类别：%s\n数量：%d\n%s" % [stack.get("name", ""), _kind_label(str(item.get("kind", ""))), int(stack.get("count", 1)), str(item.get("description", ""))]


func _inventory_input(event: InputEvent, index: int, button: Button) -> void:
	var stack := _inventory_record(index)
	if stack.is_empty():
		return
	if _is_double_activation_event(event):
		_cancel_long_press()
		selected_inventory_indices.clear()
		var item := GameData.get_item_record(str(stack.get("name", "")))
		if str(item.get("kind", "")) == "equipment":
			_select_inventory_item(index)
			# Button.pressed follows gui_input for the same physical gesture.  Keep
			# the explicit equipment selection, then suppress its duplicate toggle.
			_suppress_next_pressed_index = index
		else:
			# Consumable activation rebuilds the grid synchronously; suppress the
			# pressed callback that still belongs to the original gesture.
			_suppress_next_pressed_index = index
			_activate_inventory_index(index)
		_clear_pressed_suppression.call_deferred(index)
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
			if not _inventory_record(index).is_empty():
				item_name = str(_inventory_record(index).get("name", ""))
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
		if not _inventory_record(index).is_empty():
			_add_inventory_context_actions(index)
	if context_menu.item_count == 0:
		_add_context_action("无可用操作", {"action": "none"}, true)
	var popup_position := _press_button.get_screen_position() + _press_button.size * 0.5
	context_menu.position = Vector2i(popup_position)
	context_menu.popup()


func _add_inventory_context_actions(index: int) -> void:
	var stack := _inventory_record(index)
	if stack.is_empty():
		return
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
	selected_inventory_indices.clear()
	selected_equipment_slot = ""
	refresh()
	detail_label.text = "[color=#e8c277]%s[/color]" % result


# Direct action helpers remain available for automated tests and accessibility.
func _activate_selected_item(preferred_slot := "") -> void:
	if _inventory_record(selected_inventory_index).is_empty():
		return
	_activate_inventory_index(selected_inventory_index, preferred_slot)


func _activate_inventory_index(index: int, preferred_slot := "") -> void:
	# preferred_slot stays empty for direct double-click activation: PlayerState
	# is the authoritative equipment-slot resolver, so the UI never hardcodes a side.
	var stack := _inventory_record(index)
	if stack.is_empty():
		return
	_cancel_long_press()
	selected_inventory_index = index
	selected_inventory_indices.clear()
	selected_equipment_slot = ""
	var item := GameData.get_item_record(str(stack.get("name", "")))
	var is_equipment := str(item.get("kind", "")) == "equipment"
	# use_inventory_index emits inventory_changed synchronously.  Clear the
	# selection before that signal so a consumed stack removal cannot make the
	# signal-driven refresh show the next item under the old index.
	if not is_equipment:
		selected_inventory_index = -1
		selected_inventory_indices.clear()
	var result := PlayerState.equip_inventory_index(index, preferred_slot) if is_equipment else PlayerState.use_inventory_index(index)
	selected_inventory_index = -1
	refresh()
	detail_label.text = "[color=#e8c277]%s[/color]" % result


func _clear_pressed_suppression(index: int) -> void:
	if _suppress_next_pressed_index == index:
		_suppress_next_pressed_index = -1


func _on_auto_sort_pressed() -> void:
	_clear_inventory_action_feedback()
	GothicUIThemeScript.set_button_feedback(auto_sort_button, GothicUIThemeScript.BUTTON_FEEDBACK_BUSY, "inventory.sort")
	var result: Dictionary = PlayerState.sort_inventory_deterministic()
	selected_inventory_indices.clear()
	selected_inventory_index = -1
	refresh()
	detail_label.text = "[color=#e8c277]自动整理%s[/color]" % ("完成" if bool(result.get("success", false)) else "失败")
	_show_inventory_action_result(auto_sort_button, bool(result.get("success", false)), "inventory.sort")


func _on_discard_pressed() -> void:
	var indices: Array = selected_inventory_indices.keys()
	_clear_inventory_action_feedback()
	GothicUIThemeScript.set_button_feedback(discard_button, GothicUIThemeScript.BUTTON_FEEDBACK_BUSY, "inventory.discard")
	var result: Dictionary = PlayerState.destroy_inventory_indices(indices)
	selected_inventory_indices.clear()
	selected_inventory_index = -1
	refresh()
	detail_label.text = "[color=#e8c277]丢弃 %d 个物品格[/color]" % int(result.get("destroyed", 0))
	_show_inventory_action_result(discard_button, int(result.get("destroyed", 0)) > 0, "inventory.discard")


func _show_inventory_action_result(button: Button, success: bool, group: String) -> void:
	_action_feedback_serial += 1
	var serial := _action_feedback_serial
	GothicUIThemeScript.set_button_feedback(
		button,
		GothicUIThemeScript.BUTTON_FEEDBACK_SUCCESS if success else GothicUIThemeScript.BUTTON_FEEDBACK_FAILURE,
		group,
	)
	get_tree().create_timer(1.0 if success else 0.45).timeout.connect(func() -> void:
		if serial == _action_feedback_serial and is_instance_valid(button) and button.is_inside_tree():
			GothicUIThemeScript.clear_button_feedback(button)
	)


func _clear_inventory_action_feedback() -> void:
	_action_feedback_serial += 1
	GothicUIThemeScript.clear_button_feedback(auto_sort_button)
	GothicUIThemeScript.clear_button_feedback(discard_button)


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
	return "[color=#f2c783][font_size=18]%s[/font_size][/color]\n%s　重量 %d\n耐久 %d/%d\n%s\n%s\n穿戴要求：%s" % [
		stack.get("name", ""), category, int(item.get("weight", 0)), current_durability, maximum_durability,
		_stat_line(item), _advanced_stat_line(item), _player_requirement_label(item),
	]


func _player_requirement_label(item: Dictionary) -> String:
	var requirement := EquipmentRulesScript.requirement_for(item)
	var labels := {
		EquipmentRulesScript.NEED_LEVEL: "等级",
		EquipmentRulesScript.NEED_ATTACK: "攻击",
		EquipmentRulesScript.NEED_MAGIC: "魔法",
		EquipmentRulesScript.NEED_TAO: "道术",
	}
	var need_type := int(requirement.get("type", EquipmentRulesScript.NEED_LEVEL))
	return "%s%d" % [str(labels.get(need_type, "特殊条件")), maxi(0, int(requirement.get("value", 0)))]


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


func _slots_for_category(category: String) -> Array[String]:
	match category:
		"武器": return ["武器"]
		"盔甲": return ["衣服"]
		"衣服": return ["衣服"]
		"头盔": return ["头盔"]
		"项链": return ["项链"]
		"手镯": return ["左手镯", "右手镯"]
		"戒指": return ["左戒指", "右戒指"]
		"圣物": return ["圣物"]
		"徽章": return ["徽章"]
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
	button.icon = null
	var icon_rect := button.get_node_or_null("CenteredPixelIcon") as TextureRect
	if texture == null:
		if icon_rect != null:
			icon_rect.texture = null
			icon_rect.hide()
		return
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	# The original client inventory art stays at its native 1:1 pixel size.
	# Only its position changes; scaling it to fill the slot makes it look soft.
	var display_size := source_size
	if icon_rect == null:
		icon_rect = TextureRect.new()
		icon_rect.name = "CenteredPixelIcon"
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon_rect)
	icon_rect.texture = texture
	icon_rect.position = (button.size - display_size) * 0.5
	icon_rect.size = display_size
	icon_rect.show()


func _value(value: Variant) -> String:
	return "—" if value == null else str(value)


func _section_panel(node_name: String, at: Vector2, panel_size: Vector2) -> Control:
	var rect := Rect2(at + Vector2(0, -SECTION_VERTICAL_SHIFT), panel_size)
	return GothicFrameFactoryScript.add_filled_section(self, node_name, rect)


func _section_title(text_value: String, section_width: float) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = Vector2(14, 10)
	label.size = Vector2(section_width - 28.0, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicSectionTitle"
	return label


func _close() -> void:
	_clear_inventory_action_feedback()
	_cancel_long_press()
	context_menu.hide()
	hide()
	closed.emit()
