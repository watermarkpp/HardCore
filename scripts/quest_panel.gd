class_name QuestPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")

signal closed

const PANEL_SIZE := Vector2(1020, 636)
const QUEST_CARD_SIZE := Vector2(286, 62)

var title_label: Label
var description_label: RichTextLabel
var status_label: Label
var action_button: Button
var quest_list: VBoxContainer
var quest_buttons: Array[Button] = []
var quest_name_label: Label
var quest_meta_label: Label
var objective_label: RichTextLabel
var reward_label: RichTextLabel
var current_quest_id := ""
var npc_display_name := "比奇老兵"
var _selected_quest_id := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_bottom = PANEL_SIZE.y * 0.5
	z_index = 65
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GothicUIThemeScript.build()
	theme_type_variation = "GothicModalFrame"
	_build_modal_surface()
	_build_header()
	_build_quest_list()
	_build_quest_detail()
	PlayerState.quests_changed.connect(refresh)
	refresh()


func _build_modal_surface() -> void:
	var surface := Panel.new()
	surface.name = "ModalSurface"
	surface.position = Vector2(18, 24)
	surface.size = Vector2(984, 590)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(282, 4)
	title_frame.size = Vector2(456, 64)
	title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_frame.theme_type_variation = "GothicTitleBar"
	add_child(title_frame)
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "任务日志"
	title_label.position = Vector2(28, 15)
	title_label.size = Vector2(400, 34)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color("f1cc88"))
	title_frame.add_child(title_label)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.position = Vector2(940, 8)
	close_button.size = Vector2(56, 56)
	close_button.theme_type_variation = "GothicComponentCloseButton"
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(_close)
	add_child(close_button)


func _build_quest_list() -> void:
	var panel := _framed_section("QuestListPanel", Rect2(24, 76, 326, 528))
	panel.add_child(_section_title("任务列表", 326))
	var chain_label := Label.new()
	chain_label.name = "QuestChainLabel"
	chain_label.text = "比奇主线 · 六段任务"
	chain_label.position = Vector2(24, 52)
	chain_label.size = Vector2(278, 24)
	chain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chain_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(chain_label)
	var scroll := ScrollContainer.new()
	scroll.name = "QuestListScroll"
	scroll.position = Vector2(18, 84)
	scroll.size = Vector2(290, 418)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	quest_list = VBoxContainer.new()
	quest_list.name = "QuestList"
	quest_list.custom_minimum_size = Vector2(286, 0)
	quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_list.add_theme_constant_override("separation", 7)
	scroll.add_child(quest_list)


