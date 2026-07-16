class_name WarehousePanel
extends Panel

var bag_list: ItemList
var stash_list: ItemList


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-310, -240)
	size = Vector2(620, 480)
	z_index = 55
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.03, 0.98)
	style.border_color = Color(0.48, 0.34, 0.20)
	style.set_border_width_all(3)
	add_theme_stylebox_override("panel", style)
	var title := Label.new()
	title.text = "比奇仓库"
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", 26)
	add_child(title)
	bag_list = _list(Vector2(24, 64), "背包")
	stash_list = _list(Vector2(324, 64), "仓库")
	var deposit := Button.new()
	deposit.text = "存入 →"
	deposit.position = Vector2(210, 388)
	deposit.size = Vector2(95, 52)
	deposit.pressed.connect(_deposit)
	add_child(deposit)
	var withdraw := Button.new()
	withdraw.text = "← 取出"
	withdraw.position = Vector2(315, 388)
	withdraw.size = Vector2(95, 52)
	withdraw.pressed.connect(_withdraw)
	add_child(withdraw)
	var close := Button.new()
	close.text = "关闭"
	close.position = Vector2(475, 388)
	close.size = Vector2(110, 52)
	close.pressed.connect(hide)
	add_child(close)


func _list(position: Vector2, label_text: String) -> ItemList:
	var label := Label.new()
	label.text = label_text
	label.position = position
	add_child(label)
	var list := ItemList.new()
	list.position = position + Vector2(0, 32)
	list.size = Vector2(270, 280)
	add_child(list)
	return list


func open_panel() -> void:
	refresh()
	show()


func refresh() -> void:
	_fill(bag_list, PlayerState.inventory)
	_fill(stash_list, PlayerState.warehouse_inventory)


func _fill(list: ItemList, records: Array) -> void:
	list.clear()
	for record: Variant in records:
		list.add_item(str(record.get("name", "未知物品")) if record is Dictionary else str(record))


func _deposit() -> void:
	var selected := bag_list.get_selected_items()
	if selected.is_empty(): return
	PlayerState.warehouse_inventory.append(PlayerState.inventory.pop_at(selected[0]))
	PlayerState.inventory_changed.emit()
	PlayerState.save_game()
	refresh()


func _withdraw() -> void:
	var selected := stash_list.get_selected_items()
	if selected.is_empty(): return
	PlayerState.inventory.append(PlayerState.warehouse_inventory.pop_at(selected[0]))
	PlayerState.inventory_changed.emit()
	PlayerState.save_game()
	refresh()
