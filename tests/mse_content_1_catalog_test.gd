extends Node


func _ready() -> void:
	var monsters := MapEditorContentCatalogService.entries("monster_spawn")
	var bosses := MapEditorContentCatalogService.entries("boss_spawn")
	var npcs := MapEditorContentCatalogService.entries("npc", 4)
	assert(monsters.size() > 0)
	assert(bosses.size() > 0)
	assert(not npcs.is_empty() and int(npcs[0].map_id) == 4)
	assert(npcs.size() == 8, "NPC目录应收敛为7种统一功能NPC和1个特殊NPC")
	var service_names := {}
	for npc_entry: Dictionary in npcs:
		var identity_id := str(npc_entry.get("service_identity_id", ""))
		if not identity_id.is_empty():
			assert(not service_names.has(identity_id), "同一功能身份不应重复出现在地图编辑器目录")
			service_names[identity_id] = str(npc_entry.get("display_name", ""))
	assert(service_names.values().has("杂货商"))
	assert(service_names.values().has("铁匠"))
	assert(service_names.values().has("书店老板"))
	assert(service_names.values().has("强化商人"))
	assert(service_names.values().has("老兵"))
	assert(service_names.values().has("药剂商"))
	assert(service_names.values().has("仓库管理员"))
	var mengzhong_general := MapEditorContentCatalogService.find("npc", "npc.478.001")
	assert(str(mengzhong_general.get("display_name", "")) == "杂货商")
	assert(str(mengzhong_general.get("content_id", "")) == "npc.4.001")
	var expansion_blacksmith := MapEditorContentCatalogService.find(
		"npc", "npc.expansion.bich_blacksmith"
	)
	assert(str(expansion_blacksmith.get("display_name", "")) == "铁匠")
	assert(str(expansion_blacksmith.get("content_id", "")) == "npc.4.002")
	var document := MapEditorTypes.new_map("content_1", 990101, "Content 1", Vector2i(64, 64))
	var spawn := MapEditorGameplaySemanticService.add_entry(document, "monster_spawn", Vector2i(20, 20), {
		"monster_id": int(monsters[0].get("monster_id", -1)),
		"display_name": monsters[0].display_name, "count": 8, "max_alive": 6,
		"respawn_seconds": 90, "radius_gu": 5.0,
	})
	assert(spawn.ok and spawn.entry.count == 8 and spawn.entry.max_alive == 6 and spawn.entry.respawn_seconds == 90)
	print("MSE_CONTENT_1_CATALOG_PASS monsters=%d bosses=%d npcs=%d" % [monsters.size(), bosses.size(), npcs.size()])
	get_tree().quit()
