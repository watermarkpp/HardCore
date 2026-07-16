class_name GameHUD
extends CanvasLayer

const MobileLayoutRules := preload("res://scripts/mobile_layout.gd")
const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")

signal movement_changed(value: Vector2)
signal attack_pressed
signal attack_released
signal interact_pressed
signal skill_pressed(slot_index: int)
signal map_travel_requested(map_id: int)
signal target_switch_pressed
signal auto_target_changed(enabled: bool)
signal special_action_pressed(effect_id: String)

var hp_label: Label
var data_label: Label
var profile_label: Label
var quest_tracker_label: Label
var loot_label: Label
var target_label: Label
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
var quick_buttons: Array[Button] = []
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
	var root := Control.new()
	root.name = "MobileSafeRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	MobileLayoutRules.apply_display_safe_area(root, get_viewport())
	get_viewport().size_changed.connect(MobileLayoutRules.apply_display_safe_area.bind(root, get_viewport()))

	var top_panel := ColorRect.new()
	top_panel.name = "TopInfoPanel"
	top_panel.color = Color(0.08, 0.035, 0.025, 0.82)
	top_panel.position = Vector2(20, 18)
	top_panel.size = Vector2(770, 158)
	# Map/player summary is intentionally removed from the gameplay HUD. Player
	# health remains attached to the actor in world space, while detailed stats
	# live in the dedicated character panel.
	top_panel.visible = false
	root.add_child(top_panel)

	hp_label = Label.new()
	hp_label.text = "比奇郊外｜生命 120 / 120"
	hp_label.position = Vector2(18, 10)
	hp_label.add_theme_font_size_override("font_size", 22)
	hp_label.add_theme_color_override("font_color", Color(0.98, 0.76, 0.53))
	top_panel.add_child(hp_label)

	data_label = Label.new()
	data_label.text = GameData.summary_text()
	data_label.position = Vector2(18, 44)
	data_label.add_theme_font_size_override("font_size", 14)
	data_label.add_theme_color_override("font_color", Color(0.84, 0.77, 0.67))
	top_panel.add_child(data_label)

	profile_label = Label.new()
	profile_label.position = Vector2(18, 70)
	profile_label.add_theme_font_size_override("font_size", 15)
	profile_label.add_theme_color_override("font_color", Color(0.82, 0.73, 0.60))
	top_panel.add_child(profile_label)

	quest_tracker_label = Label.new()
	quest_tracker_label.name = "QuestTracker"
	quest_tracker_label.position = Vector2(18, 96)
	quest_tracker_label.size = Vector2(734, 54)
	quest_tracker_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_tracker_label.add_theme_font_size_override("font_size", 14)
	quest_tracker_label.add_theme_color_override("font_color", Color(0.96, 0.83, 0.46))
	top_panel.add_child(quest_tracker_label)

	loot_label = Label.new()
	loot_label.position = Vector2(0, 164)
	loot_label.size = Vector2(1280, 40)
	loot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loot_label.add_theme_font_size_override("font_size", 24)
	loot_label.add_theme_color_override("font_color", Color(1.0, 0.83, 0.30))
	root.add_child(loot_label)

	var joystick := TouchJoystick.new()
	joystick.name = "TouchJoystick"
	joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick.offset_left = 34
	joystick.offset_top = -194
	joystick.offset_right = 194
	joystick.offset_bottom = -34
	joystick.vector_changed.connect(func(value: Vector2) -> void: movement_changed.emit(value))
	root.add_child(joystick)

	var attack_button := Button.new()
	attack_button.name = "AttackButton"
	attack_button.text = "攻击"
	attack_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	attack_button.offset_left = -186
	attack_button.offset_top = -174
	attack_button.offset_right = -42
	attack_button.offset_bottom = -30
	attack_button.add_theme_font_size_override("font_size", 28)
	attack_button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.60))
	attack_button.modulate = Color(0.92, 0.78, 0.64, 0.92)
	attack_button.mouse_filter = Control.MOUSE_FILTER_STOP
	attack_button.button_down.connect(func() -> void: attack_pressed.emit())
	attack_button.button_up.connect(func() -> void: attack_released.emit())
	root.add_child(attack_button)

	var interact_button := Button.new()
	interact_button.name = "InteractButton"
	interact_button.text = "交互"
	interact_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	interact_button.offset_left = -340
	interact_button.offset_top = -142
	interact_button.offset_right = -216
	interact_button.offset_bottom = -30
	interact_button.add_theme_font_size_override("font_size", 23)
	interact_button.button_down.connect(func() -> void: interact_pressed.emit())
	root.add_child(interact_button)

	var hint := Label.new()
	hint.name = "DesktopHint"
	hint.text = "电脑：WASD移动，E交互，空格攻击，1-4技能"
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -370
	hint.offset_top = 24
	hint.offset_right = -20
	hint.offset_bottom = 56
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", Color(0.76, 0.70, 0.61))
	hint.visible = not OS.has_feature("mobile")
	root.add_child(hint)

	target_label = Label.new()
	target_label.text = "目标：自动选敌待命"
	target_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	target_label.offset_left = -420
	target_label.offset_top = 62
	target_label.offset_right = -20
	target_label.offset_bottom = 98
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	target_label.add_theme_font_size_override("font_size", 18)
	target_label.add_theme_color_override("font_color", Color(1.0, 0.79, 0.28))
	root.add_child(target_label)

	var switch_target_button := Button.new()
	switch_target_button.name = "SwitchTargetButton"
	switch_target_button.text = "换敌"
	switch_target_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	switch_target_button.offset_left = -340
	switch_target_button.offset_top = -210
	switch_target_button.offset_right = -216
	switch_target_button.offset_bottom = -150
	switch_target_button.add_theme_font_size_override("font_size", 20)
	switch_target_button.pressed.connect(func() -> void: target_switch_pressed.emit())
	root.add_child(switch_target_button)

	auto_target_button = Button.new()
	auto_target_button.name = "AutoTargetButton"
	auto_target_button.text = "自动：开"
	auto_target_button.toggle_mode = true
	auto_target_button.button_pressed = true
	auto_target_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	auto_target_button.offset_left = -186
	auto_target_button.offset_top = -236
	auto_target_button.offset_right = -42
	auto_target_button.offset_bottom = -182
	auto_target_button.add_theme_font_size_override("font_size", 18)
	auto_target_button.toggled.connect(func(enabled: bool) -> void:
		auto_target_button.text = "自动：开" if enabled else "自动：关"
		auto_target_changed.emit(enabled)
	)
	root.add_child(auto_target_button)

	special_action_button = Button.new()
	special_action_button.name = "SpecialActionButton"
	special_action_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	special_action_button.offset_left = -340
	special_action_button.offset_top = -280
	special_action_button.offset_right = -216
	special_action_button.offset_bottom = -218
	special_action_button.add_theme_font_size_override("font_size", 18)
	special_action_button.visible = false
	special_action_button.pressed.connect(_on_special_action_button)
	root.add_child(special_action_button)

	for index in range(4):
		var skill_button := Button.new()
		skill_button.name = "SkillButton%d" % (index + 1)
		skill_button.anchor_left = 0.5
		skill_button.anchor_top = 1.0
		skill_button.anchor_right = 0.5
		skill_button.anchor_bottom = 1.0
		skill_button.offset_left = -246 + index * 122
		skill_button.offset_top = -86
		skill_button.offset_right = -136 + index * 122
		skill_button.offset_bottom = -22
		skill_button.add_theme_font_size_override("font_size", 15)
		skill_button.pressed.connect(_on_skill_button.bind(index))
		root.add_child(skill_button)
		quick_buttons.append(skill_button)

	warrior_state_label = Label.new()
	warrior_state_label.name = "WarriorStateLabel"
	warrior_state_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	warrior_state_label.offset_left = 330
	warrior_state_label.offset_top = -132
	warrior_state_label.offset_right = -330
	warrior_state_label.offset_bottom = -96
	warrior_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warrior_state_label.add_theme_font_size_override("font_size", 17)
	warrior_state_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.30))
	warrior_state_label.add_theme_color_override("font_shadow_color", Color(0.08, 0.03, 0.01, 0.95))
	warrior_state_label.add_theme_constant_override("shadow_offset_x", 2)
	warrior_state_label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(warrior_state_label)

	var inventory_button := Button.new()
	inventory_button.text = "背包"
	inventory_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	inventory_button.offset_left = -158
	inventory_button.offset_top = 68
	inventory_button.offset_right = -24
	inventory_button.offset_bottom = 118
	inventory_button.add_theme_font_size_override("font_size", 20)
	inventory_button.pressed.connect(_toggle_inventory)
	root.add_child(inventory_button)

	var profession_button := Button.new()
	profession_button.text = "职业"
	profession_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	profession_button.offset_left = -300
	profession_button.offset_top = 68
	profession_button.offset_right = -166
	profession_button.offset_bottom = 118
	profession_button.add_theme_font_size_override("font_size", 20)
	profession_button.pressed.connect(_toggle_profession)
	root.add_child(profession_button)

	var map_button := Button.new()
	map_button.text = "地图"
	map_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map_button.offset_left = -442
	map_button.offset_top = 68
	map_button.offset_right = -308
	map_button.offset_bottom = 118
	map_button.add_theme_font_size_override("font_size", 20)
	map_button.pressed.connect(_toggle_map_panel)
	root.add_child(map_button)

	inventory_panel = InventoryPanel.new()
	inventory_panel.hide()
	root.add_child(inventory_panel)
	shop_panel = ShopPanel.new()
	shop_panel.hide()
	root.add_child(shop_panel)
	skill_panel = SkillPanel.new()
	skill_panel.hide()
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
	root.add_child(map_panel)
	warehouse_panel = WarehousePanel.new()
	warehouse_panel.hide()
	root.add_child(warehouse_panel)
	PlayerState.profile_changed.connect(update_profile)
	PlayerState.quests_changed.connect(update_quest_tracker)
	PlayerState.profile_changed.connect(update_special_actions)
	PlayerState.skills_changed.connect(update_quick_slots)
	update_profile()
	update_quest_tracker()
	update_special_actions()
	update_quick_slots()


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


