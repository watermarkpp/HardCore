extends SceneTree

## One-off repair (user ruling 2026-09-16): 半兽勇士(38) and 骷髅战将(54) are
## elite monsters game-wide and every other formal map places them in the
## boss_spawn lane with boss_spawn semantic ids (snake valley, wooma forest,
## orc tomb f2/f3). Three legacy authoring rows on world_fengmo_valley and
## world_white_day_gate predate that contract: they sit in monster_spawn with
## monster_spawn ids while carrying classification elite, which the formal
## release approval rejects (spawn_semantic_kind_mismatch). Re-lane exactly
## these rows to boss_spawn with re-derived ids; all other fields, tiles and
## coordinates are preserved. Run headless:
##   godot --headless -s tools/map_editor/relane_elite_spawns.gd

const REPAIRS := [
	{
		"path": "res://map_editor_workspace/world_fengmo_valley/world_fengmo_valley.editor.json",
		"map": "world_fengmo_valley",
		"sources": [
			"mse.placement.v1.world_fengmo_valley.monster_spawn.000002",
			"mse.placement.v1.world_fengmo_valley.monster_spawn.000006",
		],
		"start_index": 4,
	},
	{
		"path": "res://map_editor_workspace/world_white_day_gate/world_white_day_gate.editor.json",
		"map": "world_white_day_gate",
		"sources": [
			"mse.placement.v1.world_white_day_gate.monster_spawn.000003",
		],
		"start_index": 7,
	},
]


func _init() -> void:
	var failed := false
	for repair: Dictionary in REPAIRS:
		if not _repair(repair):
			failed = true
	print("RELANE_ELITE_SPAWNS_%s" % ("FAILED" if failed else "PASS"))
	quit(1 if failed else 0)


func _repair(repair: Dictionary) -> bool:
	var path := str(repair["path"])
	var map_key := str(repair["map"])
	var doc_text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(doc_text)
	if not parsed is Dictionary:
		push_error("RELANE parse failed: %s" % path)
		return false
	var document: Dictionary = parsed
	var layers: Dictionary = document.get("layers", {})
	var monster_layer: Array = layers.get("monster_spawn", [])
	var boss_layer: Array = layers.get("boss_spawn", [])
	var index := int(repair["start_index"])
	var moved := 0
	for source_id: String in repair["sources"]:
		var found := -1
		for entry_index in monster_layer.size():
			var candidate: Dictionary = monster_layer[entry_index]
			if str(candidate.get("semantic_id", "")) == source_id:
				found = entry_index
				break
		if found < 0:
			push_error("RELANE source missing: %s" % source_id)
			return false
		var entry: Dictionary = monster_layer[found]
		monster_layer.remove_at(found)
		var new_id := "mse.placement.v1.%s.boss_spawn.%06d" % [map_key, index]
		entry["semantic_id"] = new_id
		entry["spawn_group_id"] = "mse.group.v1.%s.boss_spawn.%06d" % [map_key, index]
		entry["kind"] = "boss_spawn"
		boss_layer.append(entry)
		print("RELANE %s -> %s (%s)" % [source_id, new_id, str(entry.get("display_name", ""))])
		index += 1
		moved += 1
	layers["monster_spawn"] = monster_layer
	layers["boss_spawn"] = boss_layer
	document["layers"] = layers
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("RELANE write failed: %s" % path)
		return false
	file.store_string(JSON.stringify(document, "  ") + "\n")
	file.close()
	print("RELANE %s moved=%d" % [map_key, moved])
	return moved == (repair["sources"] as Array).size()
