class_name ShopPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicConfirmationPanelScript := preload("res://scripts/gothic_confirmation_panel.gd")
const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")
const QUANTITY_BUTTON_TEXTURE := preload("res://assets/ui/gothic_theme/v1/sample/button_normal.png")

signal closed
signal sell_quotes_requested(items: Array)
signal sell_requested(request: Dictionary)

const PANEL_SIZE := Vector2(1080, 620)
const CARD_SIZE := Vector2(286, 72)
const CARD_COLUMNS := 2

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
var sell_confirmation: Control
var stock: Array = []
var _trade_mode := "buy"
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


func _ready() -> void:
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
	PlayerState.profile_changed.connect(_refresh_gold)
	PlayerState.equipment_changed.connect(_refresh_repair_preview)
	PlayerState.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)
	_refresh_gold()
	_refresh_repair_preview()


func _build_modal_surface() -> void:
	var surface := Panel.new()
	surface.name = "ModalSurface"
	surface.position = Vector2(18, 24)
	surface.size = Vector2(1044, 574)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(290, 4)
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
	var panel := _framed_section("GoodsPanel", Rect2(26, 72, 650, 500))
	buy_tab_button = Button.new()
	buy_tab_button.name = "BuyTab"
	buy_tab_button.text = "购买"
	buy_tab_button.position = Vector2(20, 10)
	buy_tab_button.size = Vector2(128, 40)
	buy_tab_button.theme_type_variation = "GothicComponentSelectedButton"
	buy_tab_button.pressed.connect(_set_trade_mode.bind("buy"))
	panel.add_child(buy_tab_button)
	sell_tab_button = Button.new()
	sell_tab_button.name = "SellTab"
	sell_tab_button.text = "出售"
	sell_tab_button.position = Vector2(156, 10)
	sell_tab_button.size = Vector2(128, 40)
	sell_tab_button.theme_type_variation = "GothicComponentButton"
	sell_tab_button.pressed.connect(_set_trade_mode.bind("sell"))
	panel.add_child(sell_tab_button)
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.position = Vector2(372, 20)
	gold_label.size = Vector2(246, 28)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.theme_type_variation = "GothicMutedLabel"
	gold_label.add_theme_color_override("font_color", Color("d6b16f"))
	panel.add_child(gold_label)
	var scroll := ScrollContainer.new()
	scroll.name = "GoodsScroll"
	scroll.position = Vector2(18, 58)
	scroll.size = Vector2(614, 420)
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
	var panel := _framed_section("DetailPanel", Rect2(688, 72, 366, 500))
	panel.add_child(_section_title("商品详情", 366))
	detail_label = RichTextLabel.new()
	detail_label.name = "DetailLabel"
	detail_label.position = Vector2(26, 62)
	detail_label.size = Vector2(314, 250)
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.theme_type_variation = "GothicDetailText"
	panel.add_child(detail_label)
	buy_button = Button.new()
	buy_button.name = "BuyButton"
	buy_button.text = "购买"
	buy_button.position = Vector2(20, 334)
	buy_button.size = Vector2(326, 58)
	buy_button.theme_type_variation = "GothicComponentSelectedButton"
	buy_button.add_theme_font_size_override("font_size", 18)
	buy_button.pressed.connect(_buy_selected)
	panel.add_child(buy_button)
	repair_button = Button.new()
	repair_button.name = "RepairButton"
	repair_button.text = "维修全部装备"
	repair_button.position = Vector2(20, 404)
	repair_button.size = Vector2(326, 58)
	repair_button.theme_type_variation = "GothicComponentButton"
	repair_button.add_theme_font_size_override("font_size", 16)
	repair_button.pressed.connect(_repair_all)
	panel.add_child(repair_button)
	sell_quantity_row = Control.new()
	sell_quantity_row.name = "SellQuantityRow"
	sell_quantity_row.position = Vector2(20, 322)
	sell_quantity_row.size = Vector2(326, 46)
	sell_quantity_row.visible = false
	sell_quantity_row.clip_contents = true
	panel.add_child(sell_quantity_row)
	var minus_button := Button.new()
	minus_button.name = "DecreaseQuantity"
	minus_button.text = ""
	minus_button.tooltip_text = "减少出售数量"
	minus_button.set_meta("quantity_delta", -1)
	minus_button.add_theme_font_size_override("font_size", 18)
	minus_button.position = Vector2(8, 0)
	minus_button.size = Vector2(58, 46)
	minus_button.theme_type_variation = "GothicTransparentButton"
	minus_button.clip_contents = true
	_add_quantity_decoration(minus_button, false)
	_add_quantity_symbol(minus_button, false)
	minus_button.pressed.connect(_change_sell_quantity.bind(-1))
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
	plus_button.name = "IncreaseQuantity"
	plus_button.text = ""
	plus_button.tooltip_text = "增加出售数量"
	plus_button.set_meta("quantity_delta", 1)
	plus_button.add_theme_font_size_override("font_size", 18)
	plus_button.position = Vector2(260, 0)
	plus_button.size = Vector2(58, 46)
	plus_button.theme_type_variation = "GothicTransparentButton"
	plus_button.clip_contents = true
	_add_quantity_decoration(plus_button, true)
	_add_quantity_symbol(plus_button, true)
	plus_button.pressed.connect(_change_sell_quantity.bind(1))
	sell_quantity_row.add_child(plus_button)
	sell_one_button = Button.new()
	sell_one_button.name = "SellOneButton"
	sell_one_button.text = "出售单件"
	sell_one_button.position = Vector2(20, 376)
	sell_one_button.size = Vector2(326, 48)
	sell_one_button.theme_type_variation = "GothicComponentSelectedButton"
	sell_one_button.visible = false
	sell_one_button.pressed.connect(_request_sell.bind(1))
	panel.add_child(sell_one_button)
	sell_quantity_button = Button.new()
	sell_quantity_button.name = "SellQuantityButton"
	sell_quantity_button.text = "出售选定数量"
	sell_quantity_button.position = Vector2(20, 432)
	sell_quantity_button.size = Vector2(326, 48)
	sell_quantity_button.theme_type_variation = "GothicComponentButton"
	sell_quantity_button.visible = false
	sell_quantity_button.pressed.connect(_request_selected_quantity)
	panel.add_child(sell_quantity_button)
	sell_confirmation = GothicConfirmationPanelScript.new()
	sell_confirmation.name = "SellConfirmation"
	sell_confirmation.confirmed.connect(_on_sell_confirmation_confirmed)
	sell_confirmation.cancelled.connect(_cancel_pending_sell)
	add_child(sell_confirmation)

