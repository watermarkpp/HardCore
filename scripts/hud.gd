class_name GameHUD
extends CanvasLayer

const MobileLayoutRules := preload("res://scripts/mobile_layout.gd")
const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")
const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const HUDResourceOrbScript := preload("res://scripts/hud_resource_orb.gd")
const HUDSkillIconCatalogScript := preload("res://scripts/hud_skill_icon_catalog.gd")
const DeathRevivalPanelScript := preload("res://scripts/death_revival_panel.gd")
const LootFeedbackLayerScript := preload("res://scripts/loot_feedback_layer.gd")
const LoadingTransitionOverlayScript := preload("res://scripts/loading_transition_overlay.gd")
const HUDTargetBarTexture := preload("res://assets/ui/gothic_hud/v2/runtime/target_bar_v2.png")
const HUDUtilityStackTexture := preload("res://assets/ui/gothic_hud/v2/runtime/utility_stack_v2.png")
const HUDJoystickTexture := preload("res://assets/ui/gothic_hud/v2/runtime/joystick_v2.png")
const HUDChassisTexture := preload("res://assets/ui/gothic_hud/v2/runtime/bottom_chassis_v2.png")
const HUDRightControlsTexture := preload("res://assets/ui/gothic_hud/v2/runtime/right_controls_v2.png")
const HUD_RESOURCE_ORB_SIZE := Vector2(110, 110)
const HUD_HEALTH_ORB_CENTER := Vector2(182, 188)
const HUD_MANA_ORB_CENTER := Vector2(639, 188)

signal movement_changed(value: Vector2)
signal attack_pressed
signal attack_released
signal interact_pressed
signal skill_pressed(slot_index: int)
signal skill_quick_slot_assignment_requested(request: Dictionary)
signal skill_button_assignment_requested(request: Dictionary)
signal map_travel_requested(map_id: int)
signal map_teleport_requested(request: Dictionary)
signal map_teleport_availability_requested(map_ids: Array)
signal revival_requested(request: Dictionary)
signal loading_transition_covered(request: Dictionary)
signal loading_transition_finished(request: Dictionary)
signal target_switch_pressed
signal auto_target_changed(enabled: bool)
signal special_action_pressed(effect_id: String)

var hp_label: Label
var data_label: Label
var profile_label: Label
var quest_tracker_label: Label
var loot_label: Label
var target_label: Label
var target_health_fill: ColorRect
var auto_target_button: Button
var special_action_button: Button
var warrior_state_label: Label
var inventory_panel: InventoryPanel
var shop_panel: ShopPanel
var skill_panel: SkillPanel
var quest_panel: QuestPanel
var profession_panel: ProfessionPanel
var map_panel: MapPanel
var warehouse_panel: WarehousePanel
var death_revival_panel
var loot_feedback_layer
var loading_transition_overlay
var quick_buttons: Array[Button] = []
var health_orb: Control
var mana_orb: Control
var hud_item_buttons: Array[Button] = []
var quick_slot_labels: Array[Label] = []
var quick_slot_icons: Array[TextureRect] = []
var attack_ring_skill_icons: Array[TextureRect] = []
var attack_ring_skill_labels: Array[Label] = []
var current_zone_name := "比奇郊外"
var _last_hp := 120
var _last_max_hp := 120
var _last_mp := 40
var _last_max_mp := 40
var _loot_message_timer := 0.0
var _warrior_snapshot: Dictionary = {}
var _special_actions: Array[String] = []
var _special_action_index := 0
var _last_target_text := ""


func _ready() -> void:
	_build_approved_hud()


func _build_approved_hud() -> void:
	var root := Control.new()
	root.name = "MobileSafeRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = GothicUIThemeScript.build()
	add_child(root)
	MobileLayoutRules.apply_display_safe_area(root, get_viewport())
	get_viewport().size_changed.connect(MobileLayoutRules.apply_display_safe_area.bind(root, get_viewport()))

	_build_hidden_compatibility_info(root)
	_build_target_bar(root)
	_build_loot_feedback(root)
	_build_right_utility_stack(root)
	_build_bottom_chassis(root)
	_build_combat_controls(root)
	_build_modal_panels(root)
	_build_loading_transition()

	PlayerState.profile_changed.connect(update_profile)
	PlayerState.quests_changed.connect(update_quest_tracker)
	PlayerState.profile_changed.connect(update_special_actions)
	PlayerState.skills_changed.connect(update_quick_slots)
	update_profile()
	update_quest_tracker()
	update_special_actions()
	update_quick_slots()
	update_resources(_last_hp, _last_max_hp, _last_mp, _last_max_mp)


