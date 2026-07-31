extends Node

const CHASSIS_PATH := "res://assets/ui/gothic_hud/v2/runtime/bottom_chassis_v2.png"
const MobileLayout := preload("res://scripts/mobile_layout.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	var root := hud.get_node("MobileSafeRoot") as Control
	assert(root != null)
	assert(not (root.get_node("TopInfoPanel") as Control).visible)
	assert(hud.has_signal("skill_button_assignment_requested"), "HUD 没有转发攻击主键与六环技能分配请求")
	assert(hud.has_method("set_skill_button_assignments"), "HUD 缺少新版技能配置注入方法")
	assert(hud.has_signal("revival_requested"), "HUD 没有转发复活请求")
	assert(hud.has_method("show_death_screen"), "HUD 缺少死亡界面入口")
	assert(hud.has_method("show_loot_feedback"), "HUD 缺少结构化拾取反馈入口")
	assert(hud.get("loot_feedback_layer") != null, "HUD 没有接入战利品反馈层")
	assert(hud.has_method("begin_loading_transition") and hud.has_method("finish_loading_transition"), "HUD 缺少地图Loading过渡入口")
	var loading_overlay: Control = hud.get("loading_transition_overlay") as Control
	assert(loading_overlay != null and not loading_overlay.visible, "Loading过渡层没有以隐藏状态接入HUD")
	var covered_requests: Array[Dictionary] = []
	var finished_requests: Array[Dictionary] = []
	hud.loading_transition_covered.connect(func(request: Dictionary) -> void: covered_requests.append(request.duplicate(true)))
	hud.loading_transition_finished.connect(func(request: Dictionary) -> void: finished_requests.append(request.duplicate(true)))
	hud.begin_loading_transition("hud:test:001")
	await get_tree().create_timer(0.50).timeout
	assert(covered_requests.size() == 1 and covered_requests[0].transition_id == "hud:test:001", "HUD 没有转发Loading完全覆盖信号")
	hud.finish_loading_transition()
	await get_tree().create_timer(0.45).timeout
	assert(finished_requests.size() == 1 and finished_requests[0].transition_id == "hud:test:001", "HUD 没有转发Loading结束信号")
	var death_panel: Control = hud.get("death_revival_panel") as Control
	assert(death_panel != null and not death_panel.visible, "死亡界面没有以隐藏状态接入 HUD")

	var chassis := root.get_node("IntegratedHUDChassis") as Control
	assert(chassis != null and chassis.size == Vector2(820, 273))
	assert(chassis.get_meta("contents") == ["health_orb", "four_item_slots", "mana_orb"])
	var health_orb := chassis.get_node("HealthOrb") as Control
	var mana_orb := chassis.get_node("ManaOrb") as Control
	assert(health_orb != null and mana_orb != null)
	assert(health_orb.size == Vector2(110, 110) and mana_orb.size == Vector2(110, 110), "血蓝球没有恢复为与框体透明孔匹配的既定尺寸")
	assert(health_orb.get_meta("stable_id") == "ui.hud.resource_orb.hole_fill.v1" and mana_orb.get_meta("stable_id") == "ui.hud.resource_orb.hole_fill.v1")
	assert(is_equal_approx(health_orb.position.x + health_orb.size.x * 0.5, 181.6875), "生命球圆心偏离框体透明孔")
	assert(is_equal_approx(mana_orb.position.x + mana_orb.size.x * 0.5, 638.3125), "魔法球圆心偏离框体透明孔")
	assert(is_equal_approx(health_orb.position.y + health_orb.size.y * 0.5, mana_orb.position.y + mana_orb.size.y * 0.5), "血蓝球纵向不对称")
	assert(is_equal_approx(health_orb.position.y + health_orb.size.y * 0.5, 187.28125), "血蓝球仍保留旧的向南取整偏移")
	var expected_item_centers := [
		Vector2(284.0625, 190.9375),
		Vector2(367.34375, 190.53125),
		Vector2(453.875, 190.53125),
		Vector2(537.96875, 190.53125),
	]
	for index in range(4):
		var item_slot := chassis.get_node("ItemSlot%d" % (index + 1)) as Button
		assert(item_slot != null and item_slot.get_meta("stable_id") == "hud.item_slot.%d" % (index + 1))
		assert(item_slot.position + item_slot.size * 0.5 == expected_item_centers[index], "物品框没有使用底框源像素坐标")

	assert(hud.quick_buttons.is_empty() and hud.quick_slot_icons.is_empty(), "底框上方旧四个中央技能按钮仍然存在")
	for index in range(4):
		assert(root.get_node_or_null("SkillButton%d" % (index + 1)) == null, "旧中央技能按钮仍挂在运行时HUD")
	PlayerState.quick_slots = ["攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"]
	hud.set_skill_button_assignments({
		"contract_id": "gameplay.skill.button_assignments.v3",
		"attack": ["烈火剑法"],
		"attack_ring": ["野蛮冲撞", "烈火剑法", "半月弯刀", "刺杀剑术", "", ""],
	})
	hud.update_quick_slots()
	assert(hud.attack_ring_skill_icons.size() == 6 and hud.attack_ring_skill_labels.size() == 6)
	assert(hud.attack_slot_icon.texture != null and hud.attack_slot_icon.get_meta("skill_name", "") == "烈火剑法")
	assert((root.get_node("AttackButton") as Button).get_meta("bound_skill_name", "") == "烈火剑法")
	hud.update_warrior_states({
		"fire_enabled": true,
		"fire_armed": true,
		"fire_expires_remaining_ms": 10000,
	})
	assert("烈火:开·充能" in hud.warrior_state_label.text, "烈火状态没有显示开启和充能")
	hud.update_warrior_states({
		"fire_enabled": true,
		"fire_armed": false,
		"fire_expires_remaining_ms": 0,
		"fire_cooldown_remaining_ms": 0,
	})
	assert("烈火:开·就绪" in hud.warrior_state_label.text, "烈火状态没有显示开启就绪")
	var ring_centers := [
		Vector2(-261, -70),
		Vector2(-261, -142),
		Vector2(-261, -214),
		Vector2(-189, -286),
		Vector2(-117, -286),
		Vector2(-60, -214),
	]
	var attack_center := (root.get_node("AttackButton") as Control).position + Vector2(60, 60)
	for index in range(6):
		var ring_skill := root.get_node("AttackRingSkill%d" % (index + 1)) as Button
		assert(ring_skill != null)
		var ring_icon := ring_skill.get_node("SkillIcon") as TextureRect
		var expected_ring_skill: String = ["野蛮冲撞", "烈火剑法", "半月弯刀", "刺杀剑术", "", ""][index]
		assert(ring_icon != null and ring_icon.get_meta("skill_name", "") == expected_ring_skill)
		assert(ring_icon.position == Vector2(8, 8) and ring_icon.size == Vector2(56, 56), "环绕技能图必须完整覆盖槽内开口")
		assert(ring_skill.get_node_or_null("RoundActionFrame") != null, "环形技能缺少独立无污染圆框")
		var actual_center := ring_skill.position + ring_skill.size * 0.5
		assert(actual_center == root.size + ring_centers[index], "六个技能按钮没有使用稳定攻击环坐标")
		assert(actual_center.distance_to(attack_center) >= 96.0, "环形技能与攻击主键重叠")
	var grouped_presses: Array = []
	hud.skill_slot_pressed.connect(
		func(slot_group: String, slot_index: int) -> void:
			grouped_presses.append([slot_group, slot_index])
	)
	(root.get_node("AttackRingSkill6") as Button).pressed.emit()
	assert(grouped_presses == [["attack_ring", 5]], "HUD 六环技能点击没有保留 slot_group")
	var attack := root.get_node("AttackButton") as Button
	assert(attack.size == Vector2(120, 120), "攻击按钮视觉直径应保持缩小后的120px")
	var joystick := root.get_node("TouchJoystick") as TouchJoystick
	assert(joystick.size.x >= 150 and is_equal_approx(joystick.radius, 58.0), "摇杆触控区和缩小后的可视半径不匹配")
	assert((root.get_node("InventoryButton") as Control).position.y > (root.get_node("MapButton") as Control).position.y)
	assert((root.get_node("SkillBookButton") as Control).position.y > (root.get_node("MenuButton") as Control).position.y)
	assert((root.get_node("SwitchTargetButton") as Control).position.x > (root.get_node("InteractButton") as Control).position.x)
	var interact := root.get_node("InteractButton") as Control
	var switch_target := root.get_node("SwitchTargetButton") as Control
	var interact_fill := root.get_node("InteractFill") as Control
	var switch_target_fill := root.get_node("SwitchTargetFill") as Control
	assert(interact.size == Vector2(110, 76) and interact.position + interact.size * 0.5 == interact_fill.position + interact_fill.size * 0.5, "交互按钮未对准美术圆心")
	assert(switch_target.size == Vector2(110, 76) and switch_target.position + switch_target.size * 0.5 == switch_target_fill.position + switch_target_fill.size * 0.5, "换敌按钮未对准美术圆心")

	var image := Image.load_from_file(ProjectSettings.globalize_path(CHASSIS_PATH))
	assert(not image.is_empty() and image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH])
	assert(image.get_pixel(0, 0).a < 0.01 and image.get_pixel(image.get_width() - 1, image.get_height() - 1).a < 0.01)
	assert(image.get_pixel(223, 231).a < 0.05 and image.get_pixel(785, 231).a < 0.05, "血蓝球开口必须保持透明")
	assert(root.get_node("TargetPanel/TargetFrameArt").get_meta("stable_id") == "ui.hud.gothic.v2.target_bar")
	assert(root.get_node("UtilityStackArt").get_meta("stable_id") == "ui.hud.gothic.v2.utility_stack")
	assert(root.get_node("JoystickArt").get_meta("stable_id") == "ui.hud.gothic.v2.joystick")
	assert(root.get_node_or_null("RightControlsArt") == null, "含左边缘污染碎片的旧右侧合成图仍在运行时")
	assert(root.get_node("AttackFrame").get_meta("stable_id") == "ui.hud.gothic.v3.attack_frame")
	assert(chassis.get_node("DemonChassisArt").get_meta("stable_id") == "ui.hud.gothic.v2.bottom_chassis")
	var cleaned_image := (chassis.get_node("DemonChassisArt") as TextureRect).texture.get_image()
	assert(cleaned_image.get_pixel(1008, 260).a <= 0.01, "底框右侧污染连通碎片没有从源像素层清除")
	assert(FileAccess.file_exists("res://assets/ui/gothic_hud/v2/hud_asset_manifest.json"))
	var hud_source := FileAccess.get_file_as_string("res://scripts/hud.gd")
	assert("gothic_hud/v1" not in hud_source and "gothic_preview" not in hud_source, "正式HUD不得继续引用旧素材")
	await _assert_2664x1200_landscape_layout(root, chassis, health_orb, mana_orb)
	print("HUD_GOTHIC_RUNTIME_PASS：统一V2透明框体、动态血蓝球、4物品槽、攻击主键、6环绕技能与触控尺寸均通过")
	get_tree().quit(0)


