class_name WarehousePanel
extends Panel

const UIActivationOnceScript := preload("res://scripts/ui_activation_once.gd")

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const TouchScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")
const UIRuntimeLayoutOverridesScript := preload("res://scripts/ui_runtime_layout_overrides.gd")
const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")
const ItemDetailPresenterScript = preload("res://scripts/item_detail_docked_presenter.gd")

const UIItemDetailDockScript := preload("res://scripts/ui_item_detail_dock.gd")
const UIItemSelectionVisualScript := preload("res://scripts/ui_item_selection_visual.gd")
const UISelectionDismissGuardScript := preload("res://scripts/ui_selection_dismiss_guard.gd")

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
var selected_bag_refs: Array[Dictionary] = []
var selected_stash_refs: Array[Dictionary] = []
var selected_ref: Dictionary = {}
var _selection_revision := 0
var item_detail_presenter
var bank_balance_label: Label
var bank_deposit_button: Button
var bank_withdraw_button: Button
var _bank_transfer_pending := false
var _bank_transaction_serial := 0
var _bank_status_message := ""
var _last_bank_transfer_request: Dictionary = {}
var _last_bank_transfer_result: Dictionary = {}


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
	item_detail_presenter = ItemDetailPresenterScript.new()
	item_detail_presenter.position = Vector2(408, 112)
	item_detail_presenter.size = Vector2.ZERO
	item_detail_presenter.z_as_relative = false
	item_detail_presenter.z_index = 4095
	item_detail_presenter.set_meta("calibration_runtime_text", true)
	add_child(item_detail_presenter)
	GothicFrameFactoryScript.seal_modal_rings(self)
	visibility_changed.connect(_on_visibility_changed)
	PlayerState.inventory_changed.connect(_on_inventory_changed)
	PlayerState.profile_changed.connect(_on_profile_changed)
	_initialize_grid_cells(GRID_VISIBLE_SLOTS)
	refresh()
	_continue_grid_cell_initialization.call_deferred()
	UISelectionDismissGuardScript.attach(self)
	preload("res://scripts/ui_item_selection_lifecycle.gd").attach(self)


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
	divider.name = "TransferDivider"
	divider.position = Vector2(16, 346)
	divider.size = Vector2(92, 8)
	divider.set_meta("calibration_layer", "warehouse_transfer_divider")
	divider.set_meta("calibration_layout_revision", LAYOUT_REVISION)
	transfer_panel.add_child(divider)
	sort_button = _transfer_button("SortStashButton", "整理", Vector2(14, 382))
	sort_button.tooltip_text = "请求玩法层按既定规则整理仓库"
	sort_button.pressed.connect(_sort_requested)
	transfer_panel.add_child(sort_button)
	bank_balance_label = Label.new()
	bank_balance_label.name = "BankBalance"
	bank_balance_label.position = Vector2(8, 436)
	bank_balance_label.size = Vector2(108, 28)
	bank_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bank_balance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bank_balance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bank_balance_label.add_theme_font_size_override("font_size", 11)
	bank_balance_label.theme_type_variation = "GothicMutedLabel"
	bank_balance_label.set_meta("calibration_layout_revision", LAYOUT_REVISION)
	transfer_panel.add_child(bank_balance_label)
	bank_deposit_button = _transfer_button("BankDepositButton", "存入10万", Vector2(14, 466))
	bank_deposit_button.tooltip_text = "存入共享仓库（100000金币）"
	bank_deposit_button.pressed.connect(_on_bank_transfer_pressed.bind(true))
	transfer_panel.add_child(bank_deposit_button)
	bank_withdraw_button = _transfer_button("BankWithdrawButton", "取出10万", Vector2(14, 516))
	bank_withdraw_button.tooltip_text = "从共享仓库取出（100000金币）"
	bank_withdraw_button.pressed.connect(_on_bank_transfer_pressed.bind(false))
	transfer_panel.add_child(bank_withdraw_button)

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
	_ui_l1_bank_dirty = true
	_selection_revision += 1
	if not visible:
		_refresh_pending = true
		return
	_queue_refresh()


func _on_profile_changed() -> void:
	_ui_l1_bank_dirty = true
	_ui_l1_queue_bank_view()


