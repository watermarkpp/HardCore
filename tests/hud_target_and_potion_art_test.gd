extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var hud := GameHUD.new()
	add_child(hud)
	var names := ["超级金创药", "超级魔法药", "太阳水", "回城卷"]
	var ids: Array = []
	for name: String in names:
		ids.append(GameData.item_entity_id(name))
	hud.set_item_quick_slots(ids)
	await get_tree().process_frame
	assert(ids[0] == "hc.item.920017" and ids[1] == "hc.item.920042")
	for i in range(4):
		var source: Texture2D = UIItemTextureCache.texture_for(GameData.get_entity_record(ids[i]))
		var shown: Texture2D = hud.item_quick_slot_icons[i].texture
		if i >= 2:
			assert(source == shown, "unrequested item art changed")
			continue
		assert(shown.get_size() == source.get_size())
		assert(GameHUD.QuickItemIconLayout.prepare_texture(source, ids[i]) == shown, "cleanup did not cache its texture")
		var raw := source.get_image()
		var clean := shown.get_image()
		var changed := 0
		var mass := Vector2.ZERO
		var weight := 0.0
		for y in range(raw.get_height()):
			for x in range(raw.get_width()):
				var before := raw.get_pixel(x, y)
				var after := clean.get_pixel(x, y)
				if before != after:
					assert(x == 0 and y >= 16 and y <= 20, "bottle body pixels changed")
					assert(after.a == 0.0 and before.r == after.r and before.g == after.g and before.b == after.b)
					changed += 1
				mass += Vector2(x + 0.5, y + 0.5) * after.a
				weight += after.a
		assert(changed == 5, "expected only five isolated pixels removed")
		var optical := mass / weight
		var icon: TextureRect = hud.item_quick_slot_icons[i]
		assert((icon.position + optical).is_equal_approx(hud.hud_item_buttons[i].size * 0.5), "bottle visual mass is not centered")
	var mask := GameHUD.HUDTargetBarMaskTexture.get_image()
	assert(mask.get_size() == Vector2i(660, 109))
	assert(mask.get_used_rect() == Rect2i(99, 33, 464, 39))
	# The decorative inner edge is curved: at the center its open interior starts at row 34.
	assert(mask.get_pixel(330, 34).a == 1.0 and mask.get_pixel(330, 71).a == 1.0, "top/bottom interior gap survives")
	assert(mask.get_pixel(10, 54).a == 0.0, "decorative exterior was painted over")
	var backdrop: TextureRect = hud.target_panel.get_node("TargetHealthBackdrop")
	assert(backdrop.texture == GameHUD.HUDTargetBarMaskTexture and backdrop.modulate.a == 1.0)
	assert(backdrop.get_index() < hud.target_health_fill.get_index() and hud.target_health_fill.get_index() < hud.target_panel.get_node("TargetFrameArt").get_index())
	for hp in [0, 50, 100]:
		hud.update_target("半兽勇士", hp, 100)
		assert(is_equal_approx(hud.target_health_fill.material.get_shader_parameter("fill_ratio"), hp / 100.0))
		assert(backdrop.visible and backdrop.modulate.a == 1.0, "empty HP exposed the world background")
	var font := hud.target_label.get_theme_font("font") as SystemFont
	assert(font != null and font.font_weight == 400 and not font.font_italic)
	assert(hud.target_label.get_theme_constant("outline_size") == 0)
	assert(hud.target_label.get_theme_constant("shadow_offset_x") == 0 and hud.target_label.get_theme_constant("shadow_offset_y") == 0)
	assert(hud.target_label.get_theme_font_size("font_size") == 18)
	hud.queue_free()
	await get_tree().process_frame
	print("HUD_TARGET_AND_POTION_ART_PASS")
	get_tree().quit(0)
