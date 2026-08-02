class_name MapEditorRuntimeBridge
extends RefCounted

const BICH_MAP_ID := 4
const SAFE_RADIUS_GU := 9.0
const BOSS_RESPAWN_OVERRIDES := {
	218: 3600.0,
	221: 3600.0,
	1578: 1800.0,
}
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
	217: {
		"map_key": "orc_tomb_1",
		"display_name": "兽人古墓一层",
		"marker": "res://assets/data/runtime/map_editor/phase1_map_network.manual_ready.json",
	},
	218: {
		"map_key": "orc_tomb_2",
		"display_name": "兽人古墓二层",
		"marker": "res://assets/data/runtime/map_editor/phase1_map_network.manual_ready.json",
	},
	221: {
		"map_key": "orc_tomb_3",
		"display_name": "兽人古墓三层",
		"marker": "res://assets/data/runtime/map_editor/phase1_map_network.manual_ready.json",
	},
	406: {
		"map_key": "bich_mine_1",
		"display_name": "矿区一层",
		"marker": "res://assets/data/runtime/map_editor/phase1_map_network.manual_ready.json",
	},
	408: {
		"map_key": "bich_mine_2",
		"display_name": "矿区二层",
		"marker": "res://assets/data/runtime/map_editor/phase1_map_network.manual_ready.json",
	},
	1578: {
		"map_key": "corpse_king_hall",
		"display_name": "尸王殿",
		"marker": "res://assets/data/runtime/map_editor/phase1_map_network.manual_ready.json",
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
	return ground_position_gu_to_screen_position_px(
		runtime, _array_to_vector2(raw_tile)
	)


static func ground_position_gu_to_screen_position_px(
	runtime: Dictionary,
	ground_position_gu: Vector2
) -> Vector2:
	var raw_size: Array = runtime.get("design", {}).get(
		"design_size", [256, 256]
	)
	return MapEditorCoordinate.ground_position_gu_to_screen_position_px(
		ground_position_gu,
		Vector2i(int(raw_size[0]), int(raw_size[1]))
	)


static func cell_to_world(runtime: Dictionary, raw_cell: Array) -> Vector2:
	return ground_position_gu_to_screen_position_px(
		runtime, cell_to_ground_position_gu(raw_cell)
	)


static func world_to_tile(runtime: Dictionary, world: Vector2) -> Vector2:
	return screen_position_px_to_ground_position_gu(runtime, world)


static func screen_position_px_to_ground_position_gu(
	runtime: Dictionary,
	screen_position_px: Vector2
) -> Vector2:
	var raw_size: Array = runtime.get("design", {}).get(
		"design_size", [256, 256]
	)
	return MapEditorCoordinate.screen_position_px_to_ground_position_gu(
		screen_position_px,
		Vector2i(int(raw_size[0]), int(raw_size[1]))
	)


static func cell_to_ground_position_gu(raw_cell: Array) -> Vector2:
	return _array_to_vector2(raw_cell) + Vector2(0.5, 0.5)


static func ground_polygon_gu_to_screen_polygon_px(
	runtime: Dictionary,
	raw_polygon_ground_gu: Array
) -> PackedVector2Array:
	var projected := PackedVector2Array()
	for raw_point: Variant in raw_polygon_ground_gu:
		if raw_point is Array and raw_point.size() == 2:
			projected.append(ground_position_gu_to_screen_position_px(
				runtime, _array_to_vector2(raw_point)
			))
	return projected


static func portal_position(
	runtime_map_id: int,
	portal_id: String,
	source_map_id := -1
) -> Vector2:
	var runtime := load_map(runtime_map_id)
	if runtime.is_empty():
		return Vector2.ZERO
	var found := _portal_ground_position_result(
		runtime, portal_id, source_map_id
	)
	if not bool(found.get("ok", false)):
		return Vector2.ZERO
	return ground_position_gu_to_screen_position_px(
		runtime, found.position_ground_gu
	)


static func portal_position_ground_gu(
	runtime_map_id: int,
	portal_id: String,
	source_map_id := -1
) -> Vector2:
	var runtime := load_map(runtime_map_id)
	if runtime.is_empty():
		return Vector2.ZERO
	var found := _portal_ground_position_result(
		runtime, portal_id, source_map_id
	)
	return found.get("position_ground_gu", Vector2.ZERO)


static func _portal_ground_position_result(
	runtime: Dictionary,
	portal_id: String,
	source_map_id: int
) -> Dictionary:
	for endpoint: Dictionary in runtime.get("semantics", {}).get(
		"map_exit_points", []
	):
		if not portal_id.is_empty() and str(
			endpoint.get("semantic_id", "")
		) == portal_id:
			return {
				"ok": true,
				"position_ground_gu": cell_to_ground_position_gu(
					endpoint.get("tile", [0, 0])
				),
			}
		if (
			portal_id.is_empty()
			and source_map_id >= 0
			and int(endpoint.get("target_map_id", -1)) == source_map_id
		):
			return {
				"ok": true,
				"position_ground_gu": cell_to_ground_position_gu(
					endpoint.get("tile", [0, 0])
				),
			}
	return {"ok": false}


static func home_position() -> Vector2:
	var runtime := load_bich()
	if runtime.is_empty():
		return Vector2.ZERO
	return ground_position_gu_to_screen_position_px(
		runtime, home_position_ground_gu()
	)


static func home_position_ground_gu() -> Vector2:
	var runtime := load_bich()
	var safe_areas: Array = runtime.get("semantics", {}).get("safe_area", [])
	for safe: Dictionary in safe_areas:
		if bool(safe.get("return_anchor", false)):
			return cell_to_ground_position_gu(
				safe.get("return_tile", safe.get("tile", [128, 128]))
			)
	# Final editor maps can publish one authoritative safe area without the
	# legacy return/death/logout flags. Keep service-home spawning inside the
	# playable runtime by using that safe area's anchor tile.
	if not safe_areas.is_empty():
		var safe: Dictionary = safe_areas[0]
		return cell_to_ground_position_gu(
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
	var map_center_ground_gu := Vector2(
		(float(raw_size[0]) - 1.0) * 0.5,
		(float(raw_size[1]) - 1.0) * 0.5
	)
	var map_center_world := ground_position_gu_to_screen_position_px(
		runtime, map_center_ground_gu
	)
	var config: Dictionary = MAP_CONFIG.get(runtime_map_id, {})
	var result := {
		"name": str(config.get("display_name", "地图")),
		"runtime_map_id": runtime_map_id,
		"runtime_map_key": str(config.get("map_key", "")),
		"runtime_home_position": home_position() if runtime_map_id == BICH_MAP_ID else Vector2.ZERO,
		"runtime_home_position_ground_gu": home_position_ground_gu() if runtime_map_id == BICH_MAP_ID else Vector2.ZERO,
		"map_center_world": map_center_world,
		"map_center_ground_gu": map_center_ground_gu,
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
		result.bosses.append(_combat_spawn(
			runtime,
			entry,
			float(BOSS_RESPAWN_OVERRIDES.get(runtime_map_id, -1.0))
		))
	for entry: Dictionary in semantics.get("npc_points", []):
		var npc_id := str(entry.get("npc_id", ""))
		var stock_key := str({
			"npc.4.001": "general",
			"npc.4.002": "starter_gear",
			"npc.4.003": "books",
		}.get(npc_id, ""))
		result.npcs.append({
			"name": entry.get("display_name", "NPC"),
			"position": cell_to_world(runtime, entry.get("tile", [0, 0])),
			"position_ground_gu": cell_to_ground_position_gu(
				entry.get("tile", [0, 0])
			),
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
		var home_ground_gu := home_position_ground_gu()
		result.safe_areas.append({
			"center_ground_gu": home_ground_gu,
			"radius_gu": SAFE_RADIUS_GU,
			"shape": "circle",
			"polygon_ground_gu": PackedVector2Array(),
			"blocks_monster_damage": true,
			"blocks_monster_entry": true,
			"policy_override": "single_player_respawn_circle_9_gu",
		})
	else:
		for safe: Dictionary in semantics.get("safe_area", []):
			var converted := safe.duplicate(true)
			var center_ground_gu := cell_to_ground_position_gu(
				safe.get("tile", [0, 0])
			)
			converted["center_ground_gu"] = center_ground_gu
			converted["radius_gu"] = float(safe.get("radius_gu", 0.0))
			converted["polygon_ground_gu"] = safe.get(
				"polygon_ground_gu", []
			).duplicate(true)
			result.safe_areas.append(converted)
	return result


static func _combat_spawn(
	runtime: Dictionary,
	entry: Dictionary,
	respawn_override := -1.0
) -> Dictionary:
	var monster_key := str(entry.get("monster_id", "monster.-1"))
	var respawn_seconds := float(entry.get("respawn_seconds", 60.0))
	if respawn_override > 0.0:
		respawn_seconds = respawn_override
	return {
		"name": entry.get("display_name", ""),
		"monster_id": int(monster_key.trim_prefix("monster.")),
		"position": cell_to_world(runtime, entry.get("tile", [0, 0])),
		"position_ground_gu": cell_to_ground_position_gu(
			entry.get("tile", [0, 0])
		),
		"respawn_seconds": respawn_seconds,
		"count": int(entry.get("count", 1)),
		"max_alive": int(entry.get("max_alive", 1)),
		"radius_gu": float(entry.get("radius_gu", 0.0)),
		"spawn_group": entry.duplicate(true),
	}


static func _portal_record(
	source_map_id: int,
	runtime: Dictionary,
	entry: Dictionary
) -> Dictionary:
	return {
		"position": cell_to_world(runtime, entry.get("tile", [0, 0])),
		"position_ground_gu": cell_to_ground_position_gu(
			entry.get("tile", [0, 0])
		),
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
		"return_unlock_distance_gu": float(entry.get(
			"return_unlock_distance_gu", 0.0
		)),
		"travel_request_single_flight": bool(entry.get("travel_request_single_flight", false)),
	}


static func _array_to_vector2(raw: Array) -> Vector2:
	if raw.size() != 2:
		return Vector2.ZERO
	return Vector2(float(raw[0]), float(raw[1]))
