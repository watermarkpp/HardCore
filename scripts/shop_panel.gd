class_name ShopPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const GothicConfirmationPanelScript := preload("res://scripts/gothic_confirmation_panel.gd")
const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")
const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")
const TouchScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")
const UIRuntimeLayoutOverridesScript := preload("res://scripts/ui_runtime_layout_overrides.gd")

signal closed
signal buy_quotes_requested(stock: Array)
signal buy_requested(request: Dictionary)
signal sell_quotes_requested(items: Array)
signal sell_requested(request: Dictionary)

const PANEL_SIZE := Vector2(1080, 620)
const CARD_SIZE := Vector2(286, 72)
const CARD_COLUMNS := 2
const SHARED_SHOP_LAYOUT_REVISION := 1
const QUANTITY_HOLD_INITIAL_DELAY := 0.42
const QUANTITY_HOLD_REPEAT_INTERVAL := 0.16
const QUANTITY_HOLD_MIN_INTERVAL := 0.035
const QUANTITY_HOLD_ACCELERATION := 0.82

var shop_title: Label
var gold_label: Label
var item_list: ItemList
var buy_tab_button: Button
var sell_tab_button: Button
var goods_grid: GridContainer
var goods_buttons: Array[Button] = []
var detail_label: RichTextLabel
var buy_button: Button
var repair_button: Button
var sell_quantity_row: Control
var sell_quantity_label: Label
var sell_one_button: Button
var sell_quantity_button: Button
var decrease_quantity_button: Button
var increase_quantity_button: Button
var _quantity_hold_timer: Timer
var _quantity_hold_delta := 0
var _quantity_hold_interval := QUANTITY_HOLD_REPEAT_INTERVAL
var sell_confirmation: Control
var stock: Array = []
var _merchant_context: Dictionary = {}
var _trade_mode := "buy"
var _buy_quotes: Array = []
var _buy_quotes_by_index: Dictionary = {}
var _selected_buy_index := -1
var _buy_request_locked := false
var _buy_lock_serial := 0
var _transaction_feedback_serial := 0
var _sell_quotes: Dictionary = {}
var _selected_sell_index := -1
var _sell_quantity := 1
var _selected_sell_indices: Dictionary = {}
var _sell_quantities: Dictionary = {}
var _pending_sell_request: Dictionary = {}
var _batch_sell_queue: Array = []
var _batch_sell_active := false
var _inventory_refresh_pending := false
var _inventory_refresh_execution_count := 0
var _inventory_refresh_scheduled := false
var _goods_card_pool: Array[Button] = []
var _goods_card_creation_count := 0
var _goods_card_content_update_count := 0
var _sell_structure_indices: Array[int] = []
var _sell_structure_tokens: Array[String] = []
var _sell_structure_bind_count := 0
var _sell_quote_patch_count := 0
var _sell_visibility_change_count := 0
var _sell_catalog_lookup_count := 0
var _sell_texture_lookup_count := 0
var _applied_layout_profiles: Dictionary = {}
var _layout_apply_count := 0


func _ready() -> void:
	set_meta("calibration_retired_paths", [
		"DetailPanel/SellOneButton",
		"DetailPanel/SellQuantityRow/DecreaseQuantity/QuantityDecoration",
		"DetailPanel/SellQuantityRow/IncreaseQuantity/QuantityDecoration",
	])
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_bottom = PANEL_SIZE.y * 0.5
	z_index = 60
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GothicUIThemeScript.build()
	theme_type_variation = "GothicModalFrame"
	_build_modal_surface()
	_build_header()
	_build_goods_section()
	_build_detail_section()
	_build_compatibility_list()
	GothicFrameFactoryScript.seal_modal_rings(self)
	PlayerState.profile_changed.connect(_refresh_gold)
	PlayerState.equipment_changed.connect(_refresh_repair_preview)
	PlayerState.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)
	_refresh_gold()
	_refresh_repair_preview()
	_apply_layout_profile_once("shop_buy")


func _build_modal_surface() -> void:
	GothicFrameFactoryScript.add_modal_fill(self, PANEL_SIZE)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(290, 10)
	title_frame.size = Vector2(500, 64)
	title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_frame.theme_type_variation = "GothicTitleBar"
	add_child(title_frame)
	shop_title = Label.new()
	shop_title.name = "ShopTitle"
	shop_title.text = "商店"
	shop_title.position = Vector2(34, 15)
	shop_title.size = Vector2(432, 34)
	shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_title.add_theme_font_size_override("font_size", 24)
	shop_title.add_theme_color_override("font_color", Color("f1cc88"))
	title_frame.add_child(shop_title)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.position = Vector2(1000, 8)
	close_button.size = Vector2(56, 56)
	close_button.theme_type_variation = "GothicComponentCloseButton"
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(_close)
	add_child(close_button)


func _build_goods_section() -> void:
	var panel := _framed_section("GoodsPanel", Rect2(41.400146484375, 76, 620, 476))
	panel.set_meta("calibration_layout_revision", SHARED_SHOP_LAYOUT_REVISION)
	var decoration := panel.get_node("GoodsPanelDecoration") as Control
	decoration.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	decoration.position = Vector2(-0.599853515625, -26.4000091552734)
	decoration.size = Vector2(659.834838867188, 510)
	decoration.set_meta("calibration_layout_revision", SHARED_SHOP_LAYOUT_REVISION)
	buy_tab_button = Button.new()
	buy_tab_button.name = "BuyTab"
	buy_tab_button.text = "购买"
	buy_tab_button.position = Vector2(47.5127563476563, 10)
	buy_tab_button.size = Vector2(128, 51)
	buy_tab_button.set_meta("calibration_layout_revision", SHARED_SHOP_LAYOUT_REVISION)
	buy_tab_button.theme_type_variation = "GothicShopTradeTabSelectedGemButton"
	buy_tab_button.pressed.connect(_set_trade_mode.bind("buy"))
	panel.add_child(buy_tab_button)
	sell_tab_button = Button.new()
	sell_tab_button.name = "SellTab"
	sell_tab_button.text = "出售"
	sell_tab_button.position = Vector2(191.476745605469, 10)
	sell_tab_button.size = Vector2(128, 51)
	sell_tab_button.set_meta("calibration_layout_revision", SHARED_SHOP_LAYOUT_REVISION)
	sell_tab_button.theme_type_variation = "GothicShopTradeTabGemButton"
	sell_tab_button.pressed.connect(_set_trade_mode.bind("sell"))
	panel.add_child(sell_tab_button)
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.position = Vector2(331.2099609375, 23)
	gold_label.size = Vector2(246, 28)
	gold_label.set_meta("calibration_layout_revision", SHARED_SHOP_LAYOUT_REVISION)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.theme_type_variation = "GothicMutedLabel"
	gold_label.add_theme_color_override("font_color", Color("d6b16f"))
	panel.add_child(gold_label)
	var scroll := ScrollContainer.new()
	scroll.name = "GoodsScroll"
	scroll.position = Vector2(37.7950286865234, 66.3999786376953)
	scroll.size = Vector2(587.852905273438, 360)
	scroll.set_meta("calibration_layout_revision", SHARED_SHOP_LAYOUT_REVISION)
	# The section's approved secondary frame already defines the list boundary.
	# Keep the scroll viewport visually borderless so it does not add a third,
	# thin outline around the sellable-goods array.
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	goods_grid = GridContainer.new()
	goods_grid.name = "GoodsGrid"
	goods_grid.columns = CARD_COLUMNS
	goods_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goods_grid.add_theme_constant_override("h_separation", 12)
	goods_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(goods_grid)


