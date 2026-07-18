class_name MapEditorGameplaySemanticService
extends RefCounted

const KIND_TO_LAYER := {
	"npc": "npc_points", "monster_spawn": "monster_spawn", "boss_spawn": "boss_spawn", "door": "door_points",
	"map_entrance": "map_entrance_points", "map_exit": "map_exit_points", "respawn_point": "respawn_points",
	"safe_area": "safe_area", "light": "light", "region_trigger": "region_trigger",
}


static func add_entry(document: Dictionary, kind: String, tile: Vector2i, properties := {}) -> Dictionary:
	if not KIND_TO_LAYER.has(kind):
		return {"ok": false, "errors": ["invalid_semantic_kind"]}
	var errors := _validate(document, kind, tile, properties)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var layer := str(KIND_TO_LAYER[kind])
	var entries: Array = document.layers.get(layer, [])
	var entry := _defaults(kind, tile, properties)
	if kind == "respawn_point" and bool(entry.get("is_default", true)):
		for existing: Dictionary in entries:
			existing["is_default"] = false
	entry["semantic_id"] = _next_semantic_id(entries, kind)
	match kind:
		"map_entrance":
			if str(entry.get("entrance_id", "")).ends_with(".unassigned"):
				entry["entrance_id"] = str(entry.semantic_id)
		"map_exit":
			if str(entry.get("exit_id", "")).ends_with(".unassigned"):
				entry["exit_id"] = str(entry.semantic_id)
		"respawn_point":
			if str(entry.get("respawn_id", "")).ends_with(".unassigned"):
				entry["respawn_id"] = str(entry.semantic_id)
		"safe_area":
			if str(entry.get("area_id", "")).ends_with(".unassigned"):
				entry["area_id"] = str(entry.semantic_id)
	entries.append(entry)
	document.layers[layer] = entries
	return {"ok": true, "entry": entry, "layer": layer}


static func _next_semantic_id(entries: Array, kind: String) -> String:
	var maximum := 0
	var prefix := kind + "_"
	for entry: Dictionary in entries:
		var semantic_id := str(entry.get("semantic_id", ""))
		if semantic_id.begins_with(prefix):
			maximum = maxi(maximum, semantic_id.trim_prefix(prefix).to_int())
	return "%s_%06d" % [kind, maximum + 1]


static func repair_duplicate_ids(document: Dictionary) -> int:
	var repaired := 0
	for kind: String in KIND_TO_LAYER:
		var layer := str(KIND_TO_LAYER[kind])
		var entries: Array = document.layers.get(layer, [])
		var used := {}
		var next_number := 1
		for index in entries.size():
			var semantic_id := str(entries[index].get("semantic_id", ""))
			if semantic_id.is_empty() or used.has(semantic_id):
				while used.has("%s_%06d" % [kind, next_number]): next_number += 1
				semantic_id = "%s_%06d" % [kind, next_number]
				entries[index]["semantic_id"] = semantic_id
				repaired += 1
			used[semantic_id] = true
		document.layers[layer] = entries
	return repaired


