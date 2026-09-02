class_name WarehousePanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const TouchScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")
const UIRuntimeLayoutOverridesScript := preload("res://scripts/ui_runtime_layout_overrides.gd")
const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")

signal closed
signal warehouse_sort_requested

const PANEL_SIZE := Vector2(1164, 660)
const MODAL_SURFACE_INSET := Vector4(32, 38, 32, 34)
const SECTION_VERTICAL_SHIFT := 24.0
const BAG_CAPACITY := 100
const WAREHOUSE_PAGE_CAPACITY := 100
const WAREHOUSE_PAGE_COUNT := 5
const WAREHOUSE_DISPLAY_CAPACITY := WAREHOUSE_PAGE_CAPACITY * WAREHOUSE_PAGE_COUNT
const GRID_COLUMNS := 6
const GRID_VISIBLE_SLOTS := 30
const GRID_BACKGROUND_CELL_BATCH := 10
const ITEM_CELL_SIZE := Vector2(56, 64)
const GRID_HORIZONTAL_SEPARATION := 1.0
const GRID_VERTICAL_SEPARATION := 4.0
const GRID_ROWS := int(ceil(float(WAREHOUSE_PAGE_CAPACITY) / float(GRID_COLUMNS)))
const GRID_MINIMUM_SIZE := Vector2(
	ITEM_CELL_SIZE.x * GRID_COLUMNS + GRID_HORIZONTAL_SEPARATION * (GRID_COLUMNS - 1),
	ITEM_CELL_SIZE.y * GRID_ROWS + GRID_VERTICAL_SEPARATION * (GRID_ROWS - 1)
)
const GRID_FRAME_RECT := Rect2(6, 40, 480, 392)
const GRID_CONTENT_WIDTH := GRID_MINIMUM_SIZE.x
## The viewport is the exact six-column content width plus the visible vertical
## scrollbar.  Keeping this mathematical contract prevents saved 477px
## calibration rectangles from exposing a seventh/partial column.
const GRID_SCROLLBAR_WIDTH := 16.0
const GRID_SCROLL_WIDTH := GRID_CONTENT_WIDTH + GRID_SCROLLBAR_WIDTH
const GRID_SCROLL_RECT := Rect2((492.0 - GRID_SCROLL_WIDTH) * 0.5, 66, GRID_SCROLL_WIDTH, 340)
const THIN_BUTTON_HEIGHT := 48.0
const LAYOUT_REVISION := 3

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
var sort_button: Button
var selected_bag_indices: Dictionary = {}
var selected_stash_indices: Dictionary = {}
# Keep the scalar fields as the focused/last-selected compatibility view. The
# dictionaries above are the authoritative transfer selection.
var selected_bag_index := -1
var selected_stash_index := -1
var warehouse_page := 0
var _refresh_pending := false
var _refresh_execution_count := 0
var _refresh_scheduled := false
var _layout_initialized := false
var _layout_apply_count := 0
var _bag_cells: Array[Control] = []
var _stash_cells: Array[Control] = []
var _grid_cell_creation_count := 0
var _grid_cells_ready := false
var _grid_cell_initialization_running := false
var _action_feedback_serial := 0
var _active_selection_side := ""
var _last_transfer_batch_result: Dictionary = {}


func _ready() -> void:
	set_meta("calibration_retired_paths", [
		"StashSection/StashSectionDecoration",
		"StashSection/StashSectionDecoration/StashSectionFill",
		"StashSection/StashSectionDecoration/StashSectionFrame",
		"TransferSection/TransferSectionDecoration",
		"TransferSection/TransferSectionDecoration/TransferSectionFill",
		"TransferSection/TransferSectionDecoration/TransferSectionFrame",
		"BagSection/BagSectionDecoration",
		"BagSection/BagSectionDecoration/BagSectionFill",
		"BagSection/BagSectionDecoration/BagSectionFrame",
	])
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
	GothicFrameFactoryScript.seal_modal_rings(self)
	visibility_changed.connect(_on_visibility_changed)
	PlayerState.inventory_changed.connect(_on_inventory_changed)
	_initialize_grid_cells(GRID_VISIBLE_SLOTS)
	refresh()
	_continue_grid_cell_initialization.call_deferred()


