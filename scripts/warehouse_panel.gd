class_name WarehousePanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")

signal closed
signal warehouse_sort_requested

const PANEL_SIZE := Vector2(1164, 660)
const BAG_CAPACITY := 100
const WAREHOUSE_PAGE_CAPACITY := 100
const WAREHOUSE_PAGE_COUNT := 5
const WAREHOUSE_DISPLAY_CAPACITY := WAREHOUSE_PAGE_CAPACITY * WAREHOUSE_PAGE_COUNT
const GRID_COLUMNS := 8
const GRID_VISIBLE_SLOTS := 40
const ITEM_CELL_SIZE := Vector2(56, 64)

var bag_list: ItemList
var stash_list: ItemList
var bag_grid: GridContainer
var stash_grid: GridContainer
var bag_summary_label: Label
var stash_summary_label: Label
var transfer_detail_label: Label
var warehouse_page_label: Label
var previous_page_button: Button
var next_page_button: Button
var deposit_button: Button
var withdraw_button: Button
var selected_bag_index := -1
var selected_stash_index := -1
var warehouse_page := 0
var _refresh_pending := false
var _refresh_execution_count := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_bottom = PANEL_SIZE.y * 0.5
	z_index = 55
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GothicUIThemeScript.build()
	theme_type_variation = "GothicModalFrame"
	_build_modal_surface()
	_build_header()
	_build_storage_sections()
	_build_compatibility_lists()
	visibility_changed.connect(_on_visibility_changed)
	PlayerState.inventory_changed.connect(_on_inventory_changed)
	refresh()


