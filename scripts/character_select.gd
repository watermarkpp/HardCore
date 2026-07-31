extends Control

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const EquipmentCharacterPreviewScript := preload("res://scripts/equipment_character_preview.gd")
const TouchScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")

signal character_creation_requested(request: Dictionary)
signal character_launch_requested(request: Dictionary)

const LAUNCH_CONTRACT_ID := "ui.character.launch.v1"
const CREATION_CONTRACT_ID := "ui.character.creation.v1"
const ROSTER_TOUCH_SCROLL_CONTRACT_ID := "ui.character.roster.touch_drag.v1"
const LAUNCH_CONTEXT_META := &"pending_character_launch_context"
const FIXED_CHARACTER_GENDER := "男"
const ROSTER_DRAG_THRESHOLD := 12.0
const ROSTER_PRESS_SUPPRESSION_MSEC := 220
const HALL_TEXTURE := preload("res://assets/ui/gothic_preview/character_hall.png")
const PROFESSION_PRESENTATION := {
	"战士": {
		"id": "warrior",
		"glyph": "战",
		"role": "近战 · 爆发",
		"icon": "res://assets/ui/gothic_hud/v2/runtime/skill_icons/skill_fire_hit.png",
	},
	"法师": {
		"id": "wizard",
		"glyph": "法",
		"role": "远程 · 群攻",
		"icon": "res://assets/art/characters/wizard/effects/area_burst.png",
	},
	"道士": {
		"id": "taoist",
		"glyph": "道",
		"role": "治疗 · 召唤",
		"icon": "res://assets/art/characters/taoist/effects/mass_healing.png",
	},
}

var list_box: VBoxContainer
var name_input: LineEdit
var message_label: Label
var profession_buttons: Dictionary = {}
var profile_cards: Dictionary = {}
var profile_scroll: ScrollContainer
var ai_teammate_toggle: CheckButton
var enter_button: Button
var preview_visual_root: Control
var preview_name_label: Label
var preview_detail_label: Label
var teammate_status_label: Label
var roster_count_label: Label
var build_fingerprint_label: Label
var selected_main_profile_id := ""
var selected_ai_profile_id := ""
var selected_creation_profession := "战士"
var ai_teammate_enabled := false
var content_root: Control
var _profiles: Array[Dictionary] = []
var suppress_scene_change_for_test := false
var last_launch_request: Dictionary = {}
var last_creation_request: Dictionary = {}
var _roster_drag_candidate := false
var _roster_drag_active := false
var _roster_drag_start_position := Vector2.ZERO
var _roster_drag_start_scroll := 0
var _roster_drag_touch_index := -1
var _roster_suppress_press_until_msec := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = GothicUIThemeScript.build()
	_build_background()
	_build_content_root()
	_build_header()
	_build_roster_panel()
	_build_preview_panel()
	_build_creation_panel()
	_refresh_profiles()
	TouchScrollSupportScript.attach_tree(self)


func _input(event: InputEvent) -> void:
	if profile_scroll == null or not is_instance_valid(profile_scroll):
		return
	if str(profile_scroll.get_meta("touch_scroll_policy", "")) == TouchScrollSupportScript.STABLE_ID:
		return
	if event is InputEventScreenTouch:
		if event.pressed and profile_scroll.get_global_rect().has_point(event.position):
			_begin_roster_drag(event.position, event.index)
		elif not event.pressed and _roster_drag_candidate and event.index == _roster_drag_touch_index:
			_finish_roster_drag()
	elif event is InputEventScreenDrag:
		if _roster_drag_candidate and event.index == _roster_drag_touch_index:
			_update_roster_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and profile_scroll.get_global_rect().has_point(event.global_position):
			_begin_roster_drag(event.global_position, -1)
		elif not event.pressed and _roster_drag_candidate and _roster_drag_touch_index == -1:
			_finish_roster_drag()
	elif event is InputEventMouseMotion:
		if _roster_drag_candidate and _roster_drag_touch_index == -1 and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_update_roster_drag(event.global_position)


func _begin_roster_drag(position_value: Vector2, touch_index := -1) -> void:
	if _roster_drag_candidate:
		return
	_roster_drag_candidate = true
	_roster_drag_active = false
	_roster_drag_start_position = position_value
	_roster_drag_start_scroll = profile_scroll.scroll_vertical
	_roster_drag_touch_index = touch_index


