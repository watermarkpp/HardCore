class_name MapEditorRuntimeBridge
extends RefCounted

const BICH_MAP_ID := 4
const SAFE_RADIUS_TILES := 9.0
const MAP_CONFIG := {
	4: {
		"map_key": "bich_province",
		"display_name": "比奇省",
		"marker": "res://assets/data/runtime/map_editor/bich_province.manual_ready.json",
	},
	268: {
		"map_key": "wooma_forest",
		"display_name": "沃玛森林",
		"marker": "res://assets/data/runtime/map_editor/wooma_temple_route.manual_ready.json",
	},
	313: {
		"map_key": "wooma_temple_1",
		"display_name": "沃玛寺庙一层",
		"marker": "res://assets/data/runtime/map_editor/wooma_temple_route.manual_ready.json",
	},
	314: {
		"map_key": "wooma_temple_2",
		"display_name": "沃玛寺庙二层",
		"marker": "res://assets/data/runtime/map_editor/wooma_temple_route.manual_ready.json",
	},
	315: {
		"map_key": "wooma_temple_3",
		"display_name": "沃玛教主大厅",
		"marker": "res://assets/data/runtime/map_editor/wooma_temple_route.manual_ready.json",
	},
}

static var _runtime_cache := {}


static func has_runtime_map(runtime_map_id: int) -> bool:
	if not MAP_CONFIG.has(runtime_map_id):
		return false
	var config: Dictionary = MAP_CONFIG[runtime_map_id]
	return (
		FileAccess.file_exists(str(config.marker))
		and FileAccess.file_exists(runtime_path(runtime_map_id))
	)


static func runtime_path(runtime_map_id: int) -> String:
	if not MAP_CONFIG.has(runtime_map_id):
		return ""
	return (
		"res://assets/data/runtime/map_editor/%s.runtime.json"
		% str(MAP_CONFIG[runtime_map_id].map_key)
	)


static func ground_manifest_path(runtime_map_id: int) -> String:
	if not MAP_CONFIG.has(runtime_map_id):
		return ""
	return (
		"res://map_editor_workspace/%s/ground/ground_manifest.json"
		% str(MAP_CONFIG[runtime_map_id].map_key)
	)


static func visual_path(runtime_map_id: int) -> String:
	if not MAP_CONFIG.has(runtime_map_id):
		return ""
	return (
		"res://assets/data/runtime/map_editor/%s.visual.json"
		% str(MAP_CONFIG[runtime_map_id].map_key)
	)


static func load_map(runtime_map_id: int) -> Dictionary:
	if _runtime_cache.has(runtime_map_id):
		return _runtime_cache[runtime_map_id]
	if not has_runtime_map(runtime_map_id):
		_runtime_cache[runtime_map_id] = {}
		return {}
	var loaded := MapEditorRuntimeMapService.load_runtime(
		runtime_path(runtime_map_id)
	)
	var runtime: Dictionary = loaded.runtime if loaded.ok else {}
	if not runtime.is_empty():
		runtime["runtime_map_id"] = runtime_map_id
	_runtime_cache[runtime_map_id] = runtime
	return runtime


static func load_bich() -> Dictionary:
	return load_map(BICH_MAP_ID)


static func tile_to_world(runtime: Dictionary, raw_tile: Array) -> Vector2:
	var raw_size: Array = runtime.get("design", {}).get(
		"design_size", [256, 256]
	)
	return MapEditorCoordinate.tile_to_world(
		Vector2(float(raw_tile[0]), float(raw_tile[1])),
		Vector2i(int(raw_size[0]), int(raw_size[1]))
	)


static func world_to_tile(runtime: Dictionary, world: Vector2) -> Vector2:
	var raw_size: Array = runtime.get("design", {}).get(
		"design_size", [256, 256]
	)
	return MapEditorCoordinate.world_to_tile(
		world,
		Vector2i(int(raw_size[0]), int(raw_size[1]))
	)


static func portal_position(
	runtime_map_id: int,
	portal_id: String,
	source_map_id := -1
) -> Vector2:
	var runtime := load_map(runtime_map_id)
	if runtime.is_empty():
		return Vector2.ZERO
	for endpoint: Dictionary in runtime.get("semantics", {}).get(
		"map_exit_points", []
	):
		if not portal_id.is_empty() and str(
			endpoint.get("semantic_id", "")
		) == portal_id:
			return tile_to_world(runtime, endpoint.get("tile", [0, 0]))
		if (
			portal_id.is_empty()
			and source_map_id >= 0
			and int(endpoint.get("target_map_id", -1)) == source_map_id
		):
			return tile_to_world(runtime, endpoint.get("tile", [0, 0]))
	return Vector2.ZERO


static func home_position() -> Vector2:
	var runtime := load_bich()
	var safe_areas: Array = runtime.get("semantics", {}).get("safe_area", [])
	for safe: Dictionary in safe_areas:
		if bool(safe.get("return_anchor", false)):
			return tile_to_world(
				runtime,
				safe.get("return_tile", safe.get("tile", [128, 128]))
			)
	# Final editor maps can publish one authoritative safe area without the
	# legacy return/death/logout flags. Keep service-home spawning inside the
	# playable runtime by using that safe area's anchor tile.
	if not safe_areas.is_empty():
		var safe: Dictionary = safe_areas[0]
		return tile_to_world(
			runtime,
			safe.get("return_tile", safe.get("tile", [128, 128]))
		)
	return Vector2.ZERO


