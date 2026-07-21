class_name ProfessionPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicConfirmationPanelScript := preload("res://scripts/gothic_confirmation_panel.gd")

signal closed

const PANEL_SIZE := Vector2(1100, 636)
const PROFESSION_COPY := {
	"战士": {
		"role": "近战 · 爆发 · 生存",
		"summary": "以近身剑术持续压制敌人，在正面战斗中拥有更充足的生命。",
		"color": Color("a94a37"),
		"icon": "res://assets/ui/gothic_hud/v2/runtime/skill_icons/skill_fire_hit.png",
	},
	"法师": {
		"role": "远程 · 范围 · 魔法",
		"summary": "使用远程与范围法术控制战场，以更高魔法储备换取施法空间。",
		"color": Color("476fa8"),
		"icon": "res://assets/art/characters/wizard/effects/area_burst.png",
	},
	"道士": {
		"role": "治疗 · 辅助 · 召唤",
		"summary": "利用治疗、符咒与召唤物协同作战，擅长持续支援与牵制。",
		"color": Color("54815d"),
		"icon": "res://assets/art/characters/taoist/effects/mass_healing.png",
	},
}

var title_label: Label
var detail_label: RichTextLabel
var profession_tabs: Dictionary = {}
var selected_profession := ""
var identity_icon: TextureRect
var identity_name_label: Label
var current_badge: Label
var role_label: Label
var summary_label: RichTextLabel
var stats_label: RichTextLabel
var growth_cards: Array[Button] = []
var unlock_count_label: Label
var unlock_list: VBoxContainer
var confirm_button: Button
var confirmation_popup: Control
var last_result := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_bottom = PANEL_SIZE.y * 0.5
	z_index = 70
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GothicUIThemeScript.build()
	theme_type_variation = "GothicModalFrame"
	_build_modal_surface()
	_build_header()
	_build_profession_tabs()
	_build_identity_section()
	_build_growth_section()
	_build_unlock_section()
	_build_confirmation_popup()
	selected_profession = PlayerState.profession
	PlayerState.profession_changed.connect(_on_profession_changed)
	refresh()


func _build_modal_surface() -> void:
	var surface := Panel.new()
	surface.name = "ModalSurface"
	surface.position = Vector2(18, 24)
	surface.size = Vector2(1064, 588)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(320, 4)
	title_frame.size = Vector2(460, 64)
	title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_frame.theme_type_variation = "GothicTitleBar"
	add_child(title_frame)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = "职业成长"
	title_label.position = Vector2(30, 15)
	title_label.size = Vector2(400, 32)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color("f1cc88"))
	title_frame.add_child(title_label)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.position = Vector2(1022, 8)
	close_button.size = Vector2(56, 56)
	close_button.theme_type_variation = "GothicComponentCloseButton"
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(_close)
	add_child(close_button)


func _build_profession_tabs() -> void:
	var panel := _section_panel("ProfessionTabs", Rect2(20, 76, 1060, 80))
	for index in range(ProfessionRules.PROFESSIONS.size()):
		var profession_name: String = ProfessionRules.PROFESSIONS[index]
		var button := Button.new()
		button.name = "%sTab" % ProfessionRules.profession_id(profession_name).capitalize()
		button.text = profession_name
		button.position = Vector2(18 + index * 344, 12)
		button.size = Vector2(336, 56)
		button.theme_type_variation = "GothicComponentTabButton"
		button.add_theme_font_size_override("font_size", 20)
		button.set_meta("stable_tab_id", "profession.tab.%s" % ProfessionRules.profession_id(profession_name))
		button.set_meta("profession_id", ProfessionRules.profession_id(profession_name))
		button.pressed.connect(_preview_profession.bind(profession_name))
		panel.add_child(button)
		profession_tabs[profession_name] = button


