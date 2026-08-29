extends Node


const SOURCE_MAP_ID := "cyxg_2"
const SOURCE_IDENTITY := "chiyue_valley"
const SOURCE_DOCUMENT_SHA256 := "503865a3db719ac21d216ff209cac428d0581945ada7450b012a2b151c88f101"
const SOURCE_SPECIES := [168, 170, 172, 174, 176, 178]
const SOURCE_COUNTS := {168: 5, 170: 5, 172: 1, 174: 5, 176: 7, 178: 5}
const SPECS := [
	{
		"map_id": "chiyue_valley_secret_passage_a",
		"identity": "chiyue_valley_secret_passage_a",
		"source_line": 244,
		"extra_ids": [164, 166, 182],
		"expected_count": 31,
		"baseline_sha256": "7a6dde6b09dd7e664800e830404e07f773bf35142ffef51926bad18c18a92f7d",
		"nonmonster_raw_sha256": "be2ca0f61bcae457f927d8fcad86e025f42fb745a5800e609d35e5c1a69982c2",
		"extra_sha256": [
			"80056dfdedb4305d22ae116e93167714861101b9d342951e2ba7f5ce68291072",
			"4b76b96d900254476e7885269652f4a89e791b9d49eb5db7c0ce889212f96242",
			"bd13481863756d618a254e4609b51f472fe6bda8602bb50c38cb42cc84adfb92",
		],
	},
	{
		"map_id": "chiyue_valley_secret_passage_b",
		"identity": "chiyue_valley_secret_passage_b",
		"source_line": 251,
		"extra_ids": [164, 166, 182],
		"expected_count": 31,
		"baseline_sha256": "625566b5167acac51313ceaa3299c0a1ae09ad534cac47178abad3862e2f79de",
		"nonmonster_raw_sha256": "713283802744f69d137e2c44c4365eaf97a674084f49bdbf7d9edf3460c60325",
		"extra_sha256": [
			"2ae09a4abab1ad1deecb566900978abb241fef95f5165fa61a1fb66be34e051e",
			"e8945880df774119cdccb5215376551bec3cc01087c8210c08064d3dd1bde4a8",
			"a54c7977ba9b87cee0bd47829f768aecdf4459e09cc24d93ba59835a7168a6da",
		],
	},
]


func _ready() -> void:
	var source_path := "res://map_editor_workspace/%s/%s.editor.json" % [SOURCE_MAP_ID, SOURCE_MAP_ID]
	assert(FileAccess.file_exists(source_path), source_path)
	assert(FileAccess.get_sha256(source_path) == SOURCE_DOCUMENT_SHA256, "cyxg_2 source changed")

	var source := _load_document(source_path)
	var source_layers: Dictionary = source.get("layers", {})
	var source_monsters := _layer_array(source_layers, "monster_spawn")
	var source_bosses := _layer_array(source_layers, "boss_spawn")
	var source_special := _layer_array(source_layers, "special_monster")
	assert(source_monsters.size() == 28, "source monster count")
	assert(_species(source_monsters) == SOURCE_SPECIES, "source species set")
	assert(_counts(source_monsters) == SOURCE_COUNTS, "source species counts")
	assert(source_bosses.is_empty(), "source boss count")
	assert(source_special.is_empty(), "source special count")

	for spec: Dictionary in SPECS:
		var map_id := str(spec["map_id"])
		var identity := str(spec["identity"])
		var source_line := int(spec["source_line"])
		var document_path := "res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id]
		var baseline_path := document_path + ".bak"
		assert(FileAccess.file_exists(document_path), document_path)
		assert(FileAccess.file_exists(baseline_path), baseline_path)
		assert(FileAccess.get_sha256(baseline_path) == str(spec["baseline_sha256"]), "%s baseline changed" % map_id)

		var document := _load_document(document_path)
		var baseline := _load_document(baseline_path)
		var layers: Dictionary = document.get("layers", {})
		var baseline_layers: Dictionary = baseline.get("layers", {})
		var target_monsters := _layer_array(layers, "monster_spawn")
		var target_bosses := _layer_array(layers, "boss_spawn")
		var target_special := _layer_array(layers, "special_monster")
		var baseline_bosses := _layer_array(baseline_layers, "boss_spawn")
		var baseline_special := _layer_array(baseline_layers, "special_monster")

		assert(target_monsters.size() == int(spec["expected_count"]), "%s monster count" % map_id)
		assert(_counts(target_monsters) == {164: 1, 166: 1, 168: 5, 170: 5, 172: 1, 174: 5, 176: 7, 178: 5, 182: 1}, "%s species counts" % map_id)
		assert(target_bosses == baseline_bosses, "%s boss layer changed" % map_id)
		assert(target_special == baseline_special, "%s special layer changed" % map_id)
		assert(_nonmonster_raw_sha256(document_path) == str(spec["nonmonster_raw_sha256"]), "%s non-monster data changed" % map_id)

		var copied: Array = []
		var extras: Array = []
		for spawn: Dictionary in target_monsters:
			if SOURCE_SPECIES.has(int(spawn.get("monster_id", -1))):
				copied.append(spawn)
			else:
				extras.append(spawn)
		assert(copied == _retarget_spawns(source_monsters, identity, source_line), "%s copied spawn deep equality" % map_id)
		assert(_ids(extras) == spec["extra_ids"], "%s extra order/species" % map_id)
		assert(_hashes(extras) == spec["extra_sha256"], "%s extra objects changed" % map_id)
		assert(_species(target_monsters) == _expected_species(spec["extra_ids"]), "%s species set" % map_id)
		_assert_unique_semantic_ids(target_monsters + target_bosses + target_special, map_id)

		for spawn: Dictionary in copied:
			var authority_ref: Dictionary = spawn.get("authority_ref", {})
			assert(str(authority_ref.get("map_id", "")) == identity, "%s copied authority map" % map_id)
			assert(int(authority_ref.get("source_line", -1)) == source_line, "%s copied source line" % map_id)
			assert(str(authority_ref.get("map_id", "")) != SOURCE_IDENTITY, "%s source authority leak" % map_id)
			assert(str(spawn.get("semantic_id", "")).find("." + SOURCE_IDENTITY + ".") == -1, "%s source semantic leak" % map_id)
			assert(str(spawn.get("spawn_group_id", "")).find(":" + SOURCE_IDENTITY + ":") == -1, "%s source group leak" % map_id)

	print("MSE_CHIYUE_VALLEY_SECRET_PASSAGE_MONSTER_COPY_PASS targets=2 monsters_each=31 extras=164,166,182 bosses_preserved=true")
	get_tree().quit(0)