func _build_hidden_compatibility_info(root: Control) -> void:
	var top_panel := Panel.new()
	top_panel.name = "TopInfoPanel"
	top_panel.visible = false
	root.add_child(top_panel)

	hp_label = Label.new()
	top_panel.add_child(hp_label)
	data_label = Label.new()
	data_label.text = GameData.summary_text()
	top_panel.add_child(data_label)
	profile_label = Label.new()
	top_panel.add_child(profile_label)
	quest_tracker_label = Label.new()
	quest_tracker_label.name = "QuestTracker"
	top_panel.add_child(quest_tracker_label)

	loot_label = Label.new()
	loot_label.name = "LootNotice"
	loot_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	loot_label.offset_left = 360
	loot_label.offset_top = 132
	loot_label.offset_right = -360
	loot_label.offset_bottom = 172
	loot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loot_label.add_theme_font_size_override("font_size", 22)
	loot_label.add_theme_color_override("font_color", Color("ffd06f"))
	root.add_child(loot_label)


func _build_target_bar(root: Control) -> void:
	var target_panel := Control.new()
	target_panel.name = "TargetPanel"
	target_panel.anchor_left = 0.5
	target_panel.anchor_right = 0.5
	target_panel.offset_left = -220
	target_panel.offset_top = 20
	target_panel.offset_right = 220
	target_panel.offset_bottom = 93
	target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(target_panel)
	target_health_fill = ColorRect.new()
	target_health_fill.name = "TargetHealthFill"
	target_health_fill.position = Vector2(60, 24)
	target_health_fill.size = Vector2(320, 27)
	target_health_fill.color = Color(0.42, 0.035, 0.035, 0.88)
	target_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_panel.add_child(target_health_fill)
	var target_art := _add_full_texture(target_panel, "TargetFrameArt", HUDTargetBarTexture)
	target_art.set_meta("stable_id", "ui.hud.gothic.v2.target_bar")

	target_label = Label.new()
	target_label.name = "TargetLabel"
	target_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	target_label.text = "目标：自动锁定待命"
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	target_label.add_theme_font_size_override("font_size", 18)
	target_label.add_theme_color_override("font_color", Color("e7c38c"))
	target_panel.add_child(target_label)


func _build_loot_feedback(root: Control) -> void:
	loot_feedback_layer = LootFeedbackLayerScript.new()
	loot_feedback_layer.name = "LootFeedbackLayer"
	root.add_child(loot_feedback_layer)


func _build_loading_transition() -> void:
	loading_transition_overlay = LoadingTransitionOverlayScript.new()
	loading_transition_overlay.name = "LoadingTransitionOverlay"
	loading_transition_overlay.transition_covered.connect(
		func(request: Dictionary) -> void: loading_transition_covered.emit(request)
	)
	loading_transition_overlay.transition_finished.connect(
		func(request: Dictionary) -> void: loading_transition_finished.emit(request)
	)
	add_child(loading_transition_overlay)


func _build_right_utility_stack(root: Control) -> void:
	_add_top_right_fill(root, "ZoneFill", Rect2(-270, 34, 236, 86), "GothicArtPanelFill")
	_add_top_right_fill(root, "AutoFill", Rect2(-270, 142, 236, 40), "GothicArtToggleFill")
	_add_top_right_fill(root, "MapFill", Rect2(-270, 200, 106, 42), "GothicArtNavFill")
	_add_top_right_fill(root, "MenuFill", Rect2(-140, 200, 106, 42), "GothicArtToggleFill")
	_add_top_right_fill(root, "BagFill", Rect2(-270, 256, 106, 42), "GothicArtBagFill")
	_add_top_right_fill(root, "SkillFill", Rect2(-140, 256, 106, 42), "GothicArtBagFill")
	var stack_art := TextureRect.new()
	stack_art.name = "UtilityStackArt"
	stack_art.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stack_art.offset_left = -284
	stack_art.offset_top = 18
	stack_art.offset_right = -20
	stack_art.offset_bottom = 312
	stack_art.texture = HUDUtilityStackTexture
	stack_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stack_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stack_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack_art.set_meta("stable_id", "ui.hud.gothic.v2.utility_stack")
	root.add_child(stack_art)

	var zone_panel := Control.new()
	zone_panel.name = "ZonePanel"
	zone_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	zone_panel.offset_left = -274
	zone_panel.offset_top = 26
	zone_panel.offset_right = -30
	zone_panel.offset_bottom = 128
	root.add_child(zone_panel)
	var zone_label := Label.new()
	zone_label.name = "ZoneLabel"
	zone_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	zone_label.text = current_zone_name
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zone_label.add_theme_font_size_override("font_size", 16)
	zone_panel.add_child(zone_label)

	auto_target_button = _add_utility_button(root, "AutoTargetButton", "自动锁定：开", Rect2(-274, 136, 244, 52))
	auto_target_button.toggle_mode = true
	auto_target_button.button_pressed = true
	auto_target_button.toggled.connect(func(enabled: bool) -> void:
		auto_target_button.text = "自动锁定：开" if enabled else "自动锁定：关"
		auto_target_changed.emit(enabled)
	)

	var map_button := _add_utility_button(root, "MapButton", "地图", Rect2(-274, 193, 116, 56))
	map_button.pressed.connect(_toggle_map_panel)
	var menu_button := _add_utility_button(root, "MenuButton", "菜单", Rect2(-146, 193, 116, 56))
	menu_button.pressed.connect(_request_system_menu)
	var inventory_button := _add_utility_button(root, "InventoryButton", "背包", Rect2(-274, 249, 116, 56))
	inventory_button.pressed.connect(_toggle_inventory)
	var skill_book_button := _add_utility_button(root, "SkillBookButton", "技能", Rect2(-146, 249, 116, 56))
	skill_book_button.pressed.connect(_toggle_skill_book)


