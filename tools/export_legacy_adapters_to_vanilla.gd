extends Node

const OUTPUT := "res://assets/data/vanilla_176/"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var map_content: Array = []
	var spawn_rules: Array = []
	var npcs: Array = []
	var connections: Array = []
	for map: Variant in GameData.maps:
		if not map is Dictionary:
			continue
		var map_id := int(map.get("mapId", -1))
		var content := RegionContent.get_map_content(map_id)
		if content.is_empty():
			continue
		var common := content.duplicate(true)
		common.erase("spawns")
		common.erase("bosses")
		common.erase("npcs")
		common.erase("portals")
		map_content.append({"mapId": map_id, "content": _encode(common)})
		spawn_rules.append({"mapId": map_id, "spawns": _encode(content.get("spawns", [])), "bosses": _encode(content.get("bosses", []))})
		npcs.append({"mapId": map_id, "records": _encode(content.get("npcs", []))})
		connections.append({"mapId": map_id, "records": _encode(content.get("portals", []))})
	_write("map_content.json", _table("map_content", map_content))
	_write("spawn_rules.json", _table("spawn_rules", spawn_rules))
	_write("npcs.json", _table("npcs", npcs))
	_write("map_connections.json", _table("map_connections", connections))
	var drop_records: Array = []
	for monster_name: String in RegionContent.MONSTER_DROPS:
		drop_records.append({"monsterName": monster_name, "drops": _encode(RegionContent.MONSTER_DROPS[monster_name])})
	_write("regional_drops.json", _table("regional_drops", drop_records))
	_write("profession_growth.json", {
		"schemaVersion": 1, "layer": "vanilla_core", "source": "legacy_verified_adapter",
		"confidence": "B", "editable": false,
		"baseStats": _encode(ProfessionRules.BASE_STATS),
		"skillProfiles": _encode(ProfessionRules.SKILL_PROFILES),
		"castDefaults": _encode(ProfessionRules.CAST_DEFAULTS),
		"skillTimingOverrides": _encode(ProfessionRules.SKILL_TIMING_OVERRIDES),
	})
	print("LEGACY_ADAPTER_EXPORT_PASS maps=%d drops=%d" % [map_content.size(), drop_records.size()])
	get_tree().quit(0)


func _table(table_name: String, records: Array) -> Dictionary:
	return {"schemaVersion": 1, "layer": "vanilla_core", "table": table_name, "source": "legacy_verified_adapter", "confidence": "B", "editable": false, "records": records}


func _write(filename: String, data: Dictionary) -> void:
	var file := FileAccess.open(OUTPUT + filename, FileAccess.WRITE)
	assert(file != null, "无法写入%s" % filename)
	file.store_string(JSON.stringify(data, "  "))


func _encode(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i:
		return {"$vector2": [value.x, value.y]}
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[str(key)] = _encode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(_encode(entry))
		return result
	return value
