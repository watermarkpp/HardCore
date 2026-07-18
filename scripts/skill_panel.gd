class_name SkillPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const HUDSkillIconCatalogScript := preload("res://scripts/hud_skill_icon_catalog.gd")

signal closed
signal quick_slot_assignment_requested(request: Dictionary)

const PANEL_SIZE := Vector2(1208, 650)
const LONG_PRESS_SECONDS := 0.48
const ASSIGNABLE_QUICK_SLOT_COUNT := 3

var trainer_title: Label
var trainer_context_label: Label
var skill_list: ItemList
var skill_list_container: VBoxContainer
var skill_count_label: Label
var skill_name_label: Label
var skill_icon: TextureRect
var detail_label: RichTextLabel
var description_label: RichTextLabel
var learn_button: Button
var assign_button: Button
var assignment_buttons: Array[Button] = []
var assignment_popup: Panel
var assignment_popup_title: Label
var assignment_popup_buttons: Array[Button] = []
var skill_entries: Array = []
var skill_buttons: Array[Button] = []
var selected_skill_index := -1
var _trainer_name := "技能导师"
var _long_press_timer: Timer
var _pressed_skill_index := -1
var _press_origin := Vector2.ZERO
var _long_press_opened := false


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
	_build_skill_list_section()
	_build_skill_detail_section()
	_build_assignment_section()
	_build_assignment_popup()
	_build_compatibility_list()
	_build_long_press_timer()
	PlayerState.skills_changed.connect(refresh)
	PlayerState.inventory_changed.connect(refresh)


func _build_modal_surface() -> void:
	var surface := Panel.new()
	surface.name = "ModalSurface"
	surface.position = Vector2(18, 24)
	surface.size = Vector2(1172, 604)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(374, 4)
	title_frame.size = Vector2(460, 64)
	title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_frame.theme_type_variation = "GothicTitleBar"
	add_child(title_frame)
	trainer_title = Label.new()
	trainer_title.name = "Title"
	trainer_title.text = "技能典籍"
	trainer_title.position = Vector2(30, 15)
	trainer_title.size = Vector2(400, 32)
	trainer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trainer_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	trainer_title.add_theme_font_size_override("font_size", 24)
	trainer_title.add_theme_color_override("font_color", Color("f1cc88"))
	title_frame.add_child(trainer_title)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.position = Vector2(1128, 8)
	close_button.size = Vector2(56, 56)
	close_button.theme_type_variation = "GothicComponentCloseButton"
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(_close)
	add_child(close_button)


func _build_skill_list_section() -> void:
	var panel := _section_panel("SkillListPanel", Rect2(20, 76, 310, 548))
	panel.add_child(_section_title("人物技能", 310))
	trainer_context_label = Label.new()
	trainer_context_label.name = "TrainerContext"
	trainer_context_label.position = Vector2(18, 50)
	trainer_context_label.size = Vector2(274, 28)
	trainer_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trainer_context_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	trainer_context_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(trainer_context_label)
	var scroll := ScrollContainer.new()
	scroll.name = "SkillListScroll"
	scroll.position = Vector2(18, 86)
	scroll.size = Vector2(274, 404)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	skill_list_container = VBoxContainer.new()
	skill_list_container.name = "SkillCards"
	skill_list_container.custom_minimum_size = Vector2(266, 0)
	skill_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_list_container.add_theme_constant_override("separation", 7)
	scroll.add_child(skill_list_container)
	skill_count_label = Label.new()
	skill_count_label.name = "SkillCount"
	skill_count_label.position = Vector2(18, 500)
	skill_count_label.size = Vector2(274, 26)
	skill_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skill_count_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(skill_count_label)


