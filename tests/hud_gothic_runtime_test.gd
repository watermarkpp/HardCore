extends Node

const CHASSIS_PATH := "res://assets/ui/gothic_hud/v2/runtime/bottom_chassis_v2.png"
const ACTION_FRAME_PATH := "res://assets/ui/gothic_hud/v2/runtime/round_action_frame_v3.png"
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
	assert(health_orb.get_meta("stable_id") == "ui.hud.resource_orb.metal_mask_fit.v2" and mana_orb.get_meta("stable_id") == "ui.hud.resource_orb.metal_mask_fit.v2")
	assert(is_equal_approx(float(health_orb.get_meta("liquid_radius_ratio")), 0.49), "血球没有扩大到金属内孔")
	assert(is_equal_approx(float(mana_orb.get_meta("liquid_radius_ratio")), 0.49), "蓝球没有扩大到金属内孔")
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
	var chassis_art := chassis.get_node("DemonChassisArt") as TextureRect
	for index in range(4):
		var item_fill := chassis.get_node("ItemSlotFill%d" % (index + 1)) as Panel
		var item_slot := chassis.get_node("ItemSlot%d" % (index + 1)) as Button
		assert(item_slot != null and item_slot.get_meta("stable_id") == "hud.item_slot.%d" % (index + 1))
		assert(item_fill != null and item_fill.size == Vector2(72, 72), "物品框底色没有填满金属内孔")
		assert(item_slot.size == Vector2(72, 72) and item_slot.get_meta("metal_masked", false), "物品框触控层没有按金属内孔建立")
		assert(item_fill.position + item_fill.size * 0.5 == expected_item_centers[index], "物品框底色没有使用底框源像素坐标")
		assert(item_slot.position + item_slot.size * 0.5 == expected_item_centers[index], "物品框没有使用底框源像素坐标")
		assert(item_fill.get_index() < chassis_art.get_index() and chassis_art.get_index() < item_slot.get_index(), "物品填充、金属框与触控层次序错误")

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
	var attack_center := (root.get_node("AttackButton") as Control).position + Vector2(60, 60)
	assert(attack_center == root.size + GameHUD.HUD_ATTACK_CENTER, "攻击键没有使用统一内移圆心")
	var frame_image := Image.load_from_file(ProjectSettings.globalize_path(ACTION_FRAME_PATH))
	var visible_inner_radius_max := _measure_action_frame_visible_inner_radius_max(frame_image)
	assert(visible_inner_radius_max == 44.0, "圆框可视亮金属内沿测量结果发生漂移")
	assert(
		GameHUD.HUD_ACTION_FRAME_VISIBLE_INNER_MAX_RADIUS_SOURCE == visible_inner_radius_max,
		"HUD 未使用圆框逐方向实测的可视亮金属内沿",
	)
	var expected_attack_content_size := Vector2(90, 90)
	var expected_ring_content_size := Vector2(50, 50)
	_assert_action_frame_content_reaches_visible_inner_edge(
		frame_image,
		expected_attack_content_size.x * 0.5,
		expected_ring_content_size.x * 0.5 * float(frame_image.get_width())
			/ GameHUD.HUD_ATTACK_RING_BUTTON_SIZE.x,
	)
	var previous_ring_center := Vector2.ZERO
	for index in range(6):
		var ring_skill := root.get_node("AttackRingSkill%d" % (index + 1)) as Button
		assert(ring_skill != null)
		var ring_icon := ring_skill.get_node("SkillIcon") as TextureRect
		var ring_backdrop := ring_skill.get_node("SkillBackdrop") as Panel
		var ring_frame := ring_skill.get_node("RoundActionFrame") as TextureRect
		var expected_ring_skill: String = ["野蛮冲撞", "烈火剑法", "半月弯刀", "刺杀剑术", "", ""][index]
		assert(ring_icon != null and ring_icon.get_meta("skill_name", "") == expected_ring_skill)
		assert(ring_icon.position == Vector2(11, 11) and ring_icon.size == expected_ring_content_size, "环绕技能图没有延伸到可视金属内沿下方")
		assert(ring_backdrop.position == Vector2(11, 11) and ring_backdrop.size == expected_ring_content_size, "环绕技能底色没有延伸到可视金属内沿下方")
		assert(ring_icon.material is ShaderMaterial and ring_icon.get_meta("circular_clip", false), "环绕技能图没有圆形裁切")
		assert(ring_frame != null and ring_frame.get_index() > ring_icon.get_index(), "环形技能金属框没有覆盖在图标之上")
		assert(
			ring_frame.get_meta("visual_inner_rim_mask", "")
				== HUDAssetSanitizer.ACTION_FRAME_INNER_DARK_RIM_MASK_ID,
			"环形技能框没有清除可视内沿以内的深色空圈",
		)
		var actual_center := ring_skill.position + ring_skill.size * 0.5
		var expected_angle := GameHUD.HUD_ATTACK_RING_START_DEGREES + GameHUD.HUD_ATTACK_RING_STEP_DEGREES * index
		var expected_center := root.size + GameHUD.HUD_ATTACK_CENTER + Vector2.from_angle(deg_to_rad(expected_angle)) * GameHUD.HUD_ATTACK_RING_RADIUS
		assert(actual_center.is_equal_approx(expected_center), "六个技能按钮没有使用等角等半径攻击环")
		assert(is_equal_approx(actual_center.distance_to(attack_center), 125.0), "环形技能半径不统一")
		assert(bool(ring_skill.call("_has_point", Vector2(36, 36))) and not bool(ring_skill.call("_has_point", Vector2.ZERO)), "环形技能仍使用方形触控判定")
		if index > 0:
			assert(actual_center.distance_to(previous_ring_center) > 72.0, "相邻环形技能圆形触控区重叠")
		previous_ring_center = actual_center
		if expected_ring_skill.is_empty():
			assert(not ring_backdrop.visible and not ring_icon.visible and ring_icon.texture == null, "空技能槽仍显示黑底或图标")
			assert((ring_skill.get_node("SkillLabel") as Label).text == "空", "空技能槽中心没有只显示“空”")
			assert((ring_skill.get_node("SkillLabel") as Label).vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "空技能槽文字没有居中")
		else:
			assert(ring_backdrop.visible, "已配置技能槽的内孔底色被隐藏")
	var grouped_presses: Array = []
	hud.skill_input_started.connect(
		func(slot_group: String, slot_index: int, _token: int, _touch_id: int, _source: StringName) -> void:
			grouped_presses.append([slot_group, slot_index])
	)
	var ring_touch := InputEventScreenTouch.new()
	ring_touch.index = 6
	ring_touch.position = Vector2(36, 36)
	ring_touch.pressed = true
	(root.get_node("AttackRingSkill6") as Button).call("_gui_input", ring_touch)
	ring_touch.pressed = false
	(root.get_node("AttackRingSkill6") as Button).call("_gui_input", ring_touch)
	assert(grouped_presses == [["attack_ring", 5]], "HUD 六环技能点击没有保留 slot_group")
	var attack := root.get_node("AttackButton") as Button
	assert(attack.size == Vector2(120, 120), "攻击按钮视觉直径应保持缩小后的120px")
	assert(bool(attack.call("_has_point", Vector2(60, 60))) and not bool(attack.call("_has_point", Vector2.ZERO)), "攻击键仍使用方形触控判定")
	var attack_fill := root.get_node("AttackFill") as Control
	var attack_frame := root.get_node("AttackFrame") as Control
	assert(attack_fill.size == expected_attack_content_size, "攻击键红色填充没有延伸到可视金属内沿下方")
	assert(attack_fill.get_global_rect().get_center().is_equal_approx(attack.get_global_rect().get_center()), "攻击键红色填充没有对准圆心")
	assert(attack_frame.get_global_rect().get_center().is_equal_approx(attack.get_global_rect().get_center()), "攻击键金属框没有对准圆心")
	assert(hud.attack_slot_icon.size == expected_attack_content_size and hud.attack_slot_icon.material is ShaderMaterial, "攻击键技能图没有延伸到可视金属内沿下方")
	assert(attack_frame.get_index() > attack.get_index(), "攻击键金属框没有最后绘制遮住扩大的内容")
	assert(
		attack_frame.get_meta("visual_inner_rim_mask", "")
			== HUDAssetSanitizer.ACTION_FRAME_INNER_DARK_RIM_MASK_ID,
		"攻击键框没有清除可视内沿以内的深色空圈",
	)
	var joystick := root.get_node("TouchJoystick") as TouchJoystick
	assert(joystick.size.x >= 150 and is_equal_approx(joystick.radius, 58.0), "摇杆触控区和缩小后的可视半径不匹配")
	assert(joystick.position == Vector2(70, root.size.y - 210), "摇杆没有向安全区内部移动")
	assert(hud.warrior_state_label.offset_top == -250 and hud.warrior_state_label.offset_bottom == -222, "战士状态行没有下移到清理后的底盘上方")
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
	assert(chassis_art.get_meta("stable_id") == "ui.hud.gothic.v2.bottom_chassis")
	assert(
		chassis_art.get_meta("legacy_skill_art_mask") == HUDAssetSanitizer.CHASSIS_LEGACY_SKILL_MASK_ID,
		"底盘没有使用精确旧技能框 alpha mask",
	)
	var cleaned_image := chassis_art.texture.get_image()
	assert(cleaned_image.get_pixel(1008, 260).a <= 0.01, "底框右侧污染连通碎片没有从源像素层清除")
	var legacy_points: Array[Vector2i] = [
		Vector2i(309, 10),
		Vector2i(254, 60),
		Vector2i(441, 20),
		Vector2i(574, 20),
		Vector2i(707, 20),
		Vector2i(204, 135),
		Vector2i(806, 138),
		Vector2i(380, 138),
		Vector2i(630, 138),
		Vector2i(309, 137),
		Vector2i(309, 150),
		Vector2i(707, 150),
	]
	for point in legacy_points:
		assert(image.get_pixelv(point).a > 0.01, "旧技能框样本点在原图中不存在：%s" % point)
		assert(HUDAssetSanitizer.is_chassis_legacy_skill_pixel(point), "旧技能框样本点未进入精确 mask：%s" % point)
		assert(cleaned_image.get_pixelv(point).a <= 0.01, "旧圆框、红菱形或连接条没有清除：%s" % point)
	var protected_crest_points: Array[Vector2i] = [
		Vector2i(505, 115),
		Vector2i(505, 122),
		Vector2i(505, 130),
		Vector2i(492, 135),
		Vector2i(520, 145),
		Vector2i(505, 155),
	]
	for point in protected_crest_points:
		assert(image.get_pixelv(point).a > 0.01, "中央徽章保护样本点在原图中不存在：%s" % point)
		assert(HUDAssetSanitizer.is_chassis_center_crest_protected(point), "中央徽章样本点未进入硬保护区：%s" % point)
		assert(cleaned_image.get_pixelv(point) == image.get_pixelv(point), "中央尖头或徽章原像素被修改：%s" % point)
	for unchanged_point: Vector2i in [Vector2i(245, 145), Vector2i(400, 158), Vector2i(505, 165), Vector2i(715, 160)]:
		assert(cleaned_image.get_pixelv(unchanged_point) == image.get_pixelv(unchanged_point), "正式底盘或恶魔装饰像素被修改：%s" % unchanged_point)
	var isolated_component_cleaned := HUDAssetSanitizer.without_alpha_component(
		load(CHASSIS_PATH) as Texture2D,
		Vector2i(1008, 260),
	).get_image()
	for y in range(0, 160):
		for x in range(204, 808):
			var point := Vector2i(x, y)
			if HUDAssetSanitizer.is_chassis_legacy_skill_pixel(point):
				assert(cleaned_image.get_pixelv(point).a <= 0.01, "alpha mask 内仍有旧技能框像素：%s" % point)
			else:
				assert(cleaned_image.get_pixelv(point) == isolated_component_cleaned.get_pixelv(point), "alpha mask 外的底盘原像素被改动：%s" % point)
	assert(FileAccess.file_exists("res://assets/ui/gothic_hud/v2/hud_asset_manifest.json"))
	var hud_source := FileAccess.get_file_as_string("res://scripts/hud.gd")
	assert("gothic_hud/v1" not in hud_source and "gothic_preview" not in hud_source, "正式HUD不得继续引用旧素材")
	await _assert_2664x1200_landscape_layout(root, chassis, health_orb, mana_orb)
	print("HUD_GOTHIC_RUNTIME_PASS：统一V2透明框体、动态血蓝球、4物品槽、攻击主键、6环绕技能与触控尺寸均通过")
	get_tree().quit(0)