func _on_visibility_changed() -> void:
	var session := get_node_or_null("R3SelectionLifecycle")
	if session != null:
		session.call("sync_visibility")
	if not is_visible_in_tree():
		_ui_l1_bank_dirty = true
		_ui_dismiss_selection()
		return
	if visible and _refresh_pending:
		refresh()
	_ui_l1_flush_bank_view_if_dirty()


func refresh() -> void:
	if bag_grid == null or stash_grid == null:
		return
	_refresh_pending = false
	_refresh_scheduled = false
	_refresh_execution_count += 1
	_sanitize_transfer_selections()
	_reconcile_semantic_selections()
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
	# Restore full view-sync responsibility: refresh() must also flush the
	# bank view so any gold mutation while the panel is visible reaches
	# bank_balance_label. _refresh_bank_state self-guards on
	# is_visible_in_tree + dirty, keeping the L1 hidden-panel skip intact.
	_refresh_bank_state()
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
	UIActivationOnceScript.attach(button, _select_grid_button.bind(button))
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
	UIItemSelectionVisualScript.apply(button, selected, &"GothicComponentSlotButton", &"GothicComponentSelectedSlotButton")
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
		selected_bag_refs.clear()
		selected_stash_refs.clear()
		selected_ref = {}
		_active_selection_side = side
	var selection: Dictionary = selected_bag_indices if side == "bag" else selected_stash_indices
	var refs: Array[Dictionary] = selected_bag_refs if side == "bag" else selected_stash_refs
	var record := _bag_record(index) if side == "bag" else _warehouse_record(index)
	var selection_ref := _selection_ref(side, index, record)
	var existing_position := -1
	for ref_index in range(refs.size()):
		if _same_selection_ref(refs[ref_index], selection_ref):
			existing_position = ref_index
			break
	if selection.has(index):
		selection.erase(index)
		if existing_position >= 0:
			refs.remove_at(existing_position)
	else:
		selection[index] = true
		refs.append(selection_ref)
	if side == "bag":
		selected_bag_indices = selection
		selected_bag_refs = refs
	else:
		selected_stash_indices = selection
		selected_stash_refs = refs
	if selection.is_empty():
		_active_selection_side = ""
	selected_ref = refs.back() if not refs.is_empty() else {}
	_sync_primary_selection_indices()
	_refresh_transfer_selection_visuals()
	_refresh_transfer_action_states()
	_refresh_transfer_detail()


func _refresh_transfer_selection_visuals() -> void:
	for side: String in ["bag", "stash"]:
		var cells: Array[Control] = _bag_cells if side == "bag" else _stash_cells
		var selection: Dictionary = selected_bag_indices if side == "bag" else selected_stash_indices
		for cell: Control in cells:
			var button := cell.get_node("ItemButton") as Button
			var data_index := int(button.get_meta("data_index", -1))
			UIItemSelectionVisualScript.apply(button, selection.has(data_index), &"GothicComponentSlotButton", &"GothicComponentSelectedSlotButton")
	if bag_list != null:
		bag_list.deselect_all()
		for raw_index: Variant in selected_bag_indices.keys():
			var index := int(raw_index)
			if index >= 0 and index < bag_list.item_count:
				bag_list.select(index, false)
	if stash_list != null:
		stash_list.deselect_all()
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
		selected_stash_refs.clear()
	elif _active_selection_side == "stash":
		selected_bag_indices.clear()
		selected_bag_refs.clear()
	elif not selected_bag_indices.is_empty():
		_active_selection_side = "bag"
		selected_stash_indices.clear()
		selected_stash_refs.clear()
	elif not selected_stash_indices.is_empty():
		_active_selection_side = "stash"
		selected_bag_indices.clear()
		selected_bag_refs.clear()
	if (
		(_active_selection_side == "bag" and selected_bag_indices.is_empty())
		or (_active_selection_side == "stash" and selected_stash_indices.is_empty())
	):
		_active_selection_side = ""
	_sync_primary_selection_indices()


func _refresh_transfer_action_states() -> void:
	deposit_button.disabled = selected_bag_indices.is_empty() or _first_free_slot_on_current_page() < 0
	withdraw_button.disabled = selected_stash_indices.is_empty() or PlayerState.inventory_occupied_count() >= BAG_CAPACITY
	_ui_l1_flush_bank_view_if_dirty()


func _bank_transfer_amount() -> int:
	return int(PlayerState.BANK_TRANSFER_AMOUNT)


