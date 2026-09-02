class_name QuestPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const GothicConfirmationPanelScript := preload("res://scripts/gothic_confirmation_panel.gd")
const UIRuntimeLayoutOverridesScript := preload("res://scripts/ui_runtime_layout_overrides.gd")
const TouchScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")

signal closed
signal abandon_requested(quest_id: String)

const PANEL_SIZE := Vector2(1020, 636)
const QUEST_CARD_SIZE := Vector2(286, 62)
const QUEST_CARD_SEPARATION := 7
const QUEST_LIST_LAYOUT_REVISION := 1
const ACTION_ROW_GAP := 12.0

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
var abandon_button: Button
var abandon_confirmation: Control
var story_divider: HSeparator
var current_quest_id := ""
var npc_display_name := "老兵"
var _selected_quest_id := ""
var _pending_abandon_quest_id := ""
var _action_request_locked := false
var _action_feedback_serial := 0
var _refresh_pending := false
var _refresh_scheduled := false
var _refresh_execution_count := 0
var _layout_initialized := false
var _layout_apply_count := 0


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
	GothicFrameFactoryScript.seal_modal_rings(self)
	PlayerState.quests_changed.connect(_on_quests_changed)
	visibility_changed.connect(_on_visibility_changed)
	refresh()


func _build_modal_surface() -> void:
	GothicFrameFactoryScript.add_modal_fill(self, PANEL_SIZE)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(282, 10)
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
	panel.add_child(_section_title("QuestListTitle", "任务列表", 326))
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
	# The approved secondary frame owns the list boundary.  The scroll viewport
	# must not draw an extra one-pixel outline around the task cards.
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	quest_list = VBoxContainer.new()
	quest_list.name = "QuestList"
	quest_list.custom_minimum_size = Vector2(286, 0)
	quest_list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quest_list.add_theme_constant_override("separation", QUEST_CARD_SEPARATION)
	scroll.add_child(quest_list)


func _build_quest_detail() -> void:
	var panel := _framed_section("QuestDetailPanel", Rect2(364, 76, 632, 528))
	panel.add_child(_section_title("QuestDetailTitle", "任务详情", 632))
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
	story_divider = HSeparator.new()
	story_divider.name = "StoryDivider"
	story_divider.anchor_left = 0.0
	story_divider.anchor_right = 1.0
	story_divider.anchor_top = 0.0
	story_divider.anchor_bottom = 0.0
	story_divider.offset_left = 20.0
	story_divider.offset_right = -20.0
	story_divider.offset_top = 122.0
	story_divider.offset_bottom = 130.0
	story_divider.set_meta("calibration_layer", "quest_story_divider")
	story_divider.set_meta("calibration_layout_revision", QUEST_LIST_LAYOUT_REVISION)
	panel.add_child(story_divider)
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
	rewards_panel.set_meta("calibration_layer", "quest_rewards_panel")
	panel.add_child(rewards_panel)
	var rewards_title := Label.new()
	rewards_title.name = "RewardsTitle"
	rewards_title.text = "任务奖励："
	rewards_title.position = Vector2(18, 2)
	rewards_title.size = Vector2(122, 40)
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
	status_label.size = Vector2(164, 52)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.theme_type_variation = "GothicMutedLabel"
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color("d7b56f"))
	panel.add_child(status_label)
	abandon_button = Button.new()
	abandon_button.name = "AbandonButton"
	abandon_button.text = "放弃任务"
	abandon_button.position = Vector2(204, 436)
	abandon_button.size = Vector2(128, 52)
	abandon_button.theme_type_variation = "GothicQuestAbandonPlainButton"
	abandon_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	abandon_button.add_theme_font_size_override("font_size", 16)
	abandon_button.visible = false
	abandon_button.pressed.connect(_request_abandon)
	panel.add_child(abandon_button)
	action_button = Button.new()
	action_button.name = "ActionButton"
	action_button.position = Vector2(204, 436)
	action_button.size = Vector2(400, 52)
	# Accept/claim is a transaction action.  Quest cards keep the persistent
	# selection state; this button receives only an explicit operation cue.
	action_button.theme_type_variation = "GothicQuestActionGemButton"
	action_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_button.add_theme_font_size_override("font_size", 18)
	action_button.pressed.connect(_act)
	panel.add_child(action_button)
	abandon_confirmation = GothicConfirmationPanelScript.new()
	abandon_confirmation.name = "AbandonConfirmation"
	abandon_confirmation.confirmed.connect(_on_abandon_confirmation_confirmed)
	abandon_confirmation.cancelled.connect(_cancel_pending_abandon)
	add_child(abandon_confirmation)