func _build_detail_section() -> void:
	var panel := _framed_section("DetailPanel", Rect2(674, 76, 364, 476))
	panel.set_meta("calibration_layout_revision", SHARED_SHOP_LAYOUT_REVISION)
	var decoration := panel.get_node("DetailPanelDecoration") as Control
	decoration.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	decoration.position = Vector2(-4.19891357421875, -26.3999938964844)
	decoration.size = Vector2(365.908416748047, 510)
	decoration.set_meta("calibration_layout_revision", SHARED_SHOP_LAYOUT_REVISION)
	var detail_title := _section_title("DetailTitle", "商品详情", 366)
	detail_title.set_meta("calibration_layout_revision", SHARED_SHOP_LAYOUT_REVISION)
	panel.add_child(detail_title)
	detail_label = RichTextLabel.new()
	detail_label.name = "DetailLabel"
	detail_label.set_meta("calibration_runtime_text", true)
	detail_label.position = Vector2(36.1974487304688, 129.199844360352)
	detail_label.size = Vector2(287.927917480469, 150.000259399414)
	detail_label.set_meta("calibration_layout_revision", SHARED_SHOP_LAYOUT_REVISION)
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.theme_type_variation = "GothicDetailText"
	panel.add_child(detail_label)
	buy_button = Button.new()
	buy_button.name = "BuyButton"
	buy_button.text = "购买"
	buy_button.position = Vector2(47, 318)
	buy_button.size = Vector2(270, 51)
	buy_button.set_meta("calibration_layout_revision", 1)
	# Buying is a transaction action; the buy/sell tabs own persistent selection.
	buy_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	buy_button.theme_type_variation = "GothicShopBuyActionGemButton"
	buy_button.add_theme_font_size_override("font_size", GothicUIThemeScript.BUTTON_ACTION_FONT_SIZE)
	buy_button.pressed.connect(_buy_selected)
	panel.add_child(buy_button)
	repair_button = Button.new()
	repair_button.name = "RepairButton"
	repair_button.text = "维修全部装备"
	repair_button.position = Vector2(47, 381)
	repair_button.size = Vector2(270, 51)
	repair_button.set_meta("calibration_layout_revision", 1)
	repair_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	repair_button.theme_type_variation = "GothicShopBuyActionGemButton"
	repair_button.add_theme_font_size_override("font_size", GothicUIThemeScript.BUTTON_ACTION_FONT_SIZE)
	repair_button.pressed.connect(_repair_all)
	panel.add_child(repair_button)
	sell_quantity_row = Control.new()
	sell_quantity_row.name = "SellQuantityRow"
	sell_quantity_row.position = Vector2(20, 302)
	sell_quantity_row.size = Vector2(326, 46)
	sell_quantity_row.visible = false
	sell_quantity_row.clip_contents = true
	panel.add_child(sell_quantity_row)
	var minus_button := Button.new()
	decrease_quantity_button = minus_button
	minus_button.name = "DecreaseQuantity"
	minus_button.text = ""
	minus_button.tooltip_text = "减少出售数量"
	minus_button.set_meta("quantity_delta", -1)
	minus_button.add_theme_font_size_override("font_size", 18)
	minus_button.position = Vector2(8, 0)
	minus_button.size = Vector2(58, 46)
	minus_button.theme_type_variation = "GothicShopSellQuantityPlainButton"
	minus_button.clip_contents = true
	_add_quantity_symbol(minus_button, false)
	minus_button.button_down.connect(_start_quantity_hold.bind(-1))
	minus_button.button_up.connect(_stop_quantity_hold)
	sell_quantity_row.add_child(minus_button)
	var quantity_background := Panel.new()
	quantity_background.name = "QuantityCenterBackground"
	quantity_background.position = Vector2(76, 6)
	quantity_background.size = Vector2(174, 34)
	quantity_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_background.clip_contents = true
	quantity_background.theme_type_variation = "GothicModalSurface"
	sell_quantity_row.add_child(quantity_background)
	sell_quantity_label = Label.new()
	sell_quantity_label.name = "Quantity"
	sell_quantity_label.position = Vector2(77, 7)
	sell_quantity_label.size = Vector2(172, 32)
	sell_quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sell_quantity_label.add_theme_font_size_override("font_size", 16)
	sell_quantity_row.add_child(sell_quantity_label)
	var plus_button := Button.new()
	increase_quantity_button = plus_button
	plus_button.name = "IncreaseQuantity"
	plus_button.text = ""
	plus_button.tooltip_text = "增加出售数量"
	plus_button.set_meta("quantity_delta", 1)
	plus_button.add_theme_font_size_override("font_size", 18)
	plus_button.position = Vector2(260, 0)
	plus_button.size = Vector2(58, 46)
	plus_button.theme_type_variation = "GothicShopSellQuantityPlainButton"
	plus_button.clip_contents = true
	_add_quantity_symbol(plus_button, true)
	plus_button.button_down.connect(_start_quantity_hold.bind(1))
	plus_button.button_up.connect(_stop_quantity_hold)
	sell_quantity_row.add_child(plus_button)
	_quantity_hold_timer = Timer.new()
	_quantity_hold_timer.name = "QuantityHoldTimer"
	_quantity_hold_timer.one_shot = true
	_quantity_hold_timer.timeout.connect(_on_quantity_hold_timeout)
	sell_quantity_row.add_child(_quantity_hold_timer)
	sell_quantity_button = Button.new()
	sell_quantity_button.name = "SellQuantityButton"
	sell_quantity_button.text = "出售"
	sell_quantity_button.position = Vector2(20, 356)
	sell_quantity_button.size = Vector2(326, 48)
	sell_quantity_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_quantity_button.theme_type_variation = "GothicShopSellActionGemButton"
	sell_quantity_button.add_theme_font_size_override("font_size", GothicUIThemeScript.BUTTON_ACTION_FONT_SIZE)
	sell_quantity_button.visible = false
	sell_quantity_button.pressed.connect(_request_selected_quantity)
	sell_quantity_button.set_meta("calibration_text_revision", 1)
	panel.add_child(sell_quantity_button)
	sell_confirmation = GothicConfirmationPanelScript.new()
	sell_confirmation.name = "SellConfirmation"
	sell_confirmation.confirmed.connect(_on_sell_confirmation_confirmed)
	sell_confirmation.cancelled.connect(_cancel_pending_sell)
	add_child(sell_confirmation)

func _add_quantity_symbol(button: Button, plus: bool) -> void:
	var color := Color("f2c783")
	var horizontal := ColorRect.new()
	horizontal.name = "HorizontalBar"
	horizontal.position = Vector2(22, 21.5)
	horizontal.size = Vector2(14, 3)
	horizontal.color = color
	horizontal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(horizontal)
	if plus:
		var vertical := ColorRect.new()
		vertical.name = "VerticalBar"
		vertical.position = Vector2(27.5, 16)
		vertical.size = Vector2(3, 14)
		vertical.color = color
		vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(vertical)