func _bank_boundary_message(deposit: bool, player_gold: int, shared_gold: int) -> String:
	var amount := _bank_transfer_amount()
	if deposit:
		if player_gold < amount:
			return "存入不可用：金币不足%d。" % amount
		if shared_gold > int(PlayerState.SHARED_GOLD_CAP) - amount:
			return "存入不可用：共享金币已达上限。"
	else:
		if shared_gold < amount:
			return "取出不可用：共享金币不足%d。" % amount
		if player_gold > int(PlayerState.PLAYER_GOLD_CAP) - amount:
			return "取出不可用：身上金币已达上限。"
	return ""


func _refresh_bank_state() -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		_ui_l1_bank_dirty = true
		_ui_l1_hidden_bank_skips += 1
		return
	if bank_balance_label == null or bank_deposit_button == null or bank_withdraw_button == null:
		return
	_ui_l1_bank_dirty = false
	_ui_l1_bank_read_count += 1
	var player_gold := int(PlayerState.gold)
	var shared_gold := int(PlayerState.shared_gold_balance())
	bank_balance_label.text = "金币：%d\n共享：%d" % [player_gold, shared_gold]
	bank_balance_label.tooltip_text = "身上金币：%d；共享金币：%d" % [player_gold, shared_gold]
	var busy_text := "共享金币操作处理中，请稍候。" if _bank_transfer_pending else ""
	var deposit_boundary := _bank_boundary_message(true, player_gold, shared_gold)
	var withdraw_boundary := _bank_boundary_message(false, player_gold, shared_gold)
	bank_deposit_button.disabled = _bank_transfer_pending or not deposit_boundary.is_empty()
	bank_withdraw_button.disabled = _bank_transfer_pending or not withdraw_boundary.is_empty()
	bank_deposit_button.tooltip_text = (
		busy_text
		if not busy_text.is_empty()
		else deposit_boundary
		if not deposit_boundary.is_empty()
		else "存入共享仓库（%d金币）" % _bank_transfer_amount()
	)
	bank_withdraw_button.tooltip_text = (
		busy_text
		if not busy_text.is_empty()
		else withdraw_boundary
		if not withdraw_boundary.is_empty()
		else "从共享仓库取出（%d金币）" % _bank_transfer_amount()
	)


func _bank_result_message(deposit: bool, result: Dictionary) -> String:
	var action := "存入" if deposit else "取出"
	var amount := _bank_transfer_amount()
	if bool(result.get("success", false)):
		return "%s成功：%d金币。" % [action, amount]
	match str(result.get("reason", "")):
		"insufficient_balance_or_cap":
			return "%s失败：金币余额或上限不足。" % action
		"stale_transaction_sequence":
			return "共享金币状态已变化，请刷新后重试。"
		"duplicate_transaction":
			return "该共享金币请求已处理，未重复执行。"
		"save_failed":
			return "%s失败：存档失败，金币未改变。" % action
		"stale_profile":
			return "共享金币状态已过期，请刷新后重试。"
		"storage_unavailable":
			return "共享金币暂不可用，请稍后重试。"
		_:
			return "%s失败：请求未完成。" % action


func _on_bank_transfer_pressed(deposit: bool) -> void:
	if _bank_transfer_pending:
		return
	_refresh_bank_state()
	var player_gold := int(PlayerState.gold)
	var shared_gold := int(PlayerState.shared_gold_balance())
	var boundary := _bank_boundary_message(deposit, player_gold, shared_gold)
	if not boundary.is_empty():
		_bank_status_message = boundary
		transfer_detail_label.text = boundary
		return
	var transaction_sequence := int(PlayerState.next_shared_gold_transaction_sequence())
	if transaction_sequence <= 0:
		_bank_status_message = "共享金币事务不可用，请稍后重试。"
		transfer_detail_label.text = _bank_status_message
		_refresh_bank_state()
		return
	_bank_transaction_serial += 1
	var transaction_id := "warehouse-bank-%d-%d" % [transaction_sequence, _bank_transaction_serial]
	_submit_bank_transfer(deposit, transaction_id, transaction_sequence)