func _build_modal_surface() -> void:
	GothicFrameFactoryScript.add_modal_fill(self, PANEL_SIZE)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(352, 10)
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
	var stash_frame := GothicFrameFactoryScript.add_filled_section(stash_panel, "StashGridV3Frame", GRID_FRAME_RECT)
	stash_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stash_frame.set_meta("calibration_layer", "warehouse_stash_grid_decoration")
	stash_panel.add_child(_section_title("StashTitle", "个人仓库", 492))
	stash_grid = _build_item_grid(stash_panel, "StashScroll", "StashGrid")
	stash_panel.add_child(_paging_hint("StashPagingHint", "每页 100 格　·　下拉查看本页后 70 格"))
	_build_page_controls(stash_panel)
	stash_summary_label = _summary_label("StashSummary")
	stash_panel.add_child(stash_summary_label)

	var transfer_panel := _section_panel("TransferSection", Rect2(520, 72, 124, 566))
	transfer_panel.add_child(_section_title("TransferTitle", "转移", 124))
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
	sort_button = _transfer_button("SortStashButton", "整理", Vector2(14, 382))
	sort_button.tooltip_text = "请求玩法层按既定规则整理仓库"
	sort_button.pressed.connect(_sort_requested)
	transfer_panel.add_child(sort_button)

	var bag_panel := _section_panel("BagSection", Rect2(652, 72, 492, 566))
	var bag_frame := GothicFrameFactoryScript.add_filled_section(bag_panel, "BagGridV3Frame", GRID_FRAME_RECT)
	bag_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_frame.set_meta("calibration_layer", "warehouse_bag_grid_decoration")
	bag_panel.add_child(_section_title("BagTitle", "人物背包", 492))
	bag_grid = _build_item_grid(bag_panel, "BagScroll", "BagGrid")
	bag_panel.add_child(_paging_hint("BagPagingHint", "首屏 30 格　·　下拉查看 31–100 格"))
	bag_summary_label = _summary_label("BagSummary")
	bag_panel.add_child(bag_summary_label)