func _add_quantity_decoration(button: Button, flip_h: bool) -> void:
	var decoration := TextureRect.new()
	decoration.name = "QuantityDecoration"
	var atlas := AtlasTexture.new()
	atlas.atlas = QUANTITY_BUTTON_TEXTURE
	atlas.region = Rect2(0, 0, 58, 46)
	decoration.texture = atlas
	decoration.position = Vector2(3, 3)
	decoration.size = Vector2(52, 40)
	decoration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	decoration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	decoration.flip_h = flip_h
	decoration.set_meta("atlas_region", atlas.region)
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.show_behind_parent = true
	button.add_child(decoration)

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


func _framed_section(node_name: String, rect: Rect2) -> Panel:
	var surface := Panel.new()
	surface.name = "%sSurface" % node_name
	surface.position = rect.position
	surface.size = rect.size
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)
	var frame := Panel.new()
	frame.name = node_name
	frame.position = rect.position
	frame.size = rect.size
	frame.theme_type_variation = "GothicInsetFrame"
	add_child(frame)
	return frame


func _section_title(text_value: String, section_width: float) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = Vector2(24, 18)
	label.size = Vector2(section_width - 48.0, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicSectionTitle"
	return label


func open_for(display_name: String, new_stock: Array) -> void:
	stock = new_stock
	_sell_quotes.clear()
	_selected_sell_index = -1
	_sell_quantity = 1
	_selected_sell_indices.clear()
	_sell_quantities.clear()
	shop_title.text = display_name
	item_list.clear()
	for entry: Variant in stock:
		item_list.add_item("%s　%d金币" % [entry.get("name", "物品"), int(entry.get("price", 0))])
	_set_trade_mode("buy")
	_refresh_gold()
	_refresh_repair_preview()
	show()


func _rebuild_goods_cards() -> void:
	_clear_goods_cards()
	for index in range(stock.size()):
		var entry: Dictionary = stock[index]
		var card := Button.new()
		card.name = "GoodsCard_%d" % index
		card.custom_minimum_size = CARD_SIZE
		card.size = CARD_SIZE
		card.toggle_mode = true
		card.theme_type_variation = "GothicComponentShopCard"
		card.tooltip_text = str(entry.get("name", "物品"))
		card.pressed.connect(_select_shop_item.bind(index))
		card.set_meta("stock_index", index)
		goods_grid.add_child(card)
		goods_buttons.append(card)
		_build_card_contents(card, entry)


func _rebuild_sell_cards() -> void:
	_clear_goods_cards()
	for inventory_index in range(PlayerState.inventory.size()):
		var record: Variant = PlayerState.inventory[inventory_index]
		if not record is Dictionary:
			continue
		var sell_record: Dictionary = record
		var quote_key := sell_quote_key(inventory_index, sell_record)
		var quote: Dictionary = _sell_quotes.get(quote_key, {})
		var sellable := bool(quote.get("sellable", false))
		var price_text := "%d 金币 / 件" % int(quote.get("unit_price", 0)) if sellable else str(quote.get("reason", "等待商店报价"))
		var card := Button.new()
		card.name = "SellCard_%d" % inventory_index
		card.custom_minimum_size = CARD_SIZE
		card.size = CARD_SIZE
		card.toggle_mode = true
		card.theme_type_variation = "GothicComponentShopCard"
		card.tooltip_text = str(quote.get("reason", "等待玩法层提供出售报价"))
		card.pressed.connect(_select_sell_item.bind(inventory_index))
		card.set_meta("inventory_index", inventory_index)
		card.set_meta("quote_key", quote_key)
		goods_grid.add_child(card)
		goods_buttons.append(card)
		var display_entry: Dictionary = sell_record.duplicate(true)
		var count := int(sell_record.get("count", 1))
		if count > 1:
			display_entry["name"] = "%s ×%d" % [sell_record.get("name", "物品"), count]
		_build_card_contents(card, display_entry, price_text)


func _clear_goods_cards() -> void:
	for child: Node in goods_grid.get_children():
		child.free()
	goods_buttons.clear()


func _build_card_contents(card: Button, entry: Dictionary, price_text := "") -> void:
	var item_name := str(entry.get("name", "物品"))
	var catalog_name := item_name.split(" ×")[0]
	var texture := _item_texture(GameData.get_item_record(catalog_name))
	if texture != null:
		var icon := TextureRect.new()
		icon.name = "ItemIcon"
		icon.texture = texture
		icon.size = texture.get_size()
		icon.position = Vector2(37, CARD_SIZE.y * 0.5) - icon.size * 0.5
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(icon)
	var name_label := Label.new()
	name_label.name = "ItemName"
	name_label.text = item_name
	name_label.position = Vector2(84, 11)
	name_label.size = Vector2(184, 28)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color("ecd4aa"))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_label)
	var price_label := Label.new()
	price_label.name = "Price"
	price_label.text = price_text if not price_text.is_empty() else "%d 金币" % int(entry.get("price", 0))
	price_label.position = Vector2(84, 39)
	price_label.size = Vector2(184, 22)
	price_label.add_theme_font_size_override("font_size", 13)
	price_label.add_theme_color_override("font_color", Color("b9955e"))
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(price_label)