func _build_compatibility_list() -> void:
	# Existing smoke tests and buying code select through ItemList. The rendered
	# interface uses the custom two-cell cards below.
	item_list = ItemList.new()
	item_list.name = "CompatibilityItemList"
	item_list.visible = false
	item_list.item_selected.connect(_on_item_selected)
	add_child(item_list)


func _framed_section(node_name: String, rect: Rect2) -> Control:
	return GothicFrameFactoryScript.add_filled_section(self, node_name, rect)


func _section_title(node_name: String, text_value: String, section_width: float) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.position = Vector2(24, 18)
	label.size = Vector2(section_width - 48.0, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicSectionTitle"
	return label


func open_for(display_name: String, new_stock: Array, merchant_context: Dictionary = {}) -> void:
	_stop_quantity_hold()
	stock = new_stock
	_merchant_context = merchant_context.duplicate(true) if not merchant_context.is_empty() else {}
	_buy_quotes.clear()
	_buy_quotes_by_index.clear()
	_selected_buy_index = -1
	_buy_request_locked = false
	_buy_lock_serial += 1
	_sell_quotes.clear()
	_sell_structure_indices.clear()
	_sell_structure_tokens.clear()
	_selected_sell_index = -1
	_sell_quantity = 1
	_selected_sell_indices.clear()
	_sell_quantities.clear()
	shop_title.text = display_name
	item_list.clear()
	for entry: Variant in stock:
		item_list.add_item(str(entry.get("name", "物品")))
	_set_trade_mode("buy")
	_refresh_gold()
	_refresh_repair_preview()
	show()
	buy_quotes_requested.emit(stock.duplicate(true))


func set_buy_quotes(quotes: Array) -> void:
	var preserved_index := _selected_buy_index
	_buy_quotes = quotes.duplicate(true)
	_buy_quotes_by_index.clear()
	for raw_quote: Variant in _buy_quotes:
		if raw_quote is Dictionary:
			_buy_quotes_by_index[int((raw_quote as Dictionary).get("stock_index", -1))] = raw_quote
	if _trade_mode != "buy":
		return
	if preserved_index < 0 or preserved_index >= stock.size():
		_selected_buy_index = -1
	item_list.clear()
	for index in range(stock.size()):
		var quote := _buy_quote_for_index(index)
		var item_name := str(stock[index].get("name", "物品"))
		var pack_count := maxi(1, int(quote.get("pack_count", quote.get("quantity", 1))))
		item_list.add_item("%s ×%d　%d金币" % [item_name, pack_count, int(quote.get("total_price", 0))])
	_rebuild_goods_cards()
	if _selected_buy_index >= 0 and _selected_buy_index < item_list.item_count:
		item_list.select(_selected_buy_index)
		_set_shop_card_selected(goods_buttons[_selected_buy_index], true)
		_refresh_buy_action_enabled()


func apply_buy_result(result: Dictionary) -> void:
	_show_transaction_result_feedback(buy_button, bool(result.get("success", false)), "shop.buy")
	detail_label.text = "[color=#e8c277]%s[/color]" % str(result.get("message", "购买请求已处理。"))
	if result.get("quotes", null) is Array:
		set_buy_quotes(result.get("quotes", []))
	_refresh_gold()
	_refresh_buy_action_enabled()


func _buy_quote_for_index(stock_index: int) -> Dictionary:
	var quote: Variant = _buy_quotes_by_index.get(stock_index, {})
	return quote if quote is Dictionary else {}


func _rebuild_goods_cards() -> void:
	var cards := _acquire_goods_cards(stock.size())
	for index in range(stock.size()):
		var entry: Dictionary = stock[index]
		var card: Button = cards[index]
		card.name = "GoodsCard_%d" % index
		card.tooltip_text = str(entry.get("name", "物品"))
		card.set_meta("trade_mode", "buy")
		card.set_meta("stock_index", index)
		_set_shop_card_selected(card, index == _selected_buy_index)
		var quote := _buy_quote_for_index(index)
		var pack_count := maxi(1, int(quote.get("pack_count", quote.get("quantity", 1))))
		var catalog_name := str(entry.get("name", "物品"))
		var display_name := "%s ×%d" % [catalog_name, pack_count]
		_build_card_contents(
			card,
			catalog_name,
			display_name,
			_item_texture(GameData.get_item_record(catalog_name)),
			"%d 金币" % int(quote.get("total_price", 0)),
			true,
		)


func _collect_occupied_inventory_indices() -> Array[int]:
	var occupied_indices: Array[int] = []
	for inventory_index in range(PlayerState.inventory.size()):
		var record: Variant = PlayerState.inventory[inventory_index]
		if record is Dictionary and not (record as Dictionary).is_empty():
			occupied_indices.append(inventory_index)
	return occupied_indices


func _build_sell_structure_tokens(occupied_indices: Array[int]) -> Array[String]:
	var tokens: Array[String] = []
	for inventory_index: int in occupied_indices:
		var record: Dictionary = _inventory_record(inventory_index)
		tokens.append(JSON.stringify([
			inventory_index,
			str(record.get("instance_id", "")),
			str(record.get("name", "")),
			maxi(1, int(record.get("count", 1))),
		]))
	return tokens


func _build_sell_quote_key_sequence(occupied_indices: Array[int]) -> Array[String]:
	var quote_keys: Array[String] = []
	for inventory_index: int in occupied_indices:
		quote_keys.append(sell_quote_key(inventory_index, _inventory_record(inventory_index)))
	return quote_keys


func _ensure_sell_card_capacity(required_count: int) -> void:
	while _goods_card_pool.size() < required_count:
		var card := Button.new()
		card.custom_minimum_size = CARD_SIZE
		card.size = CARD_SIZE
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.theme_type_variation = "GothicComponentShopCard"
		card.hide()
		card.pressed.connect(_on_goods_card_pressed.bind(card))
		goods_grid.add_child(card)
		_goods_card_pool.append(card)
		_goods_card_creation_count += 1


func _set_active_sell_card_count(required_count: int) -> void:
	_ensure_sell_card_capacity(required_count)
	for index in range(_goods_card_pool.size()):
		var card := _goods_card_pool[index]
		var should_show := index < required_count
		if card.visible != should_show:
			card.visible = should_show
			_sell_visibility_change_count += 1
	goods_buttons.clear()
	for index in range(required_count):
		goods_buttons.append(_goods_card_pool[index])


func _bind_sell_card_identity(
	card: Button,
	inventory_index: int,
	record: Dictionary,
	catalog: Dictionary,
	texture: Texture2D,
	quote_key: String,
) -> void:
	var catalog_name := str(record.get("name", "物品"))
	var count := maxi(1, int(record.get("count", 1)))
	var display_name := "%s ×%d" % [catalog_name, count] if count > 1 else catalog_name
	card.name = "SellCard_%d" % inventory_index
	card.set_meta("trade_mode", "sell")
	card.set_meta("inventory_index", inventory_index)
	card.set_meta("quote_key", quote_key)
	card.set_meta("catalog_name", catalog_name)
	_set_shop_card_selected(card, _selected_sell_indices.has(inventory_index))
	_build_card_contents(card, catalog_name, display_name, texture, "", false)


func _apply_sell_quote_to_card(card: Button, quote: Dictionary) -> void:
	var sellable := bool(quote.get("sellable", false))
	card.tooltip_text = str(quote.get("reason", "等待玩法层提供出售报价"))
	var price_label := card.get_node_or_null("Price") as Label
	if sellable:
		if price_label == null:
			price_label = Label.new()
			price_label.name = "Price"
			price_label.add_theme_font_size_override("font_size", 13)
			price_label.add_theme_color_override("font_color", Color("b9955e"))
			price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(price_label)
		price_label.text = "%d 金币 / 件" % int(quote.get("unit_price", 0))
		price_label.position = Vector2(84, 39)
		price_label.size = Vector2(184, 22)
		price_label.show()
	elif price_label != null:
		price_label.hide()


func _rebind_sell_structure(
	occupied_indices: Array[int], quote_keys: Array[String]
) -> void:
	_sell_structure_bind_count += 1
	_sell_structure_indices = occupied_indices.duplicate()
	_sell_structure_tokens = _build_sell_structure_tokens(occupied_indices)
	_set_active_sell_card_count(occupied_indices.size())
	var catalog_cache: Dictionary = {}
	var texture_cache: Dictionary = {}
	for display_index in range(occupied_indices.size()):
		var inventory_index := occupied_indices[display_index]
		var record := _inventory_record(inventory_index)
		var catalog_name := str(record.get("name", ""))
		var catalog: Dictionary
		if catalog_cache.has(catalog_name):
			catalog = catalog_cache[catalog_name]
		else:
			catalog = GameData.get_item_record(catalog_name)
			catalog_cache[catalog_name] = catalog
			_sell_catalog_lookup_count += 1
		var texture: Texture2D = null
		if texture_cache.has(catalog_name):
			texture = texture_cache[catalog_name] as Texture2D
		else:
			texture = _item_texture(catalog)
			texture_cache[catalog_name] = texture
			_sell_texture_lookup_count += 1
		var card: Button = goods_buttons[display_index]
		_bind_sell_card_identity(card, inventory_index, record, catalog, texture, quote_keys[display_index])
		_apply_sell_quote_to_card(card, _sell_quotes.get(quote_keys[display_index], {}))


func _patch_sell_quotes_only() -> void:
	_sell_quote_patch_count += 1
	for display_index in range(goods_buttons.size()):
		var inventory_index := _sell_structure_indices[display_index]
		var record := _inventory_record(inventory_index)
		var actual_quote_key := sell_quote_key(inventory_index, record)
		_apply_sell_quote_to_card(goods_buttons[display_index], _sell_quotes.get(actual_quote_key, {}))
		_set_shop_card_selected(goods_buttons[display_index], _selected_sell_indices.has(inventory_index))


func _clear_goods_cards() -> void:
	for card: Button in _goods_card_pool:
		if card.visible:
			card.hide()
			_sell_visibility_change_count += 1
	goods_buttons.clear()


func _acquire_goods_cards(count: int) -> Array[Button]:
	_clear_goods_cards()
	while _goods_card_pool.size() < count:
		var card := Button.new()
		card.custom_minimum_size = CARD_SIZE
		card.size = CARD_SIZE
		card.hide()
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.theme_type_variation = "GothicComponentShopCard"
		card.pressed.connect(_on_goods_card_pressed.bind(card))
		goods_grid.add_child(card)
		_goods_card_pool.append(card)
		_goods_card_creation_count += 1
	var active: Array[Button] = []
	for index in range(count):
		var card := _goods_card_pool[index]
		if not card.visible:
			card.show()
			_sell_visibility_change_count += 1
		active.append(card)
	goods_buttons = active
	return active


func _on_goods_card_pressed(card: Button) -> void:
	if str(card.get_meta("trade_mode", "buy")) == "sell":
		_select_sell_item(int(card.get_meta("inventory_index", -1)))
	else:
		_select_shop_item(int(card.get_meta("stock_index", -1)))


func _build_card_contents(
	card: Button,
	catalog_name: String,
	display_name: String,
	texture: Texture2D,
	price_text := "",
	show_price := true,
) -> void:
	_goods_card_content_update_count += 1
	var icon := card.get_node_or_null("ItemIcon") as TextureRect
	if texture != null:
		if icon == null:
			icon = TextureRect.new()
			icon.name = "ItemIcon"
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(icon)
		icon.texture = texture
		icon.size = texture.get_size()
		icon.position = Vector2(37, CARD_SIZE.y * 0.5) - icon.size * 0.5
		icon.show()
	elif icon != null:
		icon.texture = null
		icon.hide()
	var name_label := card.get_node_or_null("ItemName") as Label
	if name_label == null:
		name_label = Label.new()
		name_label.name = "ItemName"
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color("ecd4aa"))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_label)
	name_label.text = display_name
	name_label.position = Vector2(84, 11 if show_price else 22)
	name_label.size = Vector2(184, 28)
	name_label.show()
	var price_label := card.get_node_or_null("Price") as Label
	if not show_price:
		if price_label != null:
			price_label.hide()
		return
	if price_label == null:
		price_label = Label.new()
		price_label.name = "Price"
		price_label.add_theme_font_size_override("font_size", 13)
		price_label.add_theme_color_override("font_color", Color("b9955e"))
		price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(price_label)
	price_label.text = price_text
	price_label.position = Vector2(84, 39)
	price_label.size = Vector2(184, 22)
	price_label.show()


