extends Node

const Runtime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const Spatial := preload("res://scripts/world_spatial_rules.gd")
const Background := preload("res://scripts/world_background.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "actor_footprint_template_v113_20261013"
const QUERY_PATH := "res://scripts/map_editor/polygon/actor_footprint_query.gd"
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
	proof.record(ok,label)

func _run() -> void:
	_check(FileAccess.file_exists(QUERY_PATH), "bounded privately owned template query is available")
	if failures != 0:
		_finish()
		return
	var query = load(QUERY_PATH).new()
	var provider := Background.new()
	var random := RandomNumberGenerator.new()
	random.seed = 20261013
	var radii := [0.0,-0.0,0.00000001,16.0,16.000000000000004,22.627416997969522,18.0,96.0,1.0e30]
	for size: Vector2i in [Vector2i(12,12),Vector2i(1400,900),Vector2i(512,511),Vector2i(8192,4097)]:
		var actual := ObservedIndex.new()
		var reference := Index.new()
		var parts := [[[1,1],[3,1],[3,3],[1,3]]]
		_check(actual.setup(size,parts) and reference.setup(size,parts), "real index setup %s" % size)
		var snapshot := {"poly_index":actual,"design_size":size}
		provider._editor_runtime_collision_snapshot = snapshot
		for trial in range(180):
			var radius: float = radii[trial % radii.size()]
			var center := Coord.ground_position_gu_to_screen_position_px(Vector2(random.randf_range(-2,6),random.randf_range(-2,6)),size)
			var offsets := Spatial.actor_footprint_polygon_px(maxf(0.0,radius))
			var expected := PackedVector2Array()
			var max_offset := 0.0
			for offset: Vector2 in offsets:
				max_offset = maxf(max_offset,offset.length_squared())
				expected.append(Coord.screen_position_px_to_ground_position_gu(center+offset,size))
			var degenerate := max_offset <= 0.000001 * 0.000001
			var expected_points := PackedVector2Array([expected[0]]) if degenerate else expected
			var expected_result := reference.point_blocked(expected[0]) if degenerate else reference.footprint_blocked(expected)
			var result: bool = provider.is_environment_actor_blocked(center,radius)
			_check(actual.observed.to_byte_array() == expected_points.to_byte_array(), "provider ordered vertices %s/%d" % [size,trial])
			_check(result == expected_result, "provider real collision %s/%d" % [size,trial])
			_check(bool(query.blocked(snapshot,center,radius)) == expected_result, "independent query collision %s/%d" % [size,trial])
			# Mutating public generator results must not affect a private template.
			if trial % 20 == 0:
				offsets[0] = Vector2.INF
				_check(bool(query.blocked(snapshot,center,radius)) == expected_result,"public arrays do not alias private templates")
		_check(query._templates.size() <= query.CAPACITY,"cache has bounded ownership after eviction")
		_check(query.blocked(snapshot,Vector2.INF,16.0),"invalid center rejects")
		_check(query.blocked({},Vector2.ZERO,16.0),"missing index rejects")
		for radius: float in [-1.0,NAN,INF]:
			_check(provider.is_environment_actor_blocked(Vector2.ZERO,radius),"invalid formal radius rejects")
	var bits := PackedFloat64Array([16.0]).to_byte_array()
	bits.encode_u64(0,bits.decode_u64(0)+1)
	var adjacent := bits.decode_double(0)
	query.blocked(provider._editor_runtime_collision_snapshot,Vector2.ZERO,16.0)
	query.blocked(provider._editor_runtime_collision_snapshot,Vector2.ZERO,adjacent)
	var exact_entries := 0
	for template in query._templates:
		if template.radius_px == 16.0 or template.radius_px == adjacent:
			exact_entries += 1
	_check(exact_entries == 2,"adjacent float64 radii retain separate entries")
	var ownership_query = load(QUERY_PATH).new()
	var weak_templates: Array[WeakRef] = []
	for step in range(64):
		ownership_query.blocked(provider._editor_runtime_collision_snapshot,Vector2.ZERO,float(step))
		weak_templates.append(weakref(ownership_query._last))
		_check(ownership_query._templates.has(ownership_query._last),"last template remains a cache member after return")
		var retained := 0
		for reference: WeakRef in weak_templates:
			retained += 1 if reference.get_ref() != null else 0
		_check(retained <= ownership_query.CAPACITY,"evicted templates release strong ownership")
	# Hit the oldest resident slot before evicting it, exercising the case
	# where _last briefly points to the slot pop_front removes.
	ownership_query.blocked(provider._editor_runtime_collision_snapshot,Vector2.ZERO,60.0)
	var oldest: WeakRef = weakref(ownership_query._last)
	ownership_query.blocked(provider._editor_runtime_collision_snapshot,Vector2.ZERO,64.0)
	_check(oldest.get_ref() == null,"oldest last-hit template is released after eviction")
	provider.free()
	_finish()

func _finish() -> void:
	var ok := proof.write_receipt(SCENE_ID,checks,failures)
	print("ACTOR_FOOTPRINT_TEMPLATE_", "PASS" if failures == 0 and ok else "FAIL", " checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 and ok else 1)