func _build_identity_section() -> void:
	var panel := _section_panel("ProfessionIdentity", Rect2(20, 168, 300, 444))
	panel.add_child(_section_title("职业定位", 300))
	var emblem_frame := Panel.new()
	emblem_frame.name = "ProfessionEmblemFrame"
	emblem_frame.position = Vector2(22, 54)
	emblem_frame.size = Vector2(256, 170)
	emblem_frame.theme_type_variation = "GothicTabFrame"
	emblem_frame.set_meta("preview_kind", "profession_emblem")
	panel.add_child(emblem_frame)
	identity_icon = TextureRect.new()
	identity_icon.name = "ProfessionEmblem"
	identity_icon.position = Vector2(80, 20)
	identity_icon.size = Vector2(96, 96)
	identity_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	identity_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem_frame.add_child(identity_icon)
	identity_name_label = Label.new()
	identity_name_label.name = "ProfessionName"
	identity_name_label.position = Vector2(20, 116)
	identity_name_label.size = Vector2(216, 32)
	identity_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity_name_label.add_theme_font_size_override("font_size", 22)
	identity_name_label.add_theme_color_override("font_color", Color("efc67e"))
	emblem_frame.add_child(identity_name_label)
	current_badge = Label.new()
	current_badge.name = "CurrentProfessionBadge"
	current_badge.position = Vector2(32, 228)
	current_badge.size = Vector2(236, 24)
	current_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	current_badge.theme_type_variation = "GothicMutedLabel"
	panel.add_child(current_badge)
	role_label = Label.new()
	role_label.name = "Role"
	role_label.position = Vector2(26, 256)
	role_label.size = Vector2(248, 30)
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_label.add_theme_font_size_override("font_size", 18)
	role_label.add_theme_color_override("font_color", Color("e4b96f"))
	panel.add_child(role_label)
	summary_label = RichTextLabel.new()
	summary_label.name = "RoleSummary"
	summary_label.position = Vector2(30, 292)
	summary_label.size = Vector2(240, 62)
	summary_label.bbcode_enabled = true
	summary_label.fit_content = false
	summary_label.scroll_active = false
	summary_label.theme_type_variation = "GothicDetailText"
	panel.add_child(summary_label)
	stats_label = RichTextLabel.new()
	stats_label.name = "LevelStats"
	stats_label.position = Vector2(30, 356)
	stats_label.size = Vector2(240, 64)
	stats_label.bbcode_enabled = true
	stats_label.fit_content = false
	stats_label.scroll_active = false
	stats_label.theme_type_variation = "GothicDetailText"
	panel.add_child(stats_label)


func _build_growth_section() -> void:
	var panel := _section_panel("GrowthPath", Rect2(332, 168, 430, 444))
	panel.add_child(_section_title("成长路线", 430))
	for index in range(4):
		var card := Button.new()
		card.name = "GrowthStage%d" % (index + 1)
		card.position = Vector2(22, 54 + index * 84)
		card.size = Vector2(386, 74)
		card.theme_type_variation = "GothicComponentButton"
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_theme_font_size_override("font_size", 14)
		card.set_meta("stage_index", index)
		panel.add_child(card)
		growth_cards.append(card)
	var source_note := Label.new()
	source_note.name = "GrowthSourceNote"
	source_note.text = "阶段按现有技能的实际需求等级顺序归组"
	source_note.position = Vector2(24, 398)
	source_note.size = Vector2(382, 24)
	source_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	source_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	source_note.theme_type_variation = "GothicMutedLabel"
	source_note.add_theme_font_size_override("font_size", 12)
	panel.add_child(source_note)