func _build_bottom_chassis(root: Control) -> void:
	var chassis_root := Control.new()
	chassis_root.name = "IntegratedHUDChassis"
	chassis_root.anchor_left = 0.5
	chassis_root.anchor_top = 1.0
	chassis_root.anchor_right = 0.5
	chassis_root.anchor_bottom = 1.0
	chassis_root.offset_left = -410
	chassis_root.offset_top = -273
	chassis_root.offset_right = 410
	chassis_root.offset_bottom = 0
	chassis_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chassis_root.set_meta("contents", ["health_orb", "four_item_slots", "mana_orb"])
	root.add_child(chassis_root)

	health_orb = HUDResourceOrbScript.new()
	health_orb.name = "HealthOrb"
	health_orb.position = HUD_HEALTH_ORB_CENTER - HUD_RESOURCE_ORB_SIZE * 0.5
	health_orb.size = HUD_RESOURCE_ORB_SIZE
	health_orb.resource_name = "生命"
	health_orb.liquid_color = Color("a51422")
	health_orb.set_meta("stable_id", "ui.hud.resource_orb.hole_fill.v1")
	chassis_root.add_child(health_orb)

	mana_orb = HUDResourceOrbScript.new()
	mana_orb.name = "ManaOrb"
	mana_orb.position = HUD_MANA_ORB_CENTER - HUD_RESOURCE_ORB_SIZE * 0.5
	mana_orb.size = HUD_RESOURCE_ORB_SIZE
	mana_orb.resource_name = "魔法"
	mana_orb.liquid_color = Color("174eaa")
	mana_orb.set_meta("stable_id", "ui.hud.resource_orb.hole_fill.v1")
	chassis_root.add_child(mana_orb)

	var chassis := TextureRect.new()
	chassis.name = "DemonChassisArt"
	chassis.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chassis.texture = HUDChassisTexture
	chassis.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chassis.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chassis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chassis.set_meta("stable_id", "ui.hud.gothic.v2.bottom_chassis")
	chassis_root.add_child(chassis)

	var item_x := [255.0, 337.0, 424.0, 508.0]
	for index in range(4):
		var item_button := Button.new()
		item_button.name = "ItemSlot%d" % (index + 1)
		item_button.theme_type_variation = "GothicItemButton"
		item_button.position = Vector2(item_x[index], 162)
		item_button.size = Vector2(62, 62)
		item_button.text = str(index + 1)
		item_button.tooltip_text = "快捷物品 %d" % (index + 1)
		item_button.add_theme_font_size_override("font_size", 15)
		item_button.set_meta("stable_id", "hud.item_slot.%d" % (index + 1))
		chassis_root.add_child(item_button)
		hud_item_buttons.append(item_button)


