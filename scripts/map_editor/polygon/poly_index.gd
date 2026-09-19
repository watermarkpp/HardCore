extends RefCounted
## Immutable by ownership after setup. A new index is built for each release.
## Only candidate polygons in intersecting GU buckets are checked.
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const BUCKET_GU := 8.0
const MAX_BUCKET_REFERENCES := 1048576
var design_size := Vector2i.ZERO
var parts: Array[PackedVector2Array] = []
var boxes: Array[Rect2] = []
var buckets: Dictionary = {}
var ready := false

func setup(size_gu: Vector2i, convex_parts: Array) -> bool:
	if ready or size_gu.x <= 0 or size_gu.y <= 0 or convex_parts.size() > Geo.MAX_PARTS:
		return false
	design_size = size_gu
	var bucket_references := 0
	for raw: Variant in convex_parts:
		var checked := Geo.validate(raw, design_size)
		if not checked.ok or not Geo.convex(checked.points):
			return false
		var polygon: PackedVector2Array = checked.points
		var box := Geo.bounds(polygon)
		var index := parts.size()
		parts.append(polygon)
		boxes.append(box)
		var first := _bucket(box.position - Vector2.ONE * Geo.EPS)
		var last := _bucket(box.end + Vector2.ONE * Geo.EPS)
		bucket_references += (last.x - first.x + 1) * (last.y - first.y + 1)
		if bucket_references > MAX_BUCKET_REFERENCES:
			return false
		for y: int in range(first.y, last.y + 1):
			for x: int in range(first.x, last.x + 1):
				var key := Vector2i(x, y)
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(index)
	for key: Vector2i in buckets:
		(buckets[key] as Array).make_read_only()
	buckets.make_read_only()
	ready = true
	return true

func _bucket(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / BUCKET_GU), floori(p.y / BUCKET_GU))

func candidates(box: Rect2) -> Array[int]:
	var result: Array[int] = []
	var seen: Dictionary = {}
	var first := _bucket(box.position - Vector2.ONE * Geo.EPS)
	var last := _bucket(box.end + Vector2.ONE * Geo.EPS)
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			for index: int in buckets.get(Vector2i(x, y), []):
				if not seen.has(index) and boxes[index].grow(Geo.EPS).intersects(box.grow(Geo.EPS), true):
					seen[index] = true
					result.append(index)
	return result

func inside(p: Vector2, radius_gu := 0.0) -> bool:
	return ready and p.is_finite() and is_finite(radius_gu) and radius_gu >= 0.0 and p.x - radius_gu >= -Geo.EPS and p.y - radius_gu >= -Geo.EPS and p.x + radius_gu <= design_size.x + Geo.EPS and p.y + radius_gu <= design_size.y + Geo.EPS

func point_blocked(p: Vector2) -> bool:
	if not inside(p):
		return true
	for index: int in buckets.get(_bucket(p), []):
		if Geometry2D.is_point_in_polygon(p, parts[index]):
			return true
	return false

func circle_blocked(p: Vector2, radius_gu: float) -> bool:
	return capsule_blocked(p, p, radius_gu)

func capsule_blocked(a: Vector2, b: Vector2, radius_gu: float) -> bool:
	if not inside(a, radius_gu) or not inside(b, radius_gu):
		return true
	var box := Rect2(a, Vector2.ZERO).expand(b).grow(radius_gu)
	for index: int in candidates(box):
		if Geo.capsule_hits_polygon(a, b, radius_gu, parts[index]):
			return true
	return false

func footprint_blocked(footprint_ground_gu: PackedVector2Array) -> bool:
	if footprint_ground_gu.size() < 3:
		return true
	for p: Vector2 in footprint_ground_gu:
		if not inside(p):
			return true
	for index: int in candidates(Geo.bounds(footprint_ground_gu)):
		if Geo.convex_overlap(footprint_ground_gu, parts[index]):
			return true
	return false