func _update_roster_drag(position_value: Vector2) -> void:
	if not _roster_drag_candidate:
		return
	var delta := position_value - _roster_drag_start_position
	if not _roster_drag_active and absf(delta.y) < ROSTER_DRAG_THRESHOLD:
		return
	_roster_drag_active = true
	profile_scroll.scroll_vertical = maxi(0, _roster_drag_start_scroll - int(round(delta.y)))
	get_viewport().set_input_as_handled()


func _finish_roster_drag() -> bool:
	if not _roster_drag_candidate:
		return false
	var was_dragging := _roster_drag_active
	if was_dragging:
		_roster_suppress_press_until_msec = Time.get_ticks_msec() + ROSTER_PRESS_SUPPRESSION_MSEC
		get_viewport().set_input_as_handled()
	_roster_drag_candidate = false
	_roster_drag_active = false
	_roster_drag_touch_index = -1
	return was_dragging


func _roster_press_is_suppressed() -> bool:
	return Time.get_ticks_msec() <= _roster_suppress_press_until_msec


func _build_content_root() -> void:
	content_root = Control.new()
	content_root.name = "CenteredContent"
	content_root.set_anchors_preset(Control.PRESET_CENTER)
	content_root.position = Vector2(-640, -360)
	content_root.size = Vector2(1280, 720)
	content_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content_root)


func _build_background() -> void:
	var background := TextureRect.new()
	background.name = "CharacterHallBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = HALL_TEXTURE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.name = "HallShade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.008, 0.005, 0.004, 0.46)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


func _build_header() -> void:
	var top_shade := ColorRect.new()
	top_shade.name = "TopShade"
	top_shade.position = Vector2.ZERO
	top_shade.size = Vector2(1280, 92)
	top_shade.color = Color("080606b8")
	top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(top_shade)
	var title := Label.new()
	title.name = "HallTitle"
	title.text = "人物殿堂"
	title.position = Vector2(48, 15)
	title.size = Vector2(330, 44)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("e7bd76"))
	content_root.add_child(title)
	var subtitle := Label.new()
	subtitle.name = "HallSubtitle"
	subtitle.text = "选择主角色，并决定是否携带一名 AI 队友"
	subtitle.position = Vector2(50, 56)
	subtitle.size = Vector2(520, 24)
	subtitle.theme_type_variation = "GothicMutedLabel"
	content_root.add_child(subtitle)
	var archive := Label.new()
	archive.name = "ArchiveLabel"
	archive.text = "HardCore · 本地独立档案"
	archive.position = Vector2(910, 23)
	archive.size = Vector2(320, 34)
	archive.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	archive.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	archive.theme_type_variation = "GothicMutedLabel"
	content_root.add_child(archive)
	build_fingerprint_label = Label.new()
	build_fingerprint_label.name = "BuildFingerprint"
	build_fingerprint_label.text = _build_fingerprint_text()
	build_fingerprint_label.position = Vector2(760, 56)
	build_fingerprint_label.size = Vector2(470, 20)
	build_fingerprint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build_fingerprint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	build_fingerprint_label.theme_type_variation = "GothicMutedLabel"
	build_fingerprint_label.add_theme_font_size_override("font_size", 11)
	build_fingerprint_label.add_theme_color_override("font_color", Color("8f7a60"))
	build_fingerprint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_fingerprint_label.set_meta("build_fingerprint", true)
	content_root.add_child(build_fingerprint_label)


func _build_fingerprint_text() -> String:
	var app_name := str(ProjectSettings.get_setting("application/config/name", "HardCore"))
	if app_name.is_empty():
		app_name = "HardCore"
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	if version.is_empty():
		version = "dev"
	var revision := str(ProjectSettings.get_setting("application/config/build_revision", "local"))
	if revision.is_empty():
		revision = "local"
	return "%s · v%s · %s" % [app_name, version, revision.left(12)]