func _select_shop_item(index: int) -> void:
	if TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	if index < 0 or index >= stock.size():
		return
	item_list.select(index)
	_on_item_selected(index)


func _set_trade_mode(mode: String) -> void:
	_stop_quantity_hold()
	_clear_transaction_feedback()
	_trade_mode = "sell" if mode == "sell" else "buy"
	var buying := _trade_mode == "buy"
	buy_tab_button.theme_type_variation = "GothicShopTradeTabSelectedGemButton" if buying else "GothicShopTradeTabGemButton"
	sell_tab_button.theme_type_variation = "GothicShopTradeTabGemButton" if buying else "GothicShopTradeTabSelectedGemButton"
	buy_button.visible = buying
	repair_button.visible = buying and bool(_active_merchant_context().get("supports_repair", false))
	sell_quantity_row.visible = not buying
	sell_quantity_button.visible = not buying
	if buying:
		if _buy_quotes.is_empty():
			_clear_goods_cards()
		else:
			_rebuild_goods_cards()
		detail_label.text = "[color=#cdbb9e]选择商品查看属性、价格与穿戴要求。[/color]"
		_refresh_buy_action_enabled()
	else:
		_selected_sell_index = -1
		_sell_quantity = 1
		_selected_sell_indices.clear()
		_sell_quantities.clear()
		_clear_sell_structure()
		_sell_quotes.clear()
		_set_sell_actions_enabled(false)
		_update_sell_quantity_label()
		detail_label.text = "[color=#cdbb9e]出售页只显示人物背包物品；已穿戴装备不会出现在这里。[/color]"
		_request_sell_quotes()
	_apply_layout_profile_once("shop_sell" if not buying else "shop_buy")


func sell_quote_key(inventory_index: int, record: Dictionary) -> String:
	var instance_id := str(record.get("instance_id", ""))
	return "instance:%s" % instance_id if not instance_id.is_empty() else "inventory:%d" % inventory_index


func set_sell_quotes(quotes: Dictionary) -> void:
	_sell_quotes = quotes.duplicate(true)
	if _trade_mode == "sell":
		_refresh_sell_card_contents()
		for card: Button in goods_buttons:
			var selected := _selected_sell_indices.has(int(card.get_meta("inventory_index", -1)))
			_set_shop_card_selected(card, selected)
		_reclamp_sell_quantities()
		_update_sell_quantity_label()