func _build_quest_detail() -> void:
	var panel := _framed_section("QuestDetailPanel", Rect2(364, 76, 632, 528))
	panel.add_child(_section_title("任务详情", 632))
	quest_name_label = Label.new()
	quest_name_label.name = "QuestName"
	quest_name_label.position = Vector2(28, 58)
	quest_name_label.size = Vector2(576, 34)
	quest_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quest_name_label.add_theme_font_size_override("font_size", 22)
	quest_name_label.add_theme_color_override("font_color", Color("f2c783"))
	panel.add_child(quest_name_label)
	quest_meta_label = Label.new()
	quest_meta_label.name = "QuestMeta"
	quest_meta_label.position = Vector2(28, 94)
	quest_meta_label.size = Vector2(576, 24)
	quest_meta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quest_meta_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(quest_meta_label)
	var divider := HSeparator.new()
	divider.name = "StoryDivider"
	divider.position = Vector2(28, 122)
	divider.size = Vector2(576, 8)
	panel.add_child(divider)
	description_label = RichTextLabel.new()
	description_label.name = "DescriptionLabel"
	description_label.position = Vector2(28, 138)
	description_label.size = Vector2(576, 82)
	description_label.bbcode_enabled = true
	description_label.fit_content = false
	description_label.scroll_active = true
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.theme_type_variation = "GothicDetailText"
	description_label.add_theme_font_size_override("normal_font_size", 16)
	panel.add_child(description_label)
	var objective_title := Label.new()
	objective_title.name = "ObjectiveTitle"
	objective_title.text = "任务目标"
	objective_title.position = Vector2(28, 228)
	objective_title.size = Vector2(260, 28)
	objective_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	objective_title.theme_type_variation = "GothicSectionTitle"
	objective_title.add_theme_font_size_override("font_size", 18)
	panel.add_child(objective_title)
	objective_label = RichTextLabel.new()
	objective_label.name = "ObjectiveDetail"
	objective_label.position = Vector2(28, 260)
	objective_label.size = Vector2(576, 86)
	objective_label.bbcode_enabled = true
	objective_label.fit_content = false
	objective_label.scroll_active = true
	objective_label.theme_type_variation = "GothicDetailText"
	objective_label.add_theme_font_size_override("normal_font_size", 16)
	panel.add_child(objective_label)
	var rewards_panel := Panel.new()
	rewards_panel.name = "RewardsPanel"
	rewards_panel.position = Vector2(28, 356)
	rewards_panel.size = Vector2(576, 72)
	rewards_panel.theme_type_variation = "GothicInfoPanel"
	panel.add_child(rewards_panel)
	var rewards_title := Label.new()
	rewards_title.name = "RewardsTitle"
	rewards_title.text = "任务奖励"
	rewards_title.position = Vector2(18, 12)
	rewards_title.size = Vector2(116, 48)
	rewards_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rewards_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rewards_title.add_theme_font_size_override("font_size", 17)
	rewards_title.add_theme_color_override("font_color", Color("e5bd78"))
	rewards_panel.add_child(rewards_title)
	reward_label = RichTextLabel.new()
	reward_label.name = "RewardDetail"
	reward_label.position = Vector2(150, 14)
	reward_label.size = Vector2(404, 44)
	reward_label.bbcode_enabled = true
	reward_label.fit_content = false
	reward_label.scroll_active = true
	reward_label.theme_type_variation = "GothicDetailText"
	rewards_panel.add_child(reward_label)
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.position = Vector2(28, 436)
	status_label.size = Vector2(268, 52)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.theme_type_variation = "GothicMutedLabel"
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color("d7b56f"))
	panel.add_child(status_label)
	action_button = Button.new()
	action_button.name = "ActionButton"
	action_button.position = Vector2(312, 436)
	action_button.size = Vector2(292, 52)
	action_button.theme_type_variation = "GothicComponentSelectedButton"
	action_button.add_theme_font_size_override("font_size", 18)
	action_button.pressed.connect(_act)
	panel.add_child(action_button)


func open_for(display_name: String) -> void:
	npc_display_name = display_name
	_selected_quest_id = PlayerState.current_bich_quest_id()
	refresh()
	show()


func refresh() -> void:
	if status_label == null:
		return
	var active_quest_id := PlayerState.current_bich_quest_id()
	if _selected_quest_id.is_empty() or GameData.get_bich_quest(_selected_quest_id).is_empty():
		_selected_quest_id = active_quest_id
	if _selected_quest_id.is_empty():
		var quests := GameData.get_bich_quests()
		if not quests.is_empty() and quests[-1] is Dictionary:
			_selected_quest_id = str(quests[-1].get("id", ""))
	current_quest_id = _selected_quest_id
	_rebuild_quest_cards(active_quest_id)
	_refresh_selected_quest(active_quest_id)


func _rebuild_quest_cards(active_quest_id: String) -> void:
	for child: Node in quest_list.get_children():
		child.queue_free()
	quest_buttons.clear()
	var quests := GameData.get_bich_quests()
	for index in range(quests.size()):
		var value: Variant = quests[index]
		if not value is Dictionary:
			continue
		var quest: Dictionary = value
		var quest_id := str(quest.get("id", ""))
		var state_text := _quest_state_text(quest_id, active_quest_id)
		var button := Button.new()
		button.name = "QuestCard_%s" % quest_id
		button.custom_minimum_size = QUEST_CARD_SIZE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.text = "%02d　%s\n　　%s" % [index + 1, quest.get("name", "任务"), state_text]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 15)
		button.set_pressed_no_signal(quest_id == _selected_quest_id)
		button.theme_type_variation = "GothicComponentSelectedButton" if quest_id == _selected_quest_id else "GothicComponentButton"
		button.pressed.connect(_select_quest.bind(quest_id))
		button.set_meta("quest_id", quest_id)
		button.set_meta("quest_state", state_text)
		quest_list.add_child(button)
		quest_buttons.append(button)


