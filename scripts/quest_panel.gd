class_name QuestPanel
extends Panel

signal closed

var title_label: Label
var description_label: Label
var status_label: Label
var action_button: Button
var current_quest_id := ""
var npc_display_name := "比奇老兵"


func _ready() -> void:
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -250
	offset_top = -210
	offset_right = 250
	offset_bottom = 210
	z_index = 65
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.05, 0.032, 0.98)
	style.border_color = Color(0.72, 0.53, 0.22)
	style.set_border_width_all(3)
	add_theme_stylebox_override("panel", style)
	title_label = Label.new()
	title_label.text = "比奇老兵｜比奇任务"
	title_label.position = Vector2(24, 20)
	title_label.add_theme_font_size_override("font_size", 25)
	add_child(title_label)
	description_label = Label.new()
	description_label.position = Vector2(30, 70)
	description_label.size = Vector2(440, 145)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_font_size_override("font_size", 17)
	add_child(description_label)
	status_label = Label.new()
	status_label.position = Vector2(30, 225)
	status_label.size = Vector2(440, 45)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(1.0, 0.79, 0.38))
	add_child(status_label)
	action_button = Button.new()
	action_button.position = Vector2(45, 290)
	action_button.size = Vector2(195, 54)
	action_button.pressed.connect(_act)
	add_child(action_button)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.position = Vector2(260, 290)
	close_button.size = Vector2(195, 54)
	close_button.pressed.connect(_close)
	add_child(close_button)
	PlayerState.quests_changed.connect(refresh)
	refresh()


func open_for(display_name: String) -> void:
	npc_display_name = display_name
	refresh()
	show()


func refresh() -> void:
	if status_label == null:
		return
	current_quest_id = PlayerState.current_bich_quest_id()
	action_button.disabled = false
	if current_quest_id.is_empty():
		title_label.text = "%s｜比奇任务" % npc_display_name
		description_label.text = "比奇主线已经全部完成。"
		status_label.text = "六段任务链已完成"
		action_button.text = "已完成"
		action_button.disabled = true
		return
	var quest := GameData.get_bich_quest(current_quest_id)
	title_label.text = "%s｜%s" % [npc_display_name, quest.get("name", "任务")]
	var map_names: Array[String] = []
	for map_id: Variant in quest.get("targetMapIds", []):
		var map_data := GameData.get_map_by_id(int(map_id))
		if not map_data.is_empty() and not map_names.has(str(map_data.get("name", map_id))):
			map_names.append(str(map_data.get("name", map_id)))
	description_label.text = "%s\n目标区域：%s\n奖励：%s\n来源：%s（%s）" % [
		"；".join(PlayerState.quest_objective_lines(current_quest_id)),
		"、".join(map_names),
		PlayerState.quest_reward_label(current_quest_id),
		quest.get("sourceType", "未知"), quest.get("confidence", "?")]
	if not PlayerState.quest_states.has(current_quest_id):
		status_label.text = "尚未接受"
		action_button.text = "接受任务"
	else:
		var state: Dictionary = PlayerState.quest_states[current_quest_id]
		var ready := str(state.get("status", "")) == "ready"
		status_label.text = "｜".join(PlayerState.quest_objective_lines(current_quest_id))
		action_button.text = "领取奖励" if ready else "任务进行中"
		action_button.disabled = not ready


func _act() -> void:
	action_button.disabled = false
	if current_quest_id.is_empty():
		return
	if not PlayerState.quest_states.has(current_quest_id):
		status_label.text = PlayerState.accept_quest(current_quest_id)
	else:
		status_label.text = PlayerState.claim_quest(current_quest_id)
	refresh.call_deferred()


func _close() -> void:
	hide()
	closed.emit()
