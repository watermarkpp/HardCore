extends SceneTree

const DOCUMENT_PATH := "res://map_editor_workspace/bich_province/bich_province.editor.json"


func _init() -> void:
	var loaded := MapEditorLoadService.load_document(DOCUMENT_PATH)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var document: Dictionary = loaded.document
	document.editor_meta.revision = int(document.editor_meta.get("revision", 1)) + 1
	document.editor_meta["milestone"] = "BICH-MAP-2"
	# Idempotent rebuild of content layers; BICH-MAP-1 geometry remains untouched.
	document.layers.npc_points = []
	document.layers.monster_spawn = []
	document.layers.boss_spawn = []
	document.layers.safe_area = []
	document.layers.region_trigger = []

	# Vanilla NPCs follow the order in vanilla_176/npcs.json mapId=4.
	_npc(document, "npc.4.001", "比奇杂货商", "shop", Vector2i(103,122), "south_east", "vanilla_176")
	_npc(document, "npc.4.002", "比奇武器店", "shop", Vector2i(150,122), "south_west", "vanilla_176")
	_npc(document, "npc.4.003", "书店老板", "shop", Vector2i(136,105), "south", "vanilla_176")
	_npc(document, "npc.4.004", "武馆教头", "trainer", Vector2i(122,151), "north", "vanilla_176")
	_npc(document, "npc.4.005", "比奇老兵", "quest", Vector2i(121,105), "south", "vanilla_176")
	# Single-player service additions live in the expansion layer.
	_npc(document, "npc.expansion.bich_warehouse", "比奇仓库管理员", "warehouse", Vector2i(103,137), "east", "personal_expansion_001")
	_npc(document, "npc.expansion.bich_pharmacist", "比奇药剂商", "shop", Vector2i(151,137), "west", "personal_expansion_001")
	_npc(document, "npc.expansion.bich_blacksmith", "比奇铁匠", "repair", Vector2i(137,151), "north", "personal_expansion_001")

	var safe := MapEditorGameplaySemanticService.add_entry(document, "safe_area", Vector2i(128,128), {
		"area_id":"safe.bich_city", "display_name":"比奇主城安全区", "radius_gu":16,
		"blocks_pvp":true, "blocks_monster_damage":true, "return_anchor":true,
		"return_tile":[128,128], "forced_return_on_exit":true, "forced_return_on_process_loss":true,
	})
	assert(safe.ok)
	assert(MapEditorGameplaySemanticService.add_entry(document, "region_trigger", Vector2i(128,128), {
		"trigger_id":"trigger.bich_set_home", "radius_gu":16, "trigger_type":"enter",
		"action":"set_nearest_town_return_anchor", "once":false,
	}).ok)

	# Spawn ecology: no chickens/deer. Roads and the 16-tile city safety ring remain clear.
	# Near-field starter ring.
	_spawn_many(document, "monster.21", "稻草人", [Vector2i(82,92),Vector2i(72,118),Vector2i(79,175),Vector2i(112,181),Vector2i(177,174),Vector2i(181,112)], 7, 5, 45, 7)
	_spawn_many(document, "monster.24", "多钩猫", [Vector2i(61,78),Vector2i(55,158),Vector2i(190,77),Vector2i(202,150)], 6, 5, 55, 8)
	_spawn_many(document, "monster.26", "钉耙猫", [Vector2i(79,55),Vector2i(173,55),Vector2i(73,199),Vector2i(180,200)], 6, 5, 55, 8)
	# Far-field groups are tougher and denser.
	_spawn_many(document, "monster.34", "半兽人", [Vector2i(34,50),Vector2i(218,48),Vector2i(222,210),Vector2i(52,219)], 7, 6, 80, 10)
	_spawn_many(document, "monster.28", "森林雪人", [Vector2i(25,94),Vector2i(230,91),Vector2i(226,174)], 5, 4, 90, 9)
	_spawn_many(document, "monster.30", "食人花", [Vector2i(45,32),Vector2i(207,30),Vector2i(32,190),Vector2i(208,227)], 3, 3, 120, 5)

	var save := MapEditorSaveService.save_document(document, DOCUMENT_PATH)
	assert(save.ok, str(save.get("errors", [])))
	var approval := MapEditorBuildRuntimeService.approve_for_runtime(document)
	assert(approval.ok, str(approval.get("errors", [])))
	var runtime := MapEditorBuildRuntimeService.build(document, "res://assets/data/runtime/map_editor/bich_province.runtime.json")
	assert(runtime.ok, str(runtime.get("errors", [])))
	print("BICH_MAP_2_PASS npcs=%d spawn_groups=%d safe=%d runtime=%s" % [document.layers.npc_points.size(), document.layers.monster_spawn.size(), document.layers.safe_area.size(), runtime.path])
	quit()


func _npc(document: Dictionary, npc_id: String, display_name: String, role: String, tile: Vector2i, facing: String, source: String) -> void:
	var result := MapEditorGameplaySemanticService.add_entry(document, "npc", tile, {
		"content_id":npc_id, "npc_id":npc_id, "display_name":display_name, "service_role":role,
		"facing":facing, "safe":true, "source":source, "content_layer":"vanilla_core" if source == "vanilla_176" else "personal_expansion",
	})
	assert(result.ok, str(result.get("errors", [])))


func _spawn_many(document: Dictionary, monster_id: String, display_name: String, points: Array[Vector2i], count: int, max_alive: int, respawn: int, radius: int) -> void:
	for point: Vector2i in points:
		var result := MapEditorGameplaySemanticService.add_entry(document, "monster_spawn", point, {
			"content_id":monster_id, "monster_id":monster_id, "display_name":display_name,
			"count":count, "max_alive":max_alive, "respawn_seconds":respawn, "radius_gu":radius,
			"spawn_rule":"ambient_cluster", "source":"vanilla_176_recomposed", "road_clearance_tiles":5,
		})
		assert(result.ok, str(result.get("errors", [])))
