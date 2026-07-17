class_name ShopPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")

signal closed

const PANEL_SIZE := Vector2(1080, 620)
const CARD_SIZE := Vector2(286, 72)
const CARD_COLUMNS := 2

var shop_title: Label
var gold_label: Label
var item_list: ItemList
var goods_grid: GridContainer
var goods_buttons: Array[Button] = []
var detail_label: RichTextLabel
var buy_button: Button
var repair_button: Button
var stock: Array = []


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
	var panel := _framed_section("GoodsPanel", Rect2(26, 72, 650, 522))
	panel.add_child(_section_title("商品列表", 200))
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.position = Vector2(372, 14)
	gold_label.size = Vector2(254, 30)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.theme_type_variation = "GothicMutedLabel"
	gold_label.add_theme_color_override("font_color", Color("d6b16f"))
	panel.add_child(gold_label)
	var scroll := ScrollContainer.new()
	scroll.name = "GoodsScroll"
	scroll.position = Vector2(18, 54)
	scroll.size = Vector2(614, 446)
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
	var panel := _framed_section("DetailPanel", Rect2(688, 72, 366, 522))
	panel.add_child(_section_title("商品详情", 366))
	detail_label = RichTextLabel.new()
	detail_label.name = "DetailLabel"
	detail_label.position = Vector2(18, 56)
	detail_label.size = Vector2(330, 286)
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.theme_type_variation = "GothicDetailText"
	panel.add_child(detail_label)
	buy_button = Button.new()
	buy_button.name = "BuyButton"
	buy_button.text = "购买"
	buy_button.position = Vector2(20, 356)
	buy_button.size = Vector2(326, 58)
	buy_button.theme_type_variation = "GothicComponentSelectedButton"
	buy_button.add_theme_font_size_override("font_size", 18)
	buy_button.pressed.connect(_buy_selected)
	panel.add_child(buy_button)
	repair_button = Button.new()
	repair_button.name = "RepairButton"
	repair_button.text = "维修全部装备"
	repair_button.position = Vector2(20, 426)
	repair_button.size = Vector2(326, 58)
	repair_button.theme_type_variation = "GothicComponentButton"
	repair_button.add_theme_font_size_override("font_size", 16)
	repair_button.pressed.connect(_repair_all)
	panel.add_child(repair_button)


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
	label.position = Vector2(18, 12)
	label.size = Vector2(section_width - 36.0, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicSectionTitle"
	return label


func open_for(display_name: String, new_stock: Array) -> void:
	stock = new_stock
	shop_title.text = display_name
	item_list.clear()
	for entry: Variant in stock:
		item_list.add_item("%s　%d金币" % [entry.get("name", "物品"), int(entry.get("price", 0))])
	_rebuild_goods_cards()
	detail_label.text = "[color=#cdbb9e]选择商品查看属性、价格与穿戴要求。[/color]"
	_refresh_gold()
	_refresh_repair_preview()
	show()


func _rebuild_goods_cards() -> void:
	for child: Node in goods_grid.get_children():
		child.free()
	goods_buttons.clear()
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


func _build_card_contents(card: Button, entry: Dictionary) -> void:
	var item_name := str(entry.get("name", "物品"))
	var texture := _item_texture(GameData.get_item_record(item_name))
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
	price_label.text = "%d 金币" % int(entry.get("price", 0))
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
	var art: Variant = record.get("art", {})
	if not art is Dictionary:
		return null
	var source: Variant = art.get("inventoryIcon", {})
	var path := str(source.get("path", "")) if source is Dictionary else str(source)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _value(value: Variant) -> String:
	return "—" if value == null else str(value)


func _close() -> void:
	hide()
	closed.emit()