func update_target(target_name := "", current_hp := 0, max_hp := 0, manual_lock := false, auto_enabled := true) -> void:
	if target_label == null:
		return
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
	auto_target_button.text = "自动：开" if enabled else "自动：关"


func show_loot(item_name: String) -> void:
	if loot_label != null:
		loot_label.text = "获得：%s" % item_name
		_loot_message_timer = 2.0


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


func set_zone_name(zone_name: String) -> void:
	current_zone_name = zone_name
	if hp_label != null:
		hp_label.text = "%s｜生命" % current_zone_name


func open_shop(display_name: String, stock: Array) -> void:
	_close_modal_panels()
	shop_panel.open_for(display_name, stock)


func open_skill_trainer(display_name: String) -> void:
	_close_modal_panels()
	skill_panel.open_for(display_name)


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
		quick_buttons[index].text = "%d\n%s%s" % [index + 1, skill_name if not skill_name.is_empty() else "空", marker]


func update_warrior_states(snapshot: Dictionary) -> void:
	_warrior_snapshot = snapshot.duplicate(true)
	if warrior_state_label == null:
		return
	warrior_state_label.visible = PlayerState.profession == "战士"
	if not warrior_state_label.visible:
		return
	var fire_text := "蓄力" if bool(snapshot.get("fire_armed", false)) else "就绪"
	var ready_ms := int(snapshot.get("fire_ready_remaining_ms", 0))
	if not bool(snapshot.get("fire_armed", false)) and ready_ms > 0:
		fire_text = "冷却%.1fs" % (float(ready_ms) / 1000.0)
	warrior_state_label.text = "攻杀:%s　刺杀:%s　半月:%s　烈火:%s" % [
		"自动" if bool(snapshot.get("slaying_auto", false)) else "未学",
		"开" if bool(snapshot.get("thrusting", false)) else "关",
		"开" if bool(snapshot.get("half_moon", false)) else "关",
		fire_text,
	]
	update_quick_slots()


func _warrior_skill_marker(skill_name: String) -> String:
	match skill_name:
		"攻杀剑术": return "[自动]" if bool(_warrior_snapshot.get("slaying_auto", false)) else ""
		"刺杀剑术": return "[开]" if bool(_warrior_snapshot.get("thrusting", false)) else "[关]"
		"半月弯刀": return "[开]" if bool(_warrior_snapshot.get("half_moon", false)) else "[关]"
		"烈火剑法":
			if bool(_warrior_snapshot.get("fire_armed", false)):
				return "[蓄]"
			if int(_warrior_snapshot.get("fire_ready_remaining_ms", 0)) > 0:
				return "[冷]"
			return "[就绪]"
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
