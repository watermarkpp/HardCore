extends Node


const SOURCE_MAP_ID := "nmsm_1"
const SOURCE_IDENTITY := "cangyue_bull_temple_f1"
const SOURCE_DOCUMENT_SHA256 := "17a15f24d78056b4cd3803a69cffbfb6a006ca83bdba563fbfc9db141c5ed39b"
const SOURCE_SPECIES := [210, 212, 214, 216, 231, 232, 233, 234]
const CHEST_SPECIES := [231, 232, 233, 234]
const SPECS := [
	{"map_id": "nmsm_2", "identity": "cangyue_bull_temple_f2", "source_line": 293, "extra_ids": [], "expected_count": 33},
	{"map_id": "nmsm_3", "identity": "cangyue_bull_temple_f3", "source_line": 297, "extra_ids": [220], "expected_count": 34},
	{"map_id": "nmsm_4", "identity": "cangyue_bull_temple_f4", "source_line": 301, "extra_ids": [218, 220], "expected_count": 35},
]

const EXPECTED_EXTRAS := {
	"nmsm_2": [],
	"nmsm_3": [
		{
			"authority_ref": {
				"map_id": "cangyue_bull_temple_f3",
				"source_category_role": "ordinary",
				"source_line": 297,
				"source_token_index": 5,
			},
			"auto_placement_status": "AUTO_POSITIONED",
			"classification": "ordinary",
			"content_layer": "personal_expansion",
			"count": 1,
			"display_name": "牛魔法师",
			"kind": "monster_spawn",
			"max_alive": 1,
			"monster_id": 220,
			"occupancy_footprint_tiles": [1, 1],
			"placement_evidence": {
				"component_id": 0,
				"current_monster_library_only": true,
				"planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
				"selection_score": [0, 41, 44, 11, 3185, -11, -44],
			},
			"radius_gu": 0.0,
			"respawn_policy_id": "normal_cave",
			"runtime_export": true,
			"semantic_id": "monster_spawn.auto.v2.cangyue_bull_temple_f3.000220",
			"spawn_group_id": "auto:v2:cangyue_bull_temple_f3:ordinary:000220",
			"spawn_rule": "single_anchor_user_copy_template",
			"tile": [44, 11],
		},
	],
	"nmsm_4": [
		{
			"authority_ref": {
				"map_id": "cangyue_bull_temple_f4",
				"source_category_role": "ordinary",
				"source_line": 301,
				"source_token_index": 6,
			},
			"auto_placement_status": "AUTO_POSITIONED",
			"classification": "ordinary",
			"content_layer": "personal_expansion",
			"count": 1,
			"display_name": "牛魔将军",
			"kind": "monster_spawn",
			"max_alive": 1,
			"monster_id": 218,
			"occupancy_footprint_tiles": [1, 1],
			"placement_evidence": {
				"component_id": 0,
				"current_monster_library_only": true,
				"planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
				"selection_score": [0, 44, 44, 13, 3215, -13, -42],
			},
			"radius_gu": 0.0,
			"respawn_policy_id": "normal_cave",
			"runtime_export": true,
			"semantic_id": "monster_spawn.auto.v2.cangyue_bull_temple_f4.000218",
			"spawn_group_id": "auto:v2:cangyue_bull_temple_f4:ordinary:000218",
			"spawn_rule": "single_anchor_user_copy_template",
			"tile": [42, 13],
		},
		{
			"authority_ref": {
				"map_id": "cangyue_bull_temple_f4",
				"source_category_role": "ordinary",
				"source_line": 301,
				"source_token_index": 5,
			},
			"auto_placement_status": "AUTO_POSITIONED",
			"classification": "ordinary",
			"content_layer": "personal_expansion",
			"count": 1,
			"display_name": "牛魔法师",
			"kind": "monster_spawn",
			"max_alive": 1,
			"monster_id": 220,
			"occupancy_footprint_tiles": [1, 1],
			"placement_evidence": {
				"component_id": 0,
				"current_monster_library_only": true,
				"planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
				"selection_score": [0, 39, 36, 1, 3215, -37, -1],
			},
			"radius_gu": 0.0,
			"respawn_policy_id": "normal_cave",
			"runtime_export": true,
			"semantic_id": "monster_spawn.auto.v2.cangyue_bull_temple_f4.000220",
			"spawn_group_id": "auto:v2:cangyue_bull_temple_f4:ordinary:000220",
			"spawn_rule": "single_anchor_user_copy_template",
			"tile": [1, 37],
		},
	],
}


