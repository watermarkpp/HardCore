extends RefCounted
## Editor/build-time only. Never preload this from a gameplay hot path.
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const BAKE_SCALE := 64.0
const NAV_CLEARANCE_GU := 0.025
const MAX_PROFILES := 64
const MAX_TOTAL_FACES := 131072
const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
static var _cache_key := ""
static var _cache: Dictionary = {}

static func collect_radii() -> Dictionary:
	var radii: Dictionary = {}
	var errors: Array[String] = []
	if not FileAccess.file_exists(CATALOG_PATH):
		return {"ok": false, "errors": ["polygon_canonical_monster_catalog_missing"]}
	var text := FileAccess.get_file_as_string(CATALOG_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not parsed.get("entries_by_id", null) is Dictionary:
		return {"ok": false, "errors": ["polygon_canonical_monster_catalog_invalid"]}
	var default_radius := float(ArtSpec.MONSTER_COLLISION_RADIUS_PX) / (32.0 * sqrt(2.0))
	var boss_radius := float(ArtSpec.BOSS_COLLISION_RADIUS_PX) / (32.0 * sqrt(2.0))
	radii[Graph.key_for_radius(default_radius)] = default_radius
	radii[Graph.key_for_radius(boss_radius)] = boss_radius
	for raw: Variant in parsed.entries_by_id.values():
		if not raw is Dictionary or not bool(raw.get("runtime_allowed", false)):
			continue
		var radius := boss_radius if str(raw.get("classification", "")) == "boss" else default_radius
		if str(raw.get("classification", "")) != "boss":
			var profile: Dictionary = raw.get("combat", {}).get("behavior_profile", {})
			if profile.has("combat_radius_gu"):
				if not Geo.numeric(profile.combat_radius_gu):
					errors.append("polygon_canonical_body_radius_invalid")
					continue
				radius = maxf(0.0, float(profile.combat_radius_gu))
			elif profile.has("collisionRadius"):
				if not Geo.numeric(profile.collisionRadius):
					errors.append("polygon_canonical_body_radius_invalid")
					continue
				radius = maxf(0.0, float(profile.collisionRadius)) / (32.0 * sqrt(2.0))
		if radius > 16.0:
			errors.append("polygon_body_radius_outside_supported_range")
			continue
		radii[Graph.key_for_radius(radius)] = radius
	if radii.size() > MAX_PROFILES:
		errors.append("polygon_nav_profile_limit_exceeded")
	return {"ok": errors.is_empty(), "errors": errors, "radii": radii,
		"catalog_sha256": text.sha256_text()}

static func build(document: Dictionary) -> Dictionary:
	var prepared := Author.prepare(document)
	if not prepared.ok:
		return prepared
	var inventory := collect_radii()
	if not inventory.ok:
		return inventory
	var key := JSON.stringify([prepared.entries, document.design.design_size,
		inventory.radii, inventory.catalog_sha256], "", true, true).sha256_text()
	if key == _cache_key and not _cache.is_empty():
		return _cache.duplicate(true)
	var started := Time.get_ticks_usec()
	var index := Index.new()
	var size_gu: Vector2i = prepared.design_size
	if not index.setup(size_gu, prepared.parts):
		return {"ok": false, "errors": ["polygon_build_index_invalid"]}
	var nav_profiles: Array = []
	var total_faces := 0
	var radius_keys: Array = inventory.radii.keys()
	radius_keys.sort()
	for radius_key: String in radius_keys:
		var radius: float = inventory.radii[radius_key]
		var baked := _bake(size_gu, prepared.entries, index, radius, radius_key)
		if not baked.ok:
			return baked
		total_faces += baked.record.faces.size()
		if total_faces > MAX_TOTAL_FACES:
			return {"ok": false, "errors": ["polygon_total_nav_face_limit_exceeded"]}
		nav_profiles.append(baked.record)
	var diagnostic := Author.walkability(document)
	if not diagnostic.ok:
		return diagnostic
	var blocked: Array = diagnostic.blocked_tiles.keys()
	blocked.sort()
	var payload := {
		"coordinate_contract_id": Geo.CONTRACT,
		"ground_coordinate_contract_id": "isometric_cell_center_64x32_v2",
		"physics_source_id": Geo.PHYSICS_SOURCE,
		"convex_parts_ground_gu": prepared.parts,
		"authored_polygons_ground_gu": prepared.entries,
		"blocked_tiles": blocked, "blocked_count": blocked.size(),
		"blocked_tiles_role": "diagnostic_center_sample_only",
		"navigation": {"contract_id": "hc.polygon_nav_faces.v1", "profiles": nav_profiles,
			"clearance_gu": NAV_CLEARANCE_GU, "canonical_catalog_sha256": inventory.catalog_sha256},
	}
	_cache_key = key
	_cache = {"ok": true, "errors": [], "collision": payload,
		"report": {"convex_parts": prepared.parts.size(), "nav_profiles": nav_profiles.size(),
			"nav_faces": total_faces, "editor_build_usec": Time.get_ticks_usec() - started,
			"loading_bake_required": false}}
	return _cache.duplicate(true)

static func _scaled(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p: Vector2 in points:
		result.append(p * BAKE_SCALE)
	return result

static func _bake(size_gu: Vector2i, entries: Array, index: Index, radius: float, radius_key: String) -> Dictionary:
	var mesh := NavigationPolygon.new()
	mesh.agent_radius = (radius + NAV_CLEARANCE_GU) * BAKE_SCALE
	mesh.cell_size = 0.125
	mesh.sample_partition_type = NavigationPolygon.SAMPLE_PARTITION_TRIANGULATE
	var source := NavigationMeshSourceGeometryData2D.new()
	source.add_traversable_outline(_scaled(Geo.rectangle_points(Rect2(Vector2.ZERO, Vector2(size_gu)))))
	for record: Dictionary in entries:
		source.add_obstruction_outline(_scaled(Geo.decode(record.polygon_ground_gu)))
	NavigationServer2D.bake_from_source_geometry_data(mesh, source)
	var vertices := mesh.get_vertices()
	for i: int in range(vertices.size()):
		vertices[i] /= BAKE_SCALE
	var faces: Array = []
	if mesh.get_polygon_count() > Graph.MAX_FACES:
		return {"ok": false, "errors": ["polygon_single_nav_profile_too_large"]}
	for i: int in range(mesh.get_polygon_count()):
		var ids := mesh.get_polygon(i)
		if ids.size() < 3 or ids.size() > Geo.MAX_VERTICES:
			return {"ok": false, "errors": ["polygon_bake_invalid_face"]}
		for vertex_id: int in ids:
			if vertex_id < 0 or vertex_id >= vertices.size():
				return {"ok": false, "errors": ["polygon_bake_invalid_vertex"]}
		var face: Array = []
		var center := Vector2.ZERO
		for vertex_id: int in ids:
			face.append(vertex_id)
			center += vertices[vertex_id]
		center /= float(ids.size())
		if index.circle_blocked(center, radius):
			return {"ok": false, "errors": ["polygon_nav_bake_center_clearance_failed"]}
		for j: int in range(ids.size()):
			if index.capsule_blocked(vertices[ids[j]], vertices[ids[(j + 1) % ids.size()]], radius):
				return {"ok": false, "errors": ["polygon_nav_bake_edge_clearance_failed"]}
		faces.append(face)
	var record := {"radius_key": radius_key, "radius_gu": radius,
		"vertices_ground_gu": Geo.encode(vertices), "faces": faces}
	var graph := Graph.new()
	var checked := graph.setup(record, size_gu)
	if not checked.ok:
		return checked
	return {"ok": true, "errors": [], "record": record}
