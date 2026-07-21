class_name MapEditorRuntimeBridge
extends RefCounted

const BICH_RUNTIME := "res://assets/data/runtime/map_editor/bich_province.runtime.json"
const MANUAL_READY_MARKER := "res://assets/data/runtime/map_editor/bich_province.manual_ready.json"
const SAFE_RADIUS_TILES := 9.0
static var _bich_cache: Dictionary = {}
static var _bich_loaded := false

static func load_bich() -> Dictionary:
	# Human-authored maps are never promoted into the game merely because an
	# intermediate Runtime file exists. Codex creates the marker only after the
	# user explicitly confirms the editor map is ready to load.
	if _bich_loaded:
		return _bich_cache
	_bich_loaded = true
	if not FileAccess.file_exists(MANUAL_READY_MARKER):
		return {}
	var loaded := MapEditorRuntimeMapService.load_runtime(BICH_RUNTIME)
	_bich_cache = loaded.runtime if loaded.ok else {}
	return _bich_cache

static func tile_to_world(runtime: Dictionary, raw_tile: Array) -> Vector2:
	var raw_size: Array = runtime.get("design", {}).get("design_size", [256,256])
	return MapEditorCoordinate.tile_to_world(Vector2(float(raw_tile[0]),float(raw_tile[1])), Vector2i(int(raw_size[0]),int(raw_size[1])))

static func home_position() -> Vector2:
	var runtime := load_bich()
	for safe: Dictionary in runtime.get("semantics", {}).get("safe_area", []):
		if bool(safe.get("return_anchor", false)):
			return tile_to_world(runtime, safe.get("return_tile", safe.get("tile", [128,128])))
	return Vector2.ZERO

static func game_content() -> Dictionary:
	var runtime := load_bich()
	if runtime.is_empty(): return {}
	var design_size: Array = runtime.get("design", {}).get("design_size", [256, 256])
	var map_center_world := tile_to_world(runtime, [(float(design_size[0]) - 1.0) * 0.5, (float(design_size[1]) - 1.0) * 0.5])
	var result := {"name":"比奇省", "runtime_home_position":home_position(), "map_center_world":map_center_world, "spawns":[], "bosses":[], "npcs":[], "portals":[], "safe_areas":[], "editor_runtime":true}
	for entry: Dictionary in runtime.semantics.get("monster_spawn", []):
		var raw_id:=str(entry.get("monster_id","monster.-1")).trim_prefix("monster.")
		result.spawns.append({"name":entry.get("display_name", ""), "monster_id":int(raw_id), "position":tile_to_world(runtime, entry.tile), "respawn_seconds":entry.get("respawn_seconds",60), "count":entry.get("count",1), "max_alive":entry.get("max_alive",1), "radius_tiles":entry.get("radius_tiles",0), "spawn_group":entry})
	for entry: Dictionary in runtime.semantics.get("npc_points", []):
		var npc_id := str(entry.get("npc_id", ""))
		var stock_key := str({"npc.4.001":"general", "npc.4.002":"starter_gear", "npc.4.003":"books"}.get(npc_id, ""))
		result.npcs.append({"name":entry.get("display_name","NPC"), "position":tile_to_world(runtime,entry.tile), "kind":entry.get("service_role","dialogue"), "npc_id":npc_id, "stock":stock_key, "appearance":int(entry.get("appearance", -1))})
	for entry: Dictionary in runtime.semantics.get("door_points", []):
		if not bool(entry.get("target_configured", true)) or int(entry.get("target_map_id", -1)) < 0: continue
		result.portals.append({"position":tile_to_world(runtime,entry.tile), "target_map_id":int(entry.get("target_map_id",-1)), "label":entry.get("display_name","地图入口")})
	for entry: Dictionary in runtime.semantics.get("map_exit_points", []):
		if not bool(entry.get("target_configured", true)) or int(entry.get("target_map_id", -1)) < 0:
			continue
		result.portals.append({
			"position": tile_to_world(runtime, entry.tile),
			"target_map_id": int(entry.get("target_map_id", -1)),
			"target_entrance_id": str(entry.get("target_entrance_id", "")),
			"label": entry.get("display_name", "地图出口"),
		})
	# Single-player policy override: the safe area is a predictable circle with
	# a radius of nine logical tiles around the actual resurrection/return point.
	# Do not reuse the editor's former NPC-hull pentagon for combat rules.
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
	return result
