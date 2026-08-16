extends Node


func _ready() -> void:
	var monsters := MapEditorContentCatalogService.entries("monster_spawn")
	var bosses := MapEditorContentCatalogService.entries("boss_spawn")
	var npcs := MapEditorContentCatalogService.entries("npc", 4)
	assert(monsters.size() > 0)
	assert(bosses.size() > 0)
	assert(not npcs.is_empty() and int(npcs[0].map_id) == 4)
	var document := MapEditorTypes.new_map("content_1", 990101, "Content 1", Vector2i(64, 64))
	var spawn := MapEditorGameplaySemanticService.add_entry(document, "monster_spawn", Vector2i(20, 20), {
		"content_id": monsters[0].content_id, "monster_id": monsters[0].content_id,
		"display_name": monsters[0].display_name, "count": 8, "max_alive": 6,
		"respawn_seconds": 90, "radius_tiles": 5,
	})
	assert(spawn.ok and spawn.entry.count == 8 and spawn.entry.max_alive == 6 and spawn.entry.respawn_seconds == 90)
	print("MSE_CONTENT_1_CATALOG_PASS monsters=%d bosses=%d npcs=%d" % [monsters.size(), bosses.size(), npcs.size()])
	get_tree().quit()
