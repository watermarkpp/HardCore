extends Node
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")

# Frozen v92 reference. Deliberately retain its collecting query and ordering;
# a shared optimized helper would hide duplicate/missing-bucket regressions.
class LegacyIndex extends Index:
	func candidates(box: Rect2) -> Array[int]:
		var result: Array[int] = []
		var seen: Dictionary = {}
		var first := _bucket(box.position - Vector2.ONE * Geo.EPS)
		var last := _bucket(box.end + Vector2.ONE * Geo.EPS)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				for index: int in buckets.get(Vector2i(x, y), []):
					if not seen.has(index) and boxes[index].grow(Geo.EPS).intersects(box.grow(Geo.EPS), true):
						seen[index] = true
						result.append(index)
		return result
	func capsule_blocked(a: Vector2, b: Vector2, radius: float) -> bool:
		if not inside(a, radius) or not inside(b, radius): return true
		for i in candidates(Rect2(a, Vector2.ZERO).expand(b).grow(radius)):
			if legacy_capsule_hits_polygon(a, b, radius, parts[i]): return true
		return false
	static func legacy_capsule_hits_polygon(a: Vector2, b: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
		if Geometry2D.is_point_in_polygon(a, polygon) or Geometry2D.is_point_in_polygon(b, polygon): return true
		var inner_radius := maxf(0.0, radius - Geo.EPS)
		for i in range(polygon.size()):
			var c := polygon[i]
			var d := polygon[(i + 1) % polygon.size()]
			if Geo.segments_touch(a, b, c, d): return true
			if radius > 0.0 and legacy_segment_distance_squared(a, b, c, d) < inner_radius * inner_radius: return true
		return false
	static func legacy_segment_distance_squared(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
		if Geo.segments_touch(a, b, c, d): return 0.0
		return minf(minf(Geo.distance_squared_to_segment(a, c, d), Geo.distance_squared_to_segment(b, c, d)),
			minf(Geo.distance_squared_to_segment(c, a, b), Geo.distance_squared_to_segment(d, a, b)))
	func footprint_blocked(points: PackedVector2Array) -> bool:
		if points.size() < 3: return true
		for p in points:
			if not inside(p): return true
		for i in candidates(Geo.bounds(points)):
			if Geo.convex_overlap(points, parts[i]): return true
		return false

class QueryProbe extends Index:
	var collecting_queries := 0
	func candidates(box: Rect2) -> Array[int]:
		collecting_queries += 1
		return super.candidates(box)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260923
	var rows: Array[Dictionary] = []
	var cases := 0
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"))
	assert(registry.maps.size() >= 60)
	for entry: Dictionary in registry.maps:
		var map_id := int(entry.runtime_map_id)
		var timed := map_id in [913203, 913205]
		var runtime := MapEditorRuntimeBridge.load_map(map_id)
		assert(not runtime.is_empty())
		var size := Geo.parse_size(runtime.design.design_size)
		var current := QueryProbe.new()
		var legacy := LegacyIndex.new()
		assert(current.setup(size, runtime.collision.convex_parts_ground_gu))
		assert(legacy.setup(size, runtime.collision.convex_parts_ground_gu))
		var queries: Array[Array] = []
		# Every published map gets differential coverage; dense-map micro-timing
		# retains the larger fixed workload used in the original experiment.
		for serial in range(5000 if timed else 120):
			var a := Vector2(rng.randf_range(-0.1, size.x + 0.1), rng.randf_range(-0.1, size.y + 0.1))
			# Include zero-length, multi-bucket, local movement and exact boundaries.
			if serial % 4 == 0: a = Vector2((serial % 5) * 8.0, (serial % 9) * 8.0)
			var b := a + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
			if serial % 3 == 0: b = a
			if serial % 11 == 0: b = Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
			var radius: float = [0.0, 0.25, 0.30, 0.353553, 0.618718, 1.0][serial % 6]
			var box := Rect2(a, Vector2.ZERO).expand(b).grow(radius)
			assert(current.candidates(box) == legacy.candidates(box), "candidate order/dedup %d" % serial)
			var footprint := Geo.rectangle_points(Rect2(a - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))
			assert(current.capsule_blocked(a, b, radius) == legacy.capsule_blocked(a, b, radius), "capsule %d" % serial)
			assert(current.footprint_blocked(footprint) == legacy.footprint_blocked(footprint), "footprint %d" % serial)
			queries.append([a, b, radius, footprint])
			cases += 3
		# Isolated timing alternates both implementations in the same process.
		var times := {"legacy_usec": [], "current_usec": []}
		for trial in range(6 if timed else 0):
			var implementations: Array = [legacy, current] if trial % 2 == 0 else [current, legacy]
			for index: Index in implementations:
				var start := Time.get_ticks_usec()
				for query: Array in queries:
					index.capsule_blocked(query[0], query[1], query[2])
					index.footprint_blocked(query[3])
				var key := "legacy_usec" if index == legacy else "current_usec"
				times[key].append(Time.get_ticks_usec() - start)
		current.collecting_queries = 0
		for query: Array in queries:
			current.capsule_blocked(query[0], query[1], query[2])
			current.footprint_blocked(query[3])
		rows.append({"map_id": map_id, "cases": queries.size(), "timings": times,
			"collecting_queries_for_boolean_calls": current.collecting_queries})
		# Streaming existence queries must not materialize a full candidate list.
		assert(current.collecting_queries == 0, "boolean collision queries still collect full candidate arrays")
	var empty := QueryProbe.new()
	assert(empty.capsule_blocked(Vector2.ZERO, Vector2.ONE, 0.0))
	assert(empty.footprint_blocked(PackedVector2Array()))
	assert(empty.setup(Vector2i(16, 16), []))
	for radius in [-1.0, INF, NAN]:
		assert(empty.capsule_blocked(Vector2.ONE, Vector2.ONE, radius))
	assert(empty.capsule_blocked(Vector2.INF, Vector2.ONE, 0.0))
	assert(not empty.capsule_blocked(Vector2.ONE, Vector2.ONE, 0.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/repair_v93"))
	var file := FileAccess.open("res://outputs/repair_v93/polygon_query_streaming.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": "PASS", "differential_checks": cases, "maps": rows}, "\t"))
	file.close()
	print("POLYGON_QUERY_STREAMING_PASS maps=", rows.size(), " checks=", cases)
	get_tree().quit(0)