func _build_combat_controls(root: Control) -> void:
	var joystick_art := TextureRect.new()
	joystick_art.name = "JoystickArt"
	joystick_art.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick_art.offset_left = 34
	joystick_art.offset_top = -186
	joystick_art.offset_right = 186
	joystick_art.offset_bottom = -34
	joystick_art.texture = HUDJoystickTexture
	joystick_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	joystick_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	joystick_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick_art.set_meta("stable_id", "ui.hud.gothic.v2.joystick")
	root.add_child(joystick_art)

	var joystick := TouchJoystick.new()
	joystick.name = "TouchJoystick"
	joystick.radius = 58.0
	joystick.knob_radius = 24.0
	joystick.external_frame = true
	joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick.offset_left = 34
	joystick.offset_top = -186
	joystick.offset_right = 186
	joystick.offset_bottom = -34
	joystick.vector_changed.connect(func(value: Vector2) -> void: movement_changed.emit(value))
	root.add_child(joystick)

	for index in range(4):
		var skill_button := Button.new()
		skill_button.name = "SkillButton%d" % (index + 1)
		skill_button.theme_type_variation = "GothicTransparentButton"
		skill_button.anchor_left = 0.5
		skill_button.anchor_top = 1.0
		skill_button.anchor_right = 0.5
		skill_button.anchor_bottom = 1.0
		skill_button.offset_left = -209 + index * 108
		skill_button.offset_top = -252
		skill_button.offset_right = -109 + index * 108
		skill_button.offset_bottom = -180
		skill_button.add_theme_color_override("font_color", Color.TRANSPARENT)
		skill_button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
		skill_button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
		skill_button.pressed.connect(_on_skill_button.bind(index))
		skill_button.set_meta("stable_id", "hud.profession_skill.%d" % (index + 1))
		skill_button.set_meta("activation_mode_source", "skill.activation_mode")
		skill_button.set_meta("warrior_policy", "skill_data_declared")
		skill_button.set_meta("mage_tao_policy", "instant_or_toggle")
		root.add_child(skill_button)
		quick_buttons.append(skill_button)
		var disc := Panel.new()
		disc.name = "SkillDisc"
		disc.theme_type_variation = "GothicSkillDisc"
		disc.position = Vector2(14, 0)
		disc.size = Vector2(72, 72)
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill_button.add_child(disc)
		var skill_icon := TextureRect.new()
		skill_icon.name = "SkillIcon"
		skill_icon.position = Vector2(6, 6)
		skill_icon.size = Vector2(60, 60)
		skill_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		skill_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		skill_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill_icon.set_meta("icon_source", "quick_slot")
		disc.add_child(skill_icon)
		quick_slot_icons.append(skill_icon)
		var skill_label := Label.new()
		skill_label.name = "SkillLabel"
		skill_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
		skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		skill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		skill_label.add_theme_font_size_override("font_size", 12)
		skill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(skill_label)
		quick_slot_labels.append(skill_label)

	warrior_state_label = Label.new()
	warrior_state_label.name = "WarriorStateLabel"
	warrior_state_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	warrior_state_label.offset_left = 350
	warrior_state_label.offset_top = -294
	warrior_state_label.offset_right = -350
	warrior_state_label.offset_bottom = -266
	warrior_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warrior_state_label.add_theme_font_size_override("font_size", 15)
	warrior_state_label.add_theme_color_override("font_color", Color("efbd70"))
	root.add_child(warrior_state_label)

	_add_bottom_right_fill(root, "InteractFill", Rect2(-100, -385, 52, 52), "GothicArtCircleFill")
	_add_bottom_right_fill(root, "SwitchTargetFill", Rect2(-100, -307, 52, 52), "GothicArtCircleFill")
	_add_bottom_right_fill(root, "AttackFill", Rect2(-181, -161, 120, 120), "GothicArtAttackFill")
	var right_controls_art := TextureRect.new()
	right_controls_art.name = "RightControlsArt"
	right_controls_art.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right_controls_art.offset_left = -277
	right_controls_art.offset_top = -400
	right_controls_art.offset_right = -20
	right_controls_art.offset_bottom = 0
	right_controls_art.texture = HUDRightControlsTexture
	right_controls_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	right_controls_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right_controls_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_controls_art.set_meta("stable_id", "ui.hud.gothic.v2.right_controls")
	root.add_child(right_controls_art)

	var interact_button := Button.new()
	interact_button.name = "InteractButton"
	interact_button.theme_type_variation = "GothicTransparentButton"
	interact_button.text = "交互"
	interact_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	interact_button.offset_left = -129
	interact_button.offset_top = -404
	interact_button.offset_right = -19
	interact_button.offset_bottom = -314
	interact_button.add_theme_font_size_override("font_size", 17)
	interact_button.button_down.connect(func() -> void: interact_pressed.emit())
	root.add_child(interact_button)

	var switch_target_button := Button.new()
	switch_target_button.name = "SwitchTargetButton"
	switch_target_button.theme_type_variation = "GothicTransparentButton"
	switch_target_button.text = "换敌"
	switch_target_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	switch_target_button.offset_left = -129
	switch_target_button.offset_top = -326
	switch_target_button.offset_right = -19
	switch_target_button.offset_bottom = -236
	switch_target_button.add_theme_font_size_override("font_size", 16)
	switch_target_button.pressed.connect(func() -> void: target_switch_pressed.emit())
	root.add_child(switch_target_button)

	var attack_button := Button.new()
	attack_button.name = "AttackButton"
	attack_button.theme_type_variation = "GothicTransparentButton"
	attack_button.text = "攻击"
	attack_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	attack_button.offset_left = -181
	attack_button.offset_top = -161
	attack_button.offset_right = -61
	attack_button.offset_bottom = -41
	attack_button.add_theme_font_size_override("font_size", 24)
	attack_button.button_down.connect(func() -> void: attack_pressed.emit())
	attack_button.button_up.connect(func() -> void: attack_released.emit())
	root.add_child(attack_button)

	# The three generated apertures share a consistent -11/-10 correction
	# relative to the original touch mockup. Keep the 72px hit areas intact.
	var ring_positions := [Rect2(-273, -107, 72, 72), Rect2(-255, -211, 72, 72), Rect2(-184, -262, 72, 72)]
	for index in range(3):
		var ring_skill := Button.new()
		ring_skill.name = "AttackRingSkill%d" % (index + 1)
		ring_skill.theme_type_variation = "GothicTransparentButton"
		ring_skill.text = ""
		ring_skill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		var rect: Rect2 = ring_positions[index]
		ring_skill.offset_left = rect.position.x
		ring_skill.offset_top = rect.position.y
		ring_skill.offset_right = rect.end.x
		ring_skill.offset_bottom = rect.end.y
		ring_skill.pressed.connect(_on_skill_button.bind(index))
		ring_skill.set_meta("stable_id", "hud.attack_ring_skill.%d" % (index + 1))
		root.add_child(ring_skill)
		var ring_backdrop := Panel.new()
		ring_backdrop.name = "SkillBackdrop"
		ring_backdrop.theme_type_variation = "GothicArtCircleFill"
		ring_backdrop.position = Vector2(10, 10)
		ring_backdrop.size = Vector2(52, 52)
		ring_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring_skill.add_child(ring_backdrop)
		var ring_icon := TextureRect.new()
		ring_icon.name = "SkillIcon"
		ring_icon.position = Vector2(8, 8)
		ring_icon.size = Vector2(56, 56)
		ring_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ring_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring_icon.set_meta("icon_source", "quick_slot")
		ring_skill.add_child(ring_icon)
		attack_ring_skill_icons.append(ring_icon)
		var ring_label := Label.new()
		ring_label.name = "SkillLabel"
		ring_label.position = Vector2(4, 4)
		ring_label.size = Vector2(64, 64)
		ring_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ring_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		ring_label.add_theme_font_size_override("font_size", 13)
		ring_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring_skill.add_child(ring_label)
		attack_ring_skill_labels.append(ring_label)

	special_action_button = Button.new()
	special_action_button.name = "SpecialActionButton"
	special_action_button.theme_type_variation = "GothicUtilityButton"
	special_action_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	special_action_button.offset_left = -354
	special_action_button.offset_top = -342
	special_action_button.offset_right = -236
	special_action_button.offset_bottom = -278
	special_action_button.visible = false
	special_action_button.pressed.connect(_on_special_action_button)
	root.add_child(special_action_button)


