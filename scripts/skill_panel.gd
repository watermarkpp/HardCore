class_name SkillPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const HUDSkillIconCatalogScript := preload("res://scripts/hud_skill_icon_catalog.gd")
const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")
const TouchScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")
const GothicFrameFillScript := preload("res://scripts/gothic_frame_fill.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const UIRuntimeLayoutOverridesScript := preload("res://scripts/ui_runtime_layout_overrides.gd")
const SkillVisibilityPolicyScript := preload(
	"res://scripts/skills/skill_visibility_policy.gd"
)
const SKILL_RULES_PATH := "res://assets/data/vanilla_176/profession_combat_rules.json"

signal closed
signal quick_slot_assignment_requested(request: Dictionary)
signal skill_button_assignment_requested(request: Dictionary)

const PANEL_SIZE := Vector2(1208, 650)
const MODAL_SURFACE_INSET := Vector4(32, 38, 32, 34)
const SECTION_VERTICAL_SHIFT := 24.0
const LONG_PRESS_SECONDS := 0.48
const ATTACK_SLOT_COUNT := 1
const ATTACK_RING_SLOT_COUNT := 6

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
var center_assignment_buttons: Array[Button] = []
var attack_assignment_buttons: Array[Button] = []
var attack_ring_assignment_buttons: Array[Button] = []
var assignment_buttons: Array[Button] = []
var assignment_popup: Panel
var assignment_scrim: Panel
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
var skill_button_assignments: Dictionary = {}
var skill_button_modes: Dictionary = {}
var _refresh_pending := false
var _refresh_execution_count := 0
var _formal_skill_rules: Dictionary = {}


func _ready() -> void:
	_load_formal_skill_rules()
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
	visibility_changed.connect(_on_visibility_changed)
	PlayerState.skills_changed.connect(_on_panel_data_changed)
	PlayerState.inventory_changed.connect(_on_panel_data_changed)


func _build_modal_surface() -> void:
	var surface := GothicFrameFillScript.new()
	surface.name = "ModalSurface"
	# The large frame has two visible rings. Its source image's regular inner
	# opening starts at x=46/y=60 and ends 46/65 px before the opposite edges.
	# This code fill is placed strictly inside that opening and drawn behind the
	# frame, so neither ring nor the central ornaments can be covered.
	# The measured inner opening follows a 41 px radius from (83, 60) to
	# (42, 101). Extend the fill one pixel beneath the inner ring so its
	# antialiased edge covers the join without ever drawing above the frame.
	surface.position = Vector2(41, 59)
	surface.size = PANEL_SIZE - Vector2(82, 123)
	surface.shape_mode = GothicFrameFillScript.ShapeMode.ROUNDED_INNER
	surface.corner_radius = 42.0
	surface.show_behind_parent = true
	surface.set_meta("calibration_internal_visual", true)
	add_child(surface)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(374, 10)
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
	var panel := _section_panel("SkillDetailPanel", Rect2(342, 76, 460, 548))
	# Independent v3 secondary frame: the factory's transparent nine-slice is
	# paired with its measured V3_INNER code fill and kept behind all content.
	var detail_frame := GothicFrameFactoryScript.add_filled_section(
		panel,
		"SkillDetailV3Frame",
		Rect2(8, 42, 444, 498),
	)
	detail_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.move_child(detail_frame, 0)
	panel.add_child(_section_title("技能详情", 460))
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
	skill_name_label.size = Vector2(284, 38)
	skill_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skill_name_label.add_theme_font_size_override("font_size", 22)
	skill_name_label.add_theme_color_override("font_color", Color("f2c783"))
	panel.add_child(skill_name_label)
	detail_label = RichTextLabel.new()
	detail_label.name = "SkillStats"
	detail_label.position = Vector2(152, 104)
	detail_label.size = Vector2(284, 190)
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.theme_type_variation = "GothicDetailText"
	detail_label.add_theme_font_size_override("normal_font_size", 15)
	panel.add_child(detail_label)
	var description_title := Label.new()
	description_title.name = "DescriptionTitle"
	description_title.text = "技能说明"
	description_title.position = Vector2(24, 304)
	description_title.size = Vector2(412, 28)
	description_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description_title.theme_type_variation = "GothicSectionTitle"
	panel.add_child(description_title)
	description_label = RichTextLabel.new()
	description_label.name = "SkillDescription"
	description_label.position = Vector2(24, 338)
	description_label.size = Vector2(412, 116)
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
	learn_button.size = Vector2(412, 64)
	learn_button.theme_type_variation = "GothicComponentButton"
	learn_button.pressed.connect(_learn_selected)
	panel.add_child(learn_button)

func _build_assignment_section() -> void:
	var panel := _section_panel("AssignmentPanel", Rect2(814, 76, 374, 548))
	panel.add_child(_section_title("技能按钮配置", 374))
	var attack_title := Label.new()
	attack_title.name = "AttackSlotTitle"
	attack_title.text = "攻击主键"
	attack_title.position = Vector2(22, 50)
	attack_title.size = Vector2(330, 26)
	attack_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attack_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	attack_title.theme_type_variation = "GothicMutedLabel"
	panel.add_child(attack_title)
	var attack_slot := Button.new()
	attack_slot.name = "AttackSkillSlot"
	attack_slot.position = Vector2(18, 80)
	attack_slot.size = Vector2(230, 82)
	attack_slot.text = ""
	attack_slot.theme_type_variation = "GothicSkillConfigCompactButton"
	attack_slot.pressed.connect(_assign_selected_to_target.bind("attack", 0))
	attack_slot.set_meta("slot_group", "attack")
	attack_slot.set_meta("slot_index", 0)
	attack_slot.set_meta("stable_slot_id", "hud.attack.primary")
	panel.add_child(attack_slot)
	attack_assignment_buttons.append(attack_slot)
	assignment_buttons.append(attack_slot)
	var clear_attack := Button.new()
	clear_attack.name = "ClearAttackSkillSlot"
	clear_attack.text = "恢复\n普通攻击"
	clear_attack.position = Vector2(252, 80)
	clear_attack.size = Vector2(104, 82)
	clear_attack.theme_type_variation = "GothicSkillConfigCompactButton"
	clear_attack.pressed.connect(_request_clear_target.bind("attack", 0))
	clear_attack.set_meta("stable_slot_id", "hud.attack.primary")
	clear_attack.set_meta("assignment_action", "clear")
	panel.add_child(clear_attack)
	var ring_title := Label.new()
	ring_title.name = "AttackRingSlotsTitle"
	ring_title.text = "攻击环技能槽 1–6"
	ring_title.position = Vector2(22, 176)
	ring_title.size = Vector2(290, 26)
	ring_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ring_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring_title.theme_type_variation = "GothicMutedLabel"
	panel.add_child(ring_title)
	for slot_index in range(ATTACK_RING_SLOT_COUNT):
		var button := Button.new()
		button.name = "AttackRingSkillSlot_%d" % (slot_index + 1)
		button.position = Vector2(18 + (slot_index % 3) * 118, 208 + floori(float(slot_index) / 3.0) * 112)
		button.size = Vector2(108, 60)
		button.text = ""
		button.theme_type_variation = "GothicSkillConfigCompactButton"
		button.pressed.connect(_assign_selected_to_target.bind("attack_ring", slot_index))
		button.set_meta("slot_group", "attack_ring")
		button.set_meta("slot_index", slot_index)
		button.set_meta("stable_slot_id", "hud.attack_ring_skill.%d" % (slot_index + 1))
		panel.add_child(button)
		attack_ring_assignment_buttons.append(button)
		assignment_buttons.append(button)
		var clear_button := Button.new()
		clear_button.name = "ClearAttackRingSkillSlot_%d" % (slot_index + 1)
		clear_button.text = "清空 %d" % (slot_index + 1)
		clear_button.position = button.position + Vector2(0, 64)
		clear_button.size = Vector2(108, 40)
		clear_button.theme_type_variation = "GothicSkillConfigCompactButton"
		clear_button.pressed.connect(_request_clear_target.bind("attack_ring", slot_index))
		clear_button.set_meta("stable_slot_id", "hud.attack_ring_skill.%d" % (slot_index + 1))
		clear_button.set_meta("assignment_action", "clear")
		panel.add_child(clear_button)
	var hint := Label.new()
	hint.name = "AssignmentHint"
	hint.text = "主动技能可配置到攻击主键或六个环形技能位\n被动技能仅在技能列表中展示"
	## FREEZE-G0.2-B (FREEZE-B038): word-smart autowrap keeps the hint width
	## inside the widened 338px slot (parent-derived: 374 - 2*18) and lets the
	## height grow with the wrapped text. The muted-label variation must be
	## applied before sizing so the 14pt minimum width never clamps the slot
	## wider than the parent (previously size was assigned at the 16pt default,
	## clamping to 320px -> right edge 10px past the parent).
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.theme_type_variation = "GothicMutedLabel"
	hint.position = Vector2(18, 442)
	hint.size = Vector2(338, 72)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(hint)


func _build_assignment_popup() -> void:
	assignment_scrim = Panel.new()
	assignment_scrim.name = "AssignmentScrim"
	assignment_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	assignment_scrim.z_index = 100
	assignment_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	# This full-rect node is only an input barrier.  The visible modal background
	# belongs to PopupSurface and must never expand to the whole skill codex.
	assignment_scrim.theme_type_variation = "GothicModalScrim"
	assignment_scrim.visible = false
	add_child(assignment_scrim)
	assignment_popup = Panel.new()
	assignment_popup.name = "SkillAssignmentPopup"
	assignment_popup.set_anchors_preset(Control.PRESET_CENTER)
	assignment_popup.offset_left = -310
	assignment_popup.offset_top = -212
	assignment_popup.offset_right = 310
	assignment_popup.offset_bottom = 212
	assignment_popup.size = Vector2(620, 424)
	assignment_popup.z_index = 1
	assignment_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	assignment_popup.theme_type_variation = "GothicModalFrame"
	assignment_popup.visible = false
	assignment_scrim.add_child(assignment_popup)
	var popup_surface := Panel.new()
	popup_surface.name = "PopupSurface"
	popup_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_surface.show_behind_parent = true
	popup_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_surface.theme_type_variation = "GothicModalSurface"
	assignment_popup.add_child(popup_surface)
	assignment_popup_title = Label.new()
	assignment_popup_title.name = "PopupTitle"
	assignment_popup_title.position = Vector2(28, 28)
	assignment_popup_title.size = Vector2(564, 42)
	assignment_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	assignment_popup_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	assignment_popup_title.add_theme_font_size_override("font_size", 21)
	assignment_popup_title.add_theme_color_override("font_color", Color("f1cc88"))
	assignment_popup.add_child(assignment_popup_title)
	var hint := Label.new()
	hint.text = "选择攻击主键或六个攻击环技能槽"
	hint.position = Vector2(28, 74)
	hint.size = Vector2(564, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.theme_type_variation = "GothicMutedLabel"
	assignment_popup.add_child(hint)
	var attack_slot := Button.new()
	attack_slot.name = "PopupAttackSlot"
	attack_slot.text = "攻击主键"
	attack_slot.position = Vector2(28, 108)
	attack_slot.size = Vector2(564, 62)
	attack_slot.theme_type_variation = "GothicComponentSelectedButton"
	attack_slot.pressed.connect(_assign_selected_to_target.bind("attack", 0))
	attack_slot.set_meta("slot_group", "attack")
	attack_slot.set_meta("slot_index", 0)
	assignment_popup.add_child(attack_slot)
	assignment_popup_buttons.append(attack_slot)
	var ring_title := Label.new()
	ring_title.text = "攻击环技能槽"
	ring_title.position = Vector2(28, 178)
	ring_title.size = Vector2(564, 26)
	ring_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ring_title.theme_type_variation = "GothicSectionTitle"
	assignment_popup.add_child(ring_title)
	for slot_index in range(ATTACK_RING_SLOT_COUNT):
		var button := Button.new()
		button.name = "PopupAttackRingSlot_%d" % (slot_index + 1)
		button.text = "攻击环 %d" % (slot_index + 1)
		button.position = Vector2(28 + (slot_index % 3) * 188, 208 + floori(float(slot_index) / 3.0) * 70)
		button.size = Vector2(176, 62)
		button.theme_type_variation = "GothicComponentButton"
		button.pressed.connect(_assign_selected_to_target.bind("attack_ring", slot_index))
		button.set_meta("slot_group", "attack_ring")
		button.set_meta("slot_index", slot_index)
		assignment_popup.add_child(button)
		assignment_popup_buttons.append(button)
	var cancel_button := Button.new()
	cancel_button.name = "CancelButton"
	cancel_button.text = "取消"
	cancel_button.position = Vector2(244, 350)
	cancel_button.size = Vector2(132, 62)
	cancel_button.theme_type_variation = "GothicComponentButton"
	cancel_button.pressed.connect(_hide_assignment_popup)
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
	var all_entries: Array = GameData.get_profession_skills(
		PlayerState.profession
	)
	## Hidden skills (e.g. taoist.revelation) stay in data/saves but are
	## filtered from the visible skill system.
	skill_entries = []
	for entry: Variant in all_entries:
		if not entry is Dictionary:
			continue
		var entry_name := str((entry as Dictionary).get("skillName", ""))
		var entry_id := ProfessionRules.skill_id(entry_name)
		if entry_id.is_empty() or not SkillVisibilityPolicyScript.is_skill_visible(
			entry_id
		):
			continue
		skill_entries.append(entry)
	selected_skill_index = 0 if not skill_entries.is_empty() else -1
	refresh()
	show()


func set_skill_button_assignments(assignments: Dictionary, interaction_modes := {}) -> void:
	skill_button_assignments = assignments.duplicate(true)
	skill_button_modes = interaction_modes.duplicate(true) if interaction_modes is Dictionary else {}
	if skill_list != null:
		refresh()


func _on_panel_data_changed() -> void:
	if not visible:
		_refresh_pending = true
		return
	refresh()


func _on_visibility_changed() -> void:
	if visible and _refresh_pending:
		refresh()


func refresh() -> void:
	if skill_list == null:
		return
	_refresh_pending = false
	_refresh_execution_count += 1
	skill_list.clear()
	for entry: Variant in skill_entries:
		var skill_name := str(entry.get("skillName", "技能"))
		var learned := PlayerState.is_skill_learned(skill_name)
		var has_book := PlayerState.has_item(skill_name)
		var marker := "已学会" if learned else ("可学习" if has_book else "缺少技能书")
		skill_list.add_item("%s（%s）　Lv%d" % [skill_name, marker, int(entry.get("requiredCharacterLevel", 1))])
	_rebuild_skill_cards()
	_refresh_assignment_slots()
	trainer_context_label.text = "%s　·　%s" % [_trainer_name, PlayerState.profession]
	skill_count_label.text = "%s技能　%d 项" % [PlayerState.profession, skill_entries.size()]
	if selected_skill_index >= 0 and selected_skill_index < skill_entries.size():
		skill_list.select(selected_skill_index)
		_show_skill_detail(selected_skill_index)
	else:
		_clear_skill_detail()
	UIRuntimeLayoutOverridesScript.apply_profile(self, "skill")
	call_deferred("_ensure_skill_list_bottom_clearance")


func _on_runtime_layout_profile_applied(profile_id: String) -> void:
	if profile_id == "skill":
		_ensure_skill_list_bottom_clearance()
		call_deferred("_ensure_skill_list_bottom_clearance")


func _ensure_skill_list_bottom_clearance() -> void:
	if not is_instance_valid(skill_list_container) or not is_instance_valid(skill_list_container.get_parent()):
		return
	var scroll := skill_list_container.get_parent() as ScrollContainer
	if scroll == null:
		return
	var content_bottom := 0.0
	for child: Node in skill_list_container.get_children():
		if child is Control:
			var control := child as Control
			content_bottom = maxf(content_bottom, control.position.y + control.size.y)
	var separation := float(skill_list_container.get_theme_constant("separation"))
	var viewport_height := maxf(0.0, scroll.size.y)
	# Keep enough trailing space for the calibrated card's bottom edge to clear
	# the viewport clip at max scroll.  The extra separation is layout-relative,
	# not tied to any profession or skill name.
	var required_height := maxf(viewport_height, content_bottom + separation * 3.0)
	skill_list_container.custom_minimum_size.y = required_height
	skill_list_container.queue_sort()


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
		var interaction_label := _skill_presentation_label(skill_name)
		var status := "已学会" if learned else ("未学会" if has_book else "未学会")
		var detail_status := "Lv.%d · %s" % [level, interaction_label] if learned else ("可学习" if has_book else "缺少技能书")
		var button := Button.new()
		button.name = "SkillCard_%d" % index
		button.custom_minimum_size = Vector2(266, 64)
		button.toggle_mode = true
		button.text = "%s（%s）\n%s" % [skill_name, status, detail_status]
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 15)
		button.set_pressed_no_signal(index == selected_skill_index)
		button.theme_type_variation = "GothicComponentSelectedButton" if index == selected_skill_index else "GothicComponentButton"
		button.pressed.connect(_on_skill_selected.bind(index))
		button.gui_input.connect(_skill_card_input.bind(index))
		button.set_meta("skill_id", ProfessionRules.skill_id(skill_name))
		button.set_meta("learned", learned)
		button.set_meta("assignment_eligible", _skill_interaction_mode(skill_name) != "passive")
		skill_list_container.add_child(button)
		skill_buttons.append(button)


func _on_skill_selected(index: int) -> void:
	if index < 0 or index >= skill_entries.size():
		return
	if TouchScrollSupportScript.is_drag_active(get_tree()):
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
	var maximum_range_gu := float(combat.get("maximum_range_gu", 0.0))
	var training_points: Variant = row.get("trainingPoints", null)
	var mastery_text := "—" if training_points == null else "下级需求 %s" % training_points
	var state_text := "已学会" if learned else ("可学习" if PlayerState.has_item(skill_name) else "缺少技能书")
	skill_name_label.text = "%s（%s）" % [skill_name, state_text]
	skill_icon.texture = _skill_texture(skill_name)
	skill_icon.set_meta("skill_id", ProfessionRules.skill_id(skill_name))
	skill_icon.set_meta("skill_icon_id", HUDSkillIconCatalogScript.source_id_for(skill_name))
	skill_icon.set_meta("skill_icon_path", HUDSkillIconCatalogScript.source_path_for(skill_name))
	detail_label.text = "[color=#ddc9a9]等级：%s　　熟练度：%s\n类型：%s　　交互：%s\n目标：%s　　消耗：%d MP\n冷却：%.2f 秒　　范围：%.1f GU\n状态：%s[/color]" % [
		"Lv.%d" % learned_level if learned else "未学习",
		mastery_text,
		_cast_type_label(cast_type),
		_skill_presentation_label(skill_name),
		_target_mode_label(target_mode),
		int(row.get("manaCost", 0)),
		cooldown,
		maximum_range_gu,
		state_text,
	]
	description_label.text = "[color=#d7c3a3]%s[/color]" % _player_mechanics_description(row, combat)
	learn_button.disabled = learned
	learn_button.text = "已学习" if learned else ("使用技能书学习" if PlayerState.has_item(skill_name) else "缺少同名技能书")
	# Assignment is intentionally available only in the right-hand panel.
	learn_button.visible = not learned


func _player_mechanics_description(row: Dictionary, combat: Dictionary) -> String:
	var parts: Array[String] = []
	var base := str(row.get("description", "暂无说明")).strip_edges()
	if not base.is_empty():
		parts.append(base)
	var effect := str(row.get("effect", "")).strip_edges()
	if not effect.is_empty() and effect != "-":
		parts.append("效果：%s" % effect)
	# Only explicit player-facing fields are rendered; internal formula strings are ignored.
	var probability: Variant = combat.get("probability", combat.get("chance", null))
	if probability is float or probability is int:
		var probability_value := float(probability)
		parts.append("触发概率：%.1f%%" % (probability_value * 100.0 if probability_value <= 1.0 else probability_value))
	var cooldown := float(combat.get("cooldown", row.get("delay", 0.0)))
	if cooldown > 0.0:
		parts.append("冷却：%.2f秒" % cooldown)
	var mana := int(row.get("manaCost", combat.get("mana_cost", 0)))
	if mana > 0:
		parts.append("消耗：%d MP" % mana)
	var target := str(combat.get("target_mode", "")).strip_edges()
	if not target.is_empty() and target != "unknown":
		parts.append("目标：%s" % _target_mode_label(target))
	var range_gu := float(combat.get("maximum_range_gu", 0.0))
	if range_gu > 0.0:
		parts.append("作用范围：%.1f GU" % range_gu)
	var stable_id := str(row.get("skill_id", ProfessionRules.skill_id(str(row.get("skillName", "")))))
	var formal: Dictionary = _formal_skill_rules.get(stable_id, {})
	if not formal.is_empty():
		var group := str(formal.get("formula_group", ""))
		if group == "classic_magic_damage":
			var mp_base := int(formal.get("magic_power_base", 0))
			var p_base := int(formal.get("power_base", 0))
			parts.append("伤害公式：魔法攻击随机值＋按（技能威力随机值÷（训练等级＋1）×（技能等级＋1））正式取整所得数值＋基础威力%d；魔法威力基础值%d" % [p_base, mp_base])
		elif group == "classic_healing":
			parts.append("治疗公式：技能威力（按等级折算） + 精神力随机值×2")
		elif group == "classic_summon":
			var life_values: Array = formal.get("lifetime_seconds_by_level", [])
			var life_idx := clampi(int(combat.get("skill_level", 0)), 0, life_values.size() - 1) if not life_values.is_empty() else -1
			if life_idx >= 0:
				parts.append("召唤：召唤物等级与技能等级相同；数量%d，存在时间%.0f秒" % [int(formal.get("default_count", 1)), float(life_values[life_idx])])
		for key in ["power_base", "power_bonus", "magic_power_base", "magic_power_bonus", "area_radius_cells", "tick_interval_ms", "apply_delay_ms", "amulet_cost", "max_slave_count", "leash_range", "teleport_range"]:
			if formal.has(key):
				var labels := {"power_base":"基础威力", "power_bonus":"威力加成", "magic_power_base":"基础魔法威力", "magic_power_bonus":"魔法威力加成", "area_radius_cells":"作用格数", "tick_interval_ms":"每次间隔毫秒", "apply_delay_ms":"生效延迟毫秒", "amulet_cost":"符咒消耗", "max_slave_count":"最大召唤数", "leash_range":"跟随距离", "teleport_range":"传送距离"}
				parts.append("%s：%s" % [labels[key], str(formal[key])])
		if formal.has("multiplier_by_level"):
			var levels: Array = formal.get("multiplier_by_level")
			var idx := clampi(int(combat.get("skill_level", 0)), 0, levels.size() - 1)
			parts.append("当前等级倍率：%.2f倍" % float(levels[idx]))
		for formula_key in ["duration_formula", "success_formula", "shield_power_formula", "damage_remaining_ratio_formula", "buff_power_formula", "green_power_formula", "red_power_formula", "push_cells_formula", "anti_poison_formula"]:
			if formal.has(formula_key):
				parts.append(_translate_formal_formula(formula_key, str(formal[formula_key])))
		if stable_id == "wizard.temptation_light":
			parts.append("成功概率：目标等级不高于施法者等级+2且满足生命值条件时判定成功")
	if stable_id.begins_with("warrior."):
		var level := int(combat.get("skill_level", 0))
		match stable_id:
			"warrior.fire_sword": parts.append("烈火伤害：基础物理伤害×%.1f倍（当前等级%d）" % [WarriorCombatMath.fire_sword_multiplier(level), level])
			"warrior.slaying_swordsmanship": parts.append("攻杀：基础物理伤害+%d点；触发概率约%.1f百分比（每%d次攻击一次）" % [WarriorCombatMath.slaying_flat_damage_bonus(level), 100.0 / float(WarriorCombatMath.slaying_proc_cycle(level)), WarriorCombatMath.slaying_proc_cycle(level)])
			"warrior.thrusting": parts.append("刺杀：第二目标伤害＝基础伤害×(技能等级+2)/(训练等级+2)，并按%d百分比折算" % [WarriorCombatMath.SWORD_LONG_POWER_RATE])
			"warrior.half_moon": parts.append("半月：扇形副目标伤害＝基础伤害×(技能等级+2)/(训练等级+10)")
			"warrior.basic_swordsmanship": parts.append("基本剑术：每级增加%d点命中，直接用于命中判定" % WarriorCombatMath.basic_sword_accuracy_bonus(level))
			"warrior.wild_rush": parts.append("野蛮冲撞：仅玩家等级高于目标时成功，成功率100百分比；最多推进%d格" % [WarriorCombatMath.wild_rush_max_cells(level)])
	return "\n".join(parts)


func _load_formal_skill_rules() -> void:
	var file := FileAccess.open(SKILL_RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for profession in ["wizard", "taoist"]:
			var skills: Dictionary = parsed.get(profession, {}).get("skills", {})
			_formal_skill_rules.merge(skills, true)


func _translate_formal_formula(kind: String, formula: String) -> String:
	var labels := {"duration_formula":"持续时间公式", "success_formula":"成功判定", "shield_power_formula":"护盾强度公式", "damage_remaining_ratio_formula":"承伤剩余比例", "buff_power_formula":"增益强度公式", "green_power_formula":"绿色毒伤公式", "red_power_formula":"红色毒伤公式", "push_cells_formula":"击退格数公式", "anti_poison_formula":"抗毒判定"}
	var readable := formula
	readable = readable.replace("get_power13(60) + sc_roll*10", "按技能等级折算的防御力 + 精神力随机值×10")
	readable = readable.replace("get_power13(40) + sc_roll*3", "按技能等级折算的持续时间 + 精神力随机值×3")
	readable = readable.replace("get_power13(30) + sc_roll*3", "按技能等级折算的持续时间 + 精神力随机值×3")
	readable = readable.replace("get_power(10)", "按技能等级折算的基础持续值")
	readable = readable.replace("get_power(mc_roll + 15)", "按技能等级折算的护盾强度（魔法随机值+15）")
	readable = readable.replace("shield_power seconds", "护盾强度对应的秒数")
	readable = readable.replace("(skill_level+2)*0.08", "技能等级+2再乘8%；实际承受伤害比例，减伤比例为其余部分")
	readable = readable.replace("get_power13(40) + sc_roll*2", "按技能等级折算的毒伤 + 精神力随机值×2")
	readable = readable.replace("get_power13(30) + sc_roll*2", "按技能等级折算的毒伤 + 精神力随机值×2")
	readable = readable.replace("delphi_round(skill_level/3 * power/20)", "按技能等级与威力折算的持续时间")
	readable = readable.replace("random(target_anti_poison+7) <= 6", "随机值（目标抗毒+7）≤6；满足时抗毒判定通过")
	readable = readable.replace("random(100) < skill_level*7 + 15 + caster_level-target_level", "随机百分比 < 技能等级×7 + 15 + 施法者等级－目标等级；右侧为成功概率上限")
	readable = readable.replace("random(6) <= skill_level + 3", "1至6的随机值≤技能等级+3；成功概率=(技能等级+3)/6")
	readable = readable.replace("random(11) < skill_level * 2 + 4", "1至11的随机值<技能等级×2+4；成功概率=(技能等级×2+4)/11")
	readable = readable.replace("random_range(0,caster_level)", "0至施法者等级的随机分钟")
	readable = readable.replace("random(2)", "0至1的随机格数")
	return "%s：%s" % [labels.get(kind, "效果公式"), readable]


func _clear_skill_detail() -> void:
	skill_name_label.text = "请选择技能"
	skill_icon.texture = null
	detail_label.text = "[color=#a99479]从左侧选择技能查看完整资料。[/color]"
	description_label.text = ""
	learn_button.disabled = true
	learn_button.visible = true


func _refresh_assignment_slots() -> void:
	for slot_index in range(attack_assignment_buttons.size()):
		var skill_name := _assignment_skill_name("attack", slot_index)
		_set_assignment_button_content(attack_assignment_buttons[slot_index], "攻击主键", skill_name)
		if slot_index < assignment_popup_buttons.size():
			assignment_popup_buttons[slot_index].text = "攻击主键\n%s [%s]" % [
				skill_name if not skill_name.is_empty() else "普通攻击",
				_skill_presentation_label(skill_name),
			]
	for slot_index in range(attack_ring_assignment_buttons.size()):
		var skill_name := _assignment_skill_name("attack_ring", slot_index)
		_set_assignment_button_content(attack_ring_assignment_buttons[slot_index], "环 %d" % (slot_index + 1), skill_name)
		var popup_index := ATTACK_SLOT_COUNT + slot_index
		if popup_index < assignment_popup_buttons.size():
			assignment_popup_buttons[popup_index].text = "攻击环 %d\n%s [%s]" % [
				slot_index + 1,
				skill_name if not skill_name.is_empty() else "空",
				_skill_presentation_label(skill_name),
			]


func _assignment_skill_name(slot_group: String, slot_index: int) -> String:
	if not skill_button_assignments.is_empty():
		if not skill_button_assignments.has(slot_group):
			return ""
		var configured: Variant = skill_button_assignments.get(slot_group)
		if configured is Array and slot_index >= 0 and slot_index < configured.size():
			var array_value: Variant = configured[slot_index]
			return _assignment_value_skill_name(array_value)
		if configured is Dictionary:
			var dict_value: Variant = configured.get(slot_index, configured.get(str(slot_index), ""))
			return _assignment_value_skill_name(dict_value)
		return ""
	if PlayerState.has_method("skill_name_for_slot"):
		return str(PlayerState.call("skill_name_for_slot", slot_group, slot_index))
	# Compatibility for pre-grouped saves only. A grouped contract with an
	# empty attack-ring slot is intentionally empty and never mirrors center.
	if slot_index < PlayerState.quick_slots.size():
		return PlayerState.quick_slots[slot_index]
	return ""


func _assignment_value_skill_name(value: Variant) -> String:
	if not value is Dictionary:
		return str(value)
	return str(
		value.get(
			"skill_name",
			value.get("skillName", value.get("name", value.get("display_name", value.get("displayName", ""))))
		)
	)


func _set_assignment_button_content(button: Button, slot_label_text: String, skill_name: String) -> void:
	var old_content := button.get_node_or_null("Content")
	if old_content != null:
		old_content.free()
	var content := Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(content)
	var icon := TextureRect.new()
	icon.name = "SkillIcon"
	var compact := button.size.x < 120.0
	var primary_attack := button.name == "AttackSkillSlot" or str(button.get_meta("stable_slot_id", "")) == "hud.attack.primary"
	icon.position = Vector2((button.size.x - 40.0) * 0.5, 10) if compact else (Vector2(16, 21) if primary_attack else Vector2(8, 22))
	icon.size = Vector2(40, 40)
	icon.texture = _skill_texture(skill_name)
	icon.set_meta("skill_icon_id", HUDSkillIconCatalogScript.source_id_for(skill_name))
	icon.set_meta("skill_icon_path", HUDSkillIconCatalogScript.source_path_for(skill_name))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_meta("alignment_contract", "primary_attack_inset_centered.v2" if primary_attack else "default_assignment_icon.v1")
	content.add_child(icon)
	var slot_label := Label.new()
	slot_label.name = "SlotLabel"
	slot_label.text = slot_label_text
	slot_label.position = Vector2(4, 52) if compact else (Vector2(58, 6) if primary_attack else Vector2(52, 6))
	slot_label.size = Vector2(button.size.x - 8, 18) if compact else (Vector2(button.size.x - 64, 20) if primary_attack else Vector2(button.size.x - 58, 20))
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_label.theme_type_variation = "GothicMutedLabel"
	slot_label.add_theme_font_size_override("font_size", 12)
	content.add_child(slot_label)
	var name_label := Label.new()
	name_label.name = "SkillName"
	name_label.text = skill_name if not skill_name.is_empty() else "空"
	name_label.position = Vector2(4, 70) if compact else (Vector2(58, 28) if primary_attack else Vector2(52, 28))
	name_label.size = Vector2(button.size.x - 8, 24) if compact else (Vector2(button.size.x - 64, 26) if primary_attack else Vector2(button.size.x - 58, 26))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 13 if compact else 14)
	name_label.add_theme_color_override("font_color", Color("f0c77f"))
	content.add_child(name_label)
	var mode_label := Label.new()
	mode_label.name = "InteractionMode"
	mode_label.text = _skill_presentation_label(skill_name)
	mode_label.position = Vector2(4, 94) if compact else (Vector2(58, 56) if primary_attack else Vector2(52, 56))
	mode_label.size = Vector2(button.size.x - 8, 18) if compact else (Vector2(button.size.x - 64, 20) if primary_attack else Vector2(button.size.x - 58, 20))
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_label.add_theme_font_size_override("font_size", 12)
	mode_label.add_theme_color_override("font_color", Color("7fb789") if _skill_interaction_mode(skill_name) == "toggle" else Color("c8a871"))
	content.add_child(mode_label)
	button.set_meta("skill_name", skill_name)
	button.set_meta("interaction_mode", _skill_interaction_mode(skill_name))


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
	if _skill_interaction_mode(skill_name) == "passive":
		description_label.text = "[color=#b58b68]被动技能始终生效，只在技能列表中展示，不能配置到战斗按钮。[/color]"
		return
	_on_skill_selected(index)
	assignment_popup_title.text = "配置：%s　[%s]" % [skill_name, _skill_presentation_label(skill_name)]
	assignment_popup.set_meta("skill_name", skill_name)
	assignment_popup.set_meta("skill_id", ProfessionRules.skill_id(skill_name))
	assignment_popup.set_meta("interaction_mode", _skill_interaction_mode(skill_name))
	assignment_scrim.show()
	assignment_popup.show()


func _assign_selected_to_slot(slot_index: int) -> void:
	_assign_selected_to_target("attack_ring", slot_index)


func _assign_selected_to_target(slot_group: String, slot_index: int) -> void:
	var skill_name := ""
	if assignment_popup.visible:
		skill_name = str(assignment_popup.get_meta("skill_name", ""))
	elif selected_skill_index >= 0 and selected_skill_index < skill_entries.size():
		skill_name = str(skill_entries[selected_skill_index].get("skillName", ""))
	if not PlayerState.is_skill_learned(skill_name):
		return
	if _skill_interaction_mode(skill_name) == "passive":
		return
	var maximum := ATTACK_SLOT_COUNT if slot_group == "attack" else ATTACK_RING_SLOT_COUNT
	if slot_group not in ["attack", "attack_ring"] or slot_index < 0 or slot_index >= maximum:
		return
	var stable_slot_id := (
		"hud.attack.primary"
		if slot_group == "attack"
		else "hud.attack_ring_skill.%d" % (slot_index + 1)
	)
	var interaction_mode := _skill_interaction_mode(skill_name)
	var request := {
		"contract_id": "ui.skill.button_assignment.v3",
		"profession_id": ProfessionRules.profession_id(PlayerState.profession),
		"skill_id": ProfessionRules.skill_id(skill_name),
		"skill_name": skill_name,
		"slot_group": slot_group,
		"slot_index": slot_index,
		"slot_id": stable_slot_id,
		"interaction_mode": interaction_mode,
	}
	skill_button_assignment_requested.emit(request.duplicate(true))
	_hide_assignment_popup()


func _request_clear_target(slot_group: String, slot_index: int) -> void:
	var maximum := ATTACK_SLOT_COUNT if slot_group == "attack" else ATTACK_RING_SLOT_COUNT
	if slot_group not in ["attack", "attack_ring"] or slot_index < 0 or slot_index >= maximum:
		return
	var stable_slot_id := (
		"hud.attack.primary"
		if slot_group == "attack"
		else "hud.attack_ring_skill.%d" % (slot_index + 1)
	)
	skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v3",
		"profession_id": ProfessionRules.profession_id(PlayerState.profession),
		"skill_id": "",
		"skill_name": "",
		"slot_group": slot_group,
		"slot_index": slot_index,
		"slot_id": stable_slot_id,
		"interaction_mode": "empty",
		"clear": true,
	})