func _submit_bank_transfer(deposit: bool, transaction_id: String, transaction_sequence: int) -> void:
	if _bank_transfer_pending:
		return
	_bank_transfer_pending = true
	_last_bank_transfer_request = {
		"deposit": deposit,
		"transaction_id": transaction_id,
		"transaction_sequence": transaction_sequence,
	}
	var button: Button = bank_deposit_button if deposit else bank_withdraw_button
	_clear_transfer_feedback()
	GothicUIThemeScript.set_button_feedback(button, GothicUIThemeScript.BUTTON_FEEDBACK_BUSY, "warehouse.bank")
	_refresh_bank_state()
	var result: Dictionary = PlayerState.transfer_shared_gold(deposit, transaction_id, transaction_sequence)
	_last_bank_transfer_result = result.duplicate(true)
	_bank_status_message = _bank_result_message(deposit, result)
	transfer_detail_label.text = _bank_status_message
	# A stale sequence only refreshes the visible authority state. The failed
	# request is never replayed with a new sequence automatically.
	_refresh_bank_state()
	_show_transfer_result(button, bool(result.get("success", false)), "warehouse.bank")
	if is_inside_tree():
		await get_tree().process_frame
	_bank_transfer_pending = false
	_refresh_bank_state()


func _refresh_cell_selection(side: String, data_index: int, selected: bool) -> void:
	if data_index < 0:
		return
	var display_index := data_index if side == "bag" else data_index - warehouse_page * WAREHOUSE_PAGE_CAPACITY
	var cells := _bag_cells if side == "bag" else _stash_cells
	if display_index < 0 or display_index >= cells.size():
		return
	var button := (cells[display_index] as Control).get_node("ItemButton") as Button
	UIItemSelectionVisualScript.apply(button, selected, &"GothicComponentSlotButton", &"GothicComponentSelectedSlotButton")


func _change_warehouse_page(delta: int) -> void:
	warehouse_page = clampi(warehouse_page + delta, 0, WAREHOUSE_PAGE_COUNT - 1)
	selected_stash_indices.clear()
	selected_stash_refs.clear()
	selected_ref = {}
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
	_update_detail_presenter()


func _update_detail_presenter() -> void:
	if item_detail_presenter == null:
		return
	var side := str(selected_ref.get("container", ""))
	var index := int(selected_ref.get("slot", -1))
	var refs := selected_bag_refs if side == "bag" else selected_stash_refs
	# A batch keeps its transfer semantics, but the detail surface follows the
	# latest selected reference.  selected_ref also carries the same-instance
	# follow-up after a successful transfer clears the source batch.
	if not refs.is_empty():
		var latest_ref: Dictionary = refs.back()
		side = str(latest_ref.get("container", side))
		index = int(latest_ref.get("slot", index))
		selected_ref = latest_ref
	if side not in ["bag", "stash"] or index < 0:
		item_detail_presenter.hide_detail()
		return
	var record := _bag_record(index) if side == "bag" else _warehouse_record(index)
	if record.is_empty():
		item_detail_presenter.hide_detail()
		return
	var item := GameData.get_item_record(record)
	if item.is_empty():
		item_detail_presenter.show_message("物品目录缺少此记录。", _presenter_context(side, index))
		return
	item_detail_presenter.show_item(item, record, _presenter_context(side, index))


func _presenter_context(side: String, _index: int) -> Dictionary:
	return {"side": side}


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
	var moving_refs: Array[Dictionary] = []
	for raw_index: Variant in source_indices:
		var record := _bag_record(int(raw_index))
		if not record.is_empty():
			moving_refs.append(_selection_ref("bag", int(raw_index), record))
	_clear_transfer_feedback()
	GothicUIThemeScript.set_button_feedback(deposit_button, GothicUIThemeScript.BUTTON_FEEDBACK_BUSY, "warehouse.deposit")
	var target_slots := _free_slots_on_current_page(source_indices.size())
	var result: Dictionary = PlayerState.deposit_to_warehouse_batch(source_indices, target_slots)
	var transferred := int(result.get("transferred", 0))
	var failure_message := "" if bool(result.get("complete", false)) else str(result.get("message", "仓库存取失败。"))
	for raw_index: Variant in result.get("completed_source_indices", []):
		selected_bag_indices.erase(int(raw_index))
	_selected_transfer_refs_after_deposit(moving_refs, result)
	if selected_bag_indices.is_empty():
		_active_selection_side = ""
	_sync_primary_selection_indices()
	refresh()
	_finish_transfer_batch("deposit", "已存入", source_indices.size(), transferred, failure_message)
	_show_transfer_result(deposit_button, bool(result.get("complete", false)), "warehouse.deposit")