static func all_entries(document: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind: String in KIND_TO_LAYER:
		for entry: Dictionary in document.layers.get(KIND_TO_LAYER[kind], []):
			result.append(entry)
	return result


static func move_entry(document:Dictionary,semantic_id:String,delta:Vector2i)->Dictionary:
	for layer:String in KIND_TO_LAYER.values():
		var entries:Array=document.layers.get(layer,[])
		for index in entries.size():
			if str(entries[index].get("semantic_id",""))!=semantic_id:continue
			var tile:Array=entries[index].get("tile",[0,0]); var next:=Vector2i(int(tile[0]),int(tile[1]))+delta
			var size:Array=document.design.design_size
			if next.x<0 or next.y<0 or next.x>=int(size[0]) or next.y>=int(size[1]):return {"ok":false,"errors":["越出地图边界"]}
			if str(entries[index].get("kind", "")) == "safe_area" and str(entries[index].get("shape", "circle")) == "polygon":
				var shifted_points: Array = []
				for raw_point: Variant in entries[index].get("polygon_tiles", []):
					if not raw_point is Array or raw_point.size() != 2:
						continue
					var shifted := Vector2i(int(raw_point[0]), int(raw_point[1])) + delta
					if shifted.x < 0 or shifted.y < 0 or shifted.x >= int(size[0]) or shifted.y >= int(size[1]):
						return {"ok": false, "errors": ["安全区多边形将越出地图边界"]}
					shifted_points.append([shifted.x, shifted.y])
				entries[index]["polygon_tiles"] = shifted_points
			entries[index]["tile"]=[next.x,next.y]; document.layers[layer]=entries; return {"ok":true,"entry":entries[index]}
	return {"ok":false,"errors":["未找到功能点"]}


static func delete_entry(document:Dictionary,semantic_id:String)->Dictionary:
	for layer:String in KIND_TO_LAYER.values():
		var entries:Array=document.layers.get(layer,[])
		for index in entries.size():
			if str(entries[index].get("semantic_id",""))==semantic_id:
				entries.remove_at(index); document.layers[layer]=entries; return {"ok":true}
	return {"ok":false,"errors":["未找到功能点"]}


static func duplicate_entry_snapshot(
	document: Dictionary,
	source_entry: Dictionary,
	tile: Vector2i
) -> Dictionary:
	var kind := str(source_entry.get("kind", ""))
	if not KIND_TO_LAYER.has(kind):
		return {"ok": false, "errors": ["invalid_semantic_kind"]}
	var source_tile_raw: Array = source_entry.get("tile", [0, 0])
	var source_tile := Vector2i(int(source_tile_raw[0]), int(source_tile_raw[1]))
	var delta := tile - source_tile
	var properties := source_entry.duplicate(true)
	for identity_key: String in [
		"semantic_id", "door_id", "entrance_id", "exit_id", "respawn_id",
		"area_id", "light_id", "trigger_id", "placeholder_instance_id",
		"linked_visual_instance_id",
	]:
		properties.erase(identity_key)
	properties.erase("tile")
	properties.erase("kind")
	if kind == "safe_area" and str(source_entry.get("shape", "circle")) == "polygon":
		var translated_polygon: Array = []
		for raw_point: Variant in source_entry.get("polygon_tiles", []):
			if not raw_point is Array or raw_point.size() != 2:
				return {"ok": false, "errors": ["safe_area_polygon_point_invalid"]}
			translated_polygon.append([
				int(raw_point[0]) + delta.x,
				int(raw_point[1]) + delta.y,
			])
		properties["polygon_tiles"] = translated_polygon
	return add_entry(document, kind, tile, properties)


static func find_entry(document: Dictionary, semantic_id: String) -> Dictionary:
	for layer: String in KIND_TO_LAYER.values():
		for entry: Dictionary in document.layers.get(layer, []):
			if str(entry.get("semantic_id", "")) == semantic_id:
				return entry
	return {}


static func update_entry(document: Dictionary, semantic_id: String, properties: Dictionary) -> Dictionary:
	for layer: String in KIND_TO_LAYER.values():
		var entries: Array = document.layers.get(layer, [])
		for index in entries.size():
			if str(entries[index].get("semantic_id", "")) != semantic_id:
				continue
			for key: String in properties:
				entries[index][key] = properties[key]
			document.layers[layer] = entries
			return {"ok": true, "entry": entries[index]}
	return {"ok": false, "errors": ["未找到功能点"]}


static func sync_linked_instance_tile(document: Dictionary, instance_id: String, tile: Vector2i) -> Dictionary:
	var size: Array = document.get("design", {}).get("design_size", [0, 0])
	if tile.x < 0 or tile.y < 0 or tile.x >= int(size[0]) or tile.y >= int(size[1]):
		return {"ok": false, "errors": ["semantic_tile_out_of_bounds"], "updated": 0}
	var updated := 0
	for layer: String in KIND_TO_LAYER.values():
		var entries: Array = document.layers.get(layer, [])
		for index in entries.size():
			if str(entries[index].get("linked_visual_instance_id", "")) != instance_id:
				continue
			entries[index]["tile"] = [tile.x, tile.y]
			updated += 1
		document.layers[layer] = entries
	return {"ok": true, "updated": updated}


static func delete_linked_instance_entries(document: Dictionary, instance_id: String) -> int:
	var deleted := 0
	for layer: String in KIND_TO_LAYER.values():
		var entries: Array = document.layers.get(layer, [])
		for index in range(entries.size() - 1, -1, -1):
			if str(entries[index].get("linked_visual_instance_id", "")) != instance_id:
				continue
			entries.remove_at(index)
			deleted += 1
		document.layers[layer] = entries
	return deleted


static func _defaults(kind: String, tile: Vector2i, properties: Dictionary) -> Dictionary:
	var entry := {"kind": kind, "tile": [tile.x, tile.y], "content_layer": "personal_expansion", "runtime_export": true}
	match kind:
		"npc": entry.merge({"npc_id": "npc.unassigned", "service_role": "dialogue", "facing": "south", "safe": true})
		"monster_spawn": entry.merge({"monster_id": "monster.unassigned", "count": 1, "max_alive": 1, "respawn_seconds": 60, "radius_tiles": 2, "spawn_rule": "ambient"})
		"boss_spawn": entry.merge({"boss_id": "boss.unassigned", "count": 1, "max_alive": 1, "respawn_seconds": 1800, "radius_tiles": 0, "spawn_rule": "boss"})
		"door": entry.merge({"door_id": "door.unassigned", "target_map_id": "", "target_tile": [0, 0], "one_way": false, "semantic_role":"map_portal", "trigger_on_enter":true, "blocks_movement":false})
		"map_entrance": entry.merge({"entrance_id": "entrance.unassigned", "portal_role": "entrance", "is_default": false, "semantic_role": "map_landing_point", "blocks_movement": false})
		"map_exit": entry.merge({"exit_id": "exit.unassigned", "portal_role": "exit", "target_map_id": "", "target_entrance_id": "", "semantic_role": "map_exit_trigger", "trigger_on_enter": true, "blocks_movement": false})
		"respawn_point": entry.merge({"respawn_id": "respawn.unassigned", "is_birth_point": true, "is_respawn_point": true, "is_default": true, "semantic_role": "birth_and_respawn"})
		"safe_area": entry.merge({"area_id": "safe.unassigned", "shape": "circle", "radius_tiles": 4, "polygon_tiles": [], "blocks_pvp": true, "blocks_monster_damage": true, "return_anchor": false})
		"light": entry.merge({"light_id": "light.unassigned", "radius_tiles": 3, "color": "#f2b96d", "intensity": 1.0, "flicker": false})
		"region_trigger": entry.merge({"trigger_id": "trigger.unassigned", "radius_tiles": 2, "trigger_type": "enter", "action": "dialogue_or_event", "once": false})
	entry.merge(properties, true)
	return entry


static func _validate(document: Dictionary, kind: String, tile: Vector2i, properties: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var size: Array = document.design.get("design_size", [0, 0])
	if tile.x < 0 or tile.y < 0 or tile.x >= int(size[0]) or tile.y >= int(size[1]):
		errors.append("semantic_tile_out_of_bounds")
	if kind == "door" and str(properties.get("target_map_id", "")).strip_edges().is_empty():
		errors.append("door_target_map_required")
	if kind in ["npc", "monster_spawn", "boss_spawn"] and str(properties.get("content_id", "")).strip_edges().is_empty():
		errors.append("content_id_required")
	if kind in ["monster_spawn", "boss_spawn"]:
		if int(properties.get("count", 1)) <= 0: errors.append("positive_spawn_count_required")
		if int(properties.get("max_alive", 1)) <= 0: errors.append("positive_max_alive_required")
		if int(properties.get("respawn_seconds", 1)) <= 0: errors.append("positive_respawn_required")
	if kind == "safe_area" and str(properties.get("shape", "circle")) == "polygon":
		var polygon: Array = properties.get("polygon_tiles", [])
		if polygon.size() < 3:
			errors.append("safe_area_polygon_requires_three_points")
		for point: Variant in polygon:
			if not point is Array or point.size() != 2:
				errors.append("safe_area_polygon_point_invalid")
				continue
			if int(point[0]) < 0 or int(point[1]) < 0 or int(point[0]) >= int(size[0]) or int(point[1]) >= int(size[1]):
				errors.append("safe_area_polygon_out_of_bounds")
	if kind in ["safe_area", "light", "region_trigger"] and str(properties.get("shape", "circle")) != "polygon" and int(properties.get("radius_tiles", 0)) <= 0:
		errors.append("positive_radius_required")
	return errors