func _hide_assignment_popup() -> void:
	assignment_popup.hide()
	assignment_scrim.hide()


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
	if _pressed_skill_index < 0 or TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	_long_press_opened = true
	_open_assignment_popup_for(_pressed_skill_index)
	_pressed_skill_index = -1


func _skill_interaction_mode(skill_name: String) -> String:
	if skill_name.is_empty():
		return "empty"
	var skill_id := ProfessionRules.skill_id(skill_name)
	for key: String in [skill_id, skill_name]:
		if skill_button_modes.has(key):
			var configured := str(skill_button_modes[key])
			if configured in ["toggle", "click", "passive"]:
				return configured
	var profile := ProfessionRules.skill_profile(skill_name)
	var explicit_mode := str(profile.get("ui_interaction_mode", ""))
	if explicit_mode in ["toggle", "click", "passive"]:
		return explicit_mode
	var service_mode := str(profile.get("service_mode", ""))
	var cast_type := str(profile.get("cast_type", ""))
	if cast_type == "passive" or service_mode == "automatic_proc":
		return "passive"
	if service_mode.begins_with("toggle") or service_mode == "arm_next_hit" or cast_type == "shield":
		return "toggle"
	return "click"


func _skill_presentation_label(skill_name: String) -> String:
	# Production mode is the canonical explicit click. Its player-facing label
	# must still describe the one-shot charge instead of the retired auto toggle.
	if ProfessionRules.skill_id(skill_name) == "warrior.fire_sword":
		return "主动充能"
	return _interaction_mode_label(_skill_interaction_mode(skill_name))