func _build_unlock_section() -> void:
	var panel := _section_panel("Unlocks", Rect2(774, 168, 306, 444))
	panel.add_child(_section_title("技能解锁", 306))
	unlock_count_label = Label.new()
	unlock_count_label.name = "UnlockCount"
	unlock_count_label.position = Vector2(22, 50)
	unlock_count_label.size = Vector2(262, 26)
	unlock_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	unlock_count_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(unlock_count_label)
	var scroll := ScrollContainer.new()
	scroll.name = "UnlockScroll"
	scroll.position = Vector2(22, 82)
	scroll.size = Vector2(262, 226)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	unlock_list = VBoxContainer.new()
	unlock_list.name = "UnlockList"
	unlock_list.custom_minimum_size = Vector2(244, 0)
	unlock_list.add_theme_constant_override("separation", 4)
	scroll.add_child(unlock_list)
	detail_label = RichTextLabel.new()
	detail_label.name = "Status"
	detail_label.position = Vector2(24, 316)
	detail_label.size = Vector2(258, 42)
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = false
	detail_label.theme_type_variation = "GothicDetailText"
	panel.add_child(detail_label)
	confirm_button = Button.new()
	confirm_button.name = "ConfirmProfession"
	confirm_button.position = Vector2(35, 366)
	confirm_button.size = Vector2(236, 56)
	confirm_button.theme_type_variation = "GothicComponentButton"
	confirm_button.add_theme_font_size_override("font_size", 18)
	confirm_button.pressed.connect(_request_confirmation)
	panel.add_child(confirm_button)


func _build_confirmation_popup() -> void:
	confirmation_popup = GothicConfirmationPanelScript.new()
	confirmation_popup.name = "ProfessionConfirmation"
	confirmation_popup.confirmed.connect(_on_profession_confirmation_confirmed)
	add_child(confirmation_popup)


func refresh() -> void:
	if selected_profession.is_empty() or not ProfessionRules.is_valid_profession(selected_profession):
		selected_profession = PlayerState.profession
	var copy: Dictionary = PROFESSION_COPY.get(selected_profession, PROFESSION_COPY["战士"])
	for profession_name: String in profession_tabs:
		var button: Button = profession_tabs[profession_name]
		button.theme_type_variation = (
			"GothicComponentSelectedButton"
			if profession_name == selected_profession
			else "GothicComponentTabButton"
		)
		button.text = profession_name
	title_label.text = "职业成长"
	identity_name_label.text = selected_profession
	current_badge.text = (
		"当前职业 · 正在使用"
		if selected_profession == PlayerState.profession
		else "预览职业 · 尚未应用"
	)
	role_label.text = str(copy.get("role", ""))
	summary_label.text = "[center][color=#d5c1a1]%s[/color][/center]" % str(copy.get("summary", ""))
	var icon_path := str(copy.get("icon", ""))
	identity_icon.texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
	identity_icon.modulate = Color.WHITE
	identity_icon.set_meta("source_path", icon_path)
	var level := maxi(1, int(PlayerState.level))
	var stats: Dictionary = ProfessionRules.stats_for_level(selected_profession, level)
	stats_label.text = (
		"[center][color=#a99479]Lv.%d 玩法数据预览[/color]\n"
		+ "[color=#c95850]生命 %d[/color]   [color=#668fd1]魔法 %d[/color]   攻击 %d–%d[/center]"
	) % [
		level,
		int(stats.get("max_hp", 0)),
		int(stats.get("max_mp", 0)),
		int(stats.get("attack_min", 0)),
		int(stats.get("attack_max", 0)),
	]
	var skills := _sorted_profession_skills(selected_profession)
	_refresh_growth_cards(skills)
	_refresh_unlock_list(skills)
	confirm_button.disabled = selected_profession == PlayerState.profession
	confirm_button.text = "当前职业" if confirm_button.disabled else "确认选择 %s" % selected_profession
	if not last_result.is_empty():
		detail_label.text = "[center][color=#e4bd7c]%s[/color][/center]" % last_result
	elif confirm_button.disabled:
		detail_label.text = "[center][color=#a99479]选择分页可预览其他职业[/color][/center]"
	else:
		detail_label.text = "[center][color=#c9a36b]确认前不会修改角色数据[/color][/center]"


