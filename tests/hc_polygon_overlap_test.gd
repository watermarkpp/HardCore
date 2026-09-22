extends Node

## 2026-09-20 user order: overlapping drawn polygons must be
## (1) highlighted in the editor while drawing / committed, and
## (2) auto-merged (conservative union) at build time without changing
##     the blocked coverage in any way.
## These tests pin the merge semantics (duplicates, containment, partial
## overlap, ring-that-would-need-a-hole, owner scoping, disjoint) and the
## editor overlap predicate.

const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Controller := preload("res://scripts/map_editor/polygon/poly_editor_controller.gd")

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("FAIL_CHECK %s" % label)

func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x, y), Vector2(x + w, y),
		Vector2(x + w, y + h), Vector2(x, y + h)])

func _entry(id: String, points: PackedVector2Array, owner := "") -> Dictionary:
	var entry: Dictionary = {
		"collision_id": id, "shape": "polygon",
		"data": {"points": Geo.encode(points)},
		"blocks_player": true, "blocks_monster": true,
		"content_layer": "personal_expansion", "source": "manual",
	}
	if not owner.is_empty():
		entry["owner"] = owner
	return entry

func _doc(polys: Array) -> Dictionary:
	return {
		"map_id": "overlap_probe", "map_name": "overlap_probe",
		"content_layer": "personal_expansion",
		"design": {"design_size": [24, 24], "tile_size": [64, 32]},
		"editor_meta": {"collision_authority": "hc_polygon_v1", "revision": 1},
		"layers": {"collision": polys, "collision_erase": []},
	}

func _blocked(document: Dictionary) -> Dictionary:
	var walk := Author.walkability(document)
	check(bool(walk.ok), "walkability ok: %s" % str(walk.errors))
	return walk.blocked_tiles

func _union_blocked(polys: Array) -> Dictionary:
	## Ground truth: cell centers inside ANY input polygon.
	var result: Dictionary = {}
	for points: PackedVector2Array in polys:
		for y: int in 24:
			for x: int in 24:
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
					result["%d,%d" % [x, y]] = true
	return result

func _same_blocked(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: String in a:
		if not b.has(key):
			return false
	return true

func _run_merge_case(label: String, polys: Array, expected_entry_count: int) -> void:
	var document := _doc(polys)
	var before := _union_blocked(polys.map(func(e: Dictionary) -> PackedVector2Array:
		return Geo.decode(e.data.points)))
	var prepared := Author.prepare(document)
	check(bool(prepared.ok), "%s prepare ok: %s" % [label, str(prepared.errors)])
	check(prepared.entries.size() == expected_entry_count,
		"%s merged count %d == %d" % [label, prepared.entries.size(), expected_entry_count])
	var after := _blocked(document)
	check(_same_blocked(before, after),
		"%s coverage preserved before=%d after=%d" % [label, before.size(), after.size()])

func _ready() -> void:
	# 1. Partial overlap: two rects sharing one quadrant -> one merged polygon.
	_run_merge_case("partial_overlap", [
		_entry("poly_000001", _rect(2, 2, 4, 4)),
		_entry("poly_000002", _rect(4, 4, 4, 4)),
	], 1)
	# 2. Exact duplicate -> one polygon.
	_run_merge_case("duplicate", [
		_entry("poly_000001", _rect(2, 2, 4, 4)),
		_entry("poly_000002", _rect(2, 2, 4, 4)),
	], 1)
	# 3. Contained polygon -> the smaller one is dropped.
	_run_merge_case("contained", [
		_entry("poly_000001", _rect(2, 2, 8, 8)),
		_entry("poly_000002", _rect(3, 3, 2, 2)),
	], 1)
	# 4. Disjoint polygons -> untouched.
	_run_merge_case("disjoint", [
		_entry("poly_000001", _rect(2, 2, 4, 4)),
		_entry("poly_000002", _rect(12, 12, 4, 4)),
	], 2)
	# 5. Ring built from four strips: strip1+strip2 merge into an L, L+strip3
	#    merge into a U; the final union with strip4 would need a hole, so
	#    that merge is REJECTED -> 2 entries remain, coverage still exact.
	_run_merge_case("ring_rejects_hole_merge", [
		_entry("poly_000001", _rect(2, 2, 10, 2)),
		_entry("poly_000002", _rect(10, 2, 2, 10)),
		_entry("poly_000003", _rect(2, 10, 10, 2)),
		_entry("poly_000004", _rect(2, 2, 2, 10)),
	], 2)
	# 6. Owner scoping of the merge pass (unit level; real instance-bound
	#    records carry "owner" via Binding.gather, manual ones are empty).
	var scoped := Author.union_merge_entries([
		{"id": "poly_000001", "owner": "", "content_layer": "personal_expansion",
			"points": _rect(2, 2, 4, 4)},
		{"id": "poly_000002", "owner": "inst_000001", "content_layer": "personal_expansion",
			"points": _rect(4, 4, 4, 4)},
	])
	check(scoped.size() == 2, "owner scoped: different owners never merge (%d)" % scoped.size())
	var same_owner := Author.union_merge_entries([
		{"id": "poly_000001", "owner": "inst_000001", "content_layer": "personal_expansion",
			"points": _rect(2, 2, 4, 4)},
		{"id": "poly_000002", "owner": "inst_000001", "content_layer": "personal_expansion",
			"points": _rect(4, 4, 4, 4)},
	])
	check(same_owner.size() == 1, "same owner overlapping pair merges (%d)" % same_owner.size())
	check(str(same_owner[0].id) == "poly_000001", "merged record keeps first parent id")
	check(str(same_owner[0].owner) == "inst_000001", "merged record keeps owner")
	check(str(same_owner[0].content_layer) == "personal_expansion", "merged record keeps content layer")

	# 7. Manual records survive prepare unchanged when there is no overlap.
	var plain := _doc([
		_entry("poly_000001", _rect(2, 2, 4, 4)),
		_entry("poly_000002", _rect(12, 12, 4, 4)),
	])
	var plain_prepared := Author.prepare(plain)
	check(bool(plain_prepared.ok), "plain prepare ok: %s" % str(plain_prepared.errors))
	check(int(plain_prepared.get("merged_polys", -1)) == 0, "plain merge count 0")
	check(str(plain_prepared.entries[0].source) == "manual", "manual source preserved")
	check(str(plain_prepared.entries[0].polygon_ground_gu) == str(Geo.encode(_rect(2, 2, 4, 4))),
		"disjoint manual points unchanged")

	# 8. Editor overlap predicate (drives the highlight).
	var records: Array = [
		{"points": _rect(2, 2, 4, 4)}, {"points": _rect(12, 12, 4, 4)}]
	check(Controller.polygon_overlaps_records(_rect(4, 4, 4, 4), records, -1),
		"predicate: overlapping draft detected")
	check(not Controller.polygon_overlaps_records(_rect(18, 18, 3, 3), records, -1),
		"predicate: disjoint draft clear")
	check(not Controller.polygon_overlaps_records(_rect(4, 4, 4, 4), records, 0),
		"predicate: excluded record ignored")

	if failures.is_empty():
		print("OVERLAP_TEST_ALL_PASS")
		get_tree().quit(0)
	else:
		print("OVERLAP_TEST_FAILED count=%d" % failures.size())
		get_tree().quit(1)