func _load_document(path: String) -> Dictionary:
	var loaded := MapEditorLoadService.load_document(path, false)
	assert(loaded.ok, "%s %s" % [path, str(loaded.get("errors", []))])
	return loaded.document


func _layer_array(layers: Dictionary, key: String) -> Array:
	var value = layers.get(key, [])
	if value == null:
		return []
	return value as Array


func _nonmonster_raw_sha256(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var start := raw.find("    \"monster_spawn\": [")
	var end := raw.find("    \"npc_points\"", start)
	assert(start >= 0 and end > start, "%s monster layer bounds" % path)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update((raw.substr(0, start) + raw.substr(end)).to_utf8_buffer())
	return context.finish().hex_encode()


func _retarget_spawns(source_spawns: Array, target_identity: String, target_source_line: int) -> Array:
	var result: Array = source_spawns.duplicate(true)
	for spawn: Dictionary in result:
		if spawn.has("authority_ref"):
			var authority_ref: Dictionary = spawn["authority_ref"]
			if authority_ref.has("map_id"):
				authority_ref["map_id"] = str(authority_ref["map_id"]).replace(SOURCE_IDENTITY, target_identity)
			if authority_ref.has("source_line") and int(authority_ref["source_line"]) == 235:
				if typeof(authority_ref["source_line"]) == TYPE_FLOAT:
					authority_ref["source_line"] = float(target_source_line)
				else:
					authority_ref["source_line"] = target_source_line
		if spawn.has("semantic_id"):
			spawn["semantic_id"] = str(spawn["semantic_id"]).replace(SOURCE_IDENTITY, target_identity)
		if spawn.has("spawn_group_id"):
			spawn["spawn_group_id"] = str(spawn["spawn_group_id"]).replace(SOURCE_IDENTITY, target_identity)
	return result


func _ids(spawns: Array) -> Array:
	var ids: Array = []
	for spawn: Dictionary in spawns:
		ids.append(int(spawn.get("monster_id", -1)))
	return ids


func _species(spawns: Array) -> Array:
	var species: Array = []
	for spawn: Dictionary in spawns:
		var monster_id := int(spawn.get("monster_id", -1))
		if not species.has(monster_id):
			species.append(monster_id)
	species.sort()
	return species


func _expected_species(extra_ids: Array) -> Array:
	var expected: Array = SOURCE_SPECIES.duplicate()
	for monster_id_variant in extra_ids:
		var monster_id := int(monster_id_variant)
		if not expected.has(monster_id):
			expected.append(monster_id)
	expected.sort()
	return expected


func _counts(spawns: Array) -> Dictionary:
	var counts: Dictionary = {}
	for spawn: Dictionary in spawns:
		var monster_id := int(spawn.get("monster_id", -1))
		counts[monster_id] = int(counts.get(monster_id, 0)) + 1
	return counts


func _hashes(spawns: Array) -> Array:
	var hashes: Array = []
	for spawn: Dictionary in spawns:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(JSON.stringify(spawn).to_utf8_buffer())
		hashes.append(context.finish().hex_encode())
	return hashes


func _assert_unique_semantic_ids(spawns: Array, map_id: String) -> void:
	var seen: Dictionary = {}
	for spawn: Dictionary in spawns:
		var semantic_id := str(spawn.get("semantic_id", ""))
		assert(not semantic_id.is_empty(), "%s empty semantic id" % map_id)
		assert(not seen.has(semantic_id), "%s duplicate semantic id %s" % [map_id, semantic_id])
		seen[semantic_id] = true