func _refresh_selected_quest(active_quest_id: String) -> void:
	action_button.disabled = false
	var quest := GameData.get_bich_quest(_selected_quest_id)
	if quest.is_empty():
		title_label.text = "%s｜比奇任务" % npc_display_name
		quest_name_label.text = "比奇主线已经全部完成"
		quest_meta_label.text = "六段任务链已完成"
		description_label.text = "[color=#d8c8ae]玛法大陆仍有新的委托等待探索。[/color]"
		objective_label.text = "[color=#a99479]当前没有可执行的比奇主线目标。[/color]"
		reward_label.text = "[color=#a99479]奖励已全部领取[/color]"
		status_label.text = "全部完成"
		action_button.text = "已完成"
		action_button.disabled = true
		return
	var quest_id := str(quest.get("id", ""))
	current_quest_id = quest_id
	title_label.text = "%s｜任务日志" % npc_display_name
	quest_name_label.text = str(quest.get("name", "任务"))
	quest_meta_label.text = "委托人：%s　·　任务序号 %02d　·　资料可信度 %s" % [
		quest.get("npc", npc_display_name), int(quest.get("order", 0)), quest.get("confidence", "?"),
	]
	var map_names: Array[String] = []
	for map_id: Variant in quest.get("targetMapIds", []):
		var map_data := GameData.get_map_by_id(int(map_id))
		if not map_data.is_empty() and not map_names.has(str(map_data.get("name", map_id))):
			map_names.append(str(map_data.get("name", map_id)))
	description_label.text = "[color=#d8c8ae]任务来源：%s（%s）\n目标区域：%s[/color]" % [
		quest.get("sourceType", "未知"), quest.get("confidence", "?"),
		"、".join(map_names) if not map_names.is_empty() else "尚未记录",
	]
	var objective_lines := PlayerState.quest_objective_lines(quest_id)
	objective_label.text = "[color=#e2c89d]%s[/color]" % ("\n".join(objective_lines) if not objective_lines.is_empty() else "当前任务没有可显示目标")
	reward_label.text = "[color=#e5bd78]%s[/color]" % PlayerState.quest_reward_label(quest_id)
	var state := str(PlayerState.quest_states.get(quest_id, {}).get("status", ""))
	if state == "claimed":
		status_label.text = "任务已完成"
		action_button.text = "奖励已领取"
		action_button.disabled = true
	elif state == "ready":
		status_label.text = "目标完成，可以领取奖励"
		action_button.text = "领取奖励"
	elif state == "active":
		status_label.text = "任务进行中"
		action_button.text = "任务进行中"
		action_button.disabled = true
	elif quest_id == active_quest_id:
		status_label.text = "尚未接受"
		action_button.text = "接受任务"
	else:
		status_label.text = "完成前置任务后解锁"
		action_button.text = "尚未解锁"
		action_button.disabled = true


func _select_quest(quest_id: String) -> void:
	_selected_quest_id = quest_id
	current_quest_id = quest_id
	refresh()


func _quest_state_text(quest_id: String, active_quest_id: String) -> String:
	var state := str(PlayerState.quest_states.get(quest_id, {}).get("status", ""))
	match state:
		"claimed":
			return "已完成"
		"ready":
			return "可领取"
		"active":
			return "进行中"
	return "可接取" if quest_id == active_quest_id else "未解锁"


func _act() -> void:
	action_button.disabled = false
	if current_quest_id.is_empty():
		return
	if not PlayerState.quest_states.has(current_quest_id):
		status_label.text = PlayerState.accept_quest(current_quest_id)
	else:
		status_label.text = PlayerState.claim_quest(current_quest_id)
	_selected_quest_id = PlayerState.current_bich_quest_id()
	refresh.call_deferred()


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


func _close() -> void:
	hide()
	closed.emit()