static func game_content() -> Dictionary:
	return game_content_for_map(BICH_MAP_ID)


static func game_content_for_map(runtime_map_id: int) -> Dictionary:
	var runtime := load_map(runtime_map_id)
	if runtime.is_empty():
		return {}
	var raw_size: Array = runtime.get("design", {}).get(
		"design_size", [256, 256]
	)
	var map_center_world := tile_to_world(
		runtime,
		[(float(raw_size[0]) - 1.0) * 0.5, (float(raw_size[1]) - 1.0) * 0.5]
	)
	var config: Dictionary = MAP_CONFIG.get(runtime_map_id, {})
	var result := {
		"name": str(config.get("display_name", "地图")),
		"runtime_map_id": runtime_map_id,
		"runtime_map_key": str(config.get("map_key", "")),
		"runtime_home_position": home_position() if runtime_map_id == BICH_MAP_ID else Vector2.ZERO,
		"map_center_world": map_center_world,
		"spawns": [],
		"bosses": [],
		"npcs": [],
		"portals": [],
		"safe_areas": [],
		"editor_runtime": true,
	}
	var semantics: Dictionary = runtime.get("semantics", {})
	for entry: Dictionary in semantics.get("monster_spawn", []):
		result.spawns.append(_combat_spawn(runtime, entry))
	for entry: Dictionary in semantics.get("boss_spawn", []):
		result.bosses.append(_combat_spawn(runtime, entry))
	for entry: Dictionary in semantics.get("npc_points", []):
		var npc_id := str(entry.get("npc_id", ""))
		var stock_key := str({
			"npc.4.001": "general",
			"npc.4.002": "starter_gear",
			"npc.4.003": "books",
		}.get(npc_id, ""))
		result.npcs.append({
			"name": entry.get("display_name", "NPC"),
			"position": tile_to_world(runtime, entry.get("tile", [0, 0])),
			"kind": entry.get("service_role", "dialogue"),
			"npc_id": npc_id,
			"stock": stock_key,
			"appearance": int(entry.get("appearance", -1)),
		})
	for entry: Dictionary in semantics.get("door_points", []):
		if not bool(entry.get("target_configured", true)):
			continue
		if int(entry.get("target_map_id", -1)) < 0:
			continue
		result.portals.append(_portal_record(runtime_map_id, runtime, entry))
	for entry: Dictionary in semantics.get("map_exit_points", []):
		if not bool(entry.get("target_configured", true)):
			continue
		if int(entry.get("target_map_id", -1)) < 0:
			continue
		result.portals.append(_portal_record(runtime_map_id, runtime, entry))
	if runtime_map_id == BICH_MAP_ID:
		result.safe_areas.append({
			"center": home_position(),
			"radius": SAFE_RADIUS_TILES * ArtSpec.TILE_SIZE,
			"radius_tiles": SAFE_RADIUS_TILES,
			"shape": "circle",
			"polygon": PackedVector2Array(),
			"blocks_monster_damage": true,
			"blocks_monster_entry": true,
			"policy_override": "single_player_respawn_circle_9_tiles",
		})
	else:
		for safe: Dictionary in semantics.get("safe_area", []):
			var converted := safe.duplicate(true)
			converted["center"] = tile_to_world(
				runtime, safe.get("tile", [0, 0])
			)
			result.safe_areas.append(converted)
	return result


static func _combat_spawn(
	runtime: Dictionary,
	entry: Dictionary
) -> Dictionary:
	var monster_key := str(entry.get("monster_id", "monster.-1"))
	return {
		"name": entry.get("display_name", ""),
		"monster_id": int(monster_key.trim_prefix("monster.")),
		"position": tile_to_world(runtime, entry.get("tile", [0, 0])),
		"respawn_seconds": float(entry.get("respawn_seconds", 60.0)),
		"count": int(entry.get("count", 1)),
		"max_alive": int(entry.get("max_alive", 1)),
		"radius_tiles": float(entry.get("radius_tiles", 0.0)),
		"spawn_group": entry.duplicate(true),
	}


static func _portal_record(
	source_map_id: int,
	runtime: Dictionary,
	entry: Dictionary
) -> Dictionary:
	return {
		"position": tile_to_world(runtime, entry.get("tile", [0, 0])),
		"source_map_id": source_map_id,
		"source_portal_id": str(entry.get("semantic_id", "")),
		"target_map_id": int(entry.get("target_map_id", -1)),
		"target_map_key": str(entry.get("target_map_key", "")),
		"target_portal_id": str(entry.get("target_portal_id", "")),
		"target_entrance_id": str(entry.get("target_entrance_id", "")),
		"target_tile": entry.get("target_tile", []).duplicate(),
		"label": entry.get("display_name", "地图入口"),
		"portal_contract_id": str(entry.get("portal_contract_id", "")),
		"arrival_reentry_policy_id": str(entry.get("arrival_reentry_policy_id", "")),
		"return_minimum_seconds": float(entry.get("return_minimum_seconds", 0.0)),
		"return_unlock_distance_tiles": float(entry.get("return_unlock_distance_tiles", 0.0)),
		"travel_request_single_flight": bool(entry.get("travel_request_single_flight", false)),
	}
