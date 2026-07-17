extends Node

const CAPTURES := [
	"res://outputs/visual_acceptance/ui_gothic_preview/character_select_create.png",
	"res://outputs/visual_acceptance/ui_gothic_preview/in_game_exit_menu.png",
	"res://outputs/visual_acceptance/ui_gothic_preview/in_game_hud.png",
	"res://outputs/visual_acceptance/ui_gothic_preview/skill_assignment_page.png",
]


func _ready() -> void:
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/brand_intro.tscn", "审图样板不得替换正式入口")
	var character_select_source := FileAccess.get_file_as_string("res://scenes/character_select.tscn")
	assert(not "ui_gothic_preview" in character_select_source, "审图样板被提前接入人物选择界面")
	var preview_source := FileAccess.get_file_as_string("res://tests/ui_gothic_preview.gd")
	var runtime_icon_manifest_source := FileAccess.get_file_as_string("res://assets/ui/gothic_preview/icons/runtime_v2/runtime_icon_manifest.json")
	var runtime_icon_manifest = JSON.parse_string(runtime_icon_manifest_source)
	assert(runtime_icon_manifest is Dictionary and str(runtime_icon_manifest.get("policy", "")) == "source_pixels_cover_frame_aperture_no_matting", "HUD运行图标来源清单无效")
	assert("_resource_orb" in preview_source, "人物资源球未建立")
	assert("半兽勇士" in preview_source and "_bar(target" in preview_source, "怪物目标血条未保留")
	assert(not "_bar(player_card" in preview_source, "人物横向血条仍残留在HUD")
	assert(not "var player_card :=" in preview_source, "左上人物名称等级卡片仍残留")
	assert(not "当前追踪" in preview_source, "当前追踪面板仍残留")
	assert(not "快捷栏" in preview_source, "旧式大快捷栏仍显示在HUD")
	assert("long_press_action" in preview_source and "open_item_picker" in preview_source, "四格战斗物品栏缺少长按选物交互")
	assert("普通攻击" in preview_source and "select_attack_cast" in preview_source, "法师/道士缺少普通攻击与技能选择模式")
	assert("toggle_auto_target_lock" in preview_source and "switch_target" in preview_source, "切换敌人或自动锁定控制缺失")
	assert("choose_quick_skill_slot" in preview_source and "SkillAssignmentPopup" in preview_source, "技能页面长按分配流程缺失")
	OS.set_environment("UI_PREVIEW_MODE", "hud")
	var preview: Control = load("res://tests/ui_gothic_preview.tscn").instantiate()
	add_child(preview)
	await get_tree().process_frame
	var warrior_toggles := get_tree().get_nodes_in_group("warrior_auto_skill_toggle")
	assert(warrior_toggles.size() == 3, "战士自动开关技能数量不是3")
	var gothic_frames := get_tree().get_nodes_in_group("clean_gothic_console")
	var bottom_chassis := get_tree().get_nodes_in_group("gothic_bottom_hud_chassis")
	var resource_orbs := get_tree().get_nodes_in_group("player_resource_orb")
	assert(gothic_frames.is_empty(), "中央金色大外框仍然存在")
	assert(bottom_chassis.size() == 1 and resource_orbs.size() == 2, "下方哥特美术骨架或生命/魔法球数量错误")
	var chassis := bottom_chassis[0] as Control
	assert(not bool(chassis.get_meta("central_outer_box", true)), "下方美术骨架错误包含中央大外框")
	assert(str(chassis.get_meta("frame_source", "")) == "res://assets/ui/gothic_preview/frames/bottom_hud_chassis_runtime_v1.png", "下方骨架没有使用生成美术素材")
	var geometry_source := FileAccess.get_file_as_string("res://assets/ui/gothic_preview/frames/gothic_hud_frame_geometry_v2.json")
	var frame_geometry = JSON.parse_string(geometry_source)
	assert(frame_geometry is Dictionary, "HUD图框几何清单无法读取")
	var chassis_geometry: Dictionary = frame_geometry.get("bottomChassis", {})
	var chassis_source_size_array: Array = chassis_geometry.get("size", [1, 1])
	var chassis_source_size := Vector2(float(chassis_source_size_array[0]), float(chassis_source_size_array[1]))
	var chassis_scale := chassis.size / chassis_source_size
	var health_orb: Control
	var mana_orb: Control
	for orb: Node in resource_orbs:
		if str(orb.get_meta("resource_type", "")) == "health":
			health_orb = orb as Control
		elif str(orb.get_meta("resource_type", "")) == "mana":
			mana_orb = orb as Control
	assert(health_orb != null and mana_orb != null, "生命球或魔法球身份缺失")
	var health_center_x := health_orb.get_global_rect().get_center().x
	var mana_center_x := mana_orb.get_global_rect().get_center().x
	var chassis_rect := chassis.get_global_rect()
	assert(health_center_x < chassis_rect.get_center().x and mana_center_x > chassis_rect.get_center().x, "生命球和魔法球没有位于组合骨架中心两侧：health=%s mana=%s chassis=%s" % [health_center_x, mana_center_x, chassis_rect])
	for orb: Control in [health_orb, mana_orb]:
		var hole_key := "healthHole" if str(orb.get_meta("resource_type", "")) == "health" else "manaHole"
		var hole: Dictionary = chassis_geometry.get(hole_key, {})
		var center_array: Array = hole.get("center", [0, 0])
		var expected_center := chassis_rect.position + Vector2(float(center_array[0]) * chassis_scale.x, float(center_array[1]) * chassis_scale.y)
		var expected_radius := float(hole.get("radius", 0.0)) * minf(chassis_scale.x, chassis_scale.y)
		assert(orb.get_global_rect().get_center().distance_to(expected_center) <= 0.25, "%s球圆心没有与骨架透明孔圆心重合" % str(orb.get_meta("resource_type", "")))
		assert(absf(float(orb.get_meta("liquid_radius", 0.0)) - expected_radius) <= 0.25, "%s球半径没有与骨架透明孔半径吻合" % str(orb.get_meta("resource_type", "")))
		assert(str(orb.get_meta("geometry_policy", "")) == "opencv_alpha_hole_center_radius", "资源球没有使用实测透明孔几何策略")
	assert(get_tree().get_nodes_in_group("warrior_passive_skill_card").is_empty(), "基本剑术或攻杀剑术仍显示在HUD")
	var warrior_selection_buttons: Array[Button] = []
	for node: Node in get_tree().get_nodes_in_group("selected_attack_skill"):
		if node is Button and node.get_parent().get_meta("control_mode", "") == "profession_skill_deck":
			warrior_selection_buttons.append(node)
	assert(warrior_selection_buttons.is_empty(), "战士技能区仍残留攻击/野蛮冲撞选择模式")
	var row_counts := {}
	var enabled_count := 0
	var first_toggle: Button
	for node: Node in warrior_toggles:
		assert(node is Button and str(node.get_meta("control_mode", "")) == "toggle_auto_use", "战士技能不是可交互自动开关")
		assert(bool(node.get_meta("opaque_cell", false)), "技能格没有保持不透明")
		assert(str(node.get_meta("icon_frame_policy", "")) == "square_frame_with_runtime_skill_texture", "技能开关没有使用独立方形哥特图标框")
		assert(str(node.get_meta("frame_role", "")) == "square_skill_toggle", "技能开关没有声明方形技能框角色")
		assert(node.get_node_or_null("GothicSquareFrame") != null and node.get_node_or_null("GothicSquareFrameFill") != null and node.get_node_or_null("Icon") != null, "技能开关的方形外框、底色或动态图标层缺失")
		assert(_named_child_count(node, "Icon") == 1, "技能开关出现重复图标层")
		var toggle_icon := node.get_node("Icon") as Control
		assert(toggle_icon.size.x >= 24.0 and toggle_icon.size.y >= 24.0, "技能开关图标过小不可辨认")
		var skill_icon_source := str(node.get_meta("icon_source", ""))
		assert(skill_icon_source.begins_with("res://assets/ui/gothic_preview/icons/runtime_v2/skill_"), "战士技能开关没有使用来自真实技能画面的紧裁剪运行图标")
		if first_toggle == null:
			first_toggle = node as Button
		if (node as Button).button_pressed:
			enabled_count += 1
	for node: Node in warrior_toggles:
		var row_key := int(round((node as Control).position.y))
		row_counts[row_key] = int(row_counts.get(row_key, 0)) + 1
	assert(row_counts.size() == 1 and int(row_counts.values()[0]) == 3, "战士技能区没有只保留一行三个自动开关")
	for count: int in row_counts.values():
		assert(count <= 4, "单行技能超过4个")
	assert(enabled_count > 0 and enabled_count < warrior_toggles.size(), "三个自动技能没有同时展示开启和关闭状态")
	var item_slots := get_tree().get_nodes_in_group("combat_item_slot")
	assert(item_slots.size() == 4, "战斗物品栏不是4格")
	var configured_items: Array[String] = []
	for node: Node in item_slots:
		assert(node is Button and str(node.get_meta("tap_action", "")) == "use_item", "战斗物品格不支持单击使用")
		assert(bool(node.get_meta("opaque_cell", false)), "物品格没有保持不透明")
		assert(str(node.get_meta("slot_frame_source", "")) == "res://assets/ui/gothic_preview/frames/gothic_slot_frame_runtime_v1.png" and node.get_node_or_null("GothicSquareFrame") != null, "物品格没有使用哥特美术外框")
		assert(is_equal_approx((node as Control).size.x, (node as Control).size.y), "物品格不是正方形")
		var item_content_rect: Rect2 = node.get_meta("icon_content_rect", Rect2())
		var item_icon := node.get_node_or_null("ItemIcon") as Control
		assert(item_icon != null and item_icon.position == item_content_rect.position and item_icon.size == item_content_rect.size, "物品图标没有放入实测透明孔范围")
		assert(str(node.get_meta("long_press_action", "")) == "open_item_picker" and float(node.get_meta("long_press_seconds", 0.0)) >= 0.5, "战斗物品格不支持长按选择")
		configured_items.append(str(node.get_meta("item_name", "")))
	assert(configured_items == ["金创药", "魔法药", "回城卷", "随机传送卷"], "四格战斗物品默认配置错误")
	var first_item_slot := item_slots[0] as Button
	preview.call("_use_combat_item_slot", first_item_slot)
	assert(str(first_item_slot.get_meta("last_action", "")).begins_with("use_item:"), "轻触物品格没有执行使用动作")
	preview.call("_open_item_picker", first_item_slot)
	await get_tree().process_frame
	var picker := preview.get_node_or_null("ItemPickerPreview")
	assert(picker != null and picker.visible, "长按物品格没有弹出选择菜单")
	var picker_options := 0
	for child: Node in picker.get_children():
		if child is Button and child.has_meta("picker_item"):
			picker_options += 1
	assert(picker_options == 4, "长按物品选择菜单没有4个候选项")
	picker.queue_free()
	var old_toggle_state := first_toggle.button_pressed
	first_toggle.button_pressed = not old_toggle_state
	var first_toggle_state := first_toggle.get_node_or_null("SkillState") as Label
	assert(first_toggle.button_pressed != old_toggle_state and first_toggle_state != null and first_toggle_state.text in ["开", "关"], "战士技能无法点击切换开关")
	var found_attack := false
	var found_auto_lock := false
	var found_switch_target := false
	var found_interaction := false
	var auto_lock_button: Button
	var attack_button: Button
	var switch_target_button: Button
	var interaction_button: Button
	for child: Node in _walk(preview):
		if child is Button and str(child.get_meta("combat_action", "")) == "basic_attack":
			found_attack = str(child.get_meta("caption", "")) == "攻击" and str(child.get_meta("icon_source", "")).ends_with("function_attack.png")
			attack_button = child as Button
		if child is Button and str(child.get_meta("control_mode", "")) == "toggle_auto_target_lock":
			found_auto_lock = true
			auto_lock_button = child as Button
		if child is Button and str(child.get_meta("combat_control", "")) == "switch_target":
			found_switch_target = true
			switch_target_button = child as Button
		if child is Button and str(child.get_meta("combat_control", "")) == "interact_only":
			found_interaction = true
			interaction_button = child as Button
	assert(found_attack and found_auto_lock and found_switch_target and found_interaction, "战士攻击、自动锁定、切换敌人或独立交互按钮不完整")
	assert(attack_button.get_node_or_null("RoundActionFrame") != null and _named_child_count(attack_button, "Icon") == 1, "攻击按钮没有使用圆形图框或出现重复图标")
	var attack_icon := attack_button.get_node("Icon") as Control
	assert(attack_icon.size.x >= 35.0 and attack_icon.size.y >= 35.0, "攻击图标过小不可辨认")
	assert(switch_target_button.position.distance_to(attack_button.position) < 120.0, "切换敌人没有紧邻攻击键")
	assert(auto_lock_button.position.x >= 1128.0, "自动锁定没有进入屏幕右侧功能栏")
	assert(interaction_button.position.x >= 1180.0, "独立交互按钮没有放在屏幕最右侧")
	assert(interaction_button.position.distance_to(attack_button.position) > 120.0, "独立交互按钮仍位于技能圈内")
	assert(str(interaction_button.get_meta("interaction_action", "")) == "interact_nearest" and not bool(interaction_button.get_meta("occupies_skill_slot", true)), "交互按钮混入了技能槽或缺少唯一交互动作")
	assert(not interaction_button.get_global_rect().intersects(switch_target_button.get_global_rect()) and not switch_target_button.get_global_rect().intersects(attack_button.get_global_rect()), "右下交互、切敌和攻击按钮仍然拥挤重叠")
	var combat_skill_slots := get_tree().get_nodes_in_group("combat_skill_slot")
	assert(combat_skill_slots.size() == 3, "攻击按钮周围不是3个技能按钮")
	var hud_skill_names: Array[String] = []
	for node: Node in combat_skill_slots:
		assert(node is Button and str(node.get_meta("long_press_action", "")) == "open_skill_page", "HUD技能按钮缺少长按打开技能页")
		assert(bool(node.get_meta("opaque_cell", false)), "右下技能格没有保持不透明")
		assert(str(node.get_meta("icon_frame_policy", "")) == "generated_frame_with_replaceable_runtime_icon" and node.get_node_or_null("RoundActionFrame") != null and node.get_node_or_null("Icon") != null, "HUD技能按钮没有采用圆形外框与可替换图标分层")
		assert(_named_child_count(node, "Icon") == 1, "HUD技能按钮出现重复图标层")
		var quick_icon := node.get_node("Icon") as Control
		assert(quick_icon.size.x >= 30.0 and quick_icon.size.y >= 30.0, "HUD技能图标过小不可辨认")
		assert((node as Control).position.distance_to(attack_button.position) < 170.0, "HUD技能按钮没有围绕攻击键布局")
		if not str(node.get_meta("skill_name", "")).is_empty():
			assert(str(node.get_meta("icon_source", "")).ends_with("skill_wild_rush.png"), "野蛮冲撞没有使用实际游戏冲锋画面的紧裁剪图标")
		hud_skill_names.append(str(node.get_meta("skill_name", "")))
	assert(hud_skill_names[0] == "野蛮" and hud_skill_names[1].is_empty() and hud_skill_names[2].is_empty(), "战士三个技能按钮默认配置错误")
	var dynamic_slot := combat_skill_slots[1] as Button
	var persistent_frame := dynamic_slot.get_node("RoundActionFrame")
	preview.call("_set_quick_skill_content", dynamic_slot, "野蛮")
	assert(dynamic_slot.get_node("RoundActionFrame") == persistent_frame and _named_child_count(dynamic_slot, "Icon") == 1 and str(dynamic_slot.get_meta("icon_source", "")).ends_with("skill_wild_rush.png"), "切换技能时没有保持图标框并同步替换技能图像")
	var transparent_container_count := 0
	for node: Node in _walk(preview):
		if node is Panel and (node.has_meta("panel_role") or node.has_meta("container_policy")):
			assert(float(node.get_meta("background_alpha", -1.0)) == 0.0, "HUD非按钮面板仍有底色")
			transparent_container_count += 1
	assert(transparent_container_count >= 5, "HUD完全透明面板覆盖范围不足")
	assert(preview.call("_profession_uses_skill_toggles", "战士") and not preview.call("_profession_uses_skill_toggles", "法师") and not preview.call("_profession_uses_skill_toggles", "道士"), "职业技能开关显示规则错误")
	var old_lock_state := auto_lock_button.button_pressed
	auto_lock_button.button_pressed = not old_lock_state
	assert(auto_lock_button.button_pressed != old_lock_state and ("自动锁定：开" in auto_lock_button.text or "自动锁定：关" in auto_lock_button.text), "自动锁定开关不可交互")
	assert(preview.call("_combat_action_caption", "法师") == "释放技能" and preview.call("_combat_action_caption", "道士") == "释放技能", "法师/道士右下动作未改为释放技能")
	var mage_deck := Control.new()
	mage_deck.size = Vector2(628, 174)
	preview.add_child(mage_deck)
	preview.call("_build_profession_skill_deck", mage_deck, "法师")
	await get_tree().process_frame
	var mage_buttons: Array[Button] = []
	for child: Node in mage_deck.get_children():
		if child is Button:
			mage_buttons.append(child)
	assert(mage_buttons.size() == 7, "法师技能选择项数量错误")
	assert(str(mage_buttons[0].get_meta("skill_name", "")) == "普通攻击" and mage_buttons[0].button_pressed, "法师缺少默认普通攻击选择")
	mage_buttons[1].button_pressed = true
	assert(mage_buttons[1].button_pressed and not mage_buttons[0].button_pressed, "法师技能没有互斥选择")
	mage_deck.queue_free()
	preview.queue_free()
	await get_tree().process_frame
	OS.set_environment("UI_PREVIEW_MODE", "skill")
	var skill_preview: Control = load("res://tests/ui_gothic_preview.tscn").instantiate()
	add_child(skill_preview)
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("skill_catalog_entry").size() == 6, "技能页面没有展示战士6个技能")
	assert(get_tree().get_nodes_in_group("skill_assignment_target").size() == 3, "长按技能后没有3个技能按钮位置可选")
	var assignment_popup := skill_preview.get_node_or_null("SkillAssignmentPopup")
	assert(assignment_popup != null and assignment_popup.visible and str(assignment_popup.get_meta("skill_name", "")) == "野蛮冲撞", "技能长按分配弹窗不完整")
	skill_preview.queue_free()
	OS.unset_environment("UI_PREVIEW_MODE")
	for capture_path: String in CAPTURES:
		var image := Image.new()
		assert(image.load(ProjectSettings.globalize_path(capture_path)) == OK, "无法读取审图截图：%s" % capture_path)
		assert(image.get_size() == Vector2i(1280, 720), "审图截图分辨率错误：%s" % capture_path)
	var report := {
		"taskId": "UI-GOTHIC-PREVIEW-1",
		"status": "PASS_AWAITING_USER_APPROVAL",
		"installedIntoRuntime": false,
		"apkPackaged": false,
		"mainSceneUnchanged": true,
		"characterCreateProfessions": ["战士", "法师", "道士"],
		"playerResourcePresentation": "diablo1_style_health_and_mana_orbs",
		"playerResourcePlacement": "flanking_central_skill_and_item_console",
		"visualStyle": "clean_ancient_gothic",
		"nonButtonPanelPolicy": "fully_transparent_with_gothic_metal_line_art",
		"centralOuterFrame": false,
		"bottomHudArt": "generated_open_chassis_with_orb_bezels",
		"frameGeometryPolicy": "opencv_alpha_hole_center_radius",
		"chosenRoundFramePrototype": "B",
		"orbCentersDerivedFromFrame": true,
		"itemSlotsSquare": true,
		"skillIconLayerCount": 1,
		"skillIconSourcePolicy": "source_pixels_cover_frame_aperture_no_matting",
		"slotFramePolicy": "generated_gothic_frame_with_replaceable_runtime_icon",
		"opaqueHudCellsOnly": ["skill_cells", "item_cells", "action_buttons"],
		"playerHorizontalBarsInHud": false,
		"playerIdentityPanelInHud": false,
		"monsterTargetBarInHud": true,
		"currentTrackingPanelInHud": false,
		"combatItemSlotsInHud": 4,
		"combatItemInteraction": {"tap": "use_item", "longPress": "open_item_picker"},
		"combatItemCandidates": ["potions", "town_scroll", "random_teleport_scroll"],
		"consumablePolicy": "health_mana_auto_use_plus_four_manual_slots",
		"skillsPerRow": 4,
		"warriorSkillControl": "toggle_auto_use",
		"warriorHiddenPassiveSkills": ["基本剑术", "攻杀剑术"],
		"warriorToggleSkills": ["刺杀剑术", "半月弯刀", "烈火剑法"],
		"warriorSkillIconPolicy": "actual_primary_client_skill_frames_only",
		"functionIconPolicy": "generated_clean_gothic_allowed_for_non_skill_controls",
		"warriorInstantSkill": "野蛮冲撞",
		"warriorRightAction": "basic_attack",
		"combatSkillSlots": 3,
		"combatSkillSlotLongPress": "open_skill_page",
		"skillPageFields": ["name", "level", "mastery", "type", "mana", "cooldown", "range", "description", "source"],
		"skillAssignmentFlow": "long_press_skill_then_choose_slot_1_2_3",
		"professionToggleVisibility": {"战士": true, "法师": false, "道士": false},
		"mageTaoSkillControl": "exclusive_select_then_attack_casts_selected_skill",
		"mageTaoNormalAttackOption": true,
		"targetControls": ["switch_target_beside_attack", "toggle_auto_lock_right_rail"],
		"interactionControl": {"placement": "far_right_outside_skill_ring", "action": "interact_nearest", "dedicatedOnly": true},
		"rightActionSpacing": "non_overlapping_primary_operation_zone",
		"captureResolution": [1280, 720],
		"captures": CAPTURES,
	}
	var output_dir := ProjectSettings.globalize_path("res://outputs/validation")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var file := FileAccess.open(output_dir.path_join("ui_gothic_preview_acceptance.json"), FileAccess.WRITE)
	assert(file != null, "无法写入UI审图验收报告")
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("UI_GOTHIC_PREVIEW_TEST_PASS: 四张1280x720截图、独立交互键、人物资源球、怪物血条、正式入口隔离均通过")
	get_tree().quit(0)


func _walk(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	for child: Node in root.get_children():
		result.append_array(_walk(child))
	return result


func _named_child_count(root: Node, child_name: String) -> int:
	var count := 0
	for child: Node in root.get_children():
		if child.name == child_name:
			count += 1
	return count