func _interaction_mode_label(mode: String) -> String:
	return {
		"toggle": "开关",
		"click": "点击",
		"passive": "被动",
		"empty": "空",
	}.get(mode, "点击")


func _skill_texture(skill_name: String) -> Texture2D:
	if skill_name.is_empty():
		return null
	var texture := HUDSkillIconCatalogScript.texture_for(skill_name)
	if texture != null:
		return texture
	return UIItemTextureCacheScript.texture_for(
		GameData.get_item_record(skill_name), "inventoryIcon"
	)


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


func _section_panel(node_name: String, rect: Rect2) -> Control:
	var adjusted_rect := Rect2(rect.position + Vector2(0, -SECTION_VERTICAL_SHIFT), rect.size)
	var section := Control.new()
	section.name = node_name
	section.position = adjusted_rect.position
	section.size = adjusted_rect.size
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(section)
	var decoration := Control.new()
	decoration.name = "%sDecoration" % node_name
	decoration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.set_meta("calibration_layer", "filled_single_ring_decoration")
	section.add_child(decoration)
	var fill := GothicFrameFillScript.new()
	fill.name = "%sFill" % node_name
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# v3 inset_frame has a transparent centre; use the measured inner opening
	# rather than the legacy chamfer default so skill-page sections contain
	# their code-drawn background within the stretched frame.
	GothicFrameFactoryScript.configure_inset_fill(fill)
	fill.set_meta("calibration_internal_visual", true)
	decoration.add_child(fill)
	var frame := Panel.new()
	frame.name = "%sFrame" % node_name
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme_type_variation = "GothicInsetFrame"
	frame.set_meta("calibration_internal_visual", true)
	decoration.add_child(frame)
	return section


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
	_hide_assignment_popup()
	hide()
	closed.emit()