func _refresh_sell_card_contents() -> void:
	var occupied_indices := _collect_occupied_inventory_indices()
	var quote_keys := _build_sell_quote_key_sequence(occupied_indices)
	var structure_tokens := _build_sell_structure_tokens(occupied_indices)
	if (
		occupied_indices != _sell_structure_indices
		or structure_tokens != _sell_structure_tokens
		or goods_buttons.size() != occupied_indices.size()
	):
		_rebind_sell_structure(occupied_indices, quote_keys)
	else:
		_patch_sell_quotes_only()


func _clear_sell_structure() -> void:
	_sell_structure_indices.clear()
	_sell_structure_tokens.clear()
	_clear_goods_cards()


func _reclamp_sell_quantities() -> void:
	for index_variant in _selected_sell_indices.keys().duplicate():
		var inventory_index := int(index_variant)
		var record := _inventory_record(inventory_index)
		if record.is_empty():
			_selected_sell_indices.erase(inventory_index)
			_sell_quantities.erase(inventory_index)
			continue
		var quote: Dictionary = _sell_quotes.get(sell_quote_key(inventory_index, record), {})
		var maximum := clampi(int(quote.get("max_quantity", int(record.get("count", 1)))), 1, maxi(1, int(record.get("count", 1))))
		_sell_quantities[inventory_index] = clampi(int(_sell_quantities.get(inventory_index, 1)), 1, maximum)


func apply_sell_result(result: Dictionary) -> void:
	var message := str(result.get("message", "出售请求已处理。"))
	detail_label.text = "[color=#e8c277]%s[/color]" % message
	if _batch_sell_active:
		if result.get("quotes", null) is Dictionary:
			_sell_quotes = result.get("quotes", {}).duplicate(true)
		_refresh_gold()
		if not bool(result.get("success", false)):
			_batch_sell_queue.clear()
			_batch_sell_active = false
			_show_transaction_result_feedback(sell_quantity_button, false, "shop.sell")
			_selected_sell_indices.clear()
			_sell_quantities.clear()
			_apply_inventory_change()
			return
		if not _batch_sell_queue.is_empty():
			_emit_next_batch_request()
			return
		_batch_sell_active = false
	if result.get("quotes", null) is Dictionary:
		_sell_quotes = result.get("quotes", {}).duplicate(true)
	_refresh_gold()
	if not bool(result.get("success", false)) and _trade_mode == "sell":
		_selected_sell_index = -1
		_selected_sell_indices.clear()
		_sell_quantities.clear()
		_batch_sell_queue.clear()
		if result.get("quotes", null) is Dictionary:
			_refresh_sell_card_contents()
		else:
			_apply_inventory_change()
		_set_sell_actions_enabled(false)
	if bool(result.get("success", false)) and _trade_mode == "sell":
		_inventory_refresh_pending = false
		_selected_sell_index = -1
		_selected_sell_indices.clear()
		_sell_quantities.clear()
		_batch_sell_queue.clear()
		_batch_sell_active = false
		if result.get("quotes", null) is Dictionary:
			_refresh_sell_card_contents()
		else:
			_sell_quotes.clear()
			_clear_goods_cards()
			_request_sell_quotes()
		_set_sell_actions_enabled(false)
	_show_transaction_result_feedback(sell_quantity_button, bool(result.get("success", false)), "shop.sell")


func _request_sell_quotes() -> void:
	var items: Array = []
	var merchant_context := _active_merchant_context()
	var merchant_id := str(merchant_context.get("merchant_id", ""))
	var merchant_stock_key := str(merchant_context.get("stock_key", ""))
	for inventory_index in range(PlayerState.inventory.size()):
		var record: Variant = PlayerState.inventory[inventory_index]
		if not record is Dictionary or (record as Dictionary).is_empty():
			continue
		items.append({
			"quote_key": sell_quote_key(inventory_index, record),
			"inventory_index": inventory_index,
			"instance_id": str(record.get("instance_id", "")),
			"item_name": str(record.get("name", "")),
			"count": int(record.get("count", 1)),
			"merchant_id": merchant_id,
			"merchant_stock_key": merchant_stock_key,
		})
	sell_quotes_requested.emit(items)


func _select_sell_item(inventory_index: int) -> void:
	if TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	var record := _inventory_record(inventory_index)
	if record.is_empty():
		return
	var quote: Dictionary = _sell_quotes.get(sell_quote_key(inventory_index, record), {})
	if not bool(quote.get("sellable", false)):
		_show_sell_detail(inventory_index, quote)
		_set_sell_actions_enabled(not _selected_sell_indices.is_empty())
		return
	var old_selected_index := _selected_sell_index
	if _selected_sell_indices.has(inventory_index):
		_selected_sell_indices.erase(inventory_index)
		_sell_quantities.erase(inventory_index)
	else:
		_selected_sell_indices[inventory_index] = true
		_sell_quantities[inventory_index] = 1
	_selected_sell_index = inventory_index if _selected_sell_indices.has(inventory_index) else (_selected_sell_indices.keys()[-1] if not _selected_sell_indices.is_empty() else -1)
	for changed_index: int in [old_selected_index, inventory_index]:
		var changed_card := _sell_card_for_inventory_index(changed_index)
		if changed_card != null:
			_set_shop_card_selected(changed_card, _selected_sell_indices.has(changed_index))
	if _selected_sell_index < 0:
		_sell_quantity = 1
		_update_sell_quantity_label()
		_set_sell_actions_enabled(false)
		return
	var quote_key := sell_quote_key(_selected_sell_index, _inventory_record(_selected_sell_index))
	quote = _sell_quotes.get(quote_key, {})
	record = _inventory_record(_selected_sell_index)
	var count := maxi(1, int(record.get("count", 1)))
	var max_quantity := clampi(int(quote.get("max_quantity", count)), 1, count)
	_sell_quantity = clampi(int(_sell_quantities.get(_selected_sell_index, 1)), 1, max_quantity)
	_sell_quantities[_selected_sell_index] = _sell_quantity
	_update_sell_quantity_label()
	var sellable := bool(quote.get("sellable", false))
	_set_sell_actions_enabled(sellable)
	if quote.is_empty():
		detail_label.text = "[color=#f2c783][font_size=20]%s[/font_size][/color]\n数量：%d\n\n[color=#d4a15e]等待玩法层提供出售报价。[/color]" % [record.get("name", "物品"), count]
		return
	detail_label.text = _sell_item_detail(
		record,
		GameData.get_item_record(str(record.get("name", ""))),
		quote,
	)

func _show_sell_detail(inventory_index: int, quote: Dictionary) -> void:
	var record := _inventory_record(inventory_index)
	if record.is_empty():
		return
	var item := GameData.get_item_record(str(record.get("name", "")))
	detail_label.text = _sell_item_detail(record, item, quote)


