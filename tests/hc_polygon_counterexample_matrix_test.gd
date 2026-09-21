extends Node

## R2-W3 polygon collision counterexample matrix. Fills the coverage gaps the
## existing hc_polygon suite leaves open: negative coordinates (fail-closed
## gates), swept capsule corner/edge grazing including exact tangency and the
## EPS margin, concave parts rejected by the runtime index, collinear extra
## vertices, and the multi-generation loaded-release cache eviction
## (MAX_LOADED_RELEASES=2) with staleness guards.

const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Runtime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")

var errors: Array[String] = []
var checks := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)
		push_error("HC_POLYGON_COUNTEREXAMPLE: " + message)


func _ready() -> void:
	call_deferred("run")


func _square(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x, y), Vector2(x + w, y),
		Vector2(x + w, y + h), Vector2(x, y + h)])


func _build_index(parts: Array, size := Vector2i(40, 40)) -> Index:
	var index := Index.new()
	expect_ok(index.setup(size, parts), "index setup")
	return index


func expect_ok(value: bool, message: String) -> void:
	check(value, message)


func run() -> void:
	# ---- A. Negative coordinates are fail-closed ----
	var negative := PackedVector2Array([
		Vector2(-0.5, 2), Vector2(3, 2), Vector2(3, 5)])
	var rejected := Geo.validate(Geo.encode(negative), Vector2i(40, 40))
	check(not rejected.ok, "polygon with negative-x vertex rejected")
	check(
		"polygon_outside_map" in String(rejected.errors[0]) \
		or rejected.errors.has("polygon_outside_map"),
		"negative vertex reports polygon_outside_map: %s" % str(rejected.errors)
	)
	check(
		not Geo.validate(
			Geo.encode(PackedVector2Array([
				Vector2(2, -0.25), Vector2(6, 2), Vector2(4, 5)])),
			Vector2i(40, 40)
		).ok,
		"polygon with negative-y vertex rejected"
	)
	check(
		not Geo.validate(
			Geo.encode(PackedVector2Array([
				Vector2(38, 38), Vector2(40.5, 38), Vector2(39, 41)])),
			Vector2i(40, 40)
		).ok,
		"polygon beyond design_size rejected"
	)
	var square_index := _build_index([Geo.encode(_square(16, 16, 8, 8))])
	check(square_index.point_blocked(Vector2(-1, -1)), "negative point blocked")
	check(
		square_index.circle_blocked(Vector2(-1, 1), 0.3),
		"negative-adjacent circle blocked"
	)
	check(
		square_index.capsule_blocked(Vector2(-1, 1), Vector2(5, 5), 0.3),
		"sweep starting in negative space blocked"
	)
	check(
		square_index.capsule_blocked(Vector2(20, 20), Vector2(20, -2), 0.0),
		"sweep leaving the map blocked regardless of polygons"
	)
	check(
		not square_index.point_blocked(Vector2(0, 0)),
		"exact map corner stays walkable inside the EPS tolerance"
	)

	# ---- B. Swept capsule counterexamples ----
	# Square obstacle (16,16)-(24,24); grazing segments run parallel above the
	# top edge y=16 at distance 2.5, endpoints kept >= radius from map edges.
	var distance := 2.5
	var graze_a := Vector2(18, 16.0 - distance)
	var graze_b := Vector2(22, 16.0 - distance)
	check(
		square_index.capsule_blocked(graze_a, graze_b, distance + 0.1),
		"sweep within radius of an edge hits"
	)
	check(
		not square_index.capsule_blocked(graze_a, graze_b, distance - 0.1),
		"sweep beyond the radius misses"
	)
	check(
		not square_index.capsule_blocked(graze_a, graze_b, distance),
		"exact tangency is not penetration"
	)
	check(
		square_index.capsule_blocked(Vector2(20, 20), Vector2(30, 30), 0.0),
		"endpoint inside the polygon hits"
	)
	check(
		square_index.capsule_blocked(Vector2(12, 20), Vector2(28, 20), 0.0),
		"segment crossing an edge hits without endpoints inside"
	)
	check(
		square_index.capsule_blocked(Vector2(20, 20), Vector2(20, 20), 0.0),
		"zero-length sweep inside hits"
	)
	check(
		not square_index.capsule_blocked(Vector2(10, 10), Vector2(10, 10), 0.5),
		"zero-length sweep far outside misses"
	)
	check(
		not square_index.circle_blocked(Vector2(16 - 2.5, 20), 2.5),
		"circle exactly tangent to a vertical edge misses"
	)
	check(
		square_index.circle_blocked(Vector2(16 - 2.4, 20), 2.5),
		"circle overlapping a vertical edge hits"
	)
	# Corner vertex grazing: the vertex (16,16) shared by two edges.
	var corner_offset := 2.5 / sqrt(2.0)
	var corner_point := Vector2(16 - corner_offset, 16 - corner_offset)
	check(
		not square_index.circle_blocked(corner_point, 2.5),
		"circle exactly tangent to a corner vertex misses"
	)
	check(
		square_index.circle_blocked(corner_point + Vector2(0.2, 0.2), 2.5),
		"circle moved toward the corner tangent hits"
	)
	# Thin obstacle between the sweep and the graze target: a 0.02 GU wall.
	var thin_index := _build_index([Geo.encode(_square(20, 16, 0.02, 8))])
	check(
		thin_index.capsule_blocked(Vector2(16, 20), Vector2(24, 20), 0.0),
		"segment crossing a 0.02 GU thin wall hits"
	)
	check(
		not thin_index.point_blocked(Vector2(20.03, 20)),
		"point just past the thin wall far side is free"
	)
	check(
		thin_index.point_blocked(Vector2(20.005, 20)),
		"point inside the thin wall is blocked"
	)

	# ---- C. Concave parts and collinear extras at the runtime index ----
	var concave := PackedVector2Array([
		Vector2(4, 4), Vector2(12, 4), Vector2(12, 8),
		Vector2(8, 8), Vector2(8, 12), Vector2(4, 12)])
	var concave_index := Index.new()
	check(
		not concave_index.setup(Vector2i(40, 40), [Geo.encode(concave)]),
		"concave part rejected by the runtime index (decomposition owns concavity)"
	)
	var with_collinear := PackedVector2Array([
		Vector2(16, 16), Vector2(20, 16), Vector2(24, 16),
		Vector2(24, 24), Vector2(16, 24)])
	var collinear_index := _build_index([Geo.encode(with_collinear)])
	check(
		collinear_index.capsule_blocked(Vector2(12, 20), Vector2(28, 20), 0.0),
		"collinear extra vertex keeps obstacle semantics"
	)
	check(
		not collinear_index.circle_blocked(Vector2(12, 12), 0.5),
		"collinear extra vertex adds no phantom blocking"
	)

	# ---- D. Multi-generation loaded cache ----
	Runtime.clear_loaded_cache()
	var release_a := _release(990971, "a")
	var release_b := _release(990972, "b")
	var release_c := _release(990973, "c")
	var verified_a := Runtime.compile(release_a, 990971, false)
	check(verified_a.ok, "release A compiles: %s" % str(verified_a.errors))
	Runtime.remember_validation(release_a, verified_a)
	Runtime.seal_loaded(release_a)
	var verified_b := Runtime.compile(release_b, 990972, false)
	check(verified_b.ok, "release B compiles")
	Runtime.remember_validation(release_b, verified_b)
	Runtime.seal_loaded(release_b)
	var verified_c := Runtime.compile(release_c, 990973, false)
	check(verified_c.ok, "release C compiles")
	Runtime.remember_validation(release_c, verified_c)
	Runtime.seal_loaded(release_c)
	check(
		Runtime._loaded.size() == 2,
		"cache holds MAX_LOADED_RELEASES entries, got %d" % Runtime._loaded.size()
	)
	check(
		is_same(Runtime._loaded[0].collision, release_b.collision),
		"oldest generation (A) evicted first"
	)
	var recomputed_a := Runtime.compile(release_a, 990971, false)
	check(recomputed_a.ok, "evicted release A recompiles correctly")
	check(
		not is_same(recomputed_a.snapshot.poly_index, verified_a.snapshot.poly_index),
		"evicted release A rebuilds a fresh index instead of serving a stale one"
	)
	var original_index: Index = verified_a.snapshot.poly_index
	var rebuilt_index: Index = recomputed_a.snapshot.poly_index
	check(
		rebuilt_index.parts.size() == original_index.parts.size() \
		and str(rebuilt_index.parts[0]) == str(original_index.parts[0]) \
		and rebuilt_index.design_size == original_index.design_size,
		"rebuilt A index content identical to the original build"
	)
	# Same collision content with a different build hash must not seal into
	# the cache (staleness guard).
	var release_a2 := _release(990971, "a")
	release_a2.build_sha256 = "f".repeat(64)
	var verified_a2 := Runtime.compile(release_a2, 990971, false)
	check(verified_a2.ok, "release A2 (same content, new hash) compiles")
	Runtime.remember_validation(release_a2, verified_a2)
	Runtime.seal_loaded(release_a2)
	check(
		Runtime._loaded.size() == 2,
		"sha-mismatched seal must not grow the cache, got %d" % Runtime._loaded.size()
	)
	# Without the remember/seal boundary nothing is cached.
	Runtime.clear_loaded_cache()
	var verified_plain := Runtime.compile(release_a, 990971, false)
	check(verified_plain.ok, "plain compile without file-load boundary")
	check(
		Runtime._loaded.is_empty(),
		"generic validation never populates the loaded cache"
	)
	Runtime.clear_loaded_cache()

	if errors.is_empty():
		print("HC_POLYGON_COUNTEREXAMPLE_MATRIX_PASS checks=", checks)
	get_tree().quit(0 if errors.is_empty() else 1)


func _release(map_id: int, hash_char: String) -> Dictionary:
	var radius := 0.3
	return {
		"build_sha256": hash_char.repeat(64),
		"source": {"runtime_map_id": map_id, "map_id": "gen_%s" % hash_char},
		"design": {"design_size": [40, 40]},
		"collision": {
			"coordinate_contract_id": Geo.CONTRACT,
			"physics_source_id": Geo.PHYSICS_SOURCE,
			"ground_coordinate_contract_id": "isometric_cell_center_64x32_v2",
			"convex_parts_ground_gu": [Geo.encode(_square(16, 16, 8, 8))],
			"blocked_count": 0,
			"navigation": {
				"contract_id": "hc.polygon_nav_faces.v1",
				"profiles": [{
					"radius_gu": radius,
					"radius_key": Graph.key_for_radius(radius),
					"vertices_ground_gu": [
						[16, 16], [24, 16], [24, 24], [16, 24]],
					"faces": [[0, 1, 2], [0, 2, 3]],
				}],
			},
		},
	}