func _measure_action_frame_visible_inner_radius_max(image: Image) -> float:
	assert(not image.is_empty(), "无法读取攻击圆框源图")
	var center := Vector2(image.get_size()) * 0.5
	var maximum_inner_radius := 0.0
	for direction_index in range(360):
		var radius := _measure_action_frame_visible_inner_radius(
			image,
			center,
			Vector2.from_angle(deg_to_rad(float(direction_index))),
		)
		maximum_inner_radius = maxf(maximum_inner_radius, radius)
	return maximum_inner_radius


func _measure_action_frame_visible_inner_radius(
	image: Image,
	center: Vector2,
	direction: Vector2,
) -> float:
	for step_index in range(37):
		var radius := 30.0 + float(step_index) * 0.5
		var point := Vector2i((center + direction * radius).round())
		var color := image.get_pixelv(point)
		if color.a >= 0.5 and color.get_luminance() >= 0.20:
			return radius
	assert(false, "攻击圆框方向上没有找到可视亮金属内沿")
	return 48.0


func _assert_action_frame_content_reaches_visible_inner_edge(
	image: Image,
	attack_content_radius: float,
	ring_content_radius_in_source_pixels: float,
) -> void:
	var center := Vector2(image.get_size()) * 0.5
	var sanitized := HUDAssetSanitizer.without_action_frame_inner_dark_rim(
		load(ACTION_FRAME_PATH) as Texture2D
	).get_image()
	var inner_radii := PackedFloat32Array()
	inner_radii.resize(360)
	for direction_index in range(360):
		var direction := Vector2.from_angle(deg_to_rad(float(direction_index)))
		var inner_radius := _measure_action_frame_visible_inner_radius(image, center, direction)
		inner_radii[direction_index] = inner_radius
		assert(attack_content_radius > inner_radius, "攻击底色没有压入亮金属内沿下方")
		assert(ring_content_radius_in_source_pixels > inner_radius, "技能底色没有压入亮金属内沿下方")
		var bright_point := Vector2i((center + direction * inner_radius).round())
		assert(
			sanitized.get_pixelv(bright_point) == image.get_pixelv(bright_point),
			"可视亮金属内沿被清理：方向 %d" % direction_index,
		)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var offset := Vector2(x + 0.5, y + 0.5) - center
			if offset.length() <= 0.0 or offset.length() > 48.0:
				continue
			var direction_index := posmod(roundi(rad_to_deg(offset.angle())), 360)
			if offset.length() >= inner_radii[direction_index] + 1.0:
				continue
			var source_color := image.get_pixel(x, y)
			var source_is_bright_metal := (
				source_color.a >= HUDAssetSanitizer.ACTION_FRAME_VISUAL_METAL_MIN_ALPHA
				and source_color.get_luminance()
					>= HUDAssetSanitizer.ACTION_FRAME_VISUAL_METAL_MIN_LUMINANCE
			)
			if source_is_bright_metal:
				assert(
					sanitized.get_pixel(x, y) == source_color,
					"亮金属或四尖角像素被改变：%s" % Vector2i(x, y),
				)
			elif source_color.a > 0.0:
				assert(
					sanitized.get_pixel(x, y).a <= 0.01,
					"背景到亮金属内沿之间仍残留深色 alpha 间隙：%s" % Vector2i(x, y),
				)


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