func _sell_item_detail(record: Dictionary, item: Dictionary, quote: Dictionary) -> String:
	var lines: Array[String] = [
		"[color=#f2c783][font_size=20]%s[/font_size][/color]" % str(record.get("name", "物品")),
		"数量：%d" % maxi(1, int(record.get("count", 1))),
	]
	if not item.is_empty():
		lines.append("类别：%s　重量：%d" % [str(item.get("category", "未分类")), int(item.get("weight", 0))])
		if str(item.get("kind", "")) == "equipment":
			var current_durability := int(record.get("durability", item.get("maxDurability", 1)))
			var maximum_durability := int(record.get("max_durability", item.get("maxDurability", 1)))
			lines.append("耐久：%d/%d" % [current_durability, maximum_durability])
			lines.append(_equipment_stat_text(item))
			lines.append("穿戴要求：%s" % EquipmentRulesScript.requirement_label(item))
		elif not str(item.get("description", "")).is_empty():
			lines.append(str(item.get("description", "")))
	if bool(quote.get("sellable", false)):
		lines.append("[color=#d3a763]单件售价：%d金币[/color]" % int(quote.get("unit_price", 0)))
		var risk_text := _sell_risk_text(quote)
		if not risk_text.is_empty():
			lines.append("[color=#ef9f63]出售提示：%s[/color]" % risk_text)
	else:
		lines.append("[color=#b8a58a]不可出售：%s[/color]" % str(quote.get("reason", "暂时无法报价")))
	return "\n".join(lines)


func _equipment_stat_text(item: Dictionary) -> String:
	return "攻击 %s-%s　魔法 %s-%s\n道术 %s-%s　防御 %s-%s\n魔防 %s-%s" % [
		_value(item.get("attackMin")), _value(item.get("attackMax")),
		_value(item.get("magicMin")), _value(item.get("magicMax")),
		_value(item.get("taoMin")), _value(item.get("taoMax")),
		_value(item.get("defenseMin")), _value(item.get("defenseMax")),
		_value(item.get("mdefMin")), _value(item.get("mdefMax")),
	]


func _change_sell_quantity(delta: int) -> void:
	var record := _inventory_record(_selected_sell_index)
	if record.is_empty():
		return
	var quote: Dictionary = _sell_quotes.get(sell_quote_key(_selected_sell_index, record), {})
	var maximum := clampi(int(quote.get("max_quantity", int(record.get("count", 1)))), 1, maxi(1, int(record.get("count", 1))))
	_sell_quantity = clampi(int(_sell_quantities.get(_selected_sell_index, _sell_quantity)) + delta, 1, maximum)
	_sell_quantities[_selected_sell_index] = _sell_quantity
	_update_sell_quantity_label()


func _start_quantity_hold(delta: int) -> void:
	_stop_quantity_hold()
	var button := increase_quantity_button if delta > 0 else decrease_quantity_button
	if button == null or button.disabled:
		return
	_quantity_hold_delta = 1 if delta > 0 else -1
	_quantity_hold_interval = QUANTITY_HOLD_REPEAT_INTERVAL
	_change_sell_quantity(_quantity_hold_delta)
	button = increase_quantity_button if _quantity_hold_delta > 0 else decrease_quantity_button
	if button == null or button.disabled or _quantity_hold_timer == null:
		_stop_quantity_hold()
		return
	_quantity_hold_timer.start(QUANTITY_HOLD_INITIAL_DELAY)


func _on_quantity_hold_timeout() -> void:
	if _quantity_hold_delta == 0:
		return
	var button := increase_quantity_button if _quantity_hold_delta > 0 else decrease_quantity_button
	if button == null or button.disabled or not visible or _trade_mode != "sell":
		_stop_quantity_hold()
		return
	_change_sell_quantity(_quantity_hold_delta)
	_quantity_hold_interval = maxf(
		QUANTITY_HOLD_MIN_INTERVAL,
		_quantity_hold_interval * QUANTITY_HOLD_ACCELERATION,
	)
	button = increase_quantity_button if _quantity_hold_delta > 0 else decrease_quantity_button
	if button == null or button.disabled or _quantity_hold_timer == null:
		_stop_quantity_hold()
		return
	_quantity_hold_timer.start(_quantity_hold_interval)


func _stop_quantity_hold() -> void:
	_quantity_hold_delta = 0
	_quantity_hold_interval = QUANTITY_HOLD_REPEAT_INTERVAL
	if _quantity_hold_timer != null:
		_quantity_hold_timer.stop()


func _update_sell_quantity_label() -> void:
	if sell_quantity_label == null:
		return
	sell_quantity_label.text = "出售数量：%d" % _sell_quantity
	var selected_record := _inventory_record(_selected_sell_index)
	var maximum := 1
	var sellable := false
	if not selected_record.is_empty():
		var selected_quote: Dictionary = _sell_quotes.get(sell_quote_key(_selected_sell_index, selected_record), {})
		maximum = clampi(int(selected_quote.get("max_quantity", int(selected_record.get("count", 1)))), 1, maxi(1, int(selected_record.get("count", 1))))
		sellable = bool(selected_quote.get("sellable", false))
	if decrease_quantity_button != null:
		decrease_quantity_button.disabled = not sellable or _selected_sell_index < 0 or _sell_quantity <= 1 or maximum <= 1
	if increase_quantity_button != null:
		increase_quantity_button.disabled = not sellable or _selected_sell_index < 0 or _sell_quantity >= maximum or maximum <= 1


func _request_selected_quantity() -> void:
	_request_sell()


func _request_sell_batch() -> void:
	if _batch_sell_active:
		return
	if _selected_sell_indices.is_empty() and _selected_sell_index >= 0:
		_selected_sell_indices[_selected_sell_index] = true
		_sell_quantities[_selected_sell_index] = _sell_quantity
	if _selected_sell_indices.is_empty():
		return
	var requests: Array = []
	for index_variant in _selected_sell_indices.keys():
		var inventory_index := int(index_variant)
		var record := _inventory_record(inventory_index)
		if record.is_empty():
			continue
		var quote_key := sell_quote_key(inventory_index, record)
		var quote: Dictionary = _sell_quotes.get(quote_key, {})
		if not bool(quote.get("sellable", false)):
			continue
		var maximum := clampi(int(quote.get("max_quantity", int(record.get("count", 1)))), 1, maxi(1, int(record.get("count", 1))))
		var requested_amount := int(_sell_quantities.get(inventory_index, 1))
		requests.append({"quote_key": quote_key, "quote_id": str(quote.get("quote_id", "")), "inventory_index": inventory_index, "instance_id": str(record.get("instance_id", "")), "item_name": str(record.get("name", "")), "amount": clampi(requested_amount, 1, maximum), "requires_confirmation": bool(quote.get("requires_confirmation", false)), "merchant_id": str(quote.get("merchant_id", ""))})
	if requests.is_empty():
		return
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("inventory_index", -1)) > int(b.get("inventory_index", -1)))
	if requests.any(func(r: Dictionary) -> bool: return bool(r.get("requires_confirmation", false))):
		_pending_sell_request = {"batch": requests}
		sell_confirmation.open_confirmation({"action_id": "shop.sell.risky_item", "title": "确认批量出售", "message": "批量出售 %d 件物品，其中包含稀有物品。" % requests.size(), "confirm_label": "确认出售", "cancel_label": "取消", "tone": "danger", "context": {"quote_id": requests[0].get("quote_id", "")}})
		return
	_batch_sell_queue.clear()
	_batch_sell_active = false
	_emit_sell_request({"batch": requests, "merchant_id": str(requests[0].get("merchant_id", ""))})

