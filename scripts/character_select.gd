extends Control

var list_box: VBoxContainer
var name_input: LineEdit
var gender_select: OptionButton
var message_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	PlayerState.ensure_developer_test_character()
	PlayerState.ensure_zuma_test_character()
	_build_ui()
	_refresh_profiles()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("120d0b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 48)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 42)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	columns.add_child(left)
	var title := Label.new()
	title.text = "玛法离线"
	title.add_theme_font_size_override("font_size", 42)
	left.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "选择角色进入比奇"
	subtitle.add_theme_font_size_override("font_size", 22)
	left.add_child(subtitle)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 12)
	left.add_child(list_box)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 14)
	columns.add_child(right)
	var create_title := Label.new()
	create_title.text = "创建新角色"
	create_title.add_theme_font_size_override("font_size", 28)
	right.add_child(create_title)
	name_input = LineEdit.new()
	name_input.placeholder_text = "输入角色名（最多12字）"
	name_input.max_length = 12
	right.add_child(name_input)
	var profession := OptionButton.new()
	profession.add_item("战士")
	profession.add_item("法师（后续开放）")
	profession.add_item("道士（后续开放）")
	profession.set_item_disabled(1, true)
	profession.set_item_disabled(2, true)
	right.add_child(profession)
	gender_select = OptionButton.new()
	gender_select.add_item("男")
	gender_select.add_item("女")
	right.add_child(gender_select)
	var create_button := Button.new()
	create_button.text = "创建并进入游戏"
	create_button.custom_minimum_size.y = 64
	create_button.pressed.connect(_create_character)
	right.add_child(create_button)
	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(message_label)


func _refresh_profiles() -> void:
	for child: Node in list_box.get_children():
		child.queue_free()
	var profiles := PlayerState.list_characters()
	if profiles.is_empty():
		var empty := Label.new()
		empty.text = "暂无角色，请创建第一名战士。"
		list_box.add_child(empty)
		return
	for profile: Dictionary in profiles:
		var button := Button.new()
		button.text = "%s　Lv.%d %s%s" % [profile.get("name", "未命名"), int(profile.get("level", 1)), profile.get("gender", "男"), profile.get("profession", "战士")]
		button.custom_minimum_size.y = 72
		button.pressed.connect(_enter_character.bind(str(profile.get("id", ""))))
		list_box.add_child(button)


func _create_character() -> void:
	var error := PlayerState.create_character(name_input.text, "战士", gender_select.get_item_text(gender_select.selected))
	if not error.is_empty():
		message_label.text = error
		return
	_enter_game()


func _enter_character(profile_id: String) -> void:
	if not PlayerState.select_character(profile_id):
		message_label.text = "角色存档不存在或已损坏"
		_refresh_profiles()
		return
	_enter_game()


func _enter_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
