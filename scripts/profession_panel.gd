class_name ProfessionPanel
extends Panel

signal closed

var title_label: Label
var detail_label: Label


func _ready() -> void:
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -300
	offset_top = -220
	offset_right = 300
	offset_bottom = 220
	z_index = 70
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.038, 0.03, 0.98)
	style.border_color = Color(0.68, 0.43, 0.20)
	style.set_border_width_all(3)
	add_theme_stylebox_override("panel", style)

	title_label = Label.new()
	title_label.position = Vector2(24, 20)
	title_label.size = Vector2(552, 38)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color(0.96, 0.76, 0.42))
	add_child(title_label)

	for index in range(ProfessionRules.PROFESSIONS.size()):
		var profession_name := ProfessionRules.PROFESSIONS[index]
		var button := Button.new()
		button.text = profession_name
		button.position = Vector2(35 + index * 180, 82)
		button.size = Vector2(170, 62)
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(_select_profession.bind(profession_name))
		add_child(button)

	detail_label = Label.new()
	detail_label.position = Vector2(34, 170)
	detail_label.size = Vector2(532, 160)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 18)
	add_child(detail_label)

	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.position = Vector2(215, 355)
	close_button.size = Vector2(170, 52)
	close_button.pressed.connect(_close)
	add_child(close_button)
	PlayerState.profession_changed.connect(func(_value: String) -> void: refresh())
	refresh()


func refresh() -> void:
	if title_label == null:
		return
	title_label.text = "职业选择｜当前：%s" % PlayerState.profession
	var counts := {
		"战士": GameData.get_profession_skills("战士").size(),
		"法师": GameData.get_profession_skills("法师").size(),
		"道士": GameData.get_profession_skills("道士").size(),
	}
	detail_label.text = "战士：近战与高生命（%d技能）　法师：远程范围魔法（%d技能）\n道士：治疗、控制与召唤（%d技能）\n\n切换职业会卸下不符合职业要求的装备，并清除其他职业技能。" % [counts["战士"], counts["法师"], counts["道士"]]


func _select_profession(profession_name: String) -> void:
	detail_label.text = PlayerState.select_profession(profession_name)
	refresh.call_deferred()


func _close() -> void:
	hide()
	closed.emit()