func _withdraw() -> void:
	_sanitize_transfer_selections()
	if _active_selection_side != "stash" or selected_stash_indices.is_empty():
		return
	var source_indices := _sorted_selection_indices(selected_stash_indices)
	var moving_refs: Array[Dictionary] = []
	for raw_index: Variant in source_indices:
		var record := _warehouse_record(int(raw_index))
		if not record.is_empty():
			moving_refs.append(_selection_ref("stash", int(raw_index), record))
	_clear_transfer_feedback()
	GothicUIThemeScript.set_button_feedback(withdraw_button, GothicUIThemeScript.BUTTON_FEEDBACK_BUSY, "warehouse.withdraw")
	var result: Dictionary = PlayerState.withdraw_from_warehouse_batch(source_indices)
	var transferred := int(result.get("transferred", 0))
	var failure_message := "" if bool(result.get("complete", false)) else str(result.get("message", "仓库存取失败。"))
	for raw_index: Variant in result.get("completed_warehouse_slots", []):
		selected_stash_indices.erase(int(raw_index))
	_selected_transfer_refs_after_withdraw(moving_refs, result)
	if selected_stash_indices.is_empty():
		_active_selection_side = ""
	_sync_primary_selection_indices()
	refresh()
	_finish_transfer_batch("withdraw", "已取出", source_indices.size(), transferred, failure_message)
	_show_transfer_result(withdraw_button, bool(result.get("complete", false)), "warehouse.withdraw")


