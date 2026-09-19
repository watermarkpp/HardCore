extends RefCounted
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Binding := preload("res://scripts/map_editor/polygon/poly_instance_binding.gd")

static func prepare(document: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var design_size := Geo.parse_size(document.get("design", {}).get("design_size", []))
	var gathered := Binding.gather(document)
	errors.append_array(gathered.errors)
	var raw_entries: Variant = gathered.records
	var entries: Array = []
	var parts: Array = []
	var seen: Dictionary = {}
	if design_size == Vector2i.ZERO or not raw_entries is Array:
		return {"ok": false, "errors": ["polygon_document_invalid"], "parts": [], "entries": []}
	for raw: Variant in raw_entries:
		if not raw is Dictionary:
			errors.append("polygon_entry_not_dictionary")
			continue
		var id := str(raw.get("collision_id", ""))
		if id.is_empty() or seen.has(id):
			errors.append("polygon_id_missing_or_duplicate:%s" % id)
		seen[id] = true
		if str(raw.get("shape", "")) != "polygon":
			errors.append("polygon_mode_rejects_legacy_shapes:%s" % id)
			continue
		if raw.get("blocks_player", false) != true or raw.get("blocks_monster", false) != true:
			errors.append("polygon_v1_requires_both_actor_masks:%s" % id)
		if str(raw.get("content_layer", "")).is_empty():
			errors.append("polygon_content_layer_missing:%s" % id)
		var data: Variant = raw.get("data", {})
		var checked := Geo.validate(data.get("points", []) if data is Dictionary else [], design_size)
		if not checked.ok:
			for message: String in checked.errors:
				errors.append("%s:%s" % [id, message])
			continue
		var points: PackedVector2Array = checked.points
		var pieces: Array[PackedVector2Array] = Geometry2D.decompose_polygon_in_convex(points)
		var piece_area := 0.0
		if pieces.is_empty():
			errors.append("polygon_decomposition_failed:%s" % id)
			continue
		for piece: PackedVector2Array in pieces:
			if not Geo.convex(piece):
				errors.append("polygon_nonconvex_piece:%s" % id)
			piece_area += absf(Geo.area(piece))
			parts.append(Geo.encode(piece))
		if absf(piece_area - absf(Geo.area(points))) > maxf(0.0001, absf(Geo.area(points)) * 0.00001):
			errors.append("polygon_decomposition_area_changed:%s" % id)
		entries.append({"collision_id": id, "id": id, "shape": "polygon",
			"source": "instance" if not str(raw.get("owner", "")).is_empty() else "manual",
			"owner_instance_id": str(raw.get("owner", "")),
			"polygon_ground_gu": Geo.encode(points),
			"content_layer": str(raw.get("content_layer", "personal_expansion"))})
	if parts.size() > Geo.MAX_PARTS:
		errors.append("polygon_piece_limit_exceeded:%d" % parts.size())
	return {"ok": errors.is_empty(), "errors": errors, "entries": entries, "parts": parts, "design_size": design_size}

static func walkability(document: Dictionary) -> Dictionary:
	var prepared := prepare(document)
	var raw_size: Array = document.get("design", {}).get("design_size", [0, 0])
	var result := {"ok": prepared.ok, "errors": prepared.errors, "map_size": raw_size.duplicate(),
		"blocked_tiles": {}, "blocked_count": 0, "walkable_count": 0,
		"sources": [], "erased_tiles": [], "diagnostic_only": true}
	if not prepared.ok:
		return result
	var index := Index.new()
	var design_size: Vector2i = prepared.design_size
	if not index.setup(design_size, prepared.parts):
		result.ok = false
		result.errors = ["polygon_preview_index_invalid"]
		return result
	var blocked: Dictionary = {}
	## Only rasterize polygon bounding ranges. This grid is a preview / legacy
	## semantic bridge, NEVER physics or the polygon navigation graph.
	for part: PackedVector2Array in index.parts:
		var box := Geo.bounds(part)
		for y: int in range(maxi(0, floori(box.position.y)), mini(design_size.y, ceili(box.end.y))):
			for x: int in range(maxi(0, floori(box.position.x)), mini(design_size.x, ceili(box.end.x))):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), part):
					blocked["%d,%d" % [x, y]] = true
	result.blocked_tiles = blocked
	result.blocked_count = blocked.size()
	result.walkable_count = design_size.x * design_size.y - blocked.size()
	result.sources = prepared.entries
	return result

