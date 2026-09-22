extends RefCounted
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")

const MAX_LOADED_RELEASES := 2
static var _loaded: Array[Dictionary] = []
static var _pending: Dictionary = {}

static func remember_validation(runtime: Dictionary, result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		_pending = {"runtime": runtime, "collision": runtime.collision,
			"build_sha256": runtime.build_sha256, "snapshot": result.snapshot}

static func _seal(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values():
			_seal(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value:
			_seal(child)
		value.make_read_only()

static func seal_loaded(runtime: Dictionary) -> void:
	# Called only by successful file load, NOT generic validate/compile. The
	# published collision is static, while the editor document stays writable.
	if _pending.is_empty() or not is_same(runtime, _pending.runtime) or not is_same(runtime.get("collision"), _pending.collision):
		return
	if str(runtime.get("build_sha256", "")) != str(_pending.build_sha256):
		_pending.clear()
		return
	_seal(runtime.collision)
	if _loaded.size() >= MAX_LOADED_RELEASES:
		_loaded.pop_front()
	_loaded.append(_pending)
	_pending = {}

static func clear_loaded_cache() -> void:
	_loaded.clear()
	_pending.clear()

static func _cached(collision: Dictionary, sha: String, map_id: int, size_gu: Vector2i) -> Dictionary:
	if not collision.is_read_only():
		return {}
	for entry: Dictionary in _loaded:
		var snapshot: Dictionary = entry.snapshot
		if is_same(collision, entry.collision) and str(entry.build_sha256) == sha and int(snapshot.runtime_map_id) == map_id and snapshot.design_size == size_gu:
			return {"ok": true, "errors": [], "snapshot": snapshot.duplicate(false)}
	return {}

static func compile(runtime: Dictionary, expected_map_id := -1, include_navigation := false) -> Dictionary:
	var errors: Array[String] = []
	var build_sha: Variant = runtime.get("build_sha256", null)
	if not build_sha is String or build_sha.length() != 64 or not build_sha.is_valid_hex_number():
		errors.append("polygon_build_sha256_invalid")
	var source: Variant = runtime.get("source", {})
	var raw_map_id: Variant = source.get("runtime_map_id", null) if source is Dictionary else null
	var map_id := -1
	if not Geo.numeric(raw_map_id) or float(raw_map_id) <= 0.0 or float(raw_map_id) != floorf(float(raw_map_id)):
		errors.append("polygon_source_map_id_invalid")
	else:
		map_id = int(raw_map_id)
	if expected_map_id > 0 and map_id != expected_map_id:
		errors.append("polygon_runtime_map_id_mismatch")
	if runtime.has("runtime_map_id") and runtime.runtime_map_id != map_id:
		errors.append("polygon_top_level_map_id_mismatch")
	var design_size := Geo.parse_size(runtime.get("design", {}).get("design_size", []))
	if design_size == Vector2i.ZERO:
		errors.append("polygon_design_invalid")
	var collision: Variant = runtime.get("collision", null)
	if not collision is Dictionary:
		return {"ok": false, "errors": ["polygon_collision_missing"], "snapshot": {}}
	if str(collision.get("coordinate_contract_id", "")) != Geo.CONTRACT or str(collision.get("physics_source_id", "")) != Geo.PHYSICS_SOURCE:
		errors.append("polygon_contract_invalid")
	if str(collision.get("ground_coordinate_contract_id", "")) != "isometric_cell_center_64x32_v2":
		errors.append("polygon_ground_contract_invalid")
	var raw_parts: Variant = collision.get("convex_parts_ground_gu", null)
	if not raw_parts is Array or raw_parts.size() > Geo.MAX_PARTS:
		errors.append("polygon_convex_parts_invalid")
	var nav: Variant = collision.get("navigation", {})
	if not nav is Dictionary or str(nav.get("contract_id", "")) != "hc.polygon_nav_faces.v1":
		errors.append("polygon_navigation_contract_invalid")
	var profiles: Variant = nav.get("profiles", null) if nav is Dictionary else null
	if not profiles is Array or profiles.is_empty() or profiles.size() > 64:
		errors.append("polygon_navigation_profiles_invalid")
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "snapshot": {}}
	var cached := _cached(collision, str(build_sha), map_id, design_size)
	if not cached.is_empty():
		return cached
	var index := Index.new()
	if not index.setup(design_size, raw_parts):
		return {"ok": false, "errors": ["polygon_index_rejected"], "snapshot": {}}
	var graphs: Dictionary = {}
	var seen: Dictionary = {}
	var total_faces := 0
	for raw: Variant in profiles:
		if not raw is Dictionary:
			errors.append("polygon_nav_profile_not_dictionary")
			continue
		var key := str(raw.get("radius_key", ""))
		if key.length() != 16 or not key.is_valid_hex_number() or seen.has(key):
			errors.append("polygon_nav_radius_duplicate_or_invalid")
		seen[key] = true
		var raw_faces: Variant = raw.get("faces", null)
		if not raw_faces is Array or raw_faces.size() > Graph.MAX_FACES:
			errors.append("polygon_nav_face_count_invalid")
			continue
		total_faces += raw_faces.size()
		if include_navigation:
			var graph := Graph.new()
			var checked := graph.setup(raw, design_size)
			if not checked.ok:
				errors.append_array(checked.errors)
			else:
				graphs[key] = graph
	if total_faces > 131072:
		errors.append("polygon_total_nav_faces_exceeded")
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "snapshot": {}}
	graphs.make_read_only()
	return {"ok": true, "errors": [], "snapshot": {
		"contract_id": Geo.CONTRACT, "physics_source_id": Geo.PHYSICS_SOURCE,
		"runtime_map_id": map_id, "build_sha256": build_sha,
		"design_size": design_size, "poly_index": index, "poly_graphs": graphs,
		"blocked_cell_ids": {}, "blocked_count": int(collision.get("blocked_count", 0)),
	}}

static func context(runtime_map_id: int, runtime: Dictionary, ground_contract: String, terrain_contract: String) -> Dictionary:
	var result := compile(runtime, runtime_map_id, true)
	var blocked: Dictionary = {}
	blocked.make_read_only()
	var context_value := {"valid": false, "contract_id": terrain_contract,
		"runtime_map_id": runtime_map_id, "coordinate_contract_id": ground_contract,
		"build_sha256": str(runtime.get("build_sha256", "")), "blocked_cells": blocked,
		"design_size": Vector2i.ZERO, "reason": "polygon_context_invalid"}
	if result.ok and ground_contract == "isometric_cell_center_64x32_v2":
		var snapshot: Dictionary = result.snapshot
		context_value.valid = true
		context_value.design_size = snapshot.design_size
		context_value["blocked_count"] = 0
		context_value["poly_index"] = snapshot.poly_index
		context_value["poly_graphs"] = snapshot.poly_graphs
		context_value.reason = ""
	context_value.make_read_only()
	return context_value

static func point_world(snapshot: Dictionary, screen_position_px: Vector2) -> bool:
	if not screen_position_px.is_finite() or not snapshot.has("poly_index"):
		return true
	var point := Coord.screen_position_px_to_ground_position_gu(screen_position_px, snapshot.design_size)
	var index: Index = snapshot.poly_index
	return index.point_blocked(point)

static func actor_world(snapshot: Dictionary, center_px: Vector2, offsets_px: PackedVector2Array) -> bool:
	if not snapshot.has("poly_index") or not center_px.is_finite() or offsets_px.is_empty():
		return true
	var footprint := PackedVector2Array()
	var max_offset := 0.0
	for offset: Vector2 in offsets_px:
		if not offset.is_finite():
			return true
		max_offset = maxf(max_offset, offset.length_squared())
		footprint.append(Coord.screen_position_px_to_ground_position_gu(center_px + offset, snapshot.design_size))
	var index: Index = snapshot.poly_index
	if max_offset <= Geo.EPS * Geo.EPS:
		return index.point_blocked(footprint[0])
	return index.footprint_blocked(footprint)

static func point_walkable(context_value: Dictionary, point_gu: Vector2, radius_gu: float) -> bool:
	if not bool(context_value.get("valid", false)) or not context_value.has("poly_index"):
		return false
	var index: Index = context_value.poly_index
	return not index.circle_blocked(point_gu, radius_gu)

static func segment_walkable(context_value: Dictionary, a: Vector2, b: Vector2, radius_gu: float) -> bool:
	if not bool(context_value.get("valid", false)) or not context_value.has("poly_index"):
		return false
	var index: Index = context_value.poly_index
	return not index.capsule_blocked(a, b, radius_gu)
