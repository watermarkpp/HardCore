class_name SkillPanel
extends Panel

signal closed

var trainer_title: Label
var skill_list: ItemList
var detail_label: Label
var skill_entries: Array = []


func _ready() -> void:
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -300
	offset_top = -270
	offset_right = 300
	offset_bottom = 270
	z_index = 60
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.045, 0.055, 0.98)
	style.border_color = Color(0.36, 0.45, 0.66)
	style.set_border_width_all(3)
	add_theme_stylebox_override("panel", style)

	trainer_title = Label.new()
	trainer_title.position = Vector2(24, 18)
	trainer_title.add_theme_font_size_override("font_size", 26)
	trainer_title.add_theme_color_override("font_color", Color(0.68, 0.82, 1.0))
	add_child(trainer_title)

	skill_list = ItemList.new()
	skill_list.position = Vector2(24, 72)
	skill_list.size = Vector2(320, 380)
	skill_list.item_selected.connect(_on_skill_selected)
	add_child(skill_list)

	detail_label = Label.new()
	detail_label.position = Vector2(365, 82)
	detail_label.size = Vector2(210, 260)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(detail_label)

	var learn_button := Button.new()
	learn_button.text = "使用技能书学习"
	learn_button.position = Vector2(365, 365)
	learn_button.size = Vector2(210, 54)
	learn_button.pressed.connect(_learn_selected)
	add_child(learn_button)

	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.position = Vector2(365, 435)
	close_button.size = Vector2(210, 48)
	close_button.pressed.connect(_close)
	add_child(close_button)
	PlayerState.skills_changed.connect(refresh)
	PlayerState.inventory_changed.connect(refresh)


func open_for(display_name: String) -> void:
	trainer_title.text = "%s｜%s" % [display_name, PlayerState.profession]
	skill_entries = GameData.get_profession_skills(PlayerState.profession)
	refresh()
	show()


func refresh() -> void:
	if skill_list == null:
		return
	skill_list.clear()
	for entry: Variant in skill_entries:
		var skill_name := str(entry.get("skillName", "技能"))
		var learned := PlayerState.is_skill_learned(skill_name)
		var has_book := PlayerState.has_item(skill_name)
		var marker := "已学" if learned else ("有书" if has_book else "缺书")
		skill_list.add_item("%s　Lv%d　[%s]" % [skill_name, int(entry.get("requiredCharacterLevel", 1)), marker])
	detail_label.text = "购买或拾取同名技能书，达到人物等级后即可学习；学会后自动进入空闲快捷栏。"


func _on_skill_selected(index: int) -> void:
	if index < 0 or index >= skill_entries.size():
		return
	var entry: Dictionary = skill_entries[index]
	var skill_name := str(entry.get("skillName", ""))
	detail_label.text = "%s\n需要等级：%d\n背包技能书：%s\n状态：%s\n\n%s" % [
		skill_name, int(entry.get("requiredCharacterLevel", 1)),
		"有" if PlayerState.has_item(skill_name) else "无",
		"已学会" if PlayerState.is_skill_learned(skill_name) else "未学习",
		entry.get("description", ""),
	]


func _learn_selected() -> void:
	var selected := skill_list.get_selected_items()
	if selected.is_empty():
		detail_label.text = "请先选择技能。"
		return
	var skill_name := str(skill_entries[selected[0]].get("skillName", ""))
	detail_label.text = PlayerState.learn_skill(skill_name)
	refresh.call_deferred()


func _close() -> void:
	hide()
	closed.emit()