func _build_skill_detail_section() -> void:
	var panel := _section_panel("SkillDetailPanel", Rect2(342, 76, 500, 548))
	panel.add_child(_section_title("技能详情", 500))
	var icon_frame := Button.new()
	icon_frame.name = "SkillIconFrame"
	icon_frame.position = Vector2(24, 58)
	icon_frame.size = Vector2(112, 112)
	icon_frame.disabled = true
	icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.theme_type_variation = "GothicComponentSlotButton"
	panel.add_child(icon_frame)
	skill_icon = TextureRect.new()
	skill_icon.name = "SkillIcon"
	skill_icon.position = Vector2(10, 10)
	skill_icon.size = Vector2(92, 92)
	skill_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skill_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	skill_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	skill_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_child(skill_icon)
	skill_name_label = Label.new()
	skill_name_label.name = "SkillName"
	skill_name_label.text = "请选择技能"
	skill_name_label.position = Vector2(152, 58)
	skill_name_label.size = Vector2(324, 38)
	skill_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skill_name_label.add_theme_font_size_override("font_size", 22)
	skill_name_label.add_theme_color_override("font_color", Color("f2c783"))
	panel.add_child(skill_name_label)
	detail_label = RichTextLabel.new()
	detail_label.name = "SkillStats"
	detail_label.position = Vector2(152, 104)
	detail_label.size = Vector2(324, 190)
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.theme_type_variation = "GothicDetailText"
	detail_label.add_theme_font_size_override("normal_font_size", 15)
	panel.add_child(detail_label)
	var description_title := Label.new()
	description_title.name = "DescriptionTitle"
	description_title.text = "技能说明与来源"
	description_title.position = Vector2(24, 304)
	description_title.size = Vector2(452, 28)
	description_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description_title.theme_type_variation = "GothicSectionTitle"
	panel.add_child(description_title)
	description_label = RichTextLabel.new()
	description_label.name = "SkillDescription"
	description_label.position = Vector2(24, 338)
	description_label.size = Vector2(452, 116)
	description_label.bbcode_enabled = true
	description_label.fit_content = false
	description_label.scroll_active = true
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.theme_type_variation = "GothicDetailText"
	panel.add_child(description_label)
	learn_button = Button.new()
	learn_button.name = "LearnButton"
	learn_button.text = "使用技能书学习"
	learn_button.position = Vector2(24, 466)
	learn_button.size = Vector2(210, 64)
	learn_button.theme_type_variation = "GothicComponentButton"
	learn_button.pressed.connect(_learn_selected)
	panel.add_child(learn_button)
	assign_button = Button.new()
	assign_button.name = "AssignButton"
	assign_button.text = "配置技能按钮"
	assign_button.position = Vector2(246, 466)
	assign_button.size = Vector2(230, 64)
	assign_button.theme_type_variation = "GothicComponentSelectedButton"
	assign_button.pressed.connect(_open_assignment_popup_for_selected)
	panel.add_child(assign_button)


func _build_assignment_section() -> void:
	var panel := _section_panel("AssignmentPanel", Rect2(854, 76, 334, 548))
	panel.add_child(_section_title("战斗技能按钮", 334))
	for slot_index in range(ASSIGNABLE_QUICK_SLOT_COUNT):
		var button := Button.new()
		button.name = "QuickSlot_%d" % (slot_index + 1)
		button.position = Vector2(22, 66 + slot_index * 130)
		button.size = Vector2(290, 112)
		button.text = ""
		button.theme_type_variation = "GothicComponentButton"
		button.pressed.connect(_assign_selected_to_slot.bind(slot_index))
		button.set_meta("slot_index", slot_index)
		panel.add_child(button)
		assignment_buttons.append(button)
	var hint := Label.new()
	hint.name = "AssignmentHint"
	hint.text = "长按左侧已学技能\n再选择按钮 1 / 2 / 3"
	hint.position = Vector2(24, 458)
	hint.size = Vector2(286, 58)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.theme_type_variation = "GothicMutedLabel"
	panel.add_child(hint)