func _build_roster_panel() -> void:
	var panel := _section_panel("RosterPanel", Rect2(38, 108, 326, 574))
	panel.add_child(_section_title("已有角色", 326))
	roster_count_label = Label.new()
	roster_count_label.name = "RosterCount"
	roster_count_label.position = Vector2(24, 46)
	roster_count_label.size = Vector2(278, 22)
	roster_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roster_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	roster_count_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(roster_count_label)
	profile_scroll = ScrollContainer.new()
	profile_scroll.name = "ProfileScroll"
	profile_scroll.position = Vector2(18, 76)
	profile_scroll.size = Vector2(290, 362)
	profile_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	profile_scroll.scroll_deadzone = 100000
	profile_scroll.set_meta("touch_scroll_contract", ROSTER_TOUCH_SCROLL_CONTRACT_ID)
	panel.add_child(profile_scroll)
	list_box = VBoxContainer.new()
	list_box.name = "ProfileList"
	list_box.custom_minimum_size = Vector2(270, 0)
	list_box.add_theme_constant_override("separation", 8)
	profile_scroll.add_child(list_box)
	ai_teammate_toggle = CheckButton.new()
	ai_teammate_toggle.name = "AITeammateToggle"
	ai_teammate_toggle.text = "携带 AI 队友"
	ai_teammate_toggle.position = Vector2(26, 448)
	ai_teammate_toggle.size = Vector2(274, 48)
	ai_teammate_toggle.theme_type_variation = "GothicContentToggle"
	ai_teammate_toggle.set_meta("stable_id", "character.ai_teammate.enabled")
	ai_teammate_toggle.toggled.connect(_set_ai_teammate_enabled)
	panel.add_child(ai_teammate_toggle)
	teammate_status_label = Label.new()
	teammate_status_label.name = "TeammateStatus"
	teammate_status_label.position = Vector2(24, 500)
	teammate_status_label.size = Vector2(278, 50)
	teammate_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	teammate_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	teammate_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	teammate_status_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(teammate_status_label)


func _build_preview_panel() -> void:
	var panel := _section_panel("CharacterPreviewPanel", Rect2(380, 108, 484, 574))
	panel.add_child(_section_title("人物预览", 484))
	var stage := Control.new()
	stage.name = "PreviewStage"
	stage.position = Vector2.ZERO
	stage.size = panel.size
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stage)
	preview_visual_root = Control.new()
	preview_visual_root.name = "PreviewVisualRoot"
	preview_visual_root.position = Vector2(42, 44)
	preview_visual_root.size = Vector2(400, 350)
	preview_visual_root.clip_contents = true
	stage.add_child(preview_visual_root)
	preview_name_label = Label.new()
	preview_name_label.name = "PreviewName"
	preview_name_label.position = Vector2(54, 392)
	preview_name_label.size = Vector2(376, 32)
	preview_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_name_label.add_theme_font_size_override("font_size", 23)
	preview_name_label.add_theme_color_override("font_color", Color("efc67e"))
	stage.add_child(preview_name_label)
	preview_detail_label = Label.new()
	preview_detail_label.name = "PreviewDetail"
	preview_detail_label.position = Vector2(54, 424)
	preview_detail_label.size = Vector2(376, 22)
	preview_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_detail_label.theme_type_variation = "GothicMutedLabel"
	stage.add_child(preview_detail_label)
	enter_button = Button.new()
	enter_button.name = "EnterGame"
	enter_button.text = "进入 HardCore"
	enter_button.position = Vector2(94, 458)
	enter_button.size = Vector2(296, 62)
	enter_button.theme_type_variation = "GothicComponentSelectedButton"
	enter_button.add_theme_font_size_override("font_size", 20)
	enter_button.set_meta("stable_id", "character.launch")
	enter_button.pressed.connect(_enter_selected_character)
	panel.add_child(enter_button)
	var launch_hint := Label.new()
	launch_hint.name = "LaunchHint"
	launch_hint.text = "主角色决定世界进度；AI 队友使用自己的角色档案"
	launch_hint.position = Vector2(38, 524)
	launch_hint.size = Vector2(408, 30)
	launch_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	launch_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	launch_hint.theme_type_variation = "GothicMutedLabel"
	launch_hint.add_theme_font_size_override("font_size", 12)
	panel.add_child(launch_hint)


