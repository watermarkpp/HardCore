class_name ShopPanel
extends Panel

signal closed

var shop_title: Label
var gold_label: Label
var item_list: ItemList
var detail_label: Label
var repair_button: Button
var stock: Array = []


func _ready() -> void:
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -280
	offset_top = -260
	offset_right = 280
	offset_bottom = 260
	z_index = 60
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.045, 0.03, 0.98)
	style.border_color = Color(0.58, 0.39, 0.18)
	style.set_border_width_all(3)
	add_theme_stylebox_override("panel", style)

	shop_title = Label.new()
	shop_title.position = Vector2(24, 18)
	shop_title.add_theme_font_size_override("font_size", 26)
	shop_title.add_theme_color_override("font_color", Color(1.0, 0.79, 0.43))
	add_child(shop_title)

	gold_label = Label.new()
	gold_label.position = Vector2(370, 25)
	gold_label.size = Vector2(165, 30)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(gold_label)

	item_list = ItemList.new()
	item_list.position = Vector2(24, 72)
	item_list.size = Vector2(310, 360)
	item_list.item_selected.connect(_on_item_selected)
	add_child(item_list)

	detail_label = Label.new()
	detail_label.position = Vector2(354, 82)
	detail_label.size = Vector2(180, 250)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(detail_label)

	var buy_button := Button.new()
	buy_button.text = "购买"
	buy_button.position = Vector2(354, 334)
	buy_button.size = Vector2(180, 48)
	buy_button.pressed.connect(_buy_selected)
	add_child(buy_button)

	repair_button = Button.new()
	repair_button.text = "维修全部装备"
	repair_button.position = Vector2(354, 390)
	repair_button.size = Vector2(180, 48)
	repair_button.pressed.connect(_repair_all)
	add_child(repair_button)

	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.position = Vector2(354, 446)
	close_button.size = Vector2(180, 44)
	close_button.pressed.connect(_close)
	add_child(close_button)
	PlayerState.profile_changed.connect(_refresh_gold)
	PlayerState.equipment_changed.connect(_refresh_repair_preview)
	_refresh_repair_preview()


func open_for(display_name: String, new_stock: Array) -> void:
	stock = new_stock
	shop_title.text = display_name
	item_list.clear()
	for entry: Variant in stock:
		item_list.add_item("%s　%d金币" % [entry.get("name", "物品"), int(entry.get("price", 0))])
	detail_label.text = "选择商品查看说明。"
	_refresh_gold()
	_refresh_repair_preview()
	show()


func _refresh_gold() -> void:
	if gold_label != null:
		gold_label.text = "金币：%d" % PlayerState.gold


func _refresh_repair_preview() -> void:
	if repair_button == null:
		return
	var cost := PlayerState.repair_cost()
	repair_button.text = "维修全部（%d金币）" % cost if cost > 0 else "装备无需维修"


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= stock.size():
		return
	var entry: Dictionary = stock[index]
	var item_name := str(entry.get("name", ""))
	var item := GameData.get_item_record(item_name)
	var description := str(entry.get("description", ""))
	if not item.is_empty():
		description += "\n类别：%s\n攻击：%s-%s\n防御：%s-%s\n需要等级：%s" % [
			item.get("category", ""), _value(item.get("attackMin")), _value(item.get("attackMax")),
			_value(item.get("defenseMin")), _value(item.get("defenseMax")), _value(item.get("reqLevel")),
		]
	detail_label.text = "%s\n价格：%d金币\n\n%s" % [item_name, int(entry.get("price", 0)), description]


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
	detail_label.text = "购买成功：%s" % entry.get("name", "")


func _value(value: Variant) -> String:
	return "—" if value == null else str(value)


func _close() -> void:
	hide()
	closed.emit()
