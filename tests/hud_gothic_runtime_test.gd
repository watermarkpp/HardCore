extends Node

const CHASSIS_PATH := "res://assets/ui/gothic_hud/v2/runtime/bottom_chassis_v2.png"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	var root := hud.get_node("MobileSafeRoot") as Control
	assert(root != null)
	assert(not (root.get_node("TopInfoPanel") as Control).visible)

	var chassis := root.get_node("IntegratedHUDChassis") as Control
	assert(chassis != null and chassis.size == Vector2(820, 273))
	assert(chassis.get_meta("contents") == ["health_orb", "four_item_slots", "mana_orb"])
	assert(chassis.get_node("HealthOrb") != null and chassis.get_node("ManaOrb") != null)
	for index in range(4):
		var item_slot := chassis.get_node("ItemSlot%d" % (index + 1)) as Button
		assert(item_slot != null and item_slot.get_meta("stable_id") == "hud.item_slot.%d" % (index + 1))

	assert(hud.quick_buttons.size() == 4)
	for index in range(4):
		var skill_button := hud.quick_buttons[index]
		assert(skill_button.size.x >= 100 and skill_button.size.y >= 56)
		assert(skill_button.get_parent() == root, "四个职业技能槽不得再套公共背景面板")
		assert(skill_button.get_meta("stable_id") == "hud.profession_skill.%d" % (index + 1))
		assert(skill_button.get_meta("activation_mode_source") == "skill.activation_mode")
		assert(skill_button.get_meta("warrior_policy") == "toggle")
		assert(skill_button.get_meta("mage_tao_policy") == "instant_or_toggle")
	assert((root.get_node("SkillButton1") as Control).position.y >= 450, "职业技能槽仍然过度侵入战斗区域")
	for index in range(3):
		assert(root.get_node("AttackRingSkill%d" % (index + 1)) != null)
	var attack := root.get_node("AttackButton") as Button
	assert(attack.size == Vector2(120, 120), "攻击按钮视觉直径应保持缩小后的120px")
	var joystick := root.get_node("TouchJoystick") as TouchJoystick
	assert(joystick.size.x >= 150 and is_equal_approx(joystick.radius, 58.0), "摇杆触控区和缩小后的可视半径不匹配")
	assert((root.get_node("InventoryButton") as Control).position.y > (root.get_node("MapButton") as Control).position.y)
	assert((root.get_node("SkillBookButton") as Control).position.y > (root.get_node("MenuButton") as Control).position.y)
	assert((root.get_node("SwitchTargetButton") as Control).position.y > (root.get_node("InteractButton") as Control).position.y)

	var image := Image.load_from_file(ProjectSettings.globalize_path(CHASSIS_PATH))
	assert(not image.is_empty() and image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH])
	assert(image.get_pixel(0, 0).a < 0.01 and image.get_pixel(image.get_width() - 1, image.get_height() - 1).a < 0.01)
	assert(image.get_pixel(223, 231).a < 0.05 and image.get_pixel(785, 231).a < 0.05, "血蓝球开口必须保持透明")
	assert(root.get_node("TargetPanel/TargetFrameArt").get_meta("stable_id") == "ui.hud.gothic.v2.target_bar")
	assert(root.get_node("UtilityStackArt").get_meta("stable_id") == "ui.hud.gothic.v2.utility_stack")
	assert(root.get_node("JoystickArt").get_meta("stable_id") == "ui.hud.gothic.v2.joystick")
	assert(root.get_node("RightControlsArt").get_meta("stable_id") == "ui.hud.gothic.v2.right_controls")
	assert(chassis.get_node("DemonChassisArt").get_meta("stable_id") == "ui.hud.gothic.v2.bottom_chassis")
	assert(FileAccess.file_exists("res://assets/ui/gothic_hud/v2/hud_asset_manifest.json"))
	var hud_source := FileAccess.get_file_as_string("res://scripts/hud.gd")
	assert("gothic_hud/v1" not in hud_source and "gothic_preview" not in hud_source, "正式HUD不得继续引用旧素材")
	print("HUD_GOTHIC_RUNTIME_PASS：统一V2透明框体、动态血蓝球、4物品槽、4职业槽、3环绕技能与触控尺寸均通过")
	get_tree().quit(0)