func _build_assignment_popup() -> void:
	assignment_popup = Panel.new()
	assignment_popup.name = "SkillAssignmentPopup"
	assignment_popup.position = Vector2(354, 168)
	assignment_popup.size = Vector2(500, 300)
	assignment_popup.z_index = 100
	assignment_popup.theme_type_variation = "GothicModalFrame"
	assignment_popup.visible = false
	add_child(assignment_popup)
	assignment_popup_title = Label.new()
	assignment_popup_title.name = "PopupTitle"
	assignment_popup_title.position = Vector2(28, 34)
	assignment_popup_title.size = Vector2(444, 42)
	assignment_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	assignment_popup_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	assignment_popup_title.add_theme_font_size_override("font_size", 21)
	assignment_popup_title.add_theme_color_override("font_color", Color("f1cc88"))
	assignment_popup.add_child(assignment_popup_title)
	var hint := Label.new()
	hint.text = "选择要替换的右下战斗技能按钮"
	hint.position = Vector2(28, 82)
	hint.size = Vector2(444, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.theme_type_variation = "GothicMutedLabel"
	assignment_popup.add_child(hint)
	for slot_index in range(ASSIGNABLE_QUICK_SLOT_COUNT):
		var button := Button.new()
		button.name = "PopupSlot_%d" % (slot_index + 1)
		button.text = "按钮 %d" % (slot_index + 1)
		button.position = Vector2(34 + slot_index * 150, 130)
		button.size = Vector2(132, 78)
		button.theme_type_variation = "GothicComponentButton"
		button.pressed.connect(_assign_selected_to_slot.bind(slot_index))
		assignment_popup.add_child(button)
		assignment_popup_buttons.append(button)
	var cancel_button := Button.new()
	cancel_button.name = "CancelButton"
	cancel_button.text = "取消"
	cancel_button.position = Vector2(184, 220)
	cancel_button.size = Vector2(132, 62)
	cancel_button.theme_type_variation = "GothicComponentButton"
	cancel_button.pressed.connect(func() -> void: assignment_popup.hide())
	assignment_popup.add_child(cancel_button)


func _build_compatibility_list() -> void:
	skill_list = ItemList.new()
	skill_list.name = "CompatibilitySkillList"
	skill_list.visible = false
	skill_list.item_selected.connect(_on_skill_selected)
	add_child(skill_list)


func _build_long_press_timer() -> void:
	_long_press_timer = Timer.new()
	_long_press_timer.name = "SkillLongPressTimer"
	_long_press_timer.one_shot = true
	_long_press_timer.wait_time = LONG_PRESS_SECONDS
	_long_press_timer.timeout.connect(_on_skill_long_press)
	add_child(_long_press_timer)


func open_for(display_name: String) -> void:
	_trainer_name = display_name
	skill_entries = GameData.get_profession_skills(PlayerState.profession)
	selected_skill_index = 0 if not skill_entries.is_empty() else -1
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
	_rebuild_skill_cards()
	_refresh_assignment_slots()
	trainer_context_label.text = "%s　·　%s" % [_trainer_name, PlayerState.profession]
	skill_count_label.text = "%s技能　%d 项" % [PlayerState.profession, skill_entries.size()]
	if selected_skill_index >= 0 and selected_skill_index < skill_entries.size():
		skill_list.select(selected_skill_index)
		_show_skill_detail(selected_skill_index)
	else:
		_clear_skill_detail()


func _rebuild_skill_cards() -> void:
	for child: Node in skill_list_container.get_children():
		child.free()
	skill_buttons.clear()
	for index in range(skill_entries.size()):
		var entry: Dictionary = skill_entries[index]
		var skill_name := str(entry.get("skillName", "技能"))
		var learned := PlayerState.is_skill_learned(skill_name)
		var has_book := PlayerState.has_item(skill_name)
		var level := int(PlayerState.learned_skills.get(skill_name, 0))
		var status := "Lv.%d　已学会" % level if learned else ("可学习" if has_book else "缺少技能书")
		var button := Button.new()
		button.name = "SkillCard_%d" % index
		button.custom_minimum_size = Vector2(266, 64)
		button.toggle_mode = true
		button.text = "%s\n%s" % [skill_name, status]
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 15)
		button.set_pressed_no_signal(index == selected_skill_index)
		button.theme_type_variation = "GothicComponentSelectedButton" if index == selected_skill_index else "GothicComponentButton"
		button.pressed.connect(_on_skill_selected.bind(index))
		button.gui_input.connect(_skill_card_input.bind(index))
		button.set_meta("skill_id", ProfessionRules.skill_id(skill_name))
		button.set_meta("learned", learned)
		skill_list_container.add_child(button)
		skill_buttons.append(button)


func _on_skill_selected(index: int) -> void:
	if index < 0 or index >= skill_entries.size():
		return
	selected_skill_index = index
	skill_list.select(index)
	for button_index in range(skill_buttons.size()):
		var button := skill_buttons[button_index]
		var selected := button_index == index
		button.set_pressed_no_signal(selected)
		button.theme_type_variation = "GothicComponentSelectedButton" if selected else "GothicComponentButton"
	_show_skill_detail(index)