func _emit_next_batch_request() -> void:
	if _batch_sell_queue.is_empty():
		_batch_sell_active = false
		return
	_emit_sell_request(_batch_sell_queue.pop_front())

func _request_sell() -> void:
	_request_sell_batch()


func _on_sell_confirmation_confirmed(_confirmation: Dictionary) -> void:
	_confirm_pending_sell()


func _cancel_pending_sell(_confirmation: Dictionary) -> void:
	_pending_sell_request.clear()
	_batch_sell_queue.clear()
	_batch_sell_active = false


func _confirm_pending_sell() -> void:
	if _pending_sell_request.is_empty():
		return
	if _pending_sell_request.has("batch"):
		var confirmed_batch: Array = _pending_sell_request.get("batch", []).duplicate(true)
		_pending_sell_request.clear()
		_batch_sell_queue.clear()
		_batch_sell_active = false
		_emit_sell_request({"batch": confirmed_batch, "merchant_id": str(confirmed_batch[0].get("merchant_id", "")) if not confirmed_batch.is_empty() else ""})
		return
	var request := _pending_sell_request.duplicate(true)
	_pending_sell_request.clear()
	_emit_sell_request(request)


func _emit_sell_request(request: Dictionary) -> void:
	_clear_transaction_feedback()
	GothicUIThemeScript.set_button_feedback(
		sell_quantity_button,
		GothicUIThemeScript.BUTTON_FEEDBACK_BUSY,
		"shop.sell",
	)
	detail_label.text = "[color=#d8bd8c]出售请求已提交，等待玩法层返回交易结果。[/color]"
	sell_requested.emit(request.duplicate(true))


func _set_sell_actions_enabled(enabled: bool) -> void:
	sell_quantity_button.disabled = not enabled


func _sell_risk_text(quote: Dictionary) -> String:
	var labels := {
		"high_value": "高价值",
		"enhanced": "强化",
		"lucky": "幸运",
		"special": "特殊装备",
	}
	var parts: Array[String] = []
	for flag: Variant in quote.get("risk_flags", []):
		parts.append(str(labels.get(str(flag), str(flag))))
	return "、".join(parts)


func _on_inventory_changed() -> void:
	if _trade_mode != "sell":
		return
	if _batch_sell_active:
		_inventory_refresh_pending = true
		return
	if not visible:
		_inventory_refresh_pending = true
		return
	_queue_inventory_refresh()


func _on_visibility_changed() -> void:
	if not visible:
		_stop_quantity_hold()
		return
	if visible and _inventory_refresh_pending and _trade_mode == "sell":
		_apply_inventory_change()


func _apply_inventory_change() -> void:
	if _batch_sell_active:
		_inventory_refresh_pending = true
		return
	_inventory_refresh_pending = false
	_inventory_refresh_scheduled = false
	_inventory_refresh_execution_count += 1
	_reclamp_sell_quantities()
	_selected_sell_index = -1
	_sell_quotes.clear()
	_clear_sell_structure()
	_set_sell_actions_enabled(false)
	_request_sell_quotes()


func _queue_inventory_refresh() -> void:
	_inventory_refresh_pending = true
	if _inventory_refresh_scheduled:
		return
	_inventory_refresh_scheduled = true
	call_deferred("_flush_inventory_refresh")


func _flush_inventory_refresh() -> void:
	_inventory_refresh_scheduled = false
	if not _inventory_refresh_pending or not visible or _trade_mode != "sell":
		return
	_apply_inventory_change()


func debug_reset_operation_counters() -> void:
	_sell_structure_bind_count = 0
	_sell_quote_patch_count = 0
	_sell_visibility_change_count = 0
	_sell_catalog_lookup_count = 0
	_sell_texture_lookup_count = 0
	_goods_card_creation_count = 0
	_goods_card_content_update_count = 0
	_inventory_refresh_execution_count = 0


func debug_operation_counters() -> Dictionary:
	return {
		"sell_structure_bind_count": _sell_structure_bind_count,
		"sell_quote_patch_count": _sell_quote_patch_count,
		"goods_card_visibility_change_count": _sell_visibility_change_count,
		"goods_card_creation_count": _goods_card_creation_count,
		"goods_card_content_update_count": _goods_card_content_update_count,
		"inventory_refresh_execution_count": _inventory_refresh_execution_count,
		"sell_catalog_lookup_count": _sell_catalog_lookup_count,
		"sell_texture_lookup_count": _sell_texture_lookup_count,
	}


func _apply_layout_profile_once(profile_id: String) -> void:
	if _applied_layout_profiles.has(profile_id):
		return
	_applied_layout_profiles[profile_id] = true
	_layout_apply_count += 1
	UIRuntimeLayoutOverridesScript.apply_profile(self, profile_id)


func _refresh_gold() -> void:
	if gold_label != null:
		gold_label.text = "金币 %d" % PlayerState.gold


func _refresh_repair_preview() -> void:
	if repair_button == null:
		return
	var context := _active_merchant_context()
	repair_button.visible = _trade_mode == "buy" and bool(context.get("supports_repair", false))
	repair_button.disabled = not bool(context.get("supports_repair", false))
	if repair_button.disabled:
		return
	var cost := PlayerState.repair_cost(context)
	repair_button.text = "维修全部（%d金币）" % cost if cost > 0 else "装备无需维修"


func _on_item_selected(index: int) -> void:
	if TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	if index < 0 or index >= stock.size():
		return
	var old_selected_index := _selected_buy_index
	_selected_buy_index = index
	for card_index: int in [old_selected_index, index]:
		if card_index >= 0 and card_index < goods_buttons.size():
			_set_shop_card_selected(goods_buttons[card_index], card_index == index)
	var entry: Dictionary = stock[index]
	var item_name := str(entry.get("name", ""))
	var item := GameData.get_item_record(item_name)
	var description := _buy_item_detail(item_name, item, entry)
	var quote := _buy_quote_for_index(index)
	var pack_count := maxi(1, int(quote.get("pack_count", quote.get("quantity", 1))))
	var price_line := (
		"[color=#d3a763]价格：%d金币 × %d，共%d金币[/color]" % [
			int(quote.get("unit_price", 0)), pack_count, int(quote.get("total_price", 0)),
		]
		if bool(quote.get("valid", false))
		else "[color=#b8a58a]%s[/color]" % str(quote.get("reason", "等待玩法价格报价"))
	)
	detail_label.text = "[color=#f2c783][font_size=20]%s[/font_size][/color]\n%s\n\n%s" % [item_name, price_line, description]
	_refresh_buy_action_enabled()