func _build_item_grid(parent: Control, scroll_name: String, grid_name: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = scroll_name
	scroll.position = GRID_SCROLL_RECT.position
	scroll.size = GRID_SCROLL_RECT.size
	scroll.set_meta("calibration_layout_revision", LAYOUT_REVISION)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.clip_contents = true
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = grid_name
	grid.position = Vector2.ZERO
	grid.columns = GRID_COLUMNS
	grid.custom_minimum_size = GRID_MINIMUM_SIZE
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", int(GRID_HORIZONTAL_SEPARATION))
	grid.add_theme_constant_override("v_separation", int(GRID_VERTICAL_SEPARATION))
	scroll.add_child(grid)
	return grid


func _paging_hint(node_name: String, text_value: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.set_meta("calibration_text_revision", LAYOUT_REVISION)
	label.set_meta("calibration_layout_revision", LAYOUT_REVISION)
	label.position = Vector2(18, 408)
	label.size = Vector2(456, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicMutedLabel"
	return label


func _build_page_controls(parent: Control) -> void:
	previous_page_button = Button.new()
	previous_page_button.name = "PreviousPageButton"
	previous_page_button.text = "‹"
	previous_page_button.position = Vector2(70, 430)
	previous_page_button.size = Vector2(96, THIN_BUTTON_HEIGHT)
	previous_page_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	previous_page_button.set_meta("calibration_layout_revision", LAYOUT_REVISION)
	previous_page_button.theme_type_variation = "GothicWarehouseThinButton"
	previous_page_button.add_theme_font_size_override("font_size", 24)
	previous_page_button.pressed.connect(_change_warehouse_page.bind(-1))
	parent.add_child(previous_page_button)
	warehouse_page_label = Label.new()
	warehouse_page_label.name = "WarehousePageLabel"
	warehouse_page_label.position = Vector2(176, 430)
	warehouse_page_label.size = Vector2(140, THIN_BUTTON_HEIGHT)
	warehouse_page_label.set_meta("calibration_layout_revision", LAYOUT_REVISION)
	warehouse_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warehouse_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warehouse_page_label.theme_type_variation = "GothicSectionTitle"
	parent.add_child(warehouse_page_label)
	next_page_button = Button.new()
	next_page_button.name = "NextPageButton"
	next_page_button.text = "›"
	next_page_button.position = Vector2(326, 430)
	next_page_button.size = Vector2(96, THIN_BUTTON_HEIGHT)
	next_page_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_page_button.set_meta("calibration_layout_revision", LAYOUT_REVISION)
	next_page_button.theme_type_variation = "GothicWarehouseThinButton"
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
	button.size = Vector2(96, THIN_BUTTON_HEIGHT)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.set_meta("calibration_layout_revision", LAYOUT_REVISION)
	button.theme_type_variation = "GothicWarehouseActionPlainButton"
	button.add_theme_font_size_override("font_size", GothicUIThemeScript.BUTTON_ACTION_FONT_SIZE)
	return button


func _build_compatibility_lists() -> void:
	bag_list = ItemList.new()
	bag_list.name = "CompatibilityBagList"
	bag_list.select_mode = ItemList.SELECT_MULTI
	bag_list.visible = false
	add_child(bag_list)
	stash_list = ItemList.new()
	stash_list.name = "CompatibilityStashList"
	stash_list.select_mode = ItemList.SELECT_MULTI
	stash_list.visible = false
	add_child(stash_list)


func open_panel() -> void:
	# Preserve the complete two-grid presentation even when the player opens the
	# warehouse during the short background construction window.
	if not _grid_cells_ready:
		var first_new_index := mini(_bag_cells.size(), _stash_cells.size())
		_initialize_grid_cells(WAREHOUSE_PAGE_CAPACITY)
		_populate_grid_cells_from(first_new_index)
	show()
	# A hidden inventory signal is normally consumed synchronously by
	# visibility_changed. Keep the explicit guard for callers opening an already
	# visible panel with pending data, without rebuilding an up-to-date panel.
	if _refresh_pending:
		refresh()


func _on_inventory_changed() -> void:
	if not visible:
		_refresh_pending = true
		return
	_queue_refresh()


func _on_visibility_changed() -> void:
	if visible and _refresh_pending:
		refresh()


func refresh() -> void:
	if bag_grid == null or stash_grid == null:
		return
	_refresh_pending = false
	_refresh_scheduled = false
	_refresh_execution_count += 1
	_sanitize_transfer_selections()
	_fill_compatibility_list(bag_list, PlayerState.inventory, selected_bag_indices)
	_fill_compatibility_list(stash_list, PlayerState.warehouse_inventory, selected_stash_indices)
	_fill_grid(bag_grid, PlayerState.inventory, 0, BAG_CAPACITY, "bag", selected_bag_indices)
	var page_start := warehouse_page * WAREHOUSE_PAGE_CAPACITY
	_fill_grid(
		stash_grid,
		PlayerState.warehouse_inventory,
		page_start,
		WAREHOUSE_PAGE_CAPACITY,
		"stash",
		selected_stash_indices
	)
	bag_summary_label.text = "背包占用　%d/%d 格" % [PlayerState.inventory_occupied_count(), BAG_CAPACITY]
	stash_summary_label.text = "仓库占用　%d/%d 格" % [_warehouse_occupied_count(), WAREHOUSE_DISPLAY_CAPACITY]
	warehouse_page_label.text = "第 %d/%d 页" % [warehouse_page + 1, WAREHOUSE_PAGE_COUNT]
	previous_page_button.disabled = warehouse_page <= 0
	next_page_button.disabled = warehouse_page >= WAREHOUSE_PAGE_COUNT - 1
	_refresh_transfer_action_states()
	_refresh_transfer_detail()
	if not _layout_initialized:
		_layout_initialized = true
		_layout_apply_count += 1
		UIRuntimeLayoutOverridesScript.apply_profile(self, "warehouse")
		_stabilize_grid_layout.call_deferred()


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


func _stabilize_grid_layout() -> void:
	for scroll_path in ["StashSection/StashScroll", "BagSection/BagScroll"]:
		var scroll := get_node_or_null(scroll_path) as ScrollContainer
		if scroll != null:
			scroll.size = GRID_SCROLL_RECT.size
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.clip_contents = true
	for grid in [stash_grid, bag_grid]:
		if grid == null:
			continue
		grid.columns = GRID_COLUMNS
		grid.position = Vector2.ZERO
		grid.custom_minimum_size = GRID_MINIMUM_SIZE
		grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		grid.queue_sort()


func _fill_grid(
	grid: GridContainer,
	records: Array,
	start_index: int,
	slot_count: int,
	side: String,
	selected_indices: Dictionary
) -> void:
	if _bag_cells.is_empty() or _stash_cells.is_empty():
		_initialize_grid_cells(GRID_VISIBLE_SLOTS)
	var cells := _bag_cells if side == "bag" else _stash_cells
	for display_index in range(mini(slot_count, cells.size())):
		var data_index := start_index + display_index
		var record: Dictionary = records[data_index] if data_index < records.size() and records[data_index] is Dictionary and not (records[data_index] as Dictionary).is_empty() else {}
		_update_item_cell(cells[display_index], side, data_index, display_index, record, selected_indices.has(data_index))
	grid.queue_sort()


func _initialize_grid_cells(target_count := WAREHOUSE_PAGE_CAPACITY) -> void:
	var bounded_target := mini(WAREHOUSE_PAGE_CAPACITY, maxi(0, target_count))
	if _bag_cells.size() < bounded_target:
		for display_index in range(_bag_cells.size(), bounded_target):
			var cell := _create_item_cell("bag", display_index, display_index, {}, false)
			bag_grid.add_child(cell)
			_bag_cells.append(cell)
			_grid_cell_creation_count += 1
	if _stash_cells.size() < bounded_target:
		for display_index in range(_stash_cells.size(), bounded_target):
			var cell := _create_item_cell("stash", display_index, display_index, {}, false)
			stash_grid.add_child(cell)
			_stash_cells.append(cell)
			_grid_cell_creation_count += 1
	_grid_cells_ready = (
		_bag_cells.size() >= BAG_CAPACITY
		and _stash_cells.size() >= WAREHOUSE_PAGE_CAPACITY
	)


func _continue_grid_cell_initialization() -> void:
	if _grid_cells_ready or _grid_cell_initialization_running:
		return
	_grid_cell_initialization_running = true
	while is_inside_tree() and not _grid_cells_ready:
		var first_new_index := mini(_bag_cells.size(), _stash_cells.size())
		_initialize_grid_cells(first_new_index + GRID_BACKGROUND_CELL_BATCH)
		_populate_grid_cells_from(first_new_index)
		await get_tree().process_frame
	_grid_cell_initialization_running = false


func _populate_grid_cells_from(first_index: int) -> void:
	var page_start := warehouse_page * WAREHOUSE_PAGE_CAPACITY
	for display_index in range(first_index, _bag_cells.size()):
		var bag_record := _bag_record(display_index)
		_update_item_cell(
			_bag_cells[display_index],
			"bag",
			display_index,
			display_index,
			bag_record,
			selected_bag_indices.has(display_index)
		)
		var stash_index := page_start + display_index
		var stash_record := _warehouse_record(stash_index)
		_update_item_cell(
			_stash_cells[display_index],
			"stash",
			stash_index,
			display_index,
			stash_record,
			selected_stash_indices.has(stash_index)
		)
	bag_grid.queue_sort()
	stash_grid.queue_sort()


func wait_until_runtime_ready() -> void:
	if not _grid_cells_ready:
		_continue_grid_cell_initialization()
	while is_inside_tree() and not _grid_cells_ready:
		await get_tree().process_frame


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
	button.theme_type_variation = "GothicComponentSlotButton"
	button.disabled = true
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.tooltip_text = "空物品格"
	button.pressed.connect(_select_grid_button.bind(button))
	cell.add_child(button)
	var count_label := Label.new()
	count_label.name = "StackCount"
	count_label.set_meta("calibration_layout_revision", LAYOUT_REVISION)
	count_label.position = Vector2(30, 41)
	count_label.size = Vector2(22, 19)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.add_theme_color_override("font_color", Color.WHITE)
	count_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	count_label.add_theme_constant_override("shadow_offset_x", 2)
	count_label.add_theme_constant_override("shadow_offset_y", 2)
	count_label.hide()
	cell.add_child(count_label)
	return cell


func _update_item_cell(
	cell: Control,
	side: String,
	data_index: int,
	display_index: int,
	record: Dictionary,
	selected: bool
) -> void:
	cell.name = "%sCell_%d" % [side.capitalize(), display_index]
	var button := cell.get_node("ItemButton") as Button
	button.set_meta("side", side)
	button.set_meta("data_index", data_index)
	button.theme_type_variation = "GothicComponentSelectedSlotButton" if selected else "GothicComponentSlotButton"
	button.disabled = record.is_empty()
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE if record.is_empty() else Control.MOUSE_FILTER_STOP
	button.tooltip_text = str(record.get("name", "空物品格"))
	_set_button_texture(button, _item_texture(record))
	var count_label := cell.get_node("StackCount") as Label
	var count := int(record.get("count", 1))
	count_label.text = str(count)
	count_label.visible = not record.is_empty() and count > 1


func _select_grid_button(button: Button) -> void:
	_select_item(str(button.get_meta("side", "")), int(button.get_meta("data_index", -1)))


func _select_item(side: String, index: int) -> void:
	if TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	if side == "bag" and _bag_record(index).is_empty():
		return
	if side == "stash" and _warehouse_record(index).is_empty():
		return
	if side not in ["bag", "stash"]:
		return
	if side != _active_selection_side:
		# A batch always has exactly one source authority. Crossing the centre
		# column starts a new batch and removes every selection from the old side.
		selected_bag_indices.clear()
		selected_stash_indices.clear()
		_active_selection_side = side
	var selection := selected_bag_indices if side == "bag" else selected_stash_indices
	if selection.has(index):
		selection.erase(index)
	else:
		selection[index] = true
	if selection.is_empty():
		_active_selection_side = ""
	_sync_primary_selection_indices()
	_refresh_transfer_selection_visuals()
	_refresh_transfer_action_states()
	_refresh_transfer_detail()


func _refresh_transfer_selection_visuals() -> void:
	# Repaint from the two authoritative sets so rapid toggles and side switches
	# cannot leave a stale selected frame on a reused cell.
	for cell: Control in _bag_cells:
		var button := cell.get_node("ItemButton") as Button
		var data_index := int(button.get_meta("data_index", -1))
		button.theme_type_variation = (
			"GothicComponentSelectedSlotButton"
			if selected_bag_indices.has(data_index)
			else "GothicComponentSlotButton"
		)
	for cell: Control in _stash_cells:
		var button := cell.get_node("ItemButton") as Button
		var data_index := int(button.get_meta("data_index", -1))
		button.theme_type_variation = (
			"GothicComponentSelectedSlotButton"
			if selected_stash_indices.has(data_index)
			else "GothicComponentSlotButton"
		)
	bag_list.deselect_all()
	stash_list.deselect_all()
	for raw_index: Variant in selected_bag_indices.keys():
		var index := int(raw_index)
		if index >= 0 and index < bag_list.item_count:
			bag_list.select(index, false)
	for raw_index: Variant in selected_stash_indices.keys():
		var index := int(raw_index)
		if index >= 0 and index < stash_list.item_count:
			stash_list.select(index, false)


func _sync_primary_selection_indices() -> void:
	var bag_keys := selected_bag_indices.keys()
	var stash_keys := selected_stash_indices.keys()
	selected_bag_index = int(bag_keys.back()) if not bag_keys.is_empty() else -1
	selected_stash_index = int(stash_keys.back()) if not stash_keys.is_empty() else -1


func _sanitize_transfer_selections() -> void:
	for raw_index: Variant in selected_bag_indices.keys().duplicate():
		if _bag_record(int(raw_index)).is_empty():
			selected_bag_indices.erase(raw_index)
	for raw_index: Variant in selected_stash_indices.keys().duplicate():
		if _warehouse_record(int(raw_index)).is_empty():
			selected_stash_indices.erase(raw_index)
	if _active_selection_side == "bag":
		selected_stash_indices.clear()
	elif _active_selection_side == "stash":
		selected_bag_indices.clear()
	elif not selected_bag_indices.is_empty():
		_active_selection_side = "bag"
		selected_stash_indices.clear()
	elif not selected_stash_indices.is_empty():
		_active_selection_side = "stash"
	if (
		(_active_selection_side == "bag" and selected_bag_indices.is_empty())
		or (_active_selection_side == "stash" and selected_stash_indices.is_empty())
	):
		_active_selection_side = ""
	_sync_primary_selection_indices()


func _refresh_transfer_action_states() -> void:
	deposit_button.disabled = selected_bag_indices.is_empty() or _first_free_slot_on_current_page() < 0
	withdraw_button.disabled = selected_stash_indices.is_empty() or PlayerState.inventory_occupied_count() >= BAG_CAPACITY


func _refresh_cell_selection(side: String, data_index: int, selected: bool) -> void:
	if data_index < 0:
		return
	var display_index := data_index if side == "bag" else data_index - warehouse_page * WAREHOUSE_PAGE_CAPACITY
	var cells := _bag_cells if side == "bag" else _stash_cells
	if display_index < 0 or display_index >= cells.size():
		return
	var button := (cells[display_index] as Control).get_node("ItemButton") as Button
	button.theme_type_variation = "GothicComponentSelectedSlotButton" if selected else "GothicComponentSlotButton"


func _change_warehouse_page(delta: int) -> void:
	warehouse_page = clampi(warehouse_page + delta, 0, WAREHOUSE_PAGE_COUNT - 1)
	selected_stash_indices.clear()
	if _active_selection_side == "stash":
		_active_selection_side = ""
	_sync_primary_selection_indices()
	refresh()


func _refresh_transfer_detail() -> void:
	if selected_bag_indices.size() > 1:
		transfer_detail_label.text = "已选择 %d 件背包物品" % selected_bag_indices.size()
	elif selected_bag_index >= 0:
		transfer_detail_label.text = str(_bag_record(selected_bag_index).get("name", "未知物品"))
	elif not selected_stash_indices.is_empty() and PlayerState.inventory_occupied_count() >= BAG_CAPACITY:
		transfer_detail_label.text = "已选择 %d 件；背包已满" % selected_stash_indices.size()
	elif selected_stash_indices.size() > 1:
		transfer_detail_label.text = "已选择 %d 件仓库物品" % selected_stash_indices.size()
	elif selected_stash_index >= 0:
		transfer_detail_label.text = str(_warehouse_record(selected_stash_index).get("name", "未知物品"))
	elif _first_free_slot_on_current_page() < 0:
		transfer_detail_label.text = "当前页已满"
	else:
		transfer_detail_label.text = "选择两侧物品"


func _fill_compatibility_list(list: ItemList, records: Array, selected_indices: Dictionary) -> void:
	list.clear()
	for record: Variant in records:
		list.add_item(str(record.get("name", "")) if record is Dictionary else str(record))
	for raw_index: Variant in selected_indices.keys():
		var index := int(raw_index)
		if index >= 0 and index < list.item_count:
			list.select(index, false)


func _deposit() -> void:
	_sanitize_transfer_selections()
	if _active_selection_side != "bag" or selected_bag_indices.is_empty():
		return
	var source_indices := _sorted_selection_indices(selected_bag_indices)
	_clear_transfer_feedback()
	GothicUIThemeScript.set_button_feedback(deposit_button, GothicUIThemeScript.BUTTON_FEEDBACK_BUSY, "warehouse.deposit")
	var transferred := 0
	var failure_message := ""
	for source_index: int in source_indices:
		var target_slot := _first_free_slot_on_current_page()
		if target_slot < 0:
			failure_message = "当前仓库页空间不足。"
			break
		var result: Dictionary = PlayerState.deposit_to_warehouse(source_index, target_slot)
		if not bool(result.get("success", false)):
			failure_message = str(result.get("message", "仓库存取失败。"))
			break
		transferred += 1
		selected_bag_indices.erase(source_index)
	if selected_bag_indices.is_empty():
		_active_selection_side = ""
	_sync_primary_selection_indices()
	refresh()
	_finish_transfer_batch("deposit", "已存入", source_indices.size(), transferred, failure_message)
	_show_transfer_result(deposit_button, transferred == source_indices.size(), "warehouse.deposit")


func _withdraw() -> void:
	_sanitize_transfer_selections()
	if _active_selection_side != "stash" or selected_stash_indices.is_empty():
		return
	var source_indices := _sorted_selection_indices(selected_stash_indices)
	_clear_transfer_feedback()
	GothicUIThemeScript.set_button_feedback(withdraw_button, GothicUIThemeScript.BUTTON_FEEDBACK_BUSY, "warehouse.withdraw")
	var transferred := 0
	var failure_message := ""
	for source_index: int in source_indices:
		var result: Dictionary = PlayerState.withdraw_from_warehouse(source_index)
		if not bool(result.get("success", false)):
			failure_message = str(result.get("message", "仓库存取失败。"))
			break
		transferred += 1
		selected_stash_indices.erase(source_index)
	if selected_stash_indices.is_empty():
		_active_selection_side = ""
	_sync_primary_selection_indices()
	refresh()
	_finish_transfer_batch("withdraw", "已取出", source_indices.size(), transferred, failure_message)
	_show_transfer_result(withdraw_button, transferred == source_indices.size(), "warehouse.withdraw")


func _sorted_selection_indices(selection: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for raw_index: Variant in selection.keys():
		result.append(int(raw_index))
	result.sort()
	return result


func _finish_transfer_batch(
	operation: String,
	success_verb: String,
	requested: int,
	transferred: int,
	failure_message: String
) -> void:
	var remaining := maxi(0, requested - transferred)
	var complete := requested > 0 and remaining == 0
	_last_transfer_batch_result = {
		"operation": operation,
		"requested": requested,
		"transferred": transferred,
		"remaining": remaining,
		"complete": complete,
		"failure_message": failure_message,
	}
	if complete:
		transfer_detail_label.text = "%s %d 件物品。" % [success_verb, transferred]
	elif transferred > 0:
		transfer_detail_label.text = "%s %d 件，另有 %d 件未转移：%s" % [
			success_verb,
			transferred,
			remaining,
			failure_message if not failure_message.is_empty() else "操作未完成。",
		]
	else:
		transfer_detail_label.text = failure_message if not failure_message.is_empty() else "仓库存取失败。"


func _sort_requested() -> void:
	_clear_transfer_feedback()
	GothicUIThemeScript.set_button_feedback(sort_button, GothicUIThemeScript.BUTTON_FEEDBACK_BUSY, "warehouse.sort")
	warehouse_sort_requested.emit()


func _show_transfer_result(button: Button, success: bool, group: String) -> void:
	# Keep the initiating button's dark-red busy state for one rendered frame.
	# A late authority result still invalidates every other transfer action.
	_action_feedback_serial += 1
	var serial := _action_feedback_serial
	for action_button: Button in [deposit_button, withdraw_button, sort_button]:
		if action_button != button:
			GothicUIThemeScript.clear_button_feedback(action_button)
	if is_inside_tree():
		await get_tree().process_frame
	if serial != _action_feedback_serial or not is_instance_valid(button) or not button.is_inside_tree():
		return
	GothicUIThemeScript.set_button_feedback(
		button,
		GothicUIThemeScript.BUTTON_FEEDBACK_SUCCESS if success else GothicUIThemeScript.BUTTON_FEEDBACK_FAILURE,
		group,
	)
	get_tree().create_timer(1.0 if success else 0.45).timeout.connect(func() -> void:
		if serial == _action_feedback_serial and is_instance_valid(button) and button.is_inside_tree():
			GothicUIThemeScript.clear_button_feedback(button)
	)


func _clear_transfer_feedback() -> void:
	_action_feedback_serial += 1
	for button in [deposit_button, withdraw_button, sort_button]:
		GothicUIThemeScript.clear_button_feedback(button)


func apply_sort_result(result: Dictionary) -> void:
	if bool(result.get("success", false)):
		# Sorting changes warehouse slot identity. Any stash-side selection is
		# stale after a successful authority result and must not target new items.
		selected_stash_indices.clear()
		if _active_selection_side == "stash":
			_active_selection_side = ""
		_sync_primary_selection_indices()
	refresh()
	transfer_detail_label.text = str(result.get("message", "仓库整理请求已处理"))
	_show_transfer_result(sort_button, bool(result.get("success", false)), "warehouse.sort")


func _warehouse_record(slot_index: int) -> Dictionary:
	if not _warehouse_slot_has_item(slot_index):
		return {}
	var value: Variant = PlayerState.warehouse_inventory[slot_index]
	return value if value is Dictionary else {"name": str(value)}


func _bag_record(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= PlayerState.inventory.size():
		return {}
	var value: Variant = PlayerState.inventory[slot_index]
	return value if value is Dictionary and not (value as Dictionary).is_empty() else {}


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
	var icon_rect := button.get_node_or_null("CenteredPixelIcon") as TextureRect
	if texture == null:
		if icon_rect != null:
			icon_rect.texture = null
			icon_rect.hide()
		return
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	if icon_rect == null:
		icon_rect = TextureRect.new()
		icon_rect.name = "CenteredPixelIcon"
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon_rect)
	icon_rect.texture = texture
	icon_rect.position = (button.size - source_size) * 0.5
	icon_rect.size = source_size
	icon_rect.show()


func _section_panel(node_name: String, rect: Rect2) -> Control:
	var adjusted_rect := Rect2(rect.position + Vector2(0, -SECTION_VERTICAL_SHIFT), rect.size)
	# Section roots own content and calibrated geometry only.  Their former
	# add_filled_section() decorations created three extra, unselectable frames
	# around the left, transfer, and right columns.  Keep the stable roots while
	# leaving their visual treatment to the explicit grid frames below.
	var section := Control.new()
	section.name = node_name
	section.position = adjusted_rect.position
	section.size = adjusted_rect.size
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(section)
	return section


func _section_title(node_name: String, text_value: String, width: float) -> Label:
	var title := Label.new()
	title.name = node_name
	title.text = text_value
	title.set_meta("calibration_layout_revision", LAYOUT_REVISION)
	title.position = Vector2(18, 16)
	title.size = Vector2(width - 36.0, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.theme_type_variation = "GothicSectionTitle"
	return title


func _close() -> void:
	_clear_transfer_feedback()
	GothicUIThemeScript.clear_button_feedback(previous_page_button)
	GothicUIThemeScript.clear_button_feedback(next_page_button)
	hide()
	closed.emit()
