extends RefCounted
## Serialized convex nav faces. Graph edges go THROUGH shared portals, never
## straight through arbitrary centroids. No NavigationServer RID at runtime.
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const MAX_BUCKET_REFERENCES := 1048576
const BUCKET_GU := 8.0
const MAX_FACES := 32768
const ATTACH_LIMIT_GU := 0.20
var radius_key := ""
var radius_gu := 0.0
var vertices := PackedVector2Array()
var faces: Array[PackedVector2Array] = []
var centers := PackedVector2Array()
var links: Array = []
var buckets: Dictionary = {}
var ready := false

static func key_for_radius(value: float) -> String:
	## Exact IEEE-754 key; different body radii never share a smaller profile.
	return PackedFloat64Array([value]).to_byte_array().hex_encode()

func setup(record: Dictionary, design_size: Vector2i) -> Dictionary:
	var errors: Array[String] = []
	radius_key = str(record.get("radius_key", ""))
	var raw_radius: Variant = record.get("radius_gu", null)
	if not Geo.numeric(raw_radius) or float(raw_radius) < 0.0 or radius_key.length() != 16 or not radius_key.is_valid_hex_number():
		return {"ok": false, "errors": ["nav_radius_invalid"]}
	radius_gu = float(raw_radius)
	if key_for_radius(radius_gu) != radius_key:
		return {"ok": false, "errors": ["nav_radius_key_mismatch"]}
	var bucket_references := 0
	vertices = Geo.decode(record.get("vertices_ground_gu", []))
	var raw_faces: Variant = record.get("faces", null)
	if not raw_faces is Array or raw_faces.size() > MAX_FACES or vertices.size() > MAX_FACES * 3:
		return {"ok": false, "errors": ["nav_faces_invalid"]}
	var canonical: Dictionary = {}
	var canonical_ids: Array[int] = []
	for i: int in range(vertices.size()):
		if not canonical.has(vertices[i]):
			canonical[vertices[i]] = i
		canonical_ids.append(int(canonical[vertices[i]]))
	var edges: Dictionary = {}
	for raw: Variant in raw_faces:
		if not raw is Array or raw.size() < 3 or raw.size() > Geo.MAX_VERTICES:
			return {"ok": false, "errors": ["nav_face_vertex_count_invalid"]}
		var polygon := PackedVector2Array()
		var ids: Array[int] = []
		for value: Variant in raw:
			if not Geo.numeric(value) or float(value) != floorf(float(value)) or int(value) < 0 or int(value) >= vertices.size():
				return {"ok": false, "errors": ["nav_face_index_invalid"]}
			ids.append(canonical_ids[int(value)])
			polygon.append(vertices[int(value)])
		var checked := Geo.validate(Geo.encode(polygon), design_size)
		if not checked.ok or not Geo.convex(polygon):
			return {"ok": false, "errors": ["nav_face_not_simple_convex"]}
		var id := faces.size()
		var center := Vector2.ZERO
		for p: Vector2 in polygon:
			center += p
		center /= float(polygon.size())
		faces.append(polygon)
		centers.append(center)
		links.append([])
		var box := Geo.bounds(polygon)
		var first := _bucket(box.position)
		var last := _bucket(box.end)
		bucket_references += (last.x - first.x + 1) * (last.y - first.y + 1)
		if bucket_references > MAX_BUCKET_REFERENCES:
			return {"ok": false, "errors": ["nav_bucket_capacity_exceeded"]}
		for y: int in range(first.y, last.y + 1):
			for x: int in range(first.x, last.x + 1):
				var bucket_id := Vector2i(x, y)
				if not buckets.has(bucket_id):
					buckets[bucket_id] = []
				buckets[bucket_id].append(id)
		for i: int in range(ids.size()):
			var a := ids[i]
			var b := ids[(i + 1) % ids.size()]
			var edge_key := Vector2i(mini(a, b), maxi(a, b))
			if not edges.has(edge_key):
				edges[edge_key] = [id]
			else:
				(edges[edge_key] as Array).append(id)
				if edges[edge_key].size() > 2:
					errors.append("nav_nonmanifold_edge")
	for edge_key: Vector2i in edges:
		var owners: Array = edges[edge_key]
		if owners.size() != 2:
			continue
		var a: int = owners[0]
		var b: int = owners[1]
		var portal := (vertices[edge_key.x] + vertices[edge_key.y]) * 0.5
		var cost := centers[a].distance_to(portal) + portal.distance_to(centers[b])
		links[a].append({"to": b, "portal": portal, "cost": cost})
		links[b].append({"to": a, "portal": portal, "cost": cost})
	for row: Array in links:
		row.make_read_only()
	for row: Array in buckets.values():
		row.make_read_only()
	buckets.make_read_only()
	ready = errors.is_empty()
	return {"ok": ready, "errors": errors}

func _bucket(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / BUCKET_GU), floori(point.y / BUCKET_GU))

func locate(point: Vector2) -> int:
	if not ready or not point.is_finite():
		return -1
	for id: int in buckets.get(_bucket(point), []):
		if Geometry2D.is_point_in_polygon(point, faces[id]):
			return id
	return -1

func attach(point: Vector2, collision_index: Index, exact_radius: float) -> Dictionary:
	if not ready or collision_index.circle_blocked(point, exact_radius):
		return {}
	var inside_id := locate(point)
	if inside_id >= 0:
		return {"face": inside_id, "point": point}
	## The bake has explicit clearance. A legal actor just outside that extra
	## margin may WALK to a nearby face. This is NOT a teleport or radius change.
	var first := _bucket(point - Vector2.ONE * ATTACH_LIMIT_GU)
	var last := _bucket(point + Vector2.ONE * ATTACH_LIMIT_GU)
	var seen: Dictionary = {}
	var best := ATTACH_LIMIT_GU * ATTACH_LIMIT_GU
	var result: Dictionary = {}
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			for id: int in buckets.get(Vector2i(x, y), []):
				if seen.has(id):
					continue
				seen[id] = true
				var polygon: PackedVector2Array = faces[id]
				for i: int in range(polygon.size()):
					var nearest := Geo.nearest_on_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])
					var distance := point.distance_squared_to(nearest)
					if distance < best and not collision_index.capsule_blocked(point, nearest, exact_radius):
						best = distance
						result = {"face": id, "point": nearest}
	return result
