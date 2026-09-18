class_name InventoryPanel
extends Panel

const UIActivationOnceScript := preload("res://scripts/ui_activation_once.gd")

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const PreviewScript = preload("res://scripts/equipment_character_preview.gd")
const GothicUIThemeScript = preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript = preload("res://scripts/gothic_frame_factory.gd")
const UIItemTextureCacheScript = preload("res://scripts/ui_item_texture_cache.gd")
const TouchScrollSupportScript = preload("res://scripts/touch_scroll_support.gd")
const UIRuntimeLayoutOverridesScript = preload("res://scripts/ui_runtime_layout_overrides.gd")
const ItemDetailPresenterScript = preload("res://scripts/item_detail_docked_presenter.gd")

const UIItemDetailDockScript := preload("res://scripts/ui_item_detail_dock.gd")
const UIErrorFeedbackScript := preload("res://scripts/ui_error_feedback.gd")
const UIItemSelectionVisualScript := preload("res://scripts/ui_item_selection_visual.gd")
const UISelectionDismissGuardScript := preload("res://scripts/ui_selection_dismiss_guard.gd")

signal closed

const PANEL_SIZE := Vector2(1220, 660)
const MODAL_SURFACE_INSET := Vector4(32, 38, 32, 34)
const SECTION_VERTICAL_SHIFT := 24.0
## Two fewer columns than the former eight-column layout; capacity remains 100.
const BAG_COLUMNS := 6
## Six columns x five 64px rows (with 4px separation) fit the 340px viewport.
const BAG_VISIBLE_CAPACITY := 30
const BAG_CAPACITY := 100
const BAG_BACKGROUND_CELL_BATCH := 10
const EQUIPMENT_SLOT_LAYOUT_REVISION := 1
const ITEM_DETAIL_LAYOUT_REVISION := 1
const CHARACTER_STATS_FONT_SIZE := 16
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
	"AttributePanel/ItemDetailTitle",
	"AttributePanel/ItemDetail",
]
const LONG_PRESS_SECONDS := 0.48
const CONTEXT_MENU_POLICY_ID := "ui.inventory.context_menu_policy.v1"
const CONTEXT_MENU_ENABLED := false

var item_grid: GridContainer
var detail_label: RichTextLabel
var equipment_stats_label: RichTextLabel
var character_attribute_help: Node
var character_identity_label: RichTextLabel
var character_identity_help: Node
var bag_summary_label: Label
var character_preview: Control
var equipment_buttons: Dictionary = {}
var equipment_slot_labels: Dictionary = {}
var selected_inventory_index := -1
var selected_inventory_indices: Dictionary = {}
var selected_equipment_slot := ""
# Semantic selection mirrors the visible indices.  An instance id is preferred
# whenever the authority supplies one; stackables fall back to slot+revision.
var selected_inventory_refs: Array[Dictionary] = []
var selected_inventory_ref: Dictionary = {}
var selected_equipment_ref: Dictionary = {}
var _selection_revision := 0
var item_detail_presenter
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
var _bag_cells_ready := false
var _bag_cell_initialization_running := false
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
	_initialize_bag_cells(BAG_VISIBLE_CAPACITY)
	refresh()
	_continue_bag_cell_initialization.call_deferred()
	UISelectionDismissGuardScript.attach(self)
	preload("res://scripts/ui_item_selection_lifecycle.gd").attach(self)


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
	title.set_meta("calibration_layout_revision", 2)
	panel.add_child(title)
	character_identity_label = RichTextLabel.new()
	character_identity_label.name = "CharacterIdentity"
	character_identity_label.set_meta("calibration_runtime_text", true)
	character_identity_label.set_meta("ui_dismiss_protected", true)
	character_identity_label.fit_content = false
	character_identity_label.scroll_active = false
	character_identity_label.bbcode_enabled = true
	character_identity_label.theme_type_variation = "GothicDetailText"
	character_identity_label.add_theme_font_size_override("normal_font_size", 16)
	character_identity_label.add_theme_color_override("font_color", Color("ddc9a9"))
	panel.add_child(character_identity_label)
	character_identity_help = preload("res://scripts/item_attribute_help.gd").attach(panel, character_identity_label)
	character_identity_help.explanation_resolver = _character_attribute_explanation
	equipment_stats_label = RichTextLabel.new()
	equipment_stats_label.name = "CharacterStats"
	equipment_stats_label.set_meta("calibration_runtime_text", true)
	equipment_stats_label.set_meta("calibration_layout_revision", 3)
	equipment_stats_label.set_meta("ui_dismiss_protected", true)
	equipment_stats_label.position = Vector2(16, 16)
	equipment_stats_label.size = Vector2(218, 534)
	equipment_stats_label.fit_content = false
	equipment_stats_label.scroll_active = false
	equipment_stats_label.bbcode_enabled = true
	equipment_stats_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	equipment_stats_label.theme_type_variation = "GothicDetailText"
	equipment_stats_label.add_theme_font_size_override("normal_font_size", 16)
	equipment_stats_label.add_theme_color_override("font_color", Color("ddc9a9"))
	panel.add_child(equipment_stats_label)
	character_attribute_help = preload("res://scripts/item_attribute_help.gd").attach(panel, equipment_stats_label)
	character_attribute_help.explanation_resolver = _character_attribute_explanation
	character_identity_label.meta_clicked.connect(func(_meta: Variant) -> void: character_attribute_help.dismiss())
	equipment_stats_label.meta_clicked.connect(func(_meta: Variant) -> void: character_identity_help.dismiss())
	# The visible second-level frame has its own calibrated bounds. Follow that
	# frame instead of centering against the invisible section's old rectangle.
	var decoration := panel.get_node("AttributePanelDecoration") as Control
	var frame := decoration.get_node("AttributePanelFrame") as Control
	decoration.item_rect_changed.connect(_layout_character_attributes)
	frame.item_rect_changed.connect(_layout_character_attributes)
	_layout_character_attributes()
	var divider := HSeparator.new()
	divider.position = Vector2(16, 270)
	divider.size = Vector2(218, 8)
	divider.visible = false
	divider.set_meta("calibration_retired", true)
	panel.add_child(divider)
	var item_title := Label.new()
	item_title.name = "ItemDetailTitle"
	item_title.text = "物品属性"
	item_title.position = Vector2(16, 278)
	item_title.size = Vector2(218, 30)
	item_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_title.theme_type_variation = "GothicSectionTitle"
	item_title.visible = false
	item_title.set_meta("calibration_retired", true)
	panel.add_child(item_title)
	# Keep the old path as a hidden compatibility anchor for existing calibration
	# readers.  The live detail surface is the single shared presenter below.
	var legacy_detail := RichTextLabel.new()
	legacy_detail.name = "ItemDetail"
	legacy_detail.set_meta("calibration_runtime_text", true)
	legacy_detail.set_meta("calibration_layout_revision", ITEM_DETAIL_LAYOUT_REVISION)
	legacy_detail.position = Vector2(16, 312)
	legacy_detail.size = Vector2(218, 204)
	legacy_detail.visible = false
	legacy_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(legacy_detail)
	item_detail_presenter = ItemDetailPresenterScript.new()
	item_detail_presenter.position = Vector2(316, 110)
	item_detail_presenter.size = Vector2.ZERO
	item_detail_presenter.z_as_relative = false
	item_detail_presenter.z_index = 4095
	item_detail_presenter.set_meta("calibration_runtime_text", true)
	add_child(item_detail_presenter)
	# Existing tests and accessibility helpers use detail_label as the text sink;
	# alias it to the presenter body so no second visible detail is maintained.
	detail_label = item_detail_presenter.detail_label