func _buy_item_detail(item_name: String, item: Dictionary, entry: Dictionary) -> String:
	var lines: Array[String] = []
	var summary := GameData.item_usage_summary(item_name)
	if not item.is_empty() and str(summary.get("kind", item.get("kind", ""))) == "consumable":
		lines.append("类别：%s" % str(summary.get("category", item.get("category", "药品"))))
		var restore_health := int(summary.get("restore_health", 0))
		var restore_mana := int(summary.get("restore_mana", 0))
		var delayed := str(summary.get("effect_type", "instant")) == "delayed_restore"
		var tick_amount := int(summary.get("tick_amount", 0))
		var tick_interval := float(summary.get("tick_interval_seconds", 0.0))
		var recovery_per_second := float(summary.get("recovery_per_second", 0.0))
		var duration_seconds := float(summary.get("duration_seconds", 0.0))
		if restore_health > 0:
			if delayed:
				lines.append("持续恢复生命：每%.2f秒%d点（约%.1f点/秒）" % [tick_interval, tick_amount, recovery_per_second])
				lines.append("生命总恢复：%d点，持续约%.2f秒" % [restore_health, duration_seconds])
			else:
				lines.append("立即恢复生命：%d点" % restore_health)
		if restore_mana > 0:
			if delayed:
				lines.append("持续恢复魔法：每%.2f秒%d点（约%.1f点/秒）" % [tick_interval, tick_amount, recovery_per_second])
				lines.append("魔法总恢复：%d点，持续约%.2f秒" % [restore_mana, duration_seconds])
			else:
				lines.append("立即恢复魔法：%d点" % restore_mana)
		if restore_health <= 0 and restore_mana <= 0:
			lines.append("效果：%s" % str(summary.get("use_effect", "消耗品")))
		lines.append("使用方式：双击使用")
		lines.append("可叠加：是")
		return "\n".join(lines)
	if not item.is_empty():
		lines.append("类别：%s　重量：%d" % [str(item.get("category", "")), int(item.get("weight", 0))])
		var maximum_durability := int(item.get("maxDurability", item.get("serviceDuraMax", 0)))
		if maximum_durability > 0:
			lines.append("耐久上限：%d" % maximum_durability)
		lines.append(_equipment_stat_text(item))
		lines.append("穿戴要求：%s" % _player_requirement_label(item))
	var entry_description := str(entry.get("description", ""))
	if not entry_description.is_empty():
		lines.append(entry_description)
	return "\n".join(lines)


func _player_requirement_label(item: Dictionary) -> String:
	# EquipmentRules is authoritative for the requirement type/value. Strip its
	# source/confidence suffix from the player-facing label; those are audit
	# metadata, not gameplay instructions.
	var label := EquipmentRulesScript.requirement_label(item)
	for marker: String in ["（", "("]:
		var marker_index := label.find(marker)
		if marker_index >= 0:
			label = label.substr(0, marker_index)
	return label


func _set_shop_card_selected(card: Button, selected: bool) -> void:
	card.set_pressed_no_signal(selected)
	card.theme_type_variation = (
		"GothicComponentSelectedShopCard"
		if selected
		else "GothicComponentShopCard"
	)
	if not selected:
		card.release_focus()


func _sell_card_for_inventory_index(inventory_index: int) -> Button:
	for card: Button in goods_buttons:
		if int(card.get_meta("inventory_index", -1)) == inventory_index:
			return card
	return null


func _repair_all() -> void:
	_clear_transaction_feedback()
	GothicUIThemeScript.set_button_feedback(
		repair_button,
		GothicUIThemeScript.BUTTON_FEEDBACK_BUSY,
		"shop.repair",
	)
	var equipment_before := PlayerState.equipment.duplicate(true)
	var gold_before := PlayerState.gold
	detail_label.text = PlayerState.repair_all_equipment(_active_merchant_context())
	_refresh_gold()
	var repair_changed_state := (
		PlayerState.gold < gold_before
		and PlayerState.equipment != equipment_before
	)
	_show_transaction_result_feedback(repair_button, repair_changed_state, "shop.repair")


func _buy_selected() -> void:
	if _buy_request_locked:
		return
	var selected := item_list.get_selected_items()
	if selected.is_empty():
		detail_label.text = "请先选择商品。"
		return
	var stock_index := int(selected[0])
	var quote := _buy_quote_for_index(stock_index)
	if not bool(quote.get("valid", false)):
		detail_label.text = str(quote.get("reason", "该商品暂时无法购买。"))
		return
	_clear_transaction_feedback()
	detail_label.text = "[color=#d8bd8c]购买请求已提交，等待玩法层返回交易结果。[/color]"
	GothicUIThemeScript.set_button_feedback(
		buy_button,
		GothicUIThemeScript.BUTTON_FEEDBACK_BUSY,
		"shop.buy",
	)
	_buy_request_locked = true
	_buy_lock_serial += 1
	var lock_serial := _buy_lock_serial
	_refresh_buy_action_enabled()
	if is_inside_tree():
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			if lock_serial != _buy_lock_serial:
				return
			_buy_request_locked = false
			_refresh_buy_action_enabled()
		)
	buy_requested.emit({
		"contract_id": str(quote.get("contract_id", "")),
		"quote_id": str(quote.get("quote_id", "")),
		"stock_index": stock_index,
		"stock_key": str(quote.get("stock_key", "")),
		"item_name": str(quote.get("item_name", "")),
		"quantity": int(quote.get("pack_count", 1)),
		"merchant_id": str(quote.get("merchant_id", "")),
	})


func _refresh_buy_action_enabled() -> void:
	if buy_button == null:
		return
	var selected := _selected_buy_index >= 0 and _selected_buy_index < stock.size()
	var quote := _buy_quote_for_index(_selected_buy_index) if selected else {}
	buy_button.disabled = _buy_request_locked or not bool(quote.get("valid", false))


func _clear_transaction_feedback() -> void:
	_transaction_feedback_serial += 1
	GothicUIThemeScript.clear_button_feedback(buy_button)
	GothicUIThemeScript.clear_button_feedback(repair_button)
	GothicUIThemeScript.clear_button_feedback(sell_quantity_button)


func _show_transaction_result_feedback(button: Button, success: bool, group: String) -> void:
	_transaction_feedback_serial += 1
	var serial := _transaction_feedback_serial
	# Local repair and loopback buy/sell results may return in the same input
	# frame.  Preserve one complete busy frame so every transaction follows the
	# same visible sequence instead of collapsing directly into its result.
	if is_inside_tree():
		await get_tree().process_frame
	if serial != _transaction_feedback_serial or not is_instance_valid(button) or not button.is_inside_tree():
		return
	GothicUIThemeScript.set_button_feedback(
		button,
		GothicUIThemeScript.BUTTON_FEEDBACK_SUCCESS if success else GothicUIThemeScript.BUTTON_FEEDBACK_FAILURE,
		group,
	)
	if not is_inside_tree():
		return
	get_tree().create_timer(1.0 if success else 0.45).timeout.connect(func() -> void:
		if serial == _transaction_feedback_serial and is_instance_valid(button) and button.is_inside_tree():
			GothicUIThemeScript.clear_button_feedback(button)
	)


func _active_merchant_context() -> Dictionary:
	if not _merchant_context.is_empty():
		return _merchant_context.duplicate(true)
	if stock.is_empty() or not stock[0] is Dictionary:
		return {}
	return (stock[0].get("merchant_context", {}) as Dictionary).duplicate(true)


func _inventory_record(index: int) -> Dictionary:
	if index < 0 or index >= PlayerState.inventory.size():
		return {}
	var record: Variant = PlayerState.inventory[index]
	return record if record is Dictionary and not (record as Dictionary).is_empty() else {}


func _item_texture(record: Dictionary) -> Texture2D:
	return UIItemTextureCacheScript.texture_for(record, "inventoryIcon")


func _value(value: Variant) -> String:
	return "—" if value == null else str(value)


func _close() -> void:
	_stop_quantity_hold()
	_clear_transaction_feedback()
	sell_confirmation.close_confirmation()
	_pending_sell_request.clear()
	hide()
	closed.emit()