func _sorted_selection_indices(selection: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for raw_index: Variant in selection.keys():
		result.append(int(raw_index))
	result.sort()
	return result


func _selected_instance_ids(refs: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for selection_ref: Dictionary in refs:
		var instance_id := str(selection_ref.get("instance_id", ""))
		if not instance_id.is_empty():
			ids.append(instance_id)
	return ids


func _selected_indices_for_instance_ids(records: Array, ids: Array[String]) -> Array[int]:
	var result: Array[int] = []
	for index in range(records.size()):
		var value: Variant = records[index]
		if not value is Dictionary:
			continue
		if str((value as Dictionary).get("instance_id", "")) in ids:
			result.append(index)
	return result


func _selected_refs_for_indices(side: String, records: Array, indices: Array[int]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in indices:
		if index >= 0 and index < records.size() and records[index] is Dictionary and not (records[index] as Dictionary).is_empty():
			result.append(_selection_ref(side, index, records[index]))
	return result


func _selected_transfer_refs_after_deposit(moving_refs: Array[Dictionary], result: Dictionary) -> void:
	var ids := _selected_instance_ids(moving_refs)
	if not bool(result.get("success", false)):
		return
	if not bool(result.get("complete", false)):
		selected_bag_indices.clear()
		selected_bag_refs.clear()
		for selection_ref: Dictionary in moving_refs:
			var source_index := int(selection_ref.get("slot", -1))
			if source_index not in result.get("completed_source_indices", []) and not _bag_record(source_index).is_empty():
				selected_bag_indices[source_index] = true
				selected_bag_refs.append(_selection_ref("bag", source_index, _bag_record(source_index)))
		_active_selection_side = "bag" if not selected_bag_refs.is_empty() else ""
		selected_ref = selected_bag_refs.back() if not selected_bag_refs.is_empty() else {}
		return
	var moved_indices := _selected_indices_for_instance_ids(PlayerState.warehouse_inventory, ids)
	if moved_indices.is_empty():
		return
	var followed_refs := _selected_refs_for_indices("stash", PlayerState.warehouse_inventory, moved_indices)
	selected_bag_indices.clear()
	selected_bag_refs.clear()
	selected_stash_indices.clear()
	selected_stash_refs.clear()
	# The selection itself is cleared after a successful batch, while the
	# presenter keeps following the same instance at its new location.
	_active_selection_side = ""
	selected_ref = followed_refs.back() if not followed_refs.is_empty() else {}


func _selected_transfer_refs_after_withdraw(moving_refs: Array[Dictionary], result: Dictionary) -> void:
	var ids := _selected_instance_ids(moving_refs)
	if not bool(result.get("success", false)):
		return
	if not bool(result.get("complete", false)):
		selected_stash_indices.clear()
		selected_stash_refs.clear()
		for selection_ref: Dictionary in moving_refs:
			var source_slot := int(selection_ref.get("slot", -1))
			if source_slot not in result.get("completed_warehouse_slots", []) and not _warehouse_record(source_slot).is_empty():
				selected_stash_indices[source_slot] = true
				selected_stash_refs.append(_selection_ref("stash", source_slot, _warehouse_record(source_slot)))
		_active_selection_side = "stash" if not selected_stash_refs.is_empty() else ""
		selected_ref = selected_stash_refs.back() if not selected_stash_refs.is_empty() else {}
		return
	var moved_indices := _selected_indices_for_instance_ids(PlayerState.inventory, ids)
	if moved_indices.is_empty():
		return
	var followed_refs := _selected_refs_for_indices("bag", PlayerState.inventory, moved_indices)
	selected_stash_indices.clear()
	selected_stash_refs.clear()
	selected_bag_indices.clear()
	selected_bag_refs.clear()
	_active_selection_side = ""
	selected_ref = followed_refs.back() if not followed_refs.is_empty() else {}


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
	for action_button: Button in [deposit_button, withdraw_button, sort_button, bank_deposit_button, bank_withdraw_button]:
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
	for button in [deposit_button, withdraw_button, sort_button, bank_deposit_button, bank_withdraw_button]:
		GothicUIThemeScript.clear_button_feedback(button)


func apply_sort_result(result: Dictionary) -> void:
	if bool(result.get("success", false)):
		# Sorting changes warehouse slot identity. Any stash-side selection is
		# stale after a successful authority result and must not target new items.
		selected_stash_indices.clear()
		selected_stash_refs.clear()
		selected_ref = {}
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


func _selection_ref(side: String, index: int, record: Dictionary) -> Dictionary:
	return {
		"container": side,
		"slot": index,
		"index": index,
		"instance_id": str(record.get("instance_id", "")),
		"revision": _selection_revision,
	}


func _same_selection_ref(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty() or str(left.get("container", "")) != str(right.get("container", "")):
		return false
	var left_id := str(left.get("instance_id", ""))
	var right_id := str(right.get("instance_id", ""))
	if not left_id.is_empty() or not right_id.is_empty():
		return not left_id.is_empty() and left_id == right_id
	return int(left.get("slot", -1)) == int(right.get("slot", -1)) and int(left.get("revision", -1)) == int(right.get("revision", -1))


func _find_ref_index(selection_ref: Dictionary) -> int:
	var side := str(selection_ref.get("container", ""))
	var records: Array = PlayerState.inventory if side == "bag" else PlayerState.warehouse_inventory
	var instance_id := str(selection_ref.get("instance_id", ""))
	if not instance_id.is_empty():
		for index in range(records.size()):
			var value: Variant = records[index]
			if value is Dictionary and str((value as Dictionary).get("instance_id", "")) == instance_id:
				return index
	var slot := int(selection_ref.get("slot", -1))
	if side not in ["bag", "stash"] or slot < 0 or slot >= records.size():
		return -1
	var record: Variant = records[slot]
	if not record is Dictionary or (record as Dictionary).is_empty():
		return -1
	return slot if int(selection_ref.get("revision", _selection_revision)) == _selection_revision else -1


func _reconcile_semantic_selections() -> void:
	# A completed transfer clears the source selection but leaves one opaque
	# instance reference so the shared presenter can follow that same object at
	# its destination through the refresh signal.  Keep that ephemeral follow
	# reference only while the destination instance still resolves; ordinary
	# deselection and page changes explicitly reset selected_ref.
	var followed_ref := selected_ref
	var next_bag: Array[Dictionary] = []
	for selection_ref: Dictionary in selected_bag_refs:
		var index := _find_ref_index(selection_ref)
		if index >= 0:
			next_bag.append(_selection_ref("bag", index, _bag_record(index)))
	selected_bag_refs = next_bag
	var next_stash: Array[Dictionary] = []
	for selection_ref: Dictionary in selected_stash_refs:
		var index := _find_ref_index(selection_ref)
		if index >= 0:
			next_stash.append(_selection_ref("stash", index, _warehouse_record(index)))
	selected_stash_refs = next_stash
	selected_bag_indices.clear()
	for selection_ref: Dictionary in selected_bag_refs:
		selected_bag_indices[int(selection_ref.get("slot", -1))] = true
	selected_stash_indices.clear()
	for selection_ref: Dictionary in selected_stash_refs:
		selected_stash_indices[int(selection_ref.get("slot", -1))] = true
	if not selected_bag_refs.is_empty():
		selected_ref = selected_bag_refs.back()
	elif not selected_stash_refs.is_empty():
		selected_ref = selected_stash_refs.back()
	elif not followed_ref.is_empty() and not str(followed_ref.get("instance_id", "")).is_empty():
		var followed_index := _find_ref_index(followed_ref)
		if followed_index >= 0:
			var followed_side := str(followed_ref.get("container", ""))
			var followed_record := _bag_record(followed_index) if followed_side == "bag" else _warehouse_record(followed_index)
			selected_ref = _selection_ref(followed_side, followed_index, followed_record)
		else:
			selected_ref = {}
	else:
		selected_ref = {}
	_sync_primary_selection_indices()


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
	var free_slots := _free_slots_on_current_page(1)
	return int(free_slots[0]) if not free_slots.is_empty() else -1


func _free_slots_on_current_page(limit: int = WAREHOUSE_PAGE_CAPACITY) -> Array[int]:
	var free_slots: Array[int] = []
	var page_start := warehouse_page * WAREHOUSE_PAGE_CAPACITY
	for slot_index in range(page_start, page_start + WAREHOUSE_PAGE_CAPACITY):
		if _warehouse_slot_has_item(slot_index):
			continue
		free_slots.append(slot_index)
		if free_slots.size() >= limit:
			break
	return free_slots


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
		GameData.get_item_record(record), "inventoryIcon"
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
	_ui_dismiss_selection()
	_clear_transfer_feedback()
	GothicUIThemeScript.clear_button_feedback(previous_page_button)
	GothicUIThemeScript.clear_button_feedback(next_page_button)
	hide()
	closed.emit()


func _ui_detail_region(context: Dictionary) -> Dictionary:
	var side := str(context.get("side", "bag"))
	var path := "StashSection/StashScroll" if side == "stash" else "BagSection/BagScroll"
	return UIItemDetailDockScript.side_region(self, get_node_or_null(path) as Control, "left" if side == "stash" else "right")

func _ui_selection_token() -> Array:
	return [selected_bag_refs.duplicate(true), selected_stash_refs.duplicate(true), selected_ref.duplicate(true), warehouse_page, _selection_revision, _bank_status_message, item_detail_presenter.content_epoch() if item_detail_presenter != null else -1]

func _ui_dismiss_selection() -> void:
	selected_bag_indices.clear()
	selected_stash_indices.clear()
	selected_bag_refs.clear()
	selected_stash_refs.clear()
	selected_ref.clear()
	selected_bag_index = -1
	selected_stash_index = -1
	_active_selection_side = ""
	_bank_status_message = ""
	_clear_transfer_feedback()
	_refresh_transfer_selection_visuals()
	if item_detail_presenter != null:
		item_detail_presenter.hide_detail()
	if transfer_detail_label != null:
		transfer_detail_label.text = "选择两侧物品"
	if deposit_button != null and withdraw_button != null:
		_refresh_transfer_action_states()

# UI-L1 SUPPLEMENT BEGIN -- controlled extra members

# UI-L1: these fields own the VIEW only; they are never a money authority.
var _ui_l1_bank_dirty := true
var _ui_l1_bank_queued := false
var _ui_l1_bank_read_count := 0
var _ui_l1_hidden_bank_skips := 0

func _ui_l1_queue_bank_view() -> void:
	if _ui_l1_bank_queued or not is_inside_tree() or not is_visible_in_tree():
		return
	_ui_l1_bank_queued = true
	_ui_l1_flush_queued_bank_view.call_deferred()

func _ui_l1_flush_queued_bank_view() -> void:
	_ui_l1_bank_queued = false
	_ui_l1_flush_bank_view_if_dirty()

func _ui_l1_flush_bank_view_if_dirty() -> void:
	if _ui_l1_bank_dirty and is_inside_tree() and is_visible_in_tree():
		_refresh_bank_state()
# UI-L1 SUPPLEMENT END