func _assert_2664x1200_landscape_layout(root: Control, chassis: Control, health_orb: Control, mana_orb: Control) -> void:
	# 2664x1200 在项目 720 高的 expand 逻辑视口中为 1598.4x720；左侧 120px 挖孔折算为 72 逻辑像素。
	var physical_viewport := Vector2(2664, 1200)
	var logical_viewport := Vector2(1598.4, 720)
	var safe_rect := Rect2(120, 0, 2544, 1200)
	var margins := MobileLayout.safe_margins(physical_viewport, safe_rect, logical_viewport)
	assert(margins.is_equal_approx(Vector4(72, 0, 0, 0)), "2664x1200 安全区换算错误")
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(margins.x, margins.y)
	root.size = logical_viewport - Vector2(margins.x + margins.z, margins.y + margins.w)
	await get_tree().process_frame

	var safe_bounds := Rect2(root.global_position, root.size)
	var bounded_controls: Array[Control] = [
		chassis,
		root.get_node("TouchJoystick") as Control,
		root.get_node("UtilityStackArt") as Control,
		root.get_node("AttackButton") as Control,
		root.get_node("InteractButton") as Control,
		root.get_node("SwitchTargetButton") as Control,
	]
	for index in range(6):
		bounded_controls.append(root.get_node("AttackRingSkill%d" % (index + 1)) as Control)
	for control: Control in bounded_controls:
		var rect := control.get_global_rect()
		assert(safe_bounds.encloses(rect), "2664x1200 安全区布局溢出：%s %s / %s" % [control.name, rect, safe_bounds])

	var chassis_center_x := chassis.get_global_rect().get_center().x
	var health_center_x := health_orb.get_global_rect().get_center().x
	var mana_center_x := mana_orb.get_global_rect().get_center().x
	var orb_symmetry_error := absf((chassis_center_x - health_center_x) - (mana_center_x - chassis_center_x))
	assert(orb_symmetry_error <= 0.01, "2664x1200 血蓝球没有围绕底部框体左右对称：%.2f / %.2f / %.2f，误差 %.2f" % [health_center_x, chassis_center_x, mana_center_x, orb_symmetry_error])
	assert(health_orb.size == Vector2(110, 110) and mana_orb.size == Vector2(110, 110), "2664x1200 布局错误缩小了血蓝球")
