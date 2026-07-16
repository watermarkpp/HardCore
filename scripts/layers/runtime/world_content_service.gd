extends Node

const PATHS := {
	"map": "res://assets/data/vanilla_176/map_content.json",
	"spawn": "res://assets/data/vanilla_176/spawn_rules.json",
	"npc": "res://assets/data/vanilla_176/npcs.json",
	"connection": "res://assets/data/vanilla_176/map_connections.json",
	"drops": "res://assets/data/vanilla_176/regional_drops.json",
}

var maps: Dictionary = {}
var drops: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	maps.clear()
	drops.clear()
	for row: Variant in _records(PATHS.map):
		if row is Dictionary:
			maps[int(row.get("mapId", -1))] = _decode(row.get("content", {}))
	for row: Variant in _records(PATHS.spawn):
		if row is Dictionary:
			var content := _map_entry(int(row.get("mapId", -1)))
			content["spawns"] = _decode(row.get("spawns", []))
			content["bosses"] = _decode(row.get("bosses", []))
	for row: Variant in _records(PATHS.npc):
		if row is Dictionary:
			_map_entry(int(row.get("mapId", -1)))["npcs"] = _decode(row.get("records", []))
	for row: Variant in _records(PATHS.connection):
		if row is Dictionary:
			_map_entry(int(row.get("mapId", -1)))["portals"] = _decode(row.get("records", []))
	for row: Variant in _records(PATHS.drops):
		if row is Dictionary:
			drops[str(row.get("monsterName", ""))] = _decode(row.get("drops", []))


func has_map(map_id: int) -> bool:
	return maps.has(map_id)


func map_content(map_id: int) -> Dictionary:
	return maps.get(map_id, {}).duplicate(true)


func monster_drops(monster_name: String) -> Array:
	return drops.get(monster_name, []).duplicate(true)


func _map_entry(map_id: int) -> Dictionary:
	if not maps.has(map_id):
		maps[map_id] = {"spawns": [], "bosses": [], "npcs": [], "portals": []}
	return maps[map_id]


func _records(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("Vanilla世界表缺失：%s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed.get("records", []) if parsed is Dictionary else []


func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("$vector2"):
			var pair: Array = value["$vector2"]
			return Vector2(float(pair[0]), float(pair[1]))
		var decoded := {}
		for key: Variant in value:
			decoded[key] = _decode(value[key])
		return decoded
	if value is Array:
		var decoded: Array = []
		for entry: Variant in value:
			decoded.append(_decode(entry))
		return decoded
	return value