func _refresh_growth_cards(skills: Array) -> void:
	var groups := _split_into_stages(skills, growth_cards.size())
	for index in range(growth_cards.size()):
		var card := growth_cards[index]
		var group: Array = groups[index]
		if group.is_empty():
			card.text = "  阶段 %d\n  暂无技能数据" % (index + 1)
			card.disabled = true
			continue
		card.disabled = false
		var first_level := int(group.front().get("requiredCharacterLevel", 1))
		var last_level := int(group.back().get("requiredCharacterLevel", first_level))
		var level_text := "Lv.%d" % first_level if first_level == last_level else "Lv.%d–%d" % [first_level, last_level]
		var names: Array[String] = []
		for skill: Dictionary in group:
			names.append(str(skill.get("skillName", "")))
		card.text = "  阶段 %d  ·  %s\n  %s" % [index + 1, level_text, " · ".join(names)]
		card.tooltip_text = "实际技能需求等级：%s" % level_text


func _refresh_unlock_list(skills: Array) -> void:
	for child in unlock_list.get_children():
		child.queue_free()
	unlock_count_label.text = "%s · 共 %d 项技能" % [selected_profession, skills.size()]
	for skill: Dictionary in skills:
		var row := Label.new()
		row.name = "Skill_%s" % ProfessionRules.skill_id(str(skill.get("skillName", ""))).replace(".", "_")
		row.custom_minimum_size = Vector2(238, 32)
		row.text = "Lv.%-2d  %s" % [
			int(skill.get("requiredCharacterLevel", 1)),
			str(skill.get("skillName", "")),
		]
		row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override(
			"font_color",
			Color("e3c186") if int(skill.get("requiredCharacterLevel", 1)) <= int(PlayerState.level) else Color("8d7b68")
		)
		row.set_meta("skill_id", ProfessionRules.skill_id(str(skill.get("skillName", ""))))
		row.set_meta("required_character_level", int(skill.get("requiredCharacterLevel", 1)))
		unlock_list.add_child(row)


func _sorted_profession_skills(profession_name: String) -> Array:
	var skills: Array = GameData.get_profession_skills(profession_name).duplicate(true)
	skills.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_level := int(left.get("requiredCharacterLevel", 1))
			var right_level := int(right.get("requiredCharacterLevel", 1))
			if left_level == right_level:
				return str(left.get("skillName", "")) < str(right.get("skillName", ""))
			return left_level < right_level
	)
	return skills


func _split_into_stages(skills: Array, stage_count: int) -> Array:
	var result: Array = []
	for _index in range(stage_count):
		result.append([])
	if skills.is_empty():
		return result
	for index in range(skills.size()):
		var stage_index := mini(stage_count - 1, int(floor(float(index) * float(stage_count) / float(skills.size()))))
		result[stage_index].append(skills[index])
	return result


func _preview_profession(profession_name: String) -> void:
	if not ProfessionRules.is_valid_profession(profession_name):
		return
	selected_profession = profession_name
	last_result = ""
	refresh()


func _request_confirmation() -> void:
	if selected_profession == PlayerState.profession:
		last_result = "当前职业已经是%s" % selected_profession
		refresh()
		return
	confirmation_popup.open_confirmation({
		"action_id": "profession.change",
		"title": "确认切换为%s？" % selected_profession,
		"message": "切换职业会卸下不适用装备，并清除其他职业技能。\n确认后才会交给角色数据接口执行。",
		"confirm_label": "确认切换",
		"cancel_label": "返回预览",
		"tone": "danger",
		"context": {"profession_id": ProfessionRules.profession_id(selected_profession)},
	})


func _on_profession_confirmation_confirmed(confirmation: Dictionary) -> void:
	if str(confirmation.get("context", {}).get("profession_id", "")) != ProfessionRules.profession_id(selected_profession):
		return
	_apply_selected_profession()


func _apply_selected_profession() -> void:
	if selected_profession == PlayerState.profession:
		_hide_confirmation()
		return
	last_result = PlayerState.select_profession(selected_profession)
	_hide_confirmation()
	refresh.call_deferred()


func _hide_confirmation() -> void:
	confirmation_popup.close_confirmation()


func _on_profession_changed(value: String) -> void:
	selected_profession = value
	refresh()


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
	title.position = Vector2(18, 14)
	title.size = Vector2(width - 36.0, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.theme_type_variation = "GothicSectionTitle"
	return title


func _close() -> void:
	_hide_confirmation()
	hide()
	closed.emit()