static func merge_effective_cells(blocked: Dictionary, design_size: Vector2i) -> Dictionary:
	var rows: Dictionary = {}
	for raw_key: Variant in blocked:
		if not raw_key is String:
			return {"ok": false, "errors": ["legacy_cell_key_not_string"]}
		var values := String(raw_key).split(",", false)
		if values.size() != 2 or not values[0].is_valid_int() or not values[1].is_valid_int():
			return {"ok": false, "errors": ["legacy_cell_key_invalid"]}
		var x := int(values[0])
		var y := int(values[1])
		if x < 0 or y < 0 or x >= design_size.x or y >= design_size.y:
			return {"ok": false, "errors": ["legacy_cell_outside_map"]}
		if not rows.has(y):
			rows[y] = []
		rows[y].append(x)
	var ys: Array = rows.keys()
	ys.sort()
	var active: Dictionary = {}
	var rects: Array[Rect2i] = []
	var previous_y := -2
	for y: int in ys:
		if y != previous_y + 1:
			for r: Rect2i in active.values():
				rects.append(r)
			active.clear()
		var xs: Array = rows[y]
		xs.sort()
		var intervals: Array[Vector2i] = []
		for x: int in xs:
			if not intervals.is_empty() and x == intervals[-1].y + 1:
				intervals[-1] = Vector2i(intervals[-1].x, x)
			else:
				intervals.append(Vector2i(x, x))
		var next: Dictionary = {}
		for span: Vector2i in intervals:
			var key := Vector2i(span.x, span.y - span.x + 1)
			var r: Rect2i = active.get(key, Rect2i(span.x, y, key.y, 0))
			r.size.y += 1
			next[key] = r
			active.erase(key)
		for r: Rect2i in active.values():
			rects.append(r)
		active = next
		previous_y = y
	for r: Rect2i in active.values():
		rects.append(r)
	var area_sum := 0
	for r: Rect2i in rects:
		area_sum += r.size.x * r.size.y
	if area_sum != blocked.size():
		return {"ok": false, "errors": ["legacy_merge_cell_count_mismatch"]}
	return {"ok": true, "errors": [], "rects": rects}

static func entry(id: String, points: PackedVector2Array, source := "manual") -> Dictionary:
	return {"collision_id": id, "shape": "polygon", "data": {"points": Geo.encode(points)},
		"source": source, "blocks_player": true, "blocks_monster": true, "content_layer": "personal_expansion"}

static func next_id(entries: Array) -> String:
	var used: Dictionary = {}
	for raw: Dictionary in entries:
		used[str(raw.get("collision_id", ""))] = true
	var sequence := entries.size() + 1
	while used.has("poly_%06d" % sequence):
		sequence += 1
	return "poly_%06d" % sequence

static func migrate(document: Dictionary, effective_walkability: Dictionary) -> Dictionary:
	if Geo.enabled(document):
		return {"ok": false, "errors": ["polygon_already_migrated"]}
	var size_gu := Geo.parse_size(document.get("design", {}).get("design_size", []))
	if size_gu == Vector2i.ZERO or effective_walkability.get("map_size", []) != [size_gu.x, size_gu.y]:
		return {"ok": false, "errors": ["migration_size_mismatch"]}
	var cells: Variant = effective_walkability.get("blocked_tiles", null)
	if not cells is Dictionary:
		return {"ok": false, "errors": ["migration_requires_effective_cell_dictionary"]}
	var merged := merge_effective_cells(cells, size_gu)
	if not merged.ok:
		return merged
	var result := document.duplicate(true)
	var entries: Array = []
	for rect: Rect2i in merged.rects:
		entries.append(entry("poly_legacy_%06d" % entries.size(), Geo.rectangle_points(Rect2(rect)), "legacy_final"))
	result.layers["collision"] = entries
	var meta: Dictionary = result.get("editor_meta", {})
	meta["collision_authority"] = Geo.AUTHORITY
	meta["collision_migration_contract_id"] = "hc.effective_cell_union_migration.v1"
	meta["collision_migration_blocked_count"] = cells.size()
	meta["runtime_approved"] = false
	meta["revision"] = int(meta.get("revision", 1)) + 1
	result.editor_meta = meta
	var checked := prepare(result)
	if not checked.ok:
		return checked
	return {"ok": true, "errors": [], "document": result, "legacy_rect_count": entries.size()}

static func clear_legacy_region(entries: Array, cut: Rect2) -> Array:
	## Only immutable rectangular legacy blocks are cut. Fresh drawn polygons
	## are never deleted by this tool. Splitting produces no hole rings.
	var result: Array = []
	for raw: Dictionary in entries:
		if str(raw.get("source", "")) != "legacy_final":
			result.append(raw.duplicate(true))
			continue
		var points := Geo.decode(raw.get("data", {}).get("points", []))
		var box := Geo.bounds(points)
		var expected := Geo.rectangle_points(box)
		var exact_rectangle := points.size() == 4
		for point: Vector2 in points:
			if not expected.has(point):
				exact_rectangle = false
		if not exact_rectangle or not box.intersects(cut, false):
			result.append(raw.duplicate(true))
			continue
		for piece: Rect2 in Geo.subtract_rectangle(box, cut):
			result.append(entry("", Geo.rectangle_points(piece), "legacy_final"))
	for raw: Dictionary in result:
		if str(raw.get("collision_id", "")).is_empty():
			raw["collision_id"] = next_id(result)
	return result