func open_for(display_name: String) -> void:
	_action_request_locked = false
	_clear_action_feedback()
	npc_display_name = display_name
	_selected_quest_id = PlayerState.current_bich_quest_id()
	refresh()
	show()


func refresh() -> void:
	if status_label == null:
		return
	_refresh_pending = false
	_refresh_scheduled = false
	_refresh_execution_count += 1
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
	if not _layout_initialized:
		_layout_initialized = true
		_layout_apply_count += 1
		UIRuntimeLayoutOverridesScript.apply_profile(self, "quest")


func _on_quests_changed() -> void:
	_refresh_pending = true
	if not visible:
		return
	if _refresh_scheduled:
		return
	_refresh_scheduled = true
	call_deferred("_flush_queued_refresh")


func _on_visibility_changed() -> void:
	if visible and _refresh_pending:
		refresh()


func _flush_queued_refresh() -> void:
	_refresh_scheduled = false
	if visible and _refresh_pending:
		refresh()


func _on_runtime_layout_profile_applied(profile_id: String) -> void:
	if profile_id == "quest" and abandon_button != null:
		_stabilize_quest_list_layout()
		_stabilize_story_divider()
		_set_abandon_available(abandon_button.visible)


func _stabilize_quest_list_layout() -> void:
	if quest_list == null:
		return
	quest_list.position = Vector2.ZERO
	quest_list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quest_list.custom_minimum_size = Vector2(QUEST_CARD_SIZE.x, maxf(0.0, quest_buttons.size() * QUEST_CARD_SIZE.y + maxi(0, quest_buttons.size() - 1) * QUEST_CARD_SEPARATION))
	quest_list.add_theme_constant_override("separation", QUEST_CARD_SEPARATION)
	for button: Button in quest_buttons:
		button.custom_minimum_size = QUEST_CARD_SIZE
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quest_list.queue_sort()


func _stabilize_story_divider() -> void:
	if story_divider == null or not is_instance_valid(story_divider):
		return
	var detail_panel := story_divider.get_parent() as Control
	if detail_panel == null:
		return
	story_divider.anchor_left = 0.0
	story_divider.anchor_right = 1.0
	story_divider.offset_left = 20.0
	story_divider.offset_right = -20.0


func _rebuild_quest_cards(active_quest_id: String) -> void:
	for child: Node in quest_list.get_children():
		quest_list.remove_child(child)
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
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.toggle_mode = true
		button.text = ""
		button.set_pressed_no_signal(quest_id == _selected_quest_id)
		button.theme_type_variation = "GothicQuestCardSelectedPlainButton" if quest_id == _selected_quest_id else "GothicQuestCardPlainButton"
		button.pressed.connect(_select_quest.bind(quest_id))
		button.set_meta("quest_id", quest_id)
		button.set_meta("quest_state", state_text)
		var number_label := Label.new()
		number_label.name = "QuestNumber"
		number_label.text = "%02d" % (index + 1)
		number_label.position = Vector2(12, 0)
		number_label.size = Vector2(34, QUEST_CARD_SIZE.y)
		number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		number_label.add_theme_font_size_override("font_size", 15)
		number_label.add_theme_color_override("font_color", Color("e2c18b"))
		button.add_child(number_label)
		var name_label := Label.new()
		name_label.name = "QuestName"
		name_label.text = str(quest.get("name", "任务"))
		name_label.position = Vector2(54, 7)
		name_label.size = Vector2(212, 25)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", 16)
		button.add_child(name_label)
		var state_label := Label.new()
		state_label.name = "QuestState"
		state_label.text = state_text
		state_label.position = Vector2(54, 32)
		state_label.size = Vector2(212, 22)
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		state_label.add_theme_font_size_override("font_size", 14)
		state_label.add_theme_color_override("font_color", Color("d2b078"))
		button.add_child(state_label)
		quest_list.add_child(button)
		quest_buttons.append(button)
	_stabilize_quest_list_layout()