func _build_modal_panels(root: Control) -> void:
	inventory_panel = InventoryPanel.new()
	inventory_panel.hide()
	root.add_child(inventory_panel)
	shop_panel = ShopPanel.new()
	shop_panel.hide()
	root.add_child(shop_panel)
	skill_panel = SkillPanel.new()
	skill_panel.hide()
	skill_panel.quick_slot_assignment_requested.connect(
		func(request: Dictionary) -> void: skill_quick_slot_assignment_requested.emit(request)
	)
	skill_panel.skill_button_assignment_requested.connect(
		func(request: Dictionary) -> void: skill_button_assignment_requested.emit(request)
	)
	root.add_child(skill_panel)
	quest_panel = QuestPanel.new()
	quest_panel.hide()
	root.add_child(quest_panel)
	profession_panel = ProfessionPanel.new()
	profession_panel.hide()
	root.add_child(profession_panel)
	map_panel = MapPanel.new()
	map_panel.hide()
	map_panel.map_selected.connect(func(map_id: int) -> void: map_travel_requested.emit(map_id))
	map_panel.teleport_requested.connect(func(request: Dictionary) -> void: map_teleport_requested.emit(request))
	map_panel.teleport_availability_requested.connect(
		func(map_ids: Array) -> void: map_teleport_availability_requested.emit(map_ids)
	)
	root.add_child(map_panel)
	warehouse_panel = WarehousePanel.new()
	warehouse_panel.hide()
	root.add_child(warehouse_panel)
	death_revival_panel = DeathRevivalPanelScript.new()
	death_revival_panel.hide()
	death_revival_panel.revival_requested.connect(
		func(request: Dictionary) -> void: revival_requested.emit(request)
	)
	root.add_child(death_revival_panel)