func _select_shop_item(index: int) -> void:
	if index < 0 or index >= stock.size():
		return
	item_list.select(index)
	_on_item_selected(index)


func _set_trade_mode(mode: String) -> void:
	_trade_mode = "sell" if mode == "sell" else "buy"
	var buying := _trade_mode == "buy"
	buy_tab_button.theme_type_variation = "GothicComponentSelectedButton" if buying else "GothicComponentButton"
	sell_tab_button.theme_type_variation = "GothicComponentButton" if buying else "GothicComponentSelectedButton"
	buy_button.visible = buying
	repair_button.visible = buying
	sell_quantity_row.visible = not buying
	sell_one_button.visible = not buying
	sell_quantity_button.visible = not buying
	if buying:
		_rebuild_goods_cards()
		detail_label.text = "[color=#cdbb9e]选择商品查看属性、价格与穿戴要求。[/color]"
	else:
		_selected_sell_index = -1
		_sell_quantity = 1
		_selected_sell_indices.clear()
		_sell_quantities.clear()
		_rebuild_sell_cards()
		_set_sell_actions_enabled(false)
		_update_sell_quantity_label()
		detail_label.text = "[color=#cdbb9e]出售页只显示人物背包物品；已穿戴装备不会出现在这里。[/color]\n\n[color=#a99479]出售价格由玩法层报价，UI不会自行计算。[/color]"
		_request_sell_quotes()