func _build_creation_panel() -> void:
	var panel := _section_panel("CreationPanel", Rect2(880, 108, 362, 574))
	panel.add_child(_section_title("创建人物", 362))
	var name_caption := Label.new()
	name_caption.text = "角色名称"
	name_caption.position = Vector2(26, 56)
	name_caption.size = Vector2(310, 24)
	name_caption.theme_type_variation = "GothicMutedLabel"
	panel.add_child(name_caption)
	name_input = LineEdit.new()
	name_input.name = "CharacterName"
	name_input.placeholder_text = "输入角色名（最多12字）"
	name_input.max_length = 12
	name_input.position = Vector2(26, 84)
	name_input.size = Vector2(310, 52)
	name_input.theme_type_variation = "GothicSearchField"
	name_input.text_submitted.connect(func(_text: String) -> void: _create_character())
	panel.add_child(name_input)
	var profession_caption := Label.new()
	profession_caption.text = "选择职业"
	profession_caption.position = Vector2(26, 158)
	profession_caption.size = Vector2(310, 24)
	profession_caption.theme_type_variation = "GothicMutedLabel"
	panel.add_child(profession_caption)
	for index in range(ProfessionRules.PROFESSIONS.size()):
		var profession_name: String = ProfessionRules.PROFESSIONS[index]
		var presentation: Dictionary = PROFESSION_PRESENTATION[profession_name]
		var button := Button.new()
		button.name = "%sProfession" % str(presentation.id).capitalize()
		button.text = "%s\n%s\n%s" % [presentation.glyph, profession_name, presentation.role]
		button.position = Vector2(26 + index * 104, 190)
		button.size = Vector2(98, 132)
		button.add_theme_font_size_override("font_size", 14)
		button.set_meta("stable_id", "character.profession.%s" % presentation.id)
		button.set_meta("profession_id", presentation.id)
		button.pressed.connect(_select_creation_profession.bind(profession_name))
		panel.add_child(button)
		profession_buttons[profession_name] = button
	var create_hint := Label.new()
	create_hint.name = "CreationHint"
	create_hint.text = "职业决定初始技能、属性与成长路线"
	create_hint.position = Vector2(26, 338)
	create_hint.size = Vector2(310, 24)
	create_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	create_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	create_hint.theme_type_variation = "GothicMutedLabel"
	create_hint.add_theme_font_size_override("font_size", 12)
	panel.add_child(create_hint)
	var create_button := Button.new()
	create_button.name = "CreateCharacter"
	create_button.text = "创建角色"
	create_button.position = Vector2(26, 374)
	create_button.size = Vector2(310, 58)
	create_button.theme_type_variation = "GothicComponentButton"
	create_button.add_theme_font_size_override("font_size", 18)
	create_button.set_meta("stable_id", "character.create")
	create_button.pressed.connect(_create_character)
	panel.add_child(create_button)
	message_label = Label.new()
	message_label.name = "Message"
	message_label.position = Vector2(28, 446)
	message_label.size = Vector2(306, 82)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(message_label)
	_refresh_creation_controls()


func _refresh_profiles() -> void:
	for child in list_box.get_children():
		child.free()
	profile_cards.clear()
	_profiles = PlayerState.list_characters()
	roster_count_label.text = "%d 个角色 · 每个角色都可作为主角色" % _profiles.size()
	if _profiles.is_empty():
		selected_main_profile_id = ""
		selected_ai_profile_id = ""
		var empty := Label.new()
		empty.name = "EmptyRoster"
		empty.text = "暂无角色\n请在右侧创建第一名角色"
		empty.custom_minimum_size = Vector2(270, 90)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.theme_type_variation = "GothicMutedLabel"
		list_box.add_child(empty)
		_refresh_selection_state()
		return
	if not _profile_exists(selected_main_profile_id):
		var active_id := str(PlayerState.active_profile_id)
		selected_main_profile_id = active_id if _profile_exists(active_id) else str(_profiles[0].get("id", ""))
	if str(PlayerState.active_profile_id) != selected_main_profile_id:
		if not PlayerState.select_character(selected_main_profile_id):
			message_label.text = "默认角色存档不存在或已损坏"
	if selected_ai_profile_id == selected_main_profile_id or not _profile_exists(selected_ai_profile_id):
		selected_ai_profile_id = ""
	for profile: Dictionary in _profiles:
		_add_profile_card(profile)
	_refresh_selection_state()


func _add_profile_card(profile: Dictionary) -> void:
	var profile_id := str(profile.get("id", ""))
	var card := Control.new()
	card.name = "Profile_%s" % _safe_node_name(profile_id)
	card.custom_minimum_size = Vector2(270, 96)
	card.set_meta("profile_id", profile_id)
	list_box.add_child(card)
	var main_button := Button.new()
	main_button.name = "Main"
	main_button.text = "%s\nLv.%d  ·  %s" % [
		str(profile.get("name", "未命名")),
		int(profile.get("level", 1)),
		str(profile.get("profession", "战士")),
	]
	main_button.position = Vector2(0, 7)
	main_button.size = Vector2(184, 81)
	main_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_button.add_theme_font_size_override("font_size", 16)
	main_button.set_meta("stable_id", "character.profile.%s.main" % profile_id)
	main_button.pressed.connect(_on_profile_main_pressed.bind(profile_id))
	card.add_child(main_button)
	var ai_button := Button.new()
	ai_button.name = "AITeammate"
	ai_button.position = Vector2(190, 7)
	ai_button.size = Vector2(80, 81)
	ai_button.add_theme_font_size_override("font_size", 12)
	ai_button.set_meta("stable_id", "character.profile.%s.ai_teammate" % profile_id)
	ai_button.pressed.connect(_on_profile_ai_pressed.bind(profile_id))
	card.add_child(ai_button)
	profile_cards[profile_id] = {
		"panel": card,
		"main_button": main_button,
		"ai_button": ai_button,
		"profile": profile.duplicate(true),
	}