func _add_utility_button(root: Control, node_name: String, label_text: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label_text
	button.theme_type_variation = "GothicTransparentButton"
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = rect.position.x
	button.offset_top = rect.position.y
	button.offset_right = rect.end.x
	button.offset_bottom = rect.end.y
	button.add_theme_font_size_override("font_size", 16)
	root.add_child(button)
	return button


func _add_full_texture(parent: Control, node_name: String, texture: Texture2D) -> TextureRect:
	var art := TextureRect.new()
	art.name = node_name
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	return art


func _add_top_right_fill(root: Control, node_name: String, rect: Rect2, variation: StringName) -> Panel:
	var fill := Panel.new()
	fill.name = node_name
	fill.theme_type_variation = variation
	fill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fill.offset_left = rect.position.x
	fill.offset_top = rect.position.y
	fill.offset_right = rect.end.x
	fill.offset_bottom = rect.end.y
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	return fill


func _add_bottom_right_fill(root: Control, node_name: String, rect: Rect2, variation: StringName) -> Panel:
	var fill := Panel.new()
	fill.name = node_name
	fill.theme_type_variation = variation
	fill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fill.offset_left = rect.position.x
	fill.offset_top = rect.position.y
	fill.offset_right = rect.end.x
	fill.offset_bottom = rect.end.y
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	return fill


func _request_system_menu() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)


func _toggle_skill_book() -> void:
	if skill_panel.visible:
		skill_panel.hide()
	else:
		_close_modal_panels()
		skill_panel.open_for("技能导师")


func _process(delta: float) -> void:
	_loot_message_timer = maxf(0.0, _loot_message_timer - delta)
	if _loot_message_timer == 0.0 and loot_label != null:
		loot_label.text = ""


func update_hp(current_hp: int, max_hp: int) -> void:
	_last_hp = current_hp
	_last_max_hp = max_hp
	update_resources(_last_hp, _last_max_hp, _last_mp, _last_max_mp)


func update_resources(current_hp: int, max_hp: int, current_mp: int, max_mp: int) -> void:
	_last_hp = current_hp
	_last_max_hp = max_hp
	_last_mp = current_mp
	_last_max_mp = max_mp
	if hp_label != null:
		hp_label.text = "%s｜生命 %d/%d　魔法 %d/%d" % [current_zone_name, current_hp, max_hp, current_mp, max_mp]
	if health_orb != null:
		health_orb.call("set_values", current_hp, max_hp)
	if mana_orb != null:
		mana_orb.call("set_values", current_mp, max_mp)


