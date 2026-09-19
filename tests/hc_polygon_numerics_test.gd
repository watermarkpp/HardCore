extends Node
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
var errors: Array[String] = []
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)
		push_error("HC_POLYGON_NUMERICS: " + message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	# Binary-exact coordinates avoid confusing representation error with the
	# catastrophic cancellation in R2.2's global-coordinate Vector2.cross sum.
	for offset: float in [0.0, 64.0, 500.0, 4000.0]:
		var side: float = 0.015625
		var points: PackedVector2Array = Geo.rectangle_points(Rect2(offset, offset, side, side))
		check(absf(Geo.area(points) - side * side) < 0.0000000001,
			"small contour area remains translation-invariant at %s GU" % offset)
		var reversed: PackedVector2Array = points.duplicate()
		reversed.reverse()
		check(absf(Geo.area(reversed) + side * side) < 0.0000000001,
			"signed area remains correct for reverse winding at %s GU" % offset)
		var checked: Dictionary = Geo.validate(Geo.encode(points), Vector2i(4096, 4096))
		check(bool(checked.get("ok", false)), "valid far-origin contour must not become zero_area: %s" % str(checked))
	var concave := PackedVector2Array([Vector2(64,64), Vector2(66,64), Vector2(66,65),
		Vector2(65,65), Vector2(65,66), Vector2(64,66)])
	check(absf(Geo.area(concave) - 3.0) < 0.000001, "concave area unchanged")
	var document: Dictionary = {"design":{"design_size":[80,80]},
		"editor_meta":{"collision_authority":Geo.AUTHORITY},
		"layers":{"collision":[Author.entry("numeric_concave",concave)]}}
	var prepared: Dictionary = Author.prepare(document)
	check(bool(prepared.get("ok", false)), "far-origin concave decomposition accepted: %s" % str(prepared.get("errors",[])))
	if bool(prepared.get("ok", false)):
		var area_sum: float = 0.0
		for raw: Array in prepared.parts:
			area_sum += absf(Geo.area(Geo.decode(raw)))
		check(absf(area_sum - 3.0) < 0.00001, "convex part union area equals authored area")
	check(not Geo.validate([[64,64],[65,65],[66,66]],Vector2i(80,80)).ok,
		"collinear contour still rejected")
	check(not Geo.validate([[64,64],[66,66],[64,66],[66,64]],Vector2i(80,80)).ok,
		"self-crossing contour still rejected")
	if errors.is_empty():
		print("HC_POLYGON_NUMERICS_TEST_PASS checks=",checks)
	get_tree().quit(0 if errors.is_empty() else 1)