func _refresh_selection_state() -> void:
	for profile_id: String in profile_cards:
		var entry: Dictionary = profile_cards[profile_id]
		var main_button: Button = entry.main_button
		var ai_button: Button = entry.ai_button
		main_button.theme_type_variation = (
			"GothicComponentSelectedButton"
			if profile_id == selected_main_profile_id
			else "GothicComponentButton"
		)
		var is_ai := profile_id == selected_ai_profile_id
		ai_button.disabled = not ai_teammate_enabled or profile_id == selected_main_profile_id
		ai_button.theme_type_variation = "GothicComponentSelectedButton" if is_ai else "GothicComponentButton"
		ai_button.text = "AI队友\n已选择" if is_ai else "设为\nAI队友"
	ai_teammate_toggle.set_pressed_no_signal(ai_teammate_enabled)
	var ai_profile := _profile_by_id(selected_ai_profile_id)
	if not ai_teammate_enabled:
		teammate_status_label.text = "AI 队友：关闭"
	elif ai_profile.is_empty():
		teammate_status_label.text = "AI 队友：未选择\n请从其他角色中选择"
	else:
		teammate_status_label.text = "AI 队友：%s · Lv.%d %s" % [
			ai_profile.get("name", "未命名"),
			int(ai_profile.get("level", 1)),
			ai_profile.get("profession", "战士"),
		]
	enter_button.disabled = selected_main_profile_id.is_empty()
	enter_button.text = "选择主角色" if enter_button.disabled else "进入 HardCore"
	_refresh_character_preview()


