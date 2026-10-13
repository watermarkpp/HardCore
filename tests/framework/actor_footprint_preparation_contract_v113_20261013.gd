extends Node

const Runtime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Spatial := preload("res://scripts/world_spatial_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "actor_footprint_preparation_contract_v113_20261013"
var proof := Proof.new()
var checks := 0
var failures := 0

class ObservedIndex extends "res://scripts/map_editor/polygon/poly_index.gd":
	var observed := PackedVector2Array()
	func footprint_blocked(points: PackedVector2Array) -> bool:
		observed = points.duplicate()
		return super.footprint_blocked(points)
	func point_blocked(point: Vector2) -> bool:
		observed = PackedVector2Array([point])
		return super.point_blocked(point)

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	failures += 0 if ok else 1
	proof.record(ok, label)

func _run() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 20261013
	for size: Vector2i in [Vector2i(12,12), Vector2i(1400,900), Vector2i(512,511), Vector2i(8192,4097)]:
		var actual := ObservedIndex.new()
		var reference := Index.new()
		var parts := [[[1,1],[3,1],[3,3],[1,3]]]
		_check(actual.setup(size, parts) and reference.setup(size, parts), "real polygon indexes setup %s" % size)
		for trial in range(100):
			var ground := Vector2(random.randf_range(-1,5), random.randf_range(-1,5))
			var center := Coord.ground_position_gu_to_screen_position_px(ground,size)
			var radii := [0.0, 0.00000001, 15.999999, 16.0, 32.0, 96.0]
			var offsets := Spatial.actor_footprint_polygon_px(radii[trial % radii.size()])
			var expected := PackedVector2Array()
			for offset: Vector2 in offsets:
				expected.append(Coord.screen_position_px_to_ground_position_gu(center + offset,size))
			var result := Runtime.actor_world({"poly_index":actual,"design_size":size},center,offsets)
			var degenerate := trial % radii.size() in [0,1]
			var expected_points := PackedVector2Array([expected[0]]) if degenerate else expected
			_check(actual.observed.to_byte_array() == expected_points.to_byte_array(), "exact ordered point bytes %s/%d" % [size,trial])
			var expected_result := reference.point_blocked(expected[0]) if degenerate else reference.footprint_blocked(expected)
			_check(result == expected_result, "real footprint bool %s/%d" % [size,trial])
		_check(Runtime.actor_world({"poly_index":actual},Vector2.ZERO,PackedVector2Array([Vector2(NAN,0)])), "nonfinite first offset rejects before missing design field")
		_check(Runtime.actor_world({"poly_index":actual,"design_size":size},Vector2.ZERO,PackedVector2Array([Vector2.ONE,Vector2(INF,0)])), "nonfinite later offset rejects")
		_check(Runtime.actor_world({"poly_index":actual},Vector2.INF,PackedVector2Array([Vector2.ONE])), "nonfinite center rejects before design")
		_check(Runtime.actor_world({},Vector2.ZERO,PackedVector2Array([Vector2.ONE])), "missing index rejects")
		_check(Runtime.actor_world({"poly_index":actual},Vector2.ZERO,PackedVector2Array()), "empty footprint rejects before design")
	var receipt_ok := proof.write_receipt(SCENE_ID,checks,failures)
	print("ACTOR_FOOTPRINT_PREPARATION_", "PASS" if failures == 0 and receipt_ok else "FAIL", " checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 and receipt_ok else 1)