func update_target(target_name := "", current_hp := 0, max_hp := 0, manual_lock := false, auto_enabled := true) -> void:
	if target_label == null:
		return
	if target_health_fill != null:
		target_health_fill.visible = not target_name.is_empty() and max_hp > 0
		target_health_fill.size.x = 320.0 * clampf(float(current_hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	var next_text := "目标：自动选敌待命" if auto_enabled else "目标：手动模式待选择"
	if not target_name.is_empty():
		next_text = "目标［%s］：%s　%d/%d" % ["自动" if auto_enabled else "手动", target_name, current_hp, max_hp]
	if next_text == _last_target_text:
		return
	_last_target_text = next_text
	target_label.text = next_text


func set_auto_target_enabled(enabled: bool) -> void:
	if auto_target_button == null:
		return
	auto_target_button.set_pressed_no_signal(enabled)
	auto_target_button.text = "自动锁定：开" if enabled else "自动锁定：关"


func show_loot(item_name: String) -> void:
	show_loot_feedback({
		"event_type": "pickup_success",
		"item_name": item_name,
		"count": 1,
		"item_kind": GameData.get_item_kind(item_name),
		"emphasis": "normal",
	})


func show_loot_feedback(event: Dictionary) -> void:
	if loot_feedback_layer != null:
		loot_feedback_layer.show_feedback(event)


func begin_loading_transition(transition_id := "") -> void:
	if loading_transition_overlay != null:
		loading_transition_overlay.begin_loading(transition_id)


func finish_loading_transition() -> void:
	if loading_transition_overlay != null:
		loading_transition_overlay.finish_loading()


func update_profile() -> void:
	if profile_label == null:
		return
	var stats: Dictionary = PlayerState.computed_stats
	profile_label.text = "%s  等级%d  经验%d/%d  金币%d  攻%d-%d 魔%d-%d 道%d-%d" % [
		PlayerState.profession, PlayerState.level, PlayerState.experience, PlayerState.experience_to_next_level(), PlayerState.gold,
		int(stats.get("attack_min", 2)), int(stats.get("attack_max", 5)),
		int(stats.get("magic_min", 0)), int(stats.get("magic_max", 0)),
		int(stats.get("tao_min", 0)), int(stats.get("tao_max", 0)),
	]


func update_quest_tracker() -> void:
	if quest_tracker_label == null:
		return
	var quest_id := PlayerState.current_bich_quest_id()
	if quest_id.is_empty():
		quest_tracker_label.text = "比奇主线：全部完成"
		return
	var quest := GameData.get_bich_quest(quest_id)
	var accepted := PlayerState.quest_states.has(quest_id)
	var state: Dictionary = PlayerState.quest_states.get(quest_id, {})
	var marker := "可接" if not accepted else ("可领取" if str(state.get("status", "")) == "ready" else "进行中")
	quest_tracker_label.text = "任务[%s] %s｜%s" % [marker, quest.get("name", quest_id), "；".join(PlayerState.quest_objective_lines(quest_id))]


func update_special_actions() -> void:
	if special_action_button == null:
		return
	_special_actions = PlayerState.available_special_actions()
	if _special_actions.is_empty():
		_special_action_index = 0
		special_action_button.visible = false
		return
	_special_action_index = posmod(_special_action_index, _special_actions.size())
	special_action_button.visible = true
	special_action_button.text = "特装\n%s" % EquipmentRulesScript.special_action_label(_special_actions[_special_action_index])


func _on_special_action_button() -> void:
	if _special_actions.is_empty():
		return
	var effect_id := _special_actions[_special_action_index]
	special_action_pressed.emit(effect_id)
	if _special_actions.size() > 1:
		_special_action_index = (_special_action_index + 1) % _special_actions.size()
		update_special_actions()


func _toggle_inventory() -> void:
	if inventory_panel.visible:
		inventory_panel.hide()
	else:
		_close_modal_panels()
		inventory_panel.refresh()
		inventory_panel.show()


func _toggle_profession() -> void:
	if profession_panel.visible:
		profession_panel.hide()
	else:
		_close_modal_panels()
		profession_panel.refresh()
		profession_panel.show()


func _toggle_map_panel() -> void:
	if map_panel.visible:
		map_panel.hide()
	else:
		_close_modal_panels()
		map_panel.open_panel()


func set_map_teleport_availability(rules: Dictionary) -> void:
	if map_panel != null:
		map_panel.set_teleport_availability(rules)


func set_zone_name(zone_name: String) -> void:
	current_zone_name = zone_name
	if hp_label != null:
		hp_label.text = "%s｜生命" % current_zone_name
	var safe_root := get_node_or_null("MobileSafeRoot")
	if safe_root != null:
		var zone_label := safe_root.get_node_or_null("ZonePanel/ZoneLabel") as Label
		if zone_label != null:
			zone_label.text = current_zone_name


func open_shop(display_name: String, stock: Array) -> void:
	_close_modal_panels()
	shop_panel.open_for(display_name, stock)


func open_skill_trainer(display_name: String) -> void:
	_close_modal_panels()
	skill_panel.open_for(display_name)


func set_skill_button_assignments(assignments: Dictionary, interaction_modes := {}) -> void:
	if skill_panel != null:
		skill_panel.set_skill_button_assignments(assignments, interaction_modes)


func show_death_screen(context := {}) -> void:
	_close_modal_panels()
	if death_revival_panel != null:
		death_revival_panel.open_death_screen(context)


func set_revival_options(options: Array) -> void:
	if death_revival_panel != null:
		death_revival_panel.set_revival_options(options)


func update_revival_option(option_slot: String, state: Dictionary) -> void:
	if death_revival_panel != null:
		death_revival_panel.update_revival_option(option_slot, state)


func apply_revival_result(result: Dictionary) -> void:
	if death_revival_panel != null:
		death_revival_panel.apply_revival_result(result)


func close_death_screen() -> void:
	if death_revival_panel != null:
		death_revival_panel.close_death_screen()


func open_quest(display_name: String) -> void:
	_close_modal_panels()
	quest_panel.open_for(display_name)


func open_warehouse() -> void:
	_close_modal_panels()
	warehouse_panel.open_panel()


func show_message(message: String, seconds := 2.0) -> void:
	if loot_label != null:
		loot_label.text = message
		_loot_message_timer = seconds


func update_quick_slots() -> void:
	for index in range(quick_buttons.size()):
		var skill_name := PlayerState.quick_slots[index]
		var marker := _warrior_skill_marker(skill_name)
		var skill_texture := HUDSkillIconCatalogScript.texture_for(skill_name)
		var skill_icon_id := HUDSkillIconCatalogScript.source_id_for(skill_name)
		var skill_icon_path := HUDSkillIconCatalogScript.source_path_for(skill_name)
		var display_text := "%d\n%s%s" % [index + 1, skill_name if not skill_name.is_empty() else "空", marker]
		quick_buttons[index].text = display_text
		quick_buttons[index].tooltip_text = skill_name if not skill_name.is_empty() else "空技能槽"
		if index < quick_slot_icons.size():
			quick_slot_icons[index].texture = skill_texture
			quick_slot_icons[index].visible = skill_texture != null
			quick_slot_icons[index].set_meta("skill_name", skill_name)
			quick_slot_icons[index].set_meta("skill_icon_id", skill_icon_id)
			quick_slot_icons[index].set_meta("skill_icon_path", skill_icon_path)
		if index < quick_slot_labels.size():
			quick_slot_labels[index].text = _compact_skill_label(index, skill_name, marker, skill_texture != null)
		if index < attack_ring_skill_icons.size():
			attack_ring_skill_icons[index].texture = skill_texture
			attack_ring_skill_icons[index].visible = skill_texture != null
			attack_ring_skill_icons[index].set_meta("skill_name", skill_name)
			attack_ring_skill_icons[index].set_meta("skill_icon_id", skill_icon_id)
			attack_ring_skill_icons[index].set_meta("skill_icon_path", skill_icon_path)
		if index < attack_ring_skill_labels.size():
			attack_ring_skill_labels[index].text = str(index + 1) if skill_texture != null else "技%d" % (index + 1)
			attack_ring_skill_labels[index].tooltip_text = skill_name


func _compact_skill_label(index: int, skill_name: String, marker: String, has_icon: bool) -> String:
	var compact_name := "空" if skill_name.is_empty() else skill_name.left(2)
	var compact_marker := marker.trim_prefix("[").trim_suffix("]")
	if has_icon:
		return "%d%s" % [index + 1, "\n%s" % compact_marker if not compact_marker.is_empty() else ""]
	return "%d\n%s%s" % [index + 1, compact_name, "\n%s" % compact_marker if not compact_marker.is_empty() else ""]


func update_warrior_states(snapshot: Dictionary) -> void:
	_warrior_snapshot = snapshot.duplicate(true)
	if warrior_state_label == null:
		return
	warrior_state_label.visible = PlayerState.profession == "战士"
	if not warrior_state_label.visible:
		return
	var fire_text := _fire_sword_charge_label(snapshot)
	warrior_state_label.text = "攻杀:%s　刺杀:%s　半月:%s　烈火:%s" % [
		"自动" if bool(snapshot.get("slaying_auto", false)) else "未学",
		"开" if bool(snapshot.get("thrusting", false)) else "关",
		"开" if bool(snapshot.get("half_moon", false)) else "关",
		fire_text,
	]
	update_quick_slots()


func _fire_sword_charge_label(snapshot: Dictionary) -> String:
	# Canonical fire sword is one explicit next-melee charge, never an auto-use toggle.
	# The runtime snapshot owns these fields; UI only projects its current state.
	if bool(snapshot.get("fire_armed", false)) and int(snapshot.get("fire_expires_remaining_ms", 0)) > 0:
		return "充能"
	return "未充能·就绪"


func _warrior_skill_marker(skill_name: String) -> String:
	match skill_name:
		"攻杀剑术": return "[自动]" if bool(_warrior_snapshot.get("slaying_auto", false)) else ""
		"刺杀剑术": return "[开]" if bool(_warrior_snapshot.get("thrusting", false)) else "[关]"
		"半月弯刀": return "[开]" if bool(_warrior_snapshot.get("half_moon", false)) else "[关]"
		"烈火剑法":
			return "[%s]" % _fire_sword_charge_label(_warrior_snapshot)
	return ""


func _on_skill_button(index: int) -> void:
	skill_pressed.emit(index)


func _close_modal_panels() -> void:
	if inventory_panel != null:
		inventory_panel.hide()
	if shop_panel != null:
		shop_panel.hide()
	if skill_panel != null:
		skill_panel.hide()
	if quest_panel != null:
		quest_panel.hide()
	if profession_panel != null:
		profession_panel.hide()
	if map_panel != null:
		map_panel.hide()
	if warehouse_panel != null:
		warehouse_panel.hide()