func _build_modal_surface() -> void:
	var surface := Panel.new()
	surface.name = "ModalSurface"
	surface.position = Vector2(18, 24)
	surface.size = Vector2(1128, 616)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(352, 4)
	title_frame.size = Vector2(460, 64)
	title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_frame.theme_type_variation = "GothicTitleBar"
	add_child(title_frame)
	var title := Label.new()
	title.name = "Title"
	title.text = "仓库"
	title.position = Vector2(30, 15)
	title.size = Vector2(400, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f1cc88"))
	title_frame.add_child(title)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.position = Vector2(1084, 8)
	close_button.size = Vector2(56, 56)
	close_button.theme_type_variation = "GothicComponentCloseButton"
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(_close)
	add_child(close_button)


func _build_storage_sections() -> void:
	var stash_panel := _section_panel("StashSection", Rect2(20, 72, 492, 566))
	stash_panel.add_child(_section_title("个人仓库", 492))
	stash_grid = _build_item_grid(stash_panel, "StashScroll", "StashGrid")
	stash_panel.add_child(_paging_hint("StashPagingHint", "每页 100 格　·　下拉查看本页后 60 格"))
	_build_page_controls(stash_panel)
	stash_summary_label = _summary_label("StashSummary")
	stash_panel.add_child(stash_summary_label)

	var transfer_panel := _section_panel("TransferSection", Rect2(520, 72, 124, 566))
	transfer_panel.add_child(_section_title("转移", 124))
	transfer_detail_label = Label.new()
	transfer_detail_label.name = "TransferDetail"
	transfer_detail_label.text = "选择两侧物品"
	transfer_detail_label.position = Vector2(12, 82)
	transfer_detail_label.size = Vector2(100, 62)
	transfer_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transfer_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	transfer_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	transfer_detail_label.theme_type_variation = "GothicMutedLabel"
	transfer_panel.add_child(transfer_detail_label)
	deposit_button = _transfer_button("DepositButton", "← 存入", Vector2(14, 160))
	deposit_button.pressed.connect(_deposit)
	transfer_panel.add_child(deposit_button)
	withdraw_button = _transfer_button("WithdrawButton", "取出 →", Vector2(14, 250))
	withdraw_button.pressed.connect(_withdraw)
	transfer_panel.add_child(withdraw_button)
	var divider := HSeparator.new()
	divider.position = Vector2(16, 346)
	divider.size = Vector2(92, 8)
	transfer_panel.add_child(divider)
	var sort_button := _transfer_button("SortStashButton", "整理", Vector2(14, 382))
	sort_button.tooltip_text = "请求玩法层按既定规则整理仓库"
	sort_button.pressed.connect(func() -> void: warehouse_sort_requested.emit())
	transfer_panel.add_child(sort_button)

	var bag_panel := _section_panel("BagSection", Rect2(652, 72, 492, 566))
	bag_panel.add_child(_section_title("人物背包", 492))
	bag_grid = _build_item_grid(bag_panel, "BagScroll", "BagGrid")
	bag_panel.add_child(_paging_hint("BagPagingHint", "首屏 40 格　·　下拉查看 41–100 格"))
	bag_summary_label = _summary_label("BagSummary")
	bag_panel.add_child(bag_summary_label)


func _build_item_grid(parent: Panel, scroll_name: String, grid_name: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = scroll_name
	scroll.position = Vector2(10, 50)
	scroll.size = Vector2(472, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = grid_name
	grid.columns = GRID_COLUMNS
	grid.custom_minimum_size = Vector2(455, 0)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	return grid


func _paging_hint(node_name: String, text_value: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.position = Vector2(18, 402)
	label.size = Vector2(456, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicMutedLabel"
	return label


func _build_page_controls(parent: Panel) -> void:
	previous_page_button = Button.new()
	previous_page_button.name = "PreviousPageButton"
	previous_page_button.text = "‹"
	previous_page_button.position = Vector2(70, 430)
	previous_page_button.size = Vector2(96, 70)
	previous_page_button.theme_type_variation = "GothicComponentButton"
	previous_page_button.add_theme_font_size_override("font_size", 24)
	previous_page_button.pressed.connect(_change_warehouse_page.bind(-1))
	parent.add_child(previous_page_button)
	warehouse_page_label = Label.new()
	warehouse_page_label.name = "WarehousePageLabel"
	warehouse_page_label.position = Vector2(176, 430)
	warehouse_page_label.size = Vector2(140, 70)
	warehouse_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warehouse_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warehouse_page_label.theme_type_variation = "GothicSectionTitle"
	parent.add_child(warehouse_page_label)
	next_page_button = Button.new()
	next_page_button.name = "NextPageButton"
	next_page_button.text = "›"
	next_page_button.position = Vector2(326, 430)
	next_page_button.size = Vector2(96, 70)
	next_page_button.theme_type_variation = "GothicComponentButton"
	next_page_button.add_theme_font_size_override("font_size", 24)
	next_page_button.pressed.connect(_change_warehouse_page.bind(1))
	parent.add_child(next_page_button)


func _summary_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = Vector2(18, 506)
	label.size = Vector2(456, 34)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicMutedLabel"
	return label


func _transfer_button(node_name: String, label_text: String, position_value: Vector2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label_text
	button.position = position_value
	button.size = Vector2(96, 70)
	button.theme_type_variation = "GothicComponentButton"
	button.add_theme_font_size_override("font_size", 17)
	return button


func _build_compatibility_lists() -> void:
	bag_list = ItemList.new()
	bag_list.name = "CompatibilityBagList"
	bag_list.visible = false
	add_child(bag_list)
	stash_list = ItemList.new()
	stash_list.name = "CompatibilityStashList"
	stash_list.visible = false
	add_child(stash_list)


func open_panel() -> void:
	refresh()
	show()


func _on_inventory_changed() -> void:
	if not visible:
		_refresh_pending = true
		return
	refresh()


func _on_visibility_changed() -> void:
	if visible and _refresh_pending:
		refresh()


func refresh() -> void:
	if bag_grid == null or stash_grid == null:
		return
	_refresh_pending = false
	_refresh_execution_count += 1
	if selected_bag_index >= PlayerState.inventory.size():
		selected_bag_index = -1
	if _warehouse_record(selected_stash_index).is_empty():
		selected_stash_index = -1
	_fill_compatibility_list(bag_list, PlayerState.inventory, selected_bag_index)
	_fill_compatibility_list(stash_list, PlayerState.warehouse_inventory, selected_stash_index)
	_fill_grid(bag_grid, PlayerState.inventory, 0, BAG_CAPACITY, "bag", selected_bag_index)
	var page_start := warehouse_page * WAREHOUSE_PAGE_CAPACITY
	_fill_grid(
		stash_grid,
		PlayerState.warehouse_inventory,
		page_start,
		WAREHOUSE_PAGE_CAPACITY,
		"stash",
		selected_stash_index
	)
	bag_summary_label.text = "背包占用　%d/%d 格" % [PlayerState.inventory.size(), BAG_CAPACITY]
	stash_summary_label.text = "仓库占用　%d/%d 格" % [_warehouse_occupied_count(), WAREHOUSE_DISPLAY_CAPACITY]
	warehouse_page_label.text = "第 %d/%d 页" % [warehouse_page + 1, WAREHOUSE_PAGE_COUNT]
	previous_page_button.disabled = warehouse_page <= 0
	next_page_button.disabled = warehouse_page >= WAREHOUSE_PAGE_COUNT - 1
	deposit_button.disabled = selected_bag_index < 0 or _first_free_slot_on_current_page() < 0
	withdraw_button.disabled = selected_stash_index < 0
	_refresh_transfer_detail()


func _fill_grid(
	grid: GridContainer,
	records: Array,
	start_index: int,
	slot_count: int,
	side: String,
	selected_index: int
) -> void:
	for child: Node in grid.get_children():
		child.free()
	for display_index in range(slot_count):
		var data_index := start_index + display_index
		var record: Dictionary = records[data_index] if data_index < records.size() and records[data_index] is Dictionary else {}
		grid.add_child(_create_item_cell(side, data_index, display_index, record, data_index == selected_index))


func _create_item_cell(
	side: String,
	data_index: int,
	display_index: int,
	record: Dictionary,
	selected: bool
) -> Control:
	var cell := Control.new()
	cell.name = "%sCell_%d" % [side.capitalize(), display_index]
	cell.custom_minimum_size = ITEM_CELL_SIZE
	var button := Button.new()
	button.name = "ItemButton"
	button.position = Vector2.ZERO
	button.size = ITEM_CELL_SIZE
	button.theme_type_variation = "GothicComponentSelectedSlotButton" if selected else "GothicComponentSlotButton"
	button.disabled = record.is_empty()
	button.tooltip_text = str(record.get("name", "空物品格"))
	if record.is_empty():
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		button.pressed.connect(_select_item.bind(side, data_index))
	cell.add_child(button)
	_set_button_texture(button, _item_texture(record))
	var count := int(record.get("count", 1))
	if not record.is_empty() and count > 1:
		var count_label := Label.new()
		count_label.name = "StackCount"
		count_label.text = str(count)
		count_label.position = Vector2(30, 41)
		count_label.size = Vector2(22, 19)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.add_theme_font_size_override("font_size", 14)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		count_label.add_theme_constant_override("shadow_offset_x", 2)
		count_label.add_theme_constant_override("shadow_offset_y", 2)
		cell.add_child(count_label)
	return cell


func _select_item(side: String, index: int) -> void:
	if side == "bag":
		selected_bag_index = index
		selected_stash_index = -1
	else:
		selected_stash_index = index
		selected_bag_index = -1
	refresh()


func _change_warehouse_page(delta: int) -> void:
	warehouse_page = clampi(warehouse_page + delta, 0, WAREHOUSE_PAGE_COUNT - 1)
	selected_stash_index = -1
	refresh()


func _refresh_transfer_detail() -> void:
	if selected_bag_index >= 0:
		transfer_detail_label.text = str(PlayerState.inventory[selected_bag_index].get("name", "未知物品"))
	elif selected_stash_index >= 0:
		transfer_detail_label.text = str(_warehouse_record(selected_stash_index).get("name", "未知物品"))
	elif _first_free_slot_on_current_page() < 0:
		transfer_detail_label.text = "当前页已满"
	else:
		transfer_detail_label.text = "选择两侧物品"


func _fill_compatibility_list(list: ItemList, records: Array, selected_index: int) -> void:
	list.clear()
	for record: Variant in records:
		list.add_item(str(record.get("name", "未知物品")) if record is Dictionary else str(record))
	if selected_index >= 0:
		list.select(selected_index)


func _deposit() -> void:
	var target_slot := _first_free_slot_on_current_page()
	if selected_bag_index < 0 or selected_bag_index >= PlayerState.inventory.size() or target_slot < 0:
		return
	_ensure_warehouse_slot(target_slot)
	PlayerState.warehouse_inventory[target_slot] = PlayerState.inventory.pop_at(selected_bag_index)
	selected_bag_index = -1
	PlayerState.inventory_changed.emit()
	PlayerState.save_game()
	refresh()


func _withdraw() -> void:
	if not _warehouse_slot_has_item(selected_stash_index):
		return
	PlayerState.inventory.append(PlayerState.warehouse_inventory[selected_stash_index])
	PlayerState.warehouse_inventory[selected_stash_index] = {}
	_trim_empty_warehouse_tail()
	selected_stash_index = -1
	PlayerState.inventory_changed.emit()
	PlayerState.save_game()
	refresh()


func _warehouse_record(slot_index: int) -> Dictionary:
	if not _warehouse_slot_has_item(slot_index):
		return {}
	var value: Variant = PlayerState.warehouse_inventory[slot_index]
	return value if value is Dictionary else {"name": str(value)}


func _warehouse_slot_has_item(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= PlayerState.warehouse_inventory.size():
		return false
	var value: Variant = PlayerState.warehouse_inventory[slot_index]
	if value is Dictionary:
		return not value.is_empty()
	return value != null and not str(value).is_empty()


func _warehouse_occupied_count() -> int:
	var count := 0
	for slot_index in range(PlayerState.warehouse_inventory.size()):
		if _warehouse_slot_has_item(slot_index):
			count += 1
	return count


func _first_free_slot_on_current_page() -> int:
	var page_start := warehouse_page * WAREHOUSE_PAGE_CAPACITY
	for slot_index in range(page_start, page_start + WAREHOUSE_PAGE_CAPACITY):
		if not _warehouse_slot_has_item(slot_index):
			return slot_index
	return -1


func _ensure_warehouse_slot(slot_index: int) -> void:
	while PlayerState.warehouse_inventory.size() <= slot_index:
		PlayerState.warehouse_inventory.append({})


func _trim_empty_warehouse_tail() -> void:
	while (
		not PlayerState.warehouse_inventory.is_empty()
		and not _warehouse_slot_has_item(PlayerState.warehouse_inventory.size() - 1)
	):
		PlayerState.warehouse_inventory.pop_back()


func _item_texture(record: Dictionary) -> Texture2D:
	if record.is_empty():
		return null
	return UIItemTextureCacheScript.texture_for(
		GameData.get_item_record(str(record.get("name", ""))), "inventoryIcon"
	)


func _set_button_texture(button: Button, texture: Texture2D) -> void:
	if texture == null:
		return
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var icon_rect := TextureRect.new()
	icon_rect.name = "CenteredPixelIcon"
	icon_rect.texture = texture
	icon_rect.position = (button.size - source_size) * 0.5
	icon_rect.size = source_size
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon_rect)


func _section_panel(node_name: String, rect: Rect2) -> Panel:
	var surface := Panel.new()
	surface.name = "%sSurface" % node_name
	surface.position = rect.position
	surface.size = rect.size
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)
	var panel := Panel.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.theme_type_variation = "GothicInsetFrame"
	add_child(panel)
	return panel


func _section_title(text_value: String, width: float) -> Label:
	var title := Label.new()
	title.text = text_value
	title.position = Vector2(18, 16)
	title.size = Vector2(width - 36.0, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.theme_type_variation = "GothicSectionTitle"
	return title


func _close() -> void:
	hide()
	closed.emit()