func _show_skill_detail(index: int) -> void:
	var entry: Dictionary = skill_entries[index]
	var skill_name := str(entry.get("skillName", ""))
	var learned := PlayerState.is_skill_learned(skill_name)
	var learned_level := int(PlayerState.learned_skills.get(skill_name, 0)) if learned else -1
	var row := GameData.get_skill(skill_name, maxi(0, learned_level))
	if row.is_empty():
		row = entry
	var combat := ProfessionRules.skill_combat_profile(skill_name, learned_level)
	var cast_type := str(combat.get("cast_type", "unknown"))
	var target_mode := str(combat.get("target_mode", "unknown"))
	var cooldown := float(combat.get("cooldown", 0.0))
	var range_value := float(combat.get("range", 0.0))
	var training_points: Variant = row.get("trainingPoints", null)
	var mastery_text := "—" if training_points == null else "下级需求 %s" % training_points
	var state_text := "已学会" if learned else ("可学习" if PlayerState.has_item(skill_name) else "缺少技能书")
	skill_name_label.text = skill_name
	skill_icon.texture = _skill_texture(skill_name)
	skill_icon.set_meta("skill_id", ProfessionRules.skill_id(skill_name))
	detail_label.text = "[color=#ddc9a9]等级：%s　　熟练度：%s\n类型：%s　　目标：%s\n消耗：%d MP　　冷却：%.2f 秒\n范围：%.0f　　状态：%s[/color]" % [
		"Lv.%d" % learned_level if learned else "未学习",
		mastery_text,
		_cast_type_label(cast_type),
		_target_mode_label(target_mode),
		int(row.get("manaCost", 0)),
		cooldown,
		range_value,
		state_text,
	]
	description_label.text = "[color=#d7c3a3]%s[/color]\n\n[color=#8f7d6a]技能ID：%s\n来源：%s　可信度：%s[/color]" % [
		row.get("description", "暂无说明"),
		ProfessionRules.skill_id(skill_name),
		row.get("source", row.get("contentLayer", "vanilla_core")),
		row.get("confidence", "待核验"),
	]
	learn_button.disabled = learned
	learn_button.text = "已学会" if learned else ("使用技能书学习" if PlayerState.has_item(skill_name) else "缺少同名技能书")
	assign_button.disabled = not learned


func _clear_skill_detail() -> void:
	skill_name_label.text = "请选择技能"
	skill_icon.texture = null
	detail_label.text = "[color=#a99479]从左侧选择技能查看完整资料。[/color]"
	description_label.text = ""
	learn_button.disabled = true
	assign_button.disabled = true


func _refresh_assignment_slots() -> void:
	for slot_index in range(assignment_buttons.size()):
		var skill_name := PlayerState.quick_slots[slot_index] if slot_index < PlayerState.quick_slots.size() else ""
		_set_assignment_button_content(assignment_buttons[slot_index], slot_index, skill_name)
		if slot_index < assignment_popup_buttons.size():
			assignment_popup_buttons[slot_index].text = "按钮 %d\n%s" % [slot_index + 1, skill_name if not skill_name.is_empty() else "空"]


func _set_assignment_button_content(button: Button, slot_index: int, skill_name: String) -> void:
	var old_content := button.get_node_or_null("Content")
	if old_content != null:
		old_content.free()
	var content := Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(content)
	var icon_frame := Button.new()
	icon_frame.name = "IconFrame"
	icon_frame.position = Vector2(14, 16)
	icon_frame.size = Vector2(80, 80)
	icon_frame.disabled = true
	icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.theme_type_variation = "GothicComponentSlotButton"
	content.add_child(icon_frame)
	var icon := TextureRect.new()
	icon.name = "SkillIcon"
	icon.position = Vector2(8, 8)
	icon.size = Vector2(64, 64)
	icon.texture = _skill_texture(skill_name)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_child(icon)
	var slot_label := Label.new()
	slot_label.name = "SlotLabel"
	slot_label.text = "技能按钮 %d" % (slot_index + 1)
	slot_label.position = Vector2(104, 18)
	slot_label.size = Vector2(168, 28)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_label.theme_type_variation = "GothicMutedLabel"
	content.add_child(slot_label)
	var name_label := Label.new()
	name_label.name = "SkillName"
	name_label.text = skill_name if not skill_name.is_empty() else "空技能槽"
	name_label.position = Vector2(104, 50)
	name_label.size = Vector2(168, 36)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", Color("f0c77f"))
	content.add_child(name_label)
	button.set_meta("skill_name", skill_name)


