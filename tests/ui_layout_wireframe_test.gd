extends Node

const MODES := ["hud", "inventory", "shop", "warehouse", "quest", "map", "skill", "profession"]
const TOUCH_MIN := 56.0
const SAFE_RECT := Rect2(24, 16, 1232, 688)


func _ready() -> void:
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/startup_loading.tscn", "布局样板不得改变正式入口")
	var source := FileAccess.get_file_as_string("res://tests/ui_layout_wireframe.gd")
	assert(not "assets/ui/gothic_preview" in source, "第1步布局样板不得提前依赖哥特贴图")
	for mode in MODES:
		OS.set_environment("UI_LAYOUT_MODE", mode)
		var preview: Control = load("res://tests/ui_layout_wireframe.tscn").instantiate()
		add_child(preview)
		await get_tree().process_frame
		var touch_targets := get_tree().get_nodes_in_group("wireframe_touch_target")
		assert(touch_targets.size() > 0, "%s布局缺少触控区域" % mode)
		for node: Node in touch_targets:
			var target := node as Control
			assert(target.size.x >= TOUCH_MIN and target.size.y >= TOUCH_MIN, "%s触控区域小于56px：%s %s" % [mode, target.name, target.size])
			assert(SAFE_RECT.encloses(target.get_global_rect()), "%s触控区域越出Android安全区：%s" % [mode, target.name])
		for left_index in range(touch_targets.size()):
			for right_index in range(left_index + 1, touch_targets.size()):
				var left := touch_targets[left_index] as Control
				var right := touch_targets[right_index] as Control
				if left.get_meta("circular_touch", false) and right.get_meta("circular_touch", false):
					var required_distance := float(left.get_meta("touch_radius")) + float(right.get_meta("touch_radius"))
					assert(
						left.get_global_rect().get_center().distance_to(right.get_global_rect().get_center()) >= required_distance,
						"%s圆形触控区域发生重叠：%s / %s" % [mode, left.name, right.name]
					)
				else:
					assert(not left.get_global_rect().intersects(right.get_global_rect()), "%s触控区域发生重叠：%s / %s" % [mode, left.name, right.name])
		if mode == "hud":
			assert(get_tree().get_nodes_in_group("hud_profession_skill_slot").is_empty(), "HUD中间4个技能槽必须取消")
			assert(get_tree().get_nodes_in_group("hud_item_slot").size() == 4, "一体式底框必须包含4个物品槽")
			var ring_slots := get_tree().get_nodes_in_group("hud_attack_ring_skill")
			assert(ring_slots.size() == 6, "攻击键周围必须有6个快捷技能")
			for index in range(ring_slots.size()):
				assert(
					str((ring_slots[index] as Control).get_meta("stable_id", ""))
						== "hud.attack_ring_skill.%d" % (index + 1),
					"六技能槽稳定ID不完整"
				)
			var integrated_frame := preview.get_node_or_null("IntegratedResourceItemFrame")
			assert(integrated_frame != null and float(integrated_frame.get_meta("background_alpha", -1.0)) == 0.0, "生命球、物品与魔法球必须使用无底色的一体式美术框")
			assert(preview.get_node_or_null("CombatConsole") == null, "4物品和4职业技能槽不得再使用矩形控制台背景")
			var attack := preview.get_node("AttackButton") as Control
			assert(str(attack.get_meta("stable_id", "")) == "hud.attack.primary", "攻击主键稳定ID缺失")
			assert(attack.get_global_rect().get_center().is_equal_approx(Vector2(1095, 610)), "攻击按钮没有按统一圆心向屏幕内部移动")
			for index in range(ring_slots.size()):
				var ring := ring_slots[index] as Control
				assert(is_equal_approx(ring.get_global_rect().get_center().distance_to(attack.get_global_rect().get_center()), 125.0), "六技能环半径不统一")
		if mode != "hud":
			assert(get_tree().get_nodes_in_group("wireframe_modal").size() == 1, "%s必须有且只有一个主模态面板" % mode)
		preview.queue_free()
		await get_tree().process_frame
		var capture_path := "res://outputs/visual_acceptance/ui_layout_wireframe/%s_1280x720.png" % mode
		if FileAccess.file_exists(capture_path):
			var image := Image.new()
			assert(image.load(ProjectSettings.globalize_path(capture_path)) == OK, "无法读取布局审图截图：%s" % mode)
			assert(image.get_size() == Vector2i(1280, 720), "%s布局截图分辨率错误" % mode)
	OS.unset_environment("UI_LAYOUT_MODE")
	print("UI_LAYOUT_WIREFRAME_TEST_PASS：8套布局、56px触控下限、安全画布与正式入口隔离均通过")
	get_tree().quit(0)
