extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.ensure_zuma_test_character()
	assert(PlayerState.select_character("developer_zuma_warrior_40"))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.hud.visible = false
	if game._system_menu_layer != null:
		game._system_menu_layer.visible = false
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	var output_dir := ProjectSettings.globalize_path("res://outputs/visual_acceptance/ui_gothic_preview")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("world_scene_clean_source.png")
	var error := get_viewport().get_texture().get_image().save_png(output_path)
	assert(error == OK, "无法保存无旧HUD游戏场景")
	print("UI_CLEAN_WORLD_CAPTURE_PASS output=%s" % output_path)
	get_tree().quit(0)