func _refresh_selected_quest(active_quest_id: String) -> void:
	action_button.disabled = false
	_set_abandon_available(false)
	var quest := GameData.get_bich_quest(_selected_quest_id)
	if quest.is_empty():
		title_label.text = "%s｜比奇任务" % npc_display_name
		quest_name_label.text = "比奇主线已经全部完成"
		quest_meta_label.text = "六段任务链已完成"
		description_label.text = "[color=#d8c8ae]HardCore 世界仍有新的委托等待探索。[/color]"
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
		status_label.text = "目标完成"
		action_button.text = "领取奖励"
		_set_abandon_available(true)
	elif state == "active":
		status_label.text = ""
		action_button.text = "任务进行中"
		action_button.disabled = true
		_set_abandon_available(true)
	elif quest_id == active_quest_id:
		status_label.text = ""
		action_button.text = "接受任务"
	else:
		status_label.text = "完成前置任务后解锁"
		action_button.text = "尚未解锁"
		action_button.disabled = true


func _select_quest(quest_id: String) -> void:
	if TouchScrollSupportScript.is_drag_active(get_tree()):
		return
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
	if _action_request_locked:
		return
	if current_quest_id.is_empty():
		return
	_clear_action_feedback()
	_action_request_locked = true
	action_button.disabled = true
	GothicUIThemeScript.set_button_feedback(
		action_button,
		GothicUIThemeScript.BUTTON_FEEDBACK_BUSY,
		"quest.action",
	)
	var before_state := str(PlayerState.quest_states.get(current_quest_id, {}).get("status", ""))
	if not PlayerState.quest_states.has(current_quest_id):
		status_label.text = PlayerState.accept_quest(current_quest_id)
	else:
		status_label.text = PlayerState.claim_quest(current_quest_id)
	var after_state := str(PlayerState.quest_states.get(current_quest_id, {}).get("status", ""))
	_action_request_locked = false
	_show_action_result_feedback(after_state != before_state and not after_state.is_empty())
	_selected_quest_id = PlayerState.current_bich_quest_id()
	_on_quests_changed()


func _set_abandon_available(enabled: bool) -> void:
	abandon_button.visible = enabled
	abandon_button.disabled = not enabled
	# The authored quest profile owns the action button rectangle. Refreshes
	# and state transitions still toggle the abandon control, but must not
	# replace the user's saved action-button geometry with procedural presets
	# after the profile has been applied.
	var profile_ready := UIRuntimeLayoutOverridesScript.profile_is_ready(self, "quest")
	if enabled:
		if not profile_ready:
			action_button.position = Vector2(344, 436)
			action_button.size = Vector2(260, 52)
		# The action rectangle may come from the saved calibration profile while
		# AbandonButton was hidden and therefore absent from that profile.  Derive
		# the secondary control from the live action rectangle so both always form
		# one row without replacing the calibrated action geometry.
		abandon_button.position = Vector2(
			maxf(0.0, action_button.position.x - ACTION_ROW_GAP - abandon_button.size.x),
			action_button.position.y,
		)
		abandon_button.size.y = action_button.size.y
	elif not profile_ready:
		action_button.position = Vector2(204, 436)
		action_button.size = Vector2(400, 52)


func _request_abandon() -> void:
	if current_quest_id.is_empty():
		return
	var state := str(PlayerState.quest_states.get(current_quest_id, {}).get("status", ""))
	if state not in ["active", "ready"]:
		return
	_pending_abandon_quest_id = current_quest_id
	var quest := GameData.get_bich_quest(current_quest_id)
	abandon_confirmation.open_confirmation({
		"action_id": "quest.abandon",
		"title": "确认放弃任务",
		"message": "确认放弃“%s”？\n当前任务进度将由玩法规则决定是否保留。" % quest.get("name", "当前任务"),
		"confirm_label": "确认放弃",
		"cancel_label": "取消",
		"tone": "danger",
		"context": {"quest_id": current_quest_id},
	})


