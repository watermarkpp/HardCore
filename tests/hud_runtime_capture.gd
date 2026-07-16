extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.quick_slots = ["攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"]
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load("res://assets/ui/gothic_preview/world_scene_clean.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate = Color(0.62, 0.58, 0.54, 1.0)
	add_child(background)
	var hud := GameHUD.new()
	add_child(hud)
	var safe_margin_x := int(OS.get_environment("HUD_CAPTURE_SAFE_MARGIN_X"))
	if safe_margin_x > 0:
		var safe_root := hud.get_node("MobileSafeRoot") as Control
		safe_root.offset_left = safe_margin_x
		safe_root.offset_right = -safe_margin_x
	hud.set_zone_name("比奇省 · 恶魔营地")
	hud.update_resources(93, 120, 31, 60)
	hud.update_target("半兽勇士", 386, 520, false, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path("res://outputs/visual_acceptance/hud_runtime")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var viewport_size := get_viewport().get_visible_rect().size
	var capture_name := OS.get_environment("HUD_CAPTURE_NAME")
	if capture_name.is_empty():
		capture_name = "%dx%d" % [int(viewport_size.x), int(viewport_size.y)]
	var output_path := output_dir.path_join("hud_%s.png" % capture_name)
	assert(get_viewport().get_texture().get_image().save_png(output_path) == OK)
	print("HUD_RUNTIME_CAPTURE_PASS output=%s size=%s" % [output_path, viewport_size])
	get_tree().quit(0)