func sell_quote_key(inventory_index: int, record: Dictionary) -> String:
	var instance_id := str(record.get("instance_id", ""))
	return "instance:%s" % instance_id if not instance_id.is_empty() else "inventory:%d" % inventory_index


func set_sell_quotes(quotes: Dictionary) -> void:
	_sell_quotes = quotes.duplicate(true)
	if _trade_mode == "sell":
		_rebuild_sell_cards()
		for card: Button in goods_buttons:
			var selected := _selected_sell_indices.has(int(card.get_meta("inventory_index", -1)))
			card.set_pressed_no_signal(selected)
			card.theme_type_variation = "GothicComponentSelectedShopCard" if selected else "GothicComponentShopCard"
		_update_sell_quantity_label()


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
	if bool(result.get("success", false)) and _trade_mode == "sell":
		_inventory_refresh_pending = false
		_selected_sell_index = -1
		_selected_sell_indices.clear()
		_sell_quantities.clear()
		_batch_sell_queue.clear()
		_rebuild_sell_cards()
		_set_sell_actions_enabled(false)
		_request_sell_quotes()


func _request_sell_quotes() -> void:
	var items: Array = []
	for inventory_index in range(PlayerState.inventory.size()):
		var record: Variant = PlayerState.inventory[inventory_index]
		if not record is Dictionary:
			continue
		items.append({
			"quote_key": sell_quote_key(inventory_index, record),
			"inventory_index": inventory_index,
			"instance_id": str(record.get("instance_id", "")),
			"item_name": str(record.get("name", "")),
			"count": int(record.get("count", 1)),
		})
	sell_quotes_requested.emit(items)


func _select_sell_item(inventory_index: int) -> void:
	if inventory_index < 0 or inventory_index >= PlayerState.inventory.size():
		return
	var record: Dictionary = PlayerState.inventory[inventory_index]
	var quote: Dictionary = _sell_quotes.get(sell_quote_key(inventory_index, record), {})
	if not bool(quote.get("sellable", false)):
		_show_sell_detail(inventory_index, quote)
		_set_sell_actions_enabled(not _selected_sell_indices.is_empty())
		return
	if _selected_sell_indices.has(inventory_index):
		_selected_sell_indices.erase(inventory_index)
		_sell_quantities.erase(inventory_index)
	else:
		_selected_sell_indices[inventory_index] = true
		_sell_quantities[inventory_index] = 1
	_selected_sell_index = inventory_index if _selected_sell_indices.has(inventory_index) else (_selected_sell_indices.keys()[-1] if not _selected_sell_indices.is_empty() else -1)
	for card: Button in goods_buttons:
		var selected := _selected_sell_indices.has(int(card.get_meta("inventory_index", -1)))
		card.set_pressed_no_signal(selected)
		card.theme_type_variation = "GothicComponentSelectedShopCard" if selected else "GothicComponentShopCard"
	if _selected_sell_index < 0:
		_sell_quantity = 1
		_update_sell_quantity_label()
		_set_sell_actions_enabled(false)
		return
	var quote_key := sell_quote_key(_selected_sell_index, PlayerState.inventory[_selected_sell_index])
	quote = _sell_quotes.get(quote_key, {})
	record = PlayerState.inventory[_selected_sell_index]
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
	var risk_text := _sell_risk_text(quote)
	var reason := str(quote.get("reason", ""))
	detail_label.text = "[color=#f2c783][font_size=20]%s[/font_size][/color]\n数量：%d\n[color=#d3a763]单件报价：%d金币[/color]\n%s%s" % [
		record.get("name", "物品"), count, int(quote.get("unit_price", 0)),
		"\n[color=#ef9f63]风险：%s[/color]" % risk_text if not risk_text.is_empty() else "",
		"\n[color=#b8a58a]%s[/color]" % reason if not reason.is_empty() else "",
	]