func _on_abandon_confirmation_confirmed(confirmation: Dictionary) -> void:
	if str(confirmation.get("context", {}).get("quest_id", "")) != _pending_abandon_quest_id:
		_pending_abandon_quest_id = ""
		return
	_confirm_abandon()


func _cancel_pending_abandon(_confirmation: Dictionary) -> void:
	_pending_abandon_quest_id = ""


func _confirm_abandon() -> void:
	if _pending_abandon_quest_id.is_empty():
		return
	var quest_id := _pending_abandon_quest_id
	_pending_abandon_quest_id = ""
	_clear_action_feedback()
	abandon_button.disabled = true
	GothicUIThemeScript.set_button_feedback(
		abandon_button,
		GothicUIThemeScript.BUTTON_FEEDBACK_BUSY,
		"quest.abandon",
	)
	status_label.text = "等待放弃结果"
	abandon_requested.emit(quest_id)


func apply_abandon_result(result: Dictionary) -> void:
	var quest_id := str(result.get("quest_id", ""))
	if not quest_id.is_empty() and quest_id != current_quest_id:
		return
	_show_abandon_result_feedback(bool(result.get("success", false)))
	status_label.text = str(result.get("message", "放弃任务请求已处理"))
	if bool(result.get("success", false)):
		_selected_quest_id = PlayerState.current_bich_quest_id()
		_on_quests_changed()
	else:
		abandon_button.disabled = false


func _clear_action_feedback() -> void:
	_action_feedback_serial += 1
	GothicUIThemeScript.clear_button_feedback(action_button)
	GothicUIThemeScript.clear_button_feedback(abandon_button)


func _show_action_result_feedback(success: bool) -> void:
	_action_feedback_serial += 1
	var serial := _action_feedback_serial
	if is_inside_tree():
		await get_tree().process_frame
	if serial != _action_feedback_serial or not is_instance_valid(action_button) or not action_button.is_inside_tree():
		return
	GothicUIThemeScript.set_button_feedback(
		action_button,
		GothicUIThemeScript.BUTTON_FEEDBACK_SUCCESS if success else GothicUIThemeScript.BUTTON_FEEDBACK_FAILURE,
		"quest.action",
	)
	if not is_inside_tree():
		return
	get_tree().create_timer(1.0 if success else 0.45).timeout.connect(func() -> void:
		if serial == _action_feedback_serial and is_instance_valid(action_button) and action_button.is_inside_tree():
			GothicUIThemeScript.clear_button_feedback(action_button)
	)


func _show_abandon_result_feedback(success: bool) -> void:
	_action_feedback_serial += 1
	var serial := _action_feedback_serial
	if is_inside_tree():
		await get_tree().process_frame
	if serial != _action_feedback_serial or not is_instance_valid(abandon_button) or not abandon_button.is_inside_tree():
		return
	GothicUIThemeScript.set_button_feedback(
		abandon_button,
		GothicUIThemeScript.BUTTON_FEEDBACK_SUCCESS if success else GothicUIThemeScript.BUTTON_FEEDBACK_FAILURE,
		"quest.abandon",
	)
	if not is_inside_tree():
		return
	get_tree().create_timer(1.0 if success else 0.45).timeout.connect(func() -> void:
		if serial == _action_feedback_serial and is_instance_valid(abandon_button) and abandon_button.is_inside_tree():
			GothicUIThemeScript.clear_button_feedback(abandon_button)
	)


func _framed_section(node_name: String, rect: Rect2) -> Control:
	return GothicFrameFactoryScript.add_filled_section(self, node_name, rect)


func _section_title(node_name: String, text_value: String, section_width: float) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.position = Vector2(24, 18)
	label.size = Vector2(section_width - 48.0, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicSectionTitle"
	return label


func _close() -> void:
	abandon_confirmation.close_confirmation()
	_pending_abandon_quest_id = ""
	hide()
	closed.emit()
