extends RefCounted
## Editor/build-time only. Never preload this from a gameplay hot path.
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const Body := preload("res://scripts/actor_body_policy.gd")
const BAKE_SCALE := 64.0
const NAV_CLEARANCE_GU := 0.025
const MAX_PROFILES := 64
const MAX_TOTAL_FACES := 131072
const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
static var _cache_key := ""
static var _cache: Dictionary = {}

## Build-time dependency closure of all legally admitted bodies, including
## template/respawn/summoned identities absent from a map's current spawns.
static func collect_body_radii(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var radii: Dictionary = {}
	var monsters: Array = []
	var entries: Variant = catalog.get("entries_by_id", null)
	if not entries is Dictionary or entries.is_empty():
		return {"ok": false, "errors": ["polygon_canonical_monster_catalog_invalid"]}
	var keys: Array = entries.keys()
	keys.sort()
	for key: Variant in keys:
		var raw: Variant = entries[key]
		if not raw is Dictionary or not raw.get("runtime_allowed", null) is bool:
			errors.append("polygon_canonical_entry_invalid:%s" % str(key))
			continue
		if not raw.runtime_allowed:
			continue
		var id_value: Variant = raw.get("monster_id", null)
		if not Geo.numeric(id_value) or float(id_value) <= 0.0 or float(id_value) != floorf(float(id_value)) or str(int(id_value)) != str(key):
			errors.append("polygon_canonical_monster_id_invalid:%s" % str(key))
			continue
		var id := int(id_value)
		var admitted := MonsterIdentity.require_catalog_entry(id, "runtime")
		var classification := str(raw.get("classification", ""))
		if admitted.is_empty() or classification.is_empty() or classification != str(admitted.get("classification", "")):
			errors.append("polygon_canonical_monster_identity_invalid:%d" % id)
			continue
		var combat: Variant = raw.get("combat", null)
		var body := Body.resolve_monster_body(id, classification, combat.get("body_profile", null) if combat is Dictionary else null)
		if body.is_empty():
			errors.append("polygon_canonical_monster_body_invalid:%d" % id)
			continue
		# Exactly the factory conversion. Do not use the nominal ground_radius_gu
		# or round near 0.5: JSON parsing and division determine the live float.
		var radius := WorldSpatialRules.actor_combat_radius_gu_from_screen_radius_px(float(body.screen_radius_px))
		var radius_key := Graph.key_for_radius(radius)
		radii[radius_key] = radius
		monsters.append({"monster_id": id, "classification": classification,
			"radius_key": radius_key, "radius_gu": radius, "tier": body.tier,
			"policy_sha256": str(body.policy_sha256).to_lower(), "assignment_rule": body.assignment_rule})
	if monsters.is_empty():
		errors.append("polygon_canonical_monster_inventory_empty")
	return {"ok": errors.is_empty(), "errors": errors, "radii": radii, "monsters": monsters,
		"body_inventory_sha256": JSON.stringify(monsters, "", true, true).sha256_text()}

## Formal publication guard; generic polygon fixtures need not know the catalog.
static func validate_monster_coverage(runtime: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var inventory := collect_body_radii(parsed if parsed is Dictionary else {})
	if not inventory.ok:
		return inventory
	var errors: Array[String] = []
	var profiles: Dictionary = {}
	for raw: Variant in runtime.get("collision", {}).get("navigation", {}).get("profiles", []):
		if raw is Dictionary:
			profiles[str(raw.get("radius_key", ""))] = raw
	var available: Array = profiles.keys()
	available.sort()
	var checked: Dictionary = {}
	for key: String in inventory.radii:
		if not profiles.has(key):
			continue
		var graph := Graph.new()
		var result := graph.setup(profiles[key], Geo.parse_size(runtime.get("design", {}).get("design_size", [])))
		checked[key] = bool(result.ok) and graph.ready
	var map_id := int(runtime.get("source", {}).get("runtime_map_id", -1))
	for monster: Dictionary in inventory.monsters:
		if not bool(checked.get(monster.radius_key, false)):
			errors.append("polygon_monster_navigation_missing:map=%d:monster=%d:expected=%s:available=%s" % [map_id, monster.monster_id, monster.radius_key, str(available)])
	return {"ok": errors.is_empty(), "errors": errors, "body_inventory_sha256": inventory.body_inventory_sha256}

static func collect_radii() -> Dictionary:
	var radii: Dictionary = {}
	var errors: Array[String] = []
	if not FileAccess.file_exists(CATALOG_PATH):
		return {"ok": false, "errors": ["polygon_canonical_monster_catalog_missing"]}
	var text := FileAccess.get_file_as_string(CATALOG_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not parsed.get("entries_by_id", null) is Dictionary:
		return {"ok": false, "errors": ["polygon_canonical_monster_catalog_invalid"]}
	var bodies := collect_body_radii(parsed)
	if not bodies.ok:
		return bodies
	# Preserve legacy/nonmonster profiles during this repair; they are extras,
	# never the required admitted-monster radius authority.
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
	radii.merge(bodies.radii, true)
	if radii.size() > MAX_PROFILES:
		errors.append("polygon_nav_profile_limit_exceeded")
	return {"ok": errors.is_empty(), "errors": errors, "radii": radii,
		"catalog_sha256": text.sha256_text(), "required_radii": bodies.radii,
		"monsters": bodies.monsters, "body_inventory_sha256": bodies.body_inventory_sha256}

static func build(document: Dictionary) -> Dictionary:
	var prepared := Author.prepare(document)
	if not prepared.ok:
		return prepared
	var inventory := collect_radii()
	if not inventory.ok:
		return inventory
	var key := JSON.stringify([prepared.entries, document.design.design_size,
		inventory.radii, inventory.catalog_sha256, inventory.body_inventory_sha256], "", true, true).sha256_text()
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
			"clearance_gu": NAV_CLEARANCE_GU, "canonical_catalog_sha256": inventory.catalog_sha256,
			"body_inventory_sha256": inventory.body_inventory_sha256,
			"required_monster_radius_keys": inventory.required_radii.keys()},
	}
	_cache_key = key
	_cache = {"ok": true, "errors": [], "collision": payload,
		"report": {"convex_parts": prepared.parts.size(), "nav_profiles": nav_profiles.size(),
			"nav_faces": total_faces, "overlap_merged": int(prepared.get("merged_polys", 0)),
			"editor_build_usec": Time.get_ticks_usec() - started,
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