func _refresh_character_preview() -> void:
	for child in preview_visual_root.get_children():
		child.free()
	var profile := _profile_by_id(selected_main_profile_id)
	if profile.is_empty():
		preview_name_label.text = "尚未选择人物"
		preview_detail_label.text = "从左侧选择主角色"
		return
	var profession_name := str(profile.get("profession", "战士"))
	preview_name_label.text = str(profile.get("name", "未命名"))
	preview_detail_label.text = "%s · 等级 %d · 主角色" % [
		profession_name,
		int(profile.get("level", 1)),
	]
	var paper_doll := EquipmentCharacterPreviewScript.new()
	paper_doll.name = "RuntimePaperDoll"
	paper_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper_doll.center_on_opaque_bounds = false
	paper_doll.configure_presentation_mode("classic_avatar")
	paper_doll.configure_profile(
		profession_name,
		_profile_equipment_snapshot(selected_main_profile_id)
	)
	paper_doll.set_meta("preview_profile_id", selected_main_profile_id)
	paper_doll.set_meta("preview_source", "selected_profile_save_equipment")
	paper_doll.set_meta("paper_doll_presentation_mode", "classic_avatar")
	preview_visual_root.add_child(paper_doll)
	paper_doll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _profile_equipment_snapshot(profile_id: String) -> Dictionary:
	if profile_id.is_empty():
		return {}
	var profile_path := "%s/%s.json" % [PlayerState.profile_directory, profile_id]
	if not FileAccess.file_exists(profile_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if not parsed is Dictionary:
		return {}
	var saved_equipment: Variant = parsed.get("equipment", {})
	if not saved_equipment is Dictionary:
		return {}
	return PlayerState.migrate_equipment_slots(saved_equipment).duplicate(true)


func _on_profile_main_pressed(profile_id: String) -> void:
	if _roster_press_is_suppressed():
		return
	_select_main_profile(profile_id)


func _on_profile_ai_pressed(profile_id: String) -> void:
	if _roster_press_is_suppressed():
		return
	_select_ai_profile(profile_id)


func _select_main_profile(profile_id: String) -> void:
	if not _profile_exists(profile_id):
		return
	if profile_id == selected_ai_profile_id:
		selected_ai_profile_id = ""
	selected_main_profile_id = profile_id
	if not PlayerState.select_character(profile_id):
		message_label.text = "角色存档不存在或已损坏"
		_refresh_profiles()
		return
	message_label.text = "已选择主角色：%s" % PlayerState.character_name
	_refresh_selection_state()


func _select_ai_profile(profile_id: String) -> void:
	if not _profile_exists(profile_id) or profile_id == selected_main_profile_id:
		return
	ai_teammate_enabled = true
	selected_ai_profile_id = "" if selected_ai_profile_id == profile_id else profile_id
	message_label.text = ""
	_refresh_selection_state()


func _set_ai_teammate_enabled(enabled: bool) -> void:
	ai_teammate_enabled = enabled
	message_label.text = ""
	_refresh_selection_state()


func _select_creation_profession(profession_name: String) -> void:
	if not ProfessionRules.is_valid_profession(profession_name):
		return
	selected_creation_profession = profession_name
	message_label.text = ""
	_refresh_creation_controls()


func _refresh_creation_controls() -> void:
	for profession_name: String in profession_buttons:
		var button: Button = profession_buttons[profession_name]
		button.theme_type_variation = (
			"GothicComponentSelectedButton"
			if profession_name == selected_creation_profession
			else "GothicComponentButton"
		)


func _create_character() -> void:
	last_creation_request = build_creation_request()
	character_creation_requested.emit(last_creation_request.duplicate(true))
	var error := PlayerState.create_character(
		str(last_creation_request.character_name),
		selected_creation_profession,
		FIXED_CHARACTER_GENDER
	)
	if not error.is_empty():
		message_label.add_theme_color_override("font_color", Color("d47868"))
		message_label.text = error
		return
	selected_main_profile_id = PlayerState.active_profile_id
	selected_ai_profile_id = ""
	message_label.add_theme_color_override("font_color", Color("a8c38f"))
	message_label.text = "角色创建成功，请选择是否携带 AI 队友"
	name_input.clear()
	_refresh_profiles()


func build_creation_request() -> Dictionary:
	return {
		"contract_id": CREATION_CONTRACT_ID,
		"character_name": name_input.text.strip_edges().substr(0, 12),
		"profession_id": ProfessionRules.profession_id(selected_creation_profession),
		"profession_name": selected_creation_profession,
		"gender": FIXED_CHARACTER_GENDER,
	}


func _enter_selected_character() -> void:
	if selected_main_profile_id.is_empty():
		message_label.text = "请先选择主角色"
		return
	if not PlayerState.select_character(selected_main_profile_id):
		message_label.text = "角色存档不存在或已损坏"
		_refresh_profiles()
		return
	last_launch_request = build_launch_request()
	get_tree().root.set_meta(LAUNCH_CONTEXT_META, last_launch_request.duplicate(true))
	character_launch_requested.emit(last_launch_request.duplicate(true))
	if suppress_scene_change_for_test:
		return
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func build_launch_request() -> Dictionary:
	var teammate_id := selected_ai_profile_id if ai_teammate_enabled else ""
	if teammate_id == selected_main_profile_id or not _profile_exists(teammate_id):
		teammate_id = ""
	return {
		"contract_id": LAUNCH_CONTRACT_ID,
		"main_profile_id": selected_main_profile_id,
		"ai_teammate_enabled": ai_teammate_enabled and not teammate_id.is_empty(),
		"ai_teammate_profile_id": teammate_id,
		"ai_control_mode": "companion_ai" if not teammate_id.is_empty() else "disabled",
	}


func _profile_by_id(profile_id: String) -> Dictionary:
	for profile: Dictionary in _profiles:
		if str(profile.get("id", "")) == profile_id:
			return profile
	return {}


func _profile_exists(profile_id: String) -> bool:
	return not profile_id.is_empty() and not _profile_by_id(profile_id).is_empty()


func _safe_node_name(value: String) -> String:
	return value.replace(".", "_").replace("-", "_").replace(" ", "_")


func _section_panel(node_name: String, rect: Rect2) -> Panel:
	var surface := Panel.new()
	surface.name = "%sSurface" % node_name
	surface.position = rect.position
	surface.size = rect.size
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	content_root.add_child(surface)
	var panel := Panel.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.theme_type_variation = "GothicInsetFrame"
	content_root.add_child(panel)
	return panel


func _section_title(text_value: String, width: float) -> Label:
	var title := Label.new()
	title.text = text_value
	title.position = Vector2(18, 12)
	title.size = Vector2(width - 36.0, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.theme_type_variation = "GothicSectionTitle"
	return title