func _learn_selected() -> void:
	var index := selected_skill_index
	var selected := skill_list.get_selected_items()
	if not selected.is_empty():
		index = selected[0]
	if index < 0 or index >= skill_entries.size():
		description_label.text = "[color=#b58b68]请先选择技能。[/color]"
		return
	var skill_name := str(skill_entries[index].get("skillName", ""))
	description_label.text = "[color=#d7c3a3]%s[/color]" % PlayerState.learn_skill(skill_name)
	refresh.call_deferred()


func _open_assignment_popup_for_selected() -> void:
	_open_assignment_popup_for(selected_skill_index)


func _open_assignment_popup_for(index: int) -> void:
	if index < 0 or index >= skill_entries.size():
		return
	var skill_name := str(skill_entries[index].get("skillName", ""))
	if not PlayerState.is_skill_learned(skill_name):
		description_label.text = "[color=#b58b68]请先学习该技能，再配置战斗按钮。[/color]"
		return
	_on_skill_selected(index)
	assignment_popup_title.text = "配置：%s" % skill_name
	assignment_popup.set_meta("skill_name", skill_name)
	assignment_popup.set_meta("skill_id", ProfessionRules.skill_id(skill_name))
	assignment_popup.show()


func _assign_selected_to_slot(slot_index: int) -> void:
	if selected_skill_index < 0 or selected_skill_index >= skill_entries.size():
		return
	var skill_name := str(skill_entries[selected_skill_index].get("skillName", ""))
	if not PlayerState.is_skill_learned(skill_name):
		return
	var request := {
		"contract_id": "ui.skill.quick_slot_assignment.v1",
		"profession_id": ProfessionRules.profession_id(PlayerState.profession),
		"skill_id": ProfessionRules.skill_id(skill_name),
		"skill_name": skill_name,
		"slot_index": slot_index,
	}
	quick_slot_assignment_requested.emit(request)
	assignment_popup.hide()


func _skill_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_skill_long_press(index, event.position)
		else:
			_cancel_skill_long_press()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_skill_long_press(index, event.position)
		else:
			_cancel_skill_long_press()
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		if _pressed_skill_index == index and event.position.distance_to(_press_origin) > 18.0:
			_cancel_skill_long_press()


func _begin_skill_long_press(index: int, origin: Vector2) -> void:
	_pressed_skill_index = index
	_press_origin = origin
	_long_press_opened = false
	_long_press_timer.start()


func _cancel_skill_long_press() -> void:
	_long_press_timer.stop()
	_pressed_skill_index = -1


func _on_skill_long_press() -> void:
	if _pressed_skill_index < 0:
		return
	_long_press_opened = true
	_open_assignment_popup_for(_pressed_skill_index)
	_pressed_skill_index = -1


func _skill_texture(skill_name: String) -> Texture2D:
	if skill_name.is_empty():
		return null
	var texture := HUDSkillIconCatalogScript.texture_for(skill_name)
	if texture != null:
		return texture
	var item := GameData.get_item_record(skill_name)
	var art: Variant = item.get("art", {})
	if not art is Dictionary:
		return null
	var source: Variant = art.get("inventoryIcon", {})
	var path := str(source.get("path", "")) if source is Dictionary else str(source)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _cast_type_label(cast_type: String) -> String:
	return {
		"passive": "被动",
		"melee": "近战",
		"line": "直线",
		"area": "范围",
		"dash": "冲锋",
		"projectile": "投射",
		"summon": "召唤",
		"shield": "护盾",
	}.get(cast_type, cast_type)


func _target_mode_label(target_mode: String) -> String:
	return {
		"self": "自身",
		"self_area": "自身范围",
		"single": "单体目标",
		"direction": "方向",
		"target_area": "目标区域",
	}.get(target_mode, target_mode)


func _section_panel(node_name: String, rect: Rect2) -> Panel:
	var surface := Panel.new()
	surface.name = "%sSurface" % node_name
	surface.position = rect.position
	surface.size = rect.size
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)
	var panel := Panel.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.theme_type_variation = "GothicInsetFrame"
	add_child(panel)
	return panel


func _section_title(text_value: String, width: float) -> Label:
	var title := Label.new()
	title.text = text_value
	title.position = Vector2(18, 16)
	title.size = Vector2(width - 36.0, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.theme_type_variation = "GothicSectionTitle"
	return title


func _close() -> void:
	_cancel_skill_long_press()
	assignment_popup.hide()
	hide()
	closed.emit()