func _build_equipment_panel() -> void:
	var panel := _section_panel("EquipmentPanel", Vector2(294, 72), Vector2(390, 566))
	var title := _section_title("人物装备", 390)
	title.name = "EquipmentTitle"
	panel.add_child(title)
	character_preview = PreviewScript.new()
	character_preview.equipment_updates_owned_by_parent = true
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
	auto_sort_button.position = Vector2(47, 4)
	auto_sort_button.size = Vector2(179, 51)
	auto_sort_button.pressed.connect(_on_auto_sort_pressed)
	auto_sort_button.theme_type_variation = "GothicInventoryActionGemButton"
	actions.add_child(auto_sort_button)
	discard_button = Button.new()
	discard_button.name = "DiscardButton"
	discard_button.text = "丢弃"
	discard_button.position = Vector2(246, 4)
	discard_button.size = Vector2(179, 51)
	discard_button.pressed.connect(_on_discard_pressed)
	discard_button.theme_type_variation = "GothicInventoryActionGemButton"
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
	UIActivationOnceScript.attach(button, _select_equipment_slot.bind(slot))
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
	# The authority does not promise stable numeric indices.  Keep semantic refs
	# alive until the deferred refresh can re-resolve instance ids; this lets a
	# successful equip/unequip follow the same object without showing a stale
	# frame during the transaction callback.
	_selection_revision += 1
	_refresh_inventory_action_states()
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
	_selection_revision += 1
	_queue_refresh()


func _on_visibility_changed() -> void:
	var session := get_node_or_null("R3SelectionLifecycle")
	if session != null:
		session.call("sync_visibility")
	if not is_visible_in_tree():
		_ui_dismiss_selection()
		return
	# The background builder normally finishes before the first interaction. If
	# the player opens the panel immediately after READY, preserve the visible
	# 100-slot contract rather than exposing a partially constructed grid.
	if not _bag_cells_ready:
		_initialize_bag_cells(BAG_CAPACITY)
		_refresh_pending = true
	if _refresh_pending:
		refresh()
	# A panel can be kept alive while HUD toggles it.  Action feedback (for
	# example, "丢弃 1 个物品格") is intentionally transient; a later open must
	# not expose that result as if it were the currently selected item detail.
	if selected_inventory_index < 0 and selected_inventory_indices.is_empty() and selected_equipment_slot.is_empty():
		_hide_item_detail()


func refresh() -> void:
	if item_grid == null:
		return
	_refresh_pending = false
	_refresh_scheduled = false
	_refresh_execution_count += 1
	_reconcile_selection()
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
	_refresh_inventory_action_states()


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
			var item_ref: Variant = record if record is Dictionary else name
			_set_button_texture(button, _item_texture(GameData.get_item_record(item_ref), "inventoryIcon"))
			button.tooltip_text = _equipment_tooltip(slot, record)
		else:
			_set_button_texture(button, null)
		UIItemSelectionVisualScript.apply(button, slot == selected_equipment_slot, &"GothicEquipmentSlotButton", &"GothicSelectedEquipmentSlotButton")
		compatibility_lines.append(_compatibility_equipment_text(slot, record))
	equipment_label.text = "　".join(compatibility_lines)
	_ui_sync_empty_destinations()


