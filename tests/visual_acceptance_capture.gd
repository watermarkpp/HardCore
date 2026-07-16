extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.ensure_zuma_test_character()
	assert(PlayerState.select_character("developer_zuma_warrior_40"))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.player.facing = Vector2.DOWN
	game.player.get_node("PlayerVisual")._process(0.01)
	var output_dir := ProjectSettings.globalize_path("res://outputs/visual_acceptance")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var world_error := get_viewport().get_texture().get_image().save_png(output_dir.path_join("world_player.png"))
	assert(world_error == OK)
	game.hud._toggle_inventory()
	await get_tree().process_frame
	await get_tree().process_frame
	var error := get_viewport().get_texture().get_image().save_png(output_dir.path_join("equipment_preview.png"))
	assert(error == OK)
	print("VISUAL_ACCEPTANCE_CAPTURE_PASS")
	get_tree().quit(0)
