extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.set_later_content_enabled(true)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.hud._toggle_map_panel()
	game.hud.map_panel.search_box.text = "沃玛寺庙"
	game.hud.map_panel.refresh()
	for index in range(game.hud.map_panel.map_entries.size()):
		if int(game.hud.map_panel.map_entries[index].get("mapId", -1)) == 315:
			game.hud.map_panel.map_list.select(index)
			game.hud.map_panel._show_selected(index)
			break
