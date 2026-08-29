extends Node


const SOURCE_ID := "hadd_2"
const SOURCE_SEMANTIC := "mengzhong_dark_area"
const SPECS := [
	{"map_id": "between_life_and_death", "semantic": "mengzhong_between_life_and_death", "keep_dragon": false},
	{"map_id": "terror_space", "semantic": "mengzhong_terror_space", "keep_dragon": false},
	{"map_id": "thin_sky_passage", "semantic": "mengzhong_thin_sky_passage", "keep_dragon": false},
	{"map_id": "death_coffin", "semantic": "mengzhong_death_coffin", "keep_dragon": true},
]


func _ready() -> void:
	var source := _load_document(SOURCE_ID)
	var source_monsters: Array = source.layers.monster_spawn
	var source_bosses: Array = source.layers.boss_spawn
	assert(source_monsters.size() == 27)
	assert(source_bosses.size() == 4)

	for spec: Dictionary in SPECS:
		var map_id := str(spec.map_id)
		var semantic := str(spec.semantic)
		var document := _load_document(map_id)
		var target_monsters: Array = document.layers.monster_spawn
		var all_target_bosses: Array = document.layers.boss_spawn
		var copied_bosses: Array = all_target_bosses.filter(
			func(entry: Dictionary) -> bool: return int(entry.monster_id) != 124
		)

		assert(target_monsters == _retarget_spawns(source_monsters, semantic))
		assert(copied_bosses == _retarget_spawns(source_bosses, semantic))
		assert(target_monsters.size() == 27)
		assert(copied_bosses.size() == 4)
		assert(not JSON.stringify(target_monsters).contains(SOURCE_SEMANTIC))
		assert(not JSON.stringify(copied_bosses).contains(SOURCE_SEMANTIC))

		var dragons: Array = all_target_bosses.filter(
			func(entry: Dictionary) -> bool: return int(entry.monster_id) == 124
		)
		if bool(spec.keep_dragon):
			assert(all_target_bosses.size() == 5)
			assert(dragons.size() == 1)
			assert(str(dragons[0].display_name) == "触龙神")
			assert(str(dragons[0].semantic_id) == "boss_spawn.auto.v2.mengzhong_death_coffin.000124")
			assert(str(dragons[0].spawn_group_id) == "auto:v2:mengzhong_death_coffin:boss:000124")
		else:
			assert(all_target_bosses.size() == 4)
			assert(dragons.is_empty())

	print("MSE_DARK_AREA_MONSTER_COPY_PASS maps=4 monsters_each=27 copied_bosses_each=4 death_coffin_dragons=1")
	get_tree().quit(0)


func _load_document(map_id: String) -> Dictionary:
	var path := "res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id]
	var loaded := MapEditorLoadService.load_document(path, false)
	assert(loaded.ok, str(loaded.get("errors", [])))
	return loaded.document


func _retarget_spawns(source_spawns: Array, target_semantic: String) -> Array:
	var result: Array = source_spawns.duplicate(true)
	for spawn: Dictionary in result:
		var authority_ref: Dictionary = spawn.get("authority_ref", {})
		if str(authority_ref.get("map_id", "")) == SOURCE_SEMANTIC:
			authority_ref.map_id = target_semantic
		spawn.semantic_id = str(spawn.get("semantic_id", "")).replace(SOURCE_SEMANTIC, target_semantic)
		spawn.spawn_group_id = str(spawn.get("spawn_group_id", "")).replace(SOURCE_SEMANTIC, target_semantic)
	return result
