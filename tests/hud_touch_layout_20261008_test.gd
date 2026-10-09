extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var hud := GameHUD.new()
	add_child(hud)
	var ids: Array = []
	for name: String in ["超级金创药", "超级魔法药", "太阳水", "回城卷"]:
		ids.append(GameData.item_entity_id(name))
	hud.set_item_quick_slots(ids)
	await get_tree().process_frame
	await get_tree().process_frame
	var root: Control = hud.get_node("MobileSafeRoot")
	var attack: Button = hud.attack_button
	assert(attack.size.is_equal_approx(Vector2(102, 102)))
	assert(hud.attack_slot_icon.size.is_equal_approx(Vector2(76.5, 76.5)))
	assert((root.get_node("AttackFrame") as Control).size.is_equal_approx(Vector2(108.8, 108.8)))
	var controls: Array[Control] = [attack, hud.movement_joystick, root.get_node("SwitchTargetButton"), root.get_node("InteractButton")]
	for button: Button in hud.attack_ring_skill_buttons:
		assert(button.size.is_equal_approx(Vector2(86.4, 86.4)))
		assert((button.get_node("SkillIcon") as Control).size.is_equal_approx(Vector2(60, 60)))
		assert(not button._has_point(Vector2.ZERO))
		controls.append(button)
	assert(hud.movement_joystick.size.is_equal_approx(Vector2(182.4, 182.4)))
	assert(hud.movement_joystick.position.is_equal_approx(Vector2(54.8, root.size.y - 241.2)))
	assert(is_equal_approx(hud.movement_joystick.radius, 69.6) and is_equal_approx(hud.movement_joystick.knob_radius, 28.8))
	for name: String in ["SwitchTarget", "Interact"]:
		var button: Button = root.get_node(name + "Button")
		var frame: Control = root.get_node(name + "Frame")
		assert(button.size.is_equal_approx(Vector2(91.2, 91.2)))
		assert(button.get_global_rect().is_equal_approx(frame.get_global_rect()), "utility art and hit rect differ")
		assert(not button._has_point(Vector2.ZERO), "utility corner invisibly owns a hit")
	for a: Control in controls:
		assert(Rect2(Vector2.ZERO, root.size).encloses(a.get_rect()), "control escaped safe area: " + a.name)
		for b: Control in controls:
			if a == b or a == hud.movement_joystick or b == hud.movement_joystick:
				continue
			assert(a.get_global_rect().get_center().distance_to(b.get_global_rect().get_center()) > (a.size.x + b.size.x) * 0.5, "circular hit regions overlap: " + a.name + "/" + b.name)
	# Source-pixel geometry is the frame authority; only the two requested potions
	# center their cleaned optical mass, preserving authored native dimensions.
	for i in range(4):
		var button: Button = hud.hud_item_buttons[i]
		var icon: TextureRect = hud.item_quick_slot_icons[i]
		var visible_center: Vector2 = GameHUD.QuickItemIconLayout.visible_center(icon.texture)
		assert((icon.position + visible_center * icon.size / icon.texture.get_size()).is_equal_approx(button.size * 0.5))
		if i < 2:
			var expected_center := Vector2(13.884615, 13.542735) if i == 0 else Vector2(14.040179, 13.589286)
			assert(visible_center.is_equal_approx(expected_center), "potion optical center incorrect")
			assert(icon.size.is_equal_approx(Vector2(20, 25)), "native potion art was resized")
	hud.queue_free()
	await get_tree().process_frame
	print("HUD_TOUCH_LAYOUT_20261008_PASS")
	get_tree().quit(0)
