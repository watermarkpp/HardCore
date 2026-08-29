extends Node


const SOURCE_MAP_ID := "gmd_1"
const SOURCE_IDENTITY := "cangyue_bone_cave_f1"
const SOURCE_DOCUMENT_SHA256 := "e6390371df5fd1b063e912bf21d67b9d76ad3fde6088e380868fba5bbe3f08d6"
const SPECS := [
	{"map_id": "gmd_2", "identity": "cangyue_bone_cave_f2", "source_line": 272},
	{"map_id": "gmd_3", "identity": "cangyue_bone_cave_f3", "source_line": 276},
	{"map_id": "gmd_4", "identity": "cangyue_bone_cave_f4", "source_line": 280},
]


func _ready() -> void:
	var source_path := "res://map_editor_workspace/%s/%s.editor.json" % [SOURCE_MAP_ID, SOURCE_MAP_ID]
	assert(FileAccess.file_exists(source_path), source_path)
	assert(FileAccess.get_sha256(source_path) == SOURCE_DOCUMENT_SHA256, "gmd_1 source changed")

	var source := _load_document(SOURCE_MAP_ID)
	var source_monsters: Array = source.layers.monster_spawn
	var source_bosses: Array = source.layers.boss_spawn
	assert(source_monsters.size() == 34)
	assert(source_bosses.is_empty())

	for spec: Dictionary in SPECS:
		var map_id := str(spec["map_id"])
		var identity := str(spec["identity"])
		var source_line := int(spec["source_line"])
		var document := _load_document(map_id)
		var target_monsters: Array = document.layers.monster_spawn
		var target_bosses: Array = document.layers.boss_spawn

		assert(target_monsters.size() == 34, "%s monster count" % map_id)
		assert(target_bosses.is_empty(), "%s boss count" % map_id)
		assert(target_monsters == _retarget_spawns(source_monsters, identity, source_line), "%s spawn deep equality" % map_id)
		assert(target_bosses == source_bosses, "%s boss array mismatch" % map_id)
		assert(not JSON.stringify(target_monsters).contains(SOURCE_IDENTITY), "%s source identity residual" % map_id)
		assert(not JSON.stringify(target_bosses).contains(SOURCE_IDENTITY), "%s boss identity residual" % map_id)
		_assert_chests(target_monsters, map_id)

	print("MSE_BONE_CAVE_MONSTER_COPY_PASS targets=3 monsters_each=34 bosses_each=0 chests_each=7")
	get_tree().quit(0)


func _load_document(map_id: String) -> Dictionary:
	var path := "res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id]
	var loaded := MapEditorLoadService.load_document(path, false)
	assert(loaded.ok, str(loaded.get("errors", [])))
	return loaded.document


func _retarget_spawns(source_spawns: Array, target_identity: String, target_source_line: int) -> Array:
	var result: Array = source_spawns.duplicate(true)
	for spawn: Dictionary in result:
		if spawn.has("authority_ref"):
			var authority_ref: Dictionary = spawn["authority_ref"]
			if authority_ref.has("map_id"):
				authority_ref["map_id"] = str(authority_ref["map_id"]).replace(SOURCE_IDENTITY, target_identity)
			if authority_ref.has("source_line") and int(authority_ref["source_line"]) == 268:
				if typeof(authority_ref["source_line"]) == TYPE_FLOAT:
					authority_ref["source_line"] = float(target_source_line)
				else:
					authority_ref["source_line"] = target_source_line
		if spawn.has("semantic_id"):
			spawn["semantic_id"] = str(spawn["semantic_id"]).replace(SOURCE_IDENTITY, target_identity)
		if spawn.has("spawn_group_id"):
			spawn["spawn_group_id"] = str(spawn["spawn_group_id"]).replace(SOURCE_IDENTITY, target_identity)
	return result


func _assert_chests(spawns: Array, map_id: String) -> void:
	var chest_counts: Dictionary = {}
	for spawn: Dictionary in spawns:
		var monster_id := int(spawn.get("monster_id", -1))
		if monster_id >= 228 and monster_id <= 234:
			chest_counts[monster_id] = int(chest_counts.get(monster_id, 0)) + 1
	assert(chest_counts.size() == 7, "%s chest total" % map_id)
	for monster_id in range(228, 235):
		assert(int(chest_counts.get(monster_id, 0)) == 1, "%s chest monster_id=%d" % [map_id, monster_id])