func _refresh_character_stats() -> void:
	if equipment_stats_label == null:
		return
	if character_attribute_help != null:
		character_attribute_help.dismiss()
	if character_identity_help != null:
		character_identity_help.dismiss()
	var font_size := CHARACTER_STATS_FONT_SIZE
	character_identity_label.text = "[center][font_size=%d]%s[/font_size]\n\n[font_size=%d]%s    [url=attribute:等级][color=#8dbce8][u]等级：%d[/u][/color][/url][/font_size][/center]" % [
		font_size + 3, PlayerState.character_name.replace("[", "[lb]"),
		font_size + 1, PlayerState.profession.replace("[", "[lb]"), PlayerState.level,
	]
	equipment_stats_label.text = _character_stats_text(PlayerState.computed_stats)
	_layout_character_attributes()


func _layout_character_attributes() -> void:
	if equipment_stats_label == null or character_identity_label == null:
		return
	var panel := get_node("AttributePanel") as Control
	var decoration := panel.get_node("AttributePanelDecoration") as Control
	var frame := decoration.get_node("AttributePanelFrame") as Control
	var frame_rect := Rect2(decoration.position + frame.position, frame.size)
	var center_x := frame_rect.get_center().x
	var title := panel.get_node("AttributeTitle") as Label
	title.position = Vector2(center_x - 125.0, frame_rect.position.y)
	title.size = Vector2(250.0, 30.0)
	# At the reference 2664x1200 device, 30 logical units are 50 device pixels.
	# The reviewed candidate moved the old name down 100 px; the user's final
	# adjustment raises all content below the title by 50 px together.
	character_identity_label.position = Vector2(center_x - 109.0, 46.0)
	character_identity_label.size = Vector2(218.0, 88.0)
	# One width for the complete block, shaped from its longest complete row.
	# Values may widen/recenter the block, but cannot wrap pairs onto new rows.
	var body_width := 0.0
	var font := equipment_stats_label.get_theme_font("normal_font")
	var lines := equipment_stats_label.get_parsed_text().split("\n")
	var font_size := CHARACTER_STATS_FONT_SIZE
	var style := equipment_stats_label.get_theme_stylebox("normal")
	var margins := style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)
	for line: String in lines:
		body_width = maxf(body_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	# The approved range is zero through three digits. Keep the reviewed font
	# size while changing only the complete block's width and horizontal offset.
	equipment_stats_label.add_theme_font_size_override("normal_font_size", font_size)
	body_width = ceilf(body_width + margins)
	equipment_stats_label.position = Vector2(center_x - body_width * 0.5, 142.0)
	equipment_stats_label.size = Vector2(body_width, maxf(1.0, frame_rect.end.y - 158.0))


func _character_stats_text(stats: Dictionary) -> String:
	var help := preload("res://scripts/item_attribute_help.gd")
	var body := "生命 %d　魔法值 %d\n攻击 %d-%d\n魔法 %d-%d　道术 %d-%d\n防御 %d-%d　魔防 %d-%d\n准确 %d　敏捷 %d\n幸运 %d\n远程与魔法躲避 %d%%\n速度 %+d\n暴击 %.1f%%\n穿戴重量 %d/%d" % [
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
	return help.decorate(body)


func _character_attribute_explanation(term: String) -> String:
	if term == "等级":
		return "%d/%d" % [PlayerState.experience, PlayerState.experience_to_next_level()]
	return ""


func _refresh_bag_grid() -> void:
	if _bag_cells.is_empty():
		_initialize_bag_cells(BAG_VISIBLE_CAPACITY)
	for inventory_index in range(_bag_cells.size()):
		_update_bag_cell(inventory_index, _inventory_record(inventory_index))
	_stabilize_bag_layout()
	bag_summary_label.text = "金币 %d　负重 %d/%d" % [PlayerState.gold, PlayerState.inventory_weight(), PlayerState.max_inventory_weight()]
	if item_detail_presenter != null and item_detail_presenter.is_message_active():
		return
	if selected_inventory_index >= 0:
		_show_inventory_detail(selected_inventory_index)
	elif selected_equipment_slot.is_empty():
		_hide_item_detail()


func _initialize_bag_cells(target_count := BAG_CAPACITY) -> void:
	var bounded_target := mini(BAG_CAPACITY, maxi(0, target_count))
	for index in range(_bag_cells.size(), bounded_target):
		var cell := _create_bag_cell(index, {})
		item_grid.add_child(cell)
		_bag_cells.append(cell)
		_bag_cell_creation_count += 1
	_bag_cells_ready = _bag_cells.size() >= BAG_CAPACITY


func _continue_bag_cell_initialization() -> void:
	if _bag_cells_ready or _bag_cell_initialization_running:
		return
	_bag_cell_initialization_running = true
	while is_inside_tree() and _bag_cells.size() < BAG_CAPACITY:
		var first_new_index := _bag_cells.size()
		_initialize_bag_cells(first_new_index + BAG_BACKGROUND_CELL_BATCH)
		for index in range(first_new_index, _bag_cells.size()):
			_update_bag_cell(index, _inventory_record(index))
		item_grid.queue_sort()
		await get_tree().process_frame
	_bag_cells_ready = _bag_cells.size() >= BAG_CAPACITY
	_bag_cell_initialization_running = false


func wait_until_runtime_ready() -> void:
	if not _bag_cells_ready:
		_continue_bag_cell_initialization()
	while is_inside_tree() and not _bag_cells_ready:
		await get_tree().process_frame


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
	UIActivationOnceScript.attach(button, _select_inventory_item.bind(index))
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
	var can_receive_unequip := not occupied and _can_receive_unequip_to_index(index)
	button.name = "ItemButton" if occupied else "EmptySlotBackground"
	button.disabled = not occupied and not can_receive_unequip
	button.mouse_filter = Control.MOUSE_FILTER_STOP if occupied or can_receive_unequip else Control.MOUSE_FILTER_IGNORE
	button.tooltip_text = str(stack.get("name", "未知物品")) if occupied else ("卸下到此格" if can_receive_unequip else "空物品格")
	UIItemSelectionVisualScript.apply(button, occupied and selected_inventory_indices.has(index), &"GothicComponentSlotButton", &"GothicComponentSelectedSlotButton")
	_set_button_texture(button, UIItemTextureCacheScript.texture_for_item(stack) if occupied else null)
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


func _inventory_selection_ref(index: int, record: Dictionary) -> Dictionary:
	var instance_id := str(record.get("instance_id", ""))
	return {
		"container": "inventory",
		"slot": index,
		"index": index,
		"instance_id": instance_id,
		"revision": _selection_revision,
	}


func _equipment_selection_ref(slot: String, record: Dictionary) -> Dictionary:
	return {
		"container": "equipment",
		"slot": slot,
		"instance_id": str(record.get("instance_id", "")),
		"revision": _selection_revision,
	}


func _same_selection_ref(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty() or str(left.get("container", "")) != str(right.get("container", "")):
		return false
	var left_instance := str(left.get("instance_id", ""))
	var right_instance := str(right.get("instance_id", ""))
	if not left_instance.is_empty() or not right_instance.is_empty():
		return not left_instance.is_empty() and left_instance == right_instance
	return int(left.get("slot", -1)) == int(right.get("slot", -1)) and int(left.get("revision", -1)) == int(right.get("revision", -1))


func _find_inventory_index_for_ref(selection_ref: Dictionary) -> int:
	if selection_ref.is_empty() or str(selection_ref.get("container", "")) != "inventory":
		return -1
	var instance_id := str(selection_ref.get("instance_id", ""))
	if not instance_id.is_empty():
		for index in range(PlayerState.inventory.size()):
			var record := _inventory_record(index)
			if str(record.get("instance_id", "")) == instance_id:
				return index
	var index := int(selection_ref.get("slot", selection_ref.get("index", -1)))
	if index < 0 or index >= PlayerState.inventory.size() or _inventory_record(index).is_empty():
		return -1
	# A stackable without an opaque identity is safe only until the data revision
	# changes; otherwise a sort could silently retarget another stack.
	return index if int(selection_ref.get("revision", _selection_revision)) == _selection_revision else -1


func _reconcile_selection() -> void:
	var rebound: Array[Dictionary] = []
	var rebound_indices: Dictionary = {}
	for selection_ref: Dictionary in selected_inventory_refs:
		var index := _find_inventory_index_for_ref(selection_ref)
		if index < 0:
			continue
		var refreshed_ref := _inventory_selection_ref(index, _inventory_record(index))
		refreshed_ref["revision"] = _selection_revision
		rebound.append(refreshed_ref)
		rebound_indices[index] = true
	selected_inventory_refs = rebound
	selected_inventory_indices = rebound_indices
	selected_inventory_ref = rebound.back() if not rebound.is_empty() else {}
	selected_inventory_index = _find_inventory_index_for_ref(selected_inventory_ref)
	if not selected_equipment_slot.is_empty():
		var equipped: Variant = PlayerState.equipment.get(selected_equipment_slot, {})
		if equipped is Dictionary and not equipped.is_empty():
			selected_equipment_ref = _equipment_selection_ref(selected_equipment_slot, equipped)
		else:
			selected_equipment_slot = ""
			selected_equipment_ref.clear()


func _selection_control_context(_control: Control, extra: Dictionary = {}) -> Dictionary:
	var context := {"presentation_zone": "inventory"}
	context.merge(extra, true)
	return context


func _empty_bag_region_candidates() -> Array[Rect2]:
	# Compatibility only. R5 never places details on empty item cells.
	return []


func _hide_item_detail() -> void:
	if item_detail_presenter != null:
		item_detail_presenter.hide_detail()


func _show_presented_item(item: Dictionary, instance: Dictionary, anchor: Control, context_extra: Dictionary = {}) -> void:
	if item_detail_presenter == null:
		return
	var context := _selection_control_context(anchor, context_extra)
	item_detail_presenter.show_item(item, instance, context)
	detail_label = item_detail_presenter.detail_label


func _select_inventory_item(index: int) -> void:
	if _press_cancelled or TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	if _inventory_record(index).is_empty():
		if _can_receive_unequip_to_index(index):
			_unequip_to_inventory_slot(index)
		else:
			_ui_dismiss_selection()
		return
	if not selected_equipment_slot.is_empty() and _first_empty_inventory_slot() < 0:
		# An unequip attempt cannot proceed while the bag has no empty cell;
		# surface the failure instead of silently swallowing the intent.
		_show_error_message("背包已满，没有空位可以卸下装备。")
	if _suppress_next_pressed_index == index:
		_suppress_next_pressed_index = -1
		return
	var old_selected_index := selected_inventory_index
	var selection_ref := _inventory_selection_ref(index, _inventory_record(index))
	var existing_position := -1
	for ref_index in range(selected_inventory_refs.size()):
		if _same_selection_ref(selected_inventory_refs[ref_index], selection_ref):
			existing_position = ref_index
			break
	if existing_position >= 0:
		selected_inventory_refs.remove_at(existing_position)
		selected_inventory_indices.erase(index)
	else:
		selected_inventory_refs.append(selection_ref)
		selected_inventory_indices[index] = true
	selected_inventory_ref = selected_inventory_refs.back() if not selected_inventory_refs.is_empty() else {}
	selected_inventory_index = _find_inventory_index_for_ref(selected_inventory_ref)
	selected_equipment_slot = ""
	selected_equipment_ref.clear()
	if selected_inventory_index >= 0:
		# Multi-select remains a batch operation for actions, while the shared
		# presenter always follows the latest selected instance.  This keeps the
		# attribute view useful without enabling equipment actions for a batch.
		_show_inventory_detail(selected_inventory_index)
	else:
		_hide_item_detail()
	_refresh_equipment_slots()
	for cell_index: int in [old_selected_index, index]:
		_refresh_bag_cell_selection(cell_index)
	_refresh_inventory_action_states()


func _refresh_bag_cell_selection(index: int) -> void:
	if index < 0 or index >= _bag_cells.size():
		return
	_selection_cell_update_count += 1
	var button := _bag_cells[index].get_child(0) as Button
	UIItemSelectionVisualScript.apply(button, selected_inventory_indices.has(index), &"GothicComponentSlotButton", &"GothicComponentSelectedSlotButton")


func _clear_inventory_selection_styles() -> void:
	var changed_indices: Array = selected_inventory_indices.keys()
	if selected_inventory_index >= 0 and not changed_indices.has(selected_inventory_index):
		changed_indices.append(selected_inventory_index)
	selected_inventory_index = -1
	selected_inventory_indices.clear()
	selected_inventory_refs.clear()
	selected_inventory_ref.clear()
	for raw_index: Variant in changed_indices:
		_refresh_bag_cell_selection(int(raw_index))
	_refresh_inventory_action_states()


func _refresh_inventory_action_states() -> void:
	if discard_button == null:
		return
	# Discard is a selection-scoped transaction.  An empty selection must use
	# the shared unavailable (grey) state and must not accept pointer input.
	discard_button.disabled = selected_inventory_indices.is_empty()


## Center-screen timed toast via the owning HUD — the same channel as the
## spell prompts (e.g. "目标被遮挡或已失效"). The HUD instantiates and owns
## this panel (hud._ensure_inventory_panel), so the parent is the GameHUD.
## Unified player-error exit for every equipment/inventory rejection. Routed to
## the HUD's dedicated error channel (above all modal panels); the item detail
## region keeps presenting item name/attributes/requirements only.
func _show_error_message(message: String, seconds := 2.0) -> void:
	var hud_node := get_parent()
	if hud_node != null and hud_node.has_method("show_error_message"):
		hud_node.show_error_message(message, seconds)


func _select_equipment_slot(slot: String) -> void:
	if _press_cancelled or TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	if selected_inventory_refs.size() > 1:
		# A multi-selection is a batch operation only; never silently choose the
		# last item when the player taps an equipment slot.
		return
	if selected_inventory_index >= 0 and not _inventory_record(selected_inventory_index).is_empty():
		var item := GameData.get_item_record(_inventory_record(selected_inventory_index))
		if str(item.get("kind", "")) == "equipment":
			var allowed: Array = _slots_for_category(str(item.get("category", "")))
			if not allowed.has(slot):
				# A rejected slot click must leave both the source selection and its
				# attribute view intact; the authority was never called.
				_show_inventory_detail(selected_inventory_index)
				_show_error_message(
					"%s不能装备到%s位置。" % [
						str(item.get("name", "该装备")),
						slot,
					]
				)
				return
			var source_index := selected_inventory_index
			var expected_instance_id := str(selected_inventory_ref.get("instance_id", ""))
			var result: Dictionary = PlayerState.equip_inventory_index_result(source_index, slot, expected_instance_id)
			if bool(result.get("success", false)):
				_selection_revision = maxi(_selection_revision, int(result.get("revision", _selection_revision)))
				selected_inventory_index = -1
				selected_inventory_indices.clear()
				selected_inventory_refs.clear()
				selected_inventory_ref.clear()
				selected_equipment_slot = str(result.get("destination", {}).get("slot", slot))
				var equipped: Variant = PlayerState.equipment.get(selected_equipment_slot, {})
				selected_equipment_ref = _equipment_selection_ref(selected_equipment_slot, equipped) if equipped is Dictionary else {}
				refresh()
				_show_equipment_detail(selected_equipment_slot)
			else:
				# Rejected transactions leave the original source selection and
				# detail intact; the failure surfaces through the dedicated
				# center-screen error channel, never as a machine reason.
				_show_inventory_detail(source_index)
				_show_error_message(
					UIErrorFeedbackScript.from_result(result, "无法装备该装备。"),
					2.0
				)
			return
	if selected_equipment_slot == slot:
		_clear_equipment_selection()
		return
	selected_equipment_slot = slot
	selected_equipment_ref.clear()
	_clear_inventory_selection_styles()
	var equipped: Variant = PlayerState.equipment.get(slot, {})
	if equipped is Dictionary and not equipped.is_empty():
		selected_equipment_ref = _equipment_selection_ref(slot, equipped)
		_show_equipment_detail(slot)
	else:
		item_detail_presenter.show_message("[color=#e0bd83][font_size=18]%s[/font_size][/color]\n当前为空。按住背包中的对应装备可选择穿戴位置。" % slot, _selection_control_context(equipment_buttons.get(slot), {"presentation_zone": "equipment", "slot": slot}))
	_refresh_equipment_slots()


func _clear_equipment_selection() -> void:
	selected_equipment_slot = ""
	selected_equipment_ref.clear()
	_hide_item_detail()
	_refresh_equipment_slots()
	_refresh_inventory_action_states()


func _show_equipment_detail(slot: String) -> void:
	var equipped: Variant = PlayerState.equipment.get(slot, {})
	if not equipped is Dictionary or (equipped as Dictionary).is_empty():
		return
	var record: Dictionary = equipped
	var item := GameData.get_item_record(record)
	if item.is_empty():
		item_detail_presenter.show_message(
			"物品目录缺少此记录。",
			_selection_control_context(equipment_buttons.get(slot), {"presentation_zone": "equipment", "slot": slot}),
		)
		return
	_show_presented_item(item, record, equipment_buttons.get(slot), {"slot": slot, "presentation_zone": "equipment"})


func _can_receive_unequip_to_index(index: int) -> bool:
	if selected_equipment_slot.is_empty() or selected_equipment_ref.is_empty():
		return false
	if index < 0 or index >= BAG_CAPACITY or index >= _bag_cells.size():
		return false
	return _inventory_record(index).is_empty()


func _unequip_to_inventory_slot(index: int) -> void:
	if not _can_receive_unequip_to_index(index):
		return
	var slot := selected_equipment_slot
	var expected_instance_id := str(selected_equipment_ref.get("instance_id", ""))
	var result: Dictionary = PlayerState.unequip_to_inventory_slot(slot, index, expected_instance_id)
	if not bool(result.get("success", false)):
		# Keep the source slot selected after any rejection (stale, occupied,
		# overweight, capacity or save failure). The rejection itself surfaces
		# through the dedicated error channel.
		_show_equipment_detail(slot)
		_show_error_message(
			UIErrorFeedbackScript.from_result(result, "无法卸下该装备，请重新操作。"),
			2.0
		)
		return
	_selection_revision = maxi(_selection_revision, int(result.get("revision", _selection_revision)))
	selected_equipment_slot = ""
	selected_equipment_ref.clear()
	selected_inventory_indices.clear()
	selected_inventory_refs.clear()
	var destination: Dictionary = result.get("destination", {})
	var destination_index := int(destination.get("slot", index))
	var destination_record := _inventory_record(destination_index)
	if not destination_record.is_empty():
		selected_inventory_index = destination_index
		selected_inventory_indices[destination_index] = true
		selected_inventory_ref = _inventory_selection_ref(destination_index, destination_record)
		selected_inventory_refs.append(selected_inventory_ref.duplicate(true))
	else:
		selected_inventory_index = -1
	refresh()
	if selected_inventory_index >= 0:
		_show_inventory_detail(selected_inventory_index)
	else:
		_hide_item_detail()


func _show_inventory_detail(index: int) -> void:
	var stack := _inventory_record(index)
	if stack.is_empty():
		_hide_item_detail()
		return
	var item := GameData.get_item_record(stack)
	if item.is_empty():
		item_detail_presenter.show_message("[color=#f2c783]%s[/color]\n物品目录缺少此记录。" % stack.get("name", "未知物品"), _selection_control_context(_bag_cells[index].get_child(0) as Control if index < _bag_cells.size() else null))
		return
	var anchor: Control = _bag_cells[index].get_child(0) as Control if index < _bag_cells.size() else self
	_show_presented_item(item, stack, anchor, {"count": int(stack.get("count", 1))})


func _inventory_input(event: InputEvent, index: int, button: Button) -> void:
	var stack := _inventory_record(index)
	if stack.is_empty():
		# A populated equipment selection turns an empty cell into an explicit
		# unequip destination. Do not execute on DOWN: pressed will execute ONCE.
		if event is InputEventScreenTouch and event.pressed:
			_press_cancelled = false
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_press_cancelled = false
		return
	if _is_double_activation_event(event):
		UIActivationOnceScript.suppress_for(button)
		_cancel_long_press()
		_press_cancelled = false
		_clear_inventory_selection_styles()
		var item := GameData.get_item_record(stack)
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
	var item := GameData.get_item_record(stack)
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
	var result: Dictionary = {}
	var legacy_message := ""
	match str(action.get("action", "none")):
		"equip":
			var equip_index := int(action.get("index", -1))
			var equip_record := _inventory_record(equip_index)
			result = PlayerState.equip_inventory_index_result(equip_index, str(action.get("slot", "")), str(equip_record.get("instance_id", "")))
		"unequip":
			var target_slot := _first_empty_inventory_slot()
			if target_slot < 0:
				var occupied_slot := str(action.get("slot", ""))
				_show_equipment_detail(occupied_slot)
				_show_error_message("背包已满，没有空位可以卸下装备。")
				return
			var equipped: Variant = PlayerState.equipment.get(str(action.get("slot", "")), {})
			result = PlayerState.unequip_to_inventory_slot(str(action.get("slot", "")), target_slot, str(equipped.get("instance_id", "")) if equipped is Dictionary else "")
		"use":
			legacy_message = PlayerState.use_inventory_index(int(action.get("index", -1)))
		_:
			return
	if not legacy_message.is_empty():
		_clear_inventory_selection_styles()
		_clear_equipment_selection()
		refresh()
		item_detail_presenter.show_message("[color=#e8c277]%s[/color]" % legacy_message)
		return
	if bool(result.get("success", false)):
		_clear_inventory_selection_styles()
		selected_equipment_slot = str(result.get("destination", {}).get("slot", "")) if str(result.get("destination", {}).get("container", "")) == "equipment" else ""
		if selected_equipment_slot.is_empty():
			selected_equipment_ref = {}
		else:
			var equipped_after: Variant = PlayerState.equipment.get(selected_equipment_slot, {})
			selected_equipment_ref = _equipment_selection_ref(selected_equipment_slot, equipped_after) if equipped_after is Dictionary else {}
		refresh()
		if not selected_equipment_slot.is_empty():
			_show_equipment_detail(selected_equipment_slot)
		else:
			_hide_item_detail()
	else:
		# Failed transaction keeps the prior selection and presenter; no prose
		# substring is used to infer the authority result. The authoritative
		# failure message surfaces via the dedicated error channel.
		if not selected_inventory_ref.is_empty():
			_show_inventory_detail(selected_inventory_index)
		elif not selected_equipment_slot.is_empty():
			_show_equipment_detail(selected_equipment_slot)
		_show_error_message(
			UIErrorFeedbackScript.from_result(result, "操作未能完成，请重新操作。"),
			2.0
		)


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
	selected_inventory_indices[index] = true
	selected_inventory_ref = _inventory_selection_ref(index, stack)
	selected_inventory_refs = [selected_inventory_ref.duplicate(true)]
	selected_equipment_slot = ""
	selected_equipment_ref.clear()
	var item := GameData.get_item_record(stack)
	var is_equipment := str(item.get("kind", "")) == "equipment"
	# use_inventory_index emits inventory_changed synchronously.  Clear the
	# selection before that signal so a consumed stack removal cannot make the
	# signal-driven refresh show the next item under the old index.
	if not is_equipment:
		selected_inventory_index = -1
		selected_inventory_indices.clear()
	if is_equipment:
		var result: Dictionary = PlayerState.equip_inventory_index_result(index, preferred_slot, str(selected_inventory_ref.get("instance_id", "")))
		if bool(result.get("success", false)):
			_selection_revision = maxi(_selection_revision, int(result.get("revision", _selection_revision)))
			_clear_inventory_selection_styles()
			selected_equipment_slot = str(result.get("destination", {}).get("slot", preferred_slot))
			var equipped: Variant = PlayerState.equipment.get(selected_equipment_slot, {})
			selected_equipment_ref = _equipment_selection_ref(selected_equipment_slot, equipped) if equipped is Dictionary else {}
			refresh()
			_show_equipment_detail(selected_equipment_slot)
		else:
			_show_inventory_detail(index)
			_show_error_message(
				UIErrorFeedbackScript.from_result(result, "无法装备该装备。"),
				2.0
			)
		return
	var result_message := PlayerState.use_inventory_index(index)
	_clear_inventory_selection_styles()
	refresh()
	item_detail_presenter.show_message("[color=#e8c277]%s[/color]" % result_message)


func _clear_pressed_suppression(index: int) -> void:
	if _suppress_next_pressed_index == index:
		_suppress_next_pressed_index = -1


func _first_empty_inventory_slot() -> int:
	for index in range(BAG_CAPACITY):
		if _inventory_record(index).is_empty():
			return index
	return -1


func _on_auto_sort_pressed() -> void:
	_clear_inventory_action_feedback()
	GothicUIThemeScript.set_button_feedback(auto_sort_button, GothicUIThemeScript.BUTTON_FEEDBACK_BUSY, "inventory.sort")
	var result: Dictionary = PlayerState.sort_inventory_deterministic()
	_clear_inventory_selection_styles()
	_clear_equipment_selection()
	refresh()
	if bool(result.get("success", false)):
		item_detail_presenter.show_message("[color=#e8c277]自动整理完成[/color]")
	else:
		# A rejected sort is an operation failure: dedicated error channel,
		# while the success notice stays in the original presenter lane.
		_show_error_message("自动整理失败，物品顺序未改变。")
	_show_inventory_action_result(auto_sort_button, bool(result.get("success", false)), "inventory.sort")


func _on_discard_pressed() -> void:
	if discard_button == null or discard_button.disabled or selected_inventory_indices.is_empty():
		return
	var indices: Array = selected_inventory_indices.keys()
	_clear_inventory_action_feedback()
	var result: Dictionary = PlayerState.destroy_inventory_indices(indices)
	var destroyed := int(result.get("destroyed", 0))
	var complete := bool(result.get("success", false)) and destroyed == indices.size()
	_ui_dismiss_selection()
	refresh()
	if complete:
		# This is the deliberately removed success toast. No transient "丢弃N格",
		# no selected source/destination, no green action flash after completion.
		# The paired, minimal destroy_inventory_indices patch only returns
		# success after persistence succeeds; the UI never performs another save.
		return
	var message := str(result.get("message", ""))
	if message.is_empty():
		message = "部分物品未能丢弃，请重新选择后重试。" if destroyed > 0 else "物品状态已变化，未能丢弃，请重新选择。"
	# A failed discard is an operation failure: dedicated error channel.
	_show_error_message(UIErrorFeedbackScript.from_result(result, message))


func _show_inventory_action_result(button: Button, success: bool, group: String) -> void:
	_action_feedback_serial += 1
	var serial := _action_feedback_serial
	# Synchronous inventory mutations can finish in the same input frame.  Keep
	# the busy cue on screen for one rendered frame before presenting the result.
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


func _clear_inventory_action_feedback() -> void:
	_action_feedback_serial += 1
	GothicUIThemeScript.clear_button_feedback(auto_sort_button)
	GothicUIThemeScript.clear_button_feedback(discard_button)


func _unequip_selected() -> void:
	if selected_equipment_slot.is_empty():
		return
	var target_slot := _first_empty_inventory_slot()
	if target_slot < 0:
		_show_equipment_detail(selected_equipment_slot)
		_show_error_message("背包已满，没有空位可以卸下装备。")
		return
	var slot := selected_equipment_slot
	var result: Dictionary = PlayerState.unequip_to_inventory_slot(slot, target_slot, str(selected_equipment_ref.get("instance_id", "")))
	if not bool(result.get("success", false)):
		_show_equipment_detail(slot)
		_show_error_message(
			UIErrorFeedbackScript.from_result(result, "无法卸下该装备，请重新操作。"),
			2.0
		)
		return
	_selection_revision = maxi(_selection_revision, int(result.get("revision", _selection_revision)))
	selected_equipment_slot = ""
	selected_equipment_ref.clear()
	refresh()
	var destination_index := int(result.get("destination", {}).get("slot", target_slot))
	if not _inventory_record(destination_index).is_empty():
		selected_inventory_index = destination_index
		selected_inventory_indices[destination_index] = true
		selected_inventory_ref = _inventory_selection_ref(destination_index, _inventory_record(destination_index))
		selected_inventory_refs = [selected_inventory_ref.duplicate(true)]
		_show_inventory_detail(destination_index)
	else:
		_hide_item_detail()


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
	var item := GameData.get_item_record(record)
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
		parts.append("远程与魔法躲避 %+d%%" % int(item.get("magicEvasionPercent", 0)))
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
	_ui_dismiss_selection()
	_clear_inventory_action_feedback()
	_cancel_long_press()
	context_menu.hide()
	hide()
	closed.emit()


func _ui_detail_region(context: Dictionary) -> Dictionary:
	if str(context.get("presentation_zone", "inventory")) == "equipment":
		return UIItemDetailDockScript.equipment_region(self, equipment_buttons)
	return UIItemDetailDockScript.side_region(self, get_node_or_null("BagPanel/InventoryScroll") as Control, "right")

func _ui_selection_token() -> Array:
	return [selected_inventory_refs.duplicate(true), selected_inventory_indices.duplicate(), selected_equipment_slot, selected_equipment_ref.duplicate(true), _selection_revision, item_detail_presenter.content_epoch() if item_detail_presenter != null else -1]

func _ui_dismiss_selection() -> void:
	_clear_inventory_action_feedback()
	if _press_timer != null:
		_cancel_long_press()
	_press_cancelled = false
	_suppress_next_pressed_index = -1
	if context_menu != null:
		context_menu.hide()
	selected_equipment_slot = ""
	selected_equipment_ref.clear()
	_clear_inventory_selection_styles()
	_hide_item_detail()
	if not equipment_buttons.is_empty():
		_refresh_equipment_slots()

func _ui_sync_empty_destinations() -> void:
	# A no-selection empty cell is passive; an unequip destination is functional.
	# Refresh these flags immediately on equipment selection, not on a later
	# inventory_changed signal, so the first empty-cell click already works.
	for index in range(_bag_cells.size()):
		if not _inventory_record(index).is_empty():
			continue
		var button := _bag_cells[index].get_child(0) as Button
		var functional := _can_receive_unequip_to_index(index)
		button.disabled = not functional
		button.mouse_filter = Control.MOUSE_FILTER_STOP if functional else Control.MOUSE_FILTER_IGNORE
		button.tooltip_text = "卸下到此格" if functional else ""
		UIItemSelectionVisualScript.apply(button, false, &"GothicComponentSlotButton", &"GothicComponentSelectedSlotButton")