func _ready() -> void:
	var source_path := "res://map_editor_workspace/%s/%s.editor.json" % [SOURCE_MAP_ID, SOURCE_MAP_ID]
	assert(FileAccess.file_exists(source_path), source_path)
	assert(FileAccess.get_sha256(source_path) == SOURCE_DOCUMENT_SHA256, "nmsm_1 source changed")

	var source := _load_document(SOURCE_MAP_ID)
	var source_layers: Dictionary = source.get("layers", {})
	var source_monsters := _layer_array(source_layers, "monster_spawn")
	var source_bosses := _layer_array(source_layers, "boss_spawn")
	var source_special := _layer_array(source_layers, "special_monster")
	assert(source_monsters.size() == 33, "source monster count")
	assert(_species(source_monsters) == SOURCE_SPECIES, "source species set")
	assert(_chest_counts(source_monsters) == {231: 1, 232: 1, 233: 1, 234: 2}, "source chest baseline")
	assert(source_bosses.is_empty(), "source boss count")
	assert(source_special.is_empty(), "source special count")

	for spec: Dictionary in SPECS:
		var map_id := str(spec["map_id"])
		var identity := str(spec["identity"])
		var source_line := int(spec["source_line"])
		var document := _load_document(map_id)
		var layers: Dictionary = document.get("layers", {})
		var target_monsters := _layer_array(layers, "monster_spawn")
		var target_bosses := _layer_array(layers, "boss_spawn")
		var target_special := _layer_array(layers, "special_monster")

		assert(target_monsters.size() == int(spec["expected_count"]), "%s monster count" % map_id)
		assert(target_bosses.is_empty(), "%s boss count" % map_id)
		assert(target_special.is_empty(), "%s special count" % map_id)
		assert(target_bosses == source_bosses, "%s boss array" % map_id)
		assert(target_special == source_special, "%s special array" % map_id)
		assert(not JSON.stringify(target_monsters).contains(SOURCE_IDENTITY), "%s source identity residual" % map_id)

		var copied: Array = []
		var extras: Array = []
		for entry: Dictionary in target_monsters:
			if SOURCE_SPECIES.has(int(entry.get("monster_id", -1))):
				copied.append(entry)
			else:
				extras.append(entry)
		assert(copied == _retarget_spawns(source_monsters, identity, source_line), "%s copied spawn deep equality" % map_id)
		assert(
			_normalize_numbers(extras) == _normalize_numbers(EXPECTED_EXTRAS.get(map_id, [])),
			"%s extra object preservation" % map_id
		)
		assert(_species(target_monsters) == _expected_species(spec["extra_ids"]), "%s species set" % map_id)
		assert(_chest_counts(target_monsters) == _chest_counts(source_monsters), "%s chest species/counts" % map_id)
		_assert_unique_semantic_ids(target_monsters, map_id)

	print("MSE_BULL_TEMPLE_MONSTER_COPY_PASS targets=3 counts=33,34,35 extras=nmsm_3:220 nmsm_4:218,220")
	get_tree().quit(0)


func _load_document(map_id: String) -> Dictionary:
	var path := "res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id]
	var loaded := MapEditorLoadService.load_document(path, false)
	assert(loaded.ok, str(loaded.get("errors", [])))
	return loaded.document


func _layer_array(layers: Dictionary, key: String) -> Array:
	var value = layers.get(key, [])
	if value == null:
		return []
	return value as Array


func _retarget_spawns(source_spawns: Array, target_identity: String, target_source_line: int) -> Array:
	var result: Array = source_spawns.duplicate(true)
	for spawn: Dictionary in result:
		if spawn.has("authority_ref"):
			var authority_ref: Dictionary = spawn["authority_ref"]
			if authority_ref.has("map_id"):
				authority_ref["map_id"] = str(authority_ref["map_id"]).replace(SOURCE_IDENTITY, target_identity)
			if authority_ref.has("source_line") and int(authority_ref["source_line"]) == 289:
				if typeof(authority_ref["source_line"]) == TYPE_FLOAT:
					authority_ref["source_line"] = float(target_source_line)
				else:
					authority_ref["source_line"] = target_source_line
		if spawn.has("semantic_id"):
			spawn["semantic_id"] = str(spawn["semantic_id"]).replace(SOURCE_IDENTITY, target_identity)
		if spawn.has("spawn_group_id"):
			spawn["spawn_group_id"] = str(spawn["spawn_group_id"]).replace(SOURCE_IDENTITY, target_identity)
	return result


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


func _chest_counts(spawns: Array) -> Dictionary:
	var counts: Dictionary = {}
	for spawn: Dictionary in spawns:
		var monster_id := int(spawn.get("monster_id", -1))
		if CHEST_SPECIES.has(monster_id):
			counts[monster_id] = int(counts.get(monster_id, 0)) + 1
	return counts


func _assert_unique_semantic_ids(spawns: Array, map_id: String) -> void:
	var seen: Dictionary = {}
	for spawn: Dictionary in spawns:
		var semantic_id := str(spawn.get("semantic_id", ""))
		assert(not semantic_id.is_empty(), "%s empty semantic id" % map_id)
		assert(not seen.has(semantic_id), "%s duplicate semantic id %s" % [map_id, semantic_id])
		seen[semantic_id] = true


func _normalize_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var normalized_dictionary: Dictionary = {}
		var dictionary: Dictionary = value
		for key in dictionary:
			normalized_dictionary[key] = _normalize_numbers(dictionary[key])
		return normalized_dictionary
	if typeof(value) == TYPE_ARRAY:
		var normalized_array: Array = []
		var array: Array = value
		for item in array:
			normalized_array.append(_normalize_numbers(item))
		return normalized_array
	if typeof(value) == TYPE_INT:
		return float(value)
	return value