func _show_sell_detail(inventory_index: int, quote: Dictionary) -> void:
	var record: Dictionary = PlayerState.inventory[inventory_index]
	detail_label.text = "[color=#f2c783][font_size=20]%s[/font_size][/color]\n数量：%d\n\n[color=#d4a15e]%s[/color]" % [record.get("name", "物品"), int(record.get("count", 1)), str(quote.get("reason", "等待商店报价"))]


func _change_sell_quantity(delta: int) -> void:
	if _selected_sell_index < 0 or _selected_sell_index >= PlayerState.inventory.size():
		return
	var record: Dictionary = PlayerState.inventory[_selected_sell_index]
	var quote: Dictionary = _sell_quotes.get(sell_quote_key(_selected_sell_index, record), {})
	var maximum := clampi(int(quote.get("max_quantity", int(record.get("count", 1)))), 1, maxi(1, int(record.get("count", 1))))
	_sell_quantity = clampi(int(_sell_quantities.get(_selected_sell_index, _sell_quantity)) + delta, 1, maximum)
	_sell_quantities[_selected_sell_index] = _sell_quantity
	_update_sell_quantity_label()


func _update_sell_quantity_label() -> void:
	if sell_quantity_label == null:
		return
	sell_quantity_label.text = "出售数量：%d" % _sell_quantity
	if sell_quantity_button != null:
		sell_quantity_button.text = "出售选定数量（%d）" % _sell_quantity


func _request_selected_quantity() -> void:
	_request_sell(0)


func _request_sell_batch(amount: int) -> void:
	if _selected_sell_indices.is_empty() and _selected_sell_index >= 0:
		_selected_sell_indices[_selected_sell_index] = true
		_sell_quantities[_selected_sell_index] = _sell_quantity
	if _selected_sell_indices.is_empty():
		return
	var requests: Array = []
	for index_variant in _selected_sell_indices.keys():
		var inventory_index := int(index_variant)
		if inventory_index < 0 or inventory_index >= PlayerState.inventory.size():
			continue
		var record: Dictionary = PlayerState.inventory[inventory_index]
		var quote_key := sell_quote_key(inventory_index, record)
		var quote: Dictionary = _sell_quotes.get(quote_key, {})
		if not bool(quote.get("sellable", false)):
			continue
		var maximum := clampi(int(quote.get("max_quantity", int(record.get("count", 1)))), 1, maxi(1, int(record.get("count", 1))))
		var requested_amount := 1 if amount == 1 else int(_sell_quantities.get(inventory_index, 1))
		requests.append({"quote_key": quote_key, "quote_id": str(quote.get("quote_id", "")), "inventory_index": inventory_index, "instance_id": str(record.get("instance_id", "")), "item_name": str(record.get("name", "")), "amount": clampi(requested_amount, 1, maximum), "requires_confirmation": bool(quote.get("requires_confirmation", false))})
	if requests.is_empty():
		return
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("inventory_index", -1)) > int(b.get("inventory_index", -1)))
	if requests.any(func(r: Dictionary) -> bool: return bool(r.get("requires_confirmation", false))):
		_pending_sell_request = {"batch": requests}
		sell_confirmation.open_confirmation({"action_id": "shop.sell.risky_item", "title": "确认批量出售", "message": "批量出售 %d 件物品，其中包含高风险物品。" % requests.size(), "confirm_label": "确认出售", "cancel_label": "取消", "tone": "danger", "context": {"quote_id": requests[0].get("quote_id", "")}})
		return
	_batch_sell_queue = requests
	_batch_sell_active = true
	_emit_next_batch_request()

func _emit_next_batch_request() -> void:
	if _batch_sell_queue.is_empty():
		_batch_sell_active = false
		return
	_emit_sell_request(_batch_sell_queue.pop_front())

func _request_sell(amount: int) -> void:
	_request_sell_batch(amount)


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
		_batch_sell_queue = _pending_sell_request.get("batch", []).duplicate(true)
		_pending_sell_request.clear()
		_batch_sell_active = true
		_emit_next_batch_request()
		return
	var request := _pending_sell_request.duplicate(true)
	_pending_sell_request.clear()
	_emit_sell_request(request)


func _emit_sell_request(request: Dictionary) -> void:
	detail_label.text = "[color=#d8bd8c]出售请求已提交，等待玩法层返回交易结果。[/color]"
	sell_requested.emit(request.duplicate(true))


func _set_sell_actions_enabled(enabled: bool) -> void:
	sell_one_button.disabled = not enabled
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
	_apply_inventory_change()


func _on_visibility_changed() -> void:
	if visible and _inventory_refresh_pending and _trade_mode == "sell":
		_apply_inventory_change()


func _apply_inventory_change() -> void:
	if _batch_sell_active:
		_inventory_refresh_pending = true
		return
	_inventory_refresh_pending = false
	_inventory_refresh_execution_count += 1
	_selected_sell_index = -1
	_rebuild_sell_cards()
	_set_sell_actions_enabled(false)
	_request_sell_quotes()


func _refresh_gold() -> void:
	if gold_label != null:
		gold_label.text = "金币 %d" % PlayerState.gold


func _refresh_repair_preview() -> void:
	if repair_button == null:
		return
	var cost := PlayerState.repair_cost()
	repair_button.text = "维修全部（%d金币）" % cost if cost > 0 else "装备无需维修"


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= stock.size():
		return
	for card_index in range(goods_buttons.size()):
		var card := goods_buttons[card_index]
		var selected := card_index == index
		card.set_pressed_no_signal(selected)
		card.theme_type_variation = "GothicComponentSelectedShopCard" if selected else "GothicComponentShopCard"
	var entry: Dictionary = stock[index]
	var item_name := str(entry.get("name", ""))
	var item := GameData.get_item_record(item_name)
	var description := str(entry.get("description", ""))
	if not item.is_empty():
		description += "\n类别：%s\n攻击：%s-%s\n防御：%s-%s\n需要等级：%s" % [
			item.get("category", ""), _value(item.get("attackMin")), _value(item.get("attackMax")),
			_value(item.get("defenseMin")), _value(item.get("defenseMax")), _value(item.get("reqLevel")),
		]
	detail_label.text = "[color=#f2c783][font_size=20]%s[/font_size][/color]\n[color=#d3a763]价格：%d金币[/color]\n\n%s" % [item_name, int(entry.get("price", 0)), description]


func _repair_all() -> void:
	detail_label.text = PlayerState.repair_all_equipment()
	_refresh_gold()


func _buy_selected() -> void:
	var selected := item_list.get_selected_items()
	if selected.is_empty():
		detail_label.text = "请先选择商品。"
		return
	var entry: Dictionary = stock[selected[0]]
	var price := int(entry.get("price", 0))
	if not PlayerState.spend_gold(price):
		detail_label.text = "金币不足。"
		return
	PlayerState.add_item(str(entry.get("name", "未知物品")))
	detail_label.text = "[color=#e8c277]购买成功：%s[/color]" % entry.get("name", "")
	_refresh_gold()


func _item_texture(record: Dictionary) -> Texture2D:
	return UIItemTextureCacheScript.texture_for(record, "inventoryIcon")


func _value(value: Variant) -> String:
	return "—" if value == null else str(value)


func _close() -> void:
	sell_confirmation.close_confirmation()
	_pending_sell_request.clear()
	hide()
	closed.emit()
