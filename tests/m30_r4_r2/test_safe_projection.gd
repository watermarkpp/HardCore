extends Node

# Preserve the actual pre-R2 rule. Padding selects the destination AFTER the
# centre enters a circle; it does not expand the trigger circle. Polygon
# ejection is deliberately not introduced by this repair.
const Game := preload("res://scripts/game_root.gd")
const Rules := preload("res://scripts/world_spatial_rules.gd")
const Reference := preload("res://tests/m30_r4_r2/fixture_geometry.gd")
var failures: int = 0
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("M30_R3_SAFE " + label)

func _ready() -> void:
	var host := Game.new()
	host.current_map_id = Game.BICH_RUNTIME_MAP_ID
	host._zone_generation = 1
	var raw: Array = [{"shape": "circle", "center_ground_gu": Vector2(10, 10), "radius_gu": 1.0}]
	host._safe_zone_context = Rules.compile_safe_zone_context(host.current_map_id, 1, 1, raw)
	host._active_safe_zones = host._safe_zone_context["zones"]
	check(host._safe_zone_context_is_valid(), "compiled fixture must be valid")
	var radius: float = 0.4
	var outside: Vector2 = Vector2(11.2, 10)
	check(not Rules.point_inside_safe_zones_ground_gu(outside, host._active_safe_zones), "centre outside trigger")
	var projected: Vector2 = host.hc_m30_stable_enemy_ground_point(outside, radius, host.current_map_id)
	check(projected.is_equal_approx(outside), "outside centre unchanged even when body overlaps circle")
	check(projected.is_equal_approx(Reference.stable_reference(host, outside, radius)), "frozen formula for exterior preserved")
	var inside := Vector2(10.5, 10)
	projected = host.hc_m30_stable_enemy_ground_point(inside, radius, host.current_map_id)
	check(projected.is_equal_approx(Vector2(11.45, 10)), "inside centre moves to radius plus body/padding")
	check(projected.is_equal_approx(Reference.stable_reference(host, inside, radius)), "frozen formula for interior preserved")
	check(host.hc_m30_stable_enemy_ground_point(projected, radius, host.current_map_id).is_equal_approx(projected), "second application is stable")
	for d: int in range(8):
		var point := Vector2(10, 10) + Vector2.from_angle(TAU * float(d) / 8.0) * 2.0
		check(host.hc_m30_stable_enemy_ground_point(point, radius, host.current_map_id).is_equal_approx(point), "clear exterior direction %d" % d)
	var centre_projected: Vector2 = host.hc_m30_stable_enemy_ground_point(Vector2(10, 10), radius, host.current_map_id)
	check(centre_projected.is_equal_approx(Reference.stable_reference(host, Vector2(10, 10), radius)), "zero-direction fallback unchanged")
	var boundary := Vector2(11, 10)
	check(host.hc_m30_stable_enemy_ground_point(boundary, radius, host.current_map_id).is_equal_approx(Reference.stable_reference(host, boundary, radius)), "inclusive boundary/epsilon unchanged")
	check(not host.hc_m30_stable_enemy_ground_point(outside, radius, host.current_map_id + 1).is_finite(), "wrong-map rejects")
	check(not host.hc_m30_stable_enemy_ground_point(Vector2.INF, radius, host.current_map_id).is_finite(), "nonfinite rejects")
	check(not host.hc_m30_stable_enemy_ground_point(outside, -1.0, host.current_map_id).is_finite(), "negative radius rejects")
	host._safe_zone_context["valid"] = false
	check(not host.hc_m30_stable_enemy_ground_point(outside, radius, host.current_map_id).is_finite(), "invalid Bich context rejects")
	host._safe_zone_context["valid"] = true
	var polygon := PackedVector2Array([Vector2(9,9), Vector2(11,9), Vector2(11,11), Vector2(9,11)])
	raw = [{"shape": "polygon", "polygon_ground_gu": polygon}]
	host._safe_zone_context = Rules.compile_safe_zone_context(host.current_map_id, 2, 1, raw)
	host._active_safe_zones = host._safe_zone_context["zones"]
	check(host._safe_zone_context_is_valid(), "valid polygon fixture")
	check(host.hc_m30_stable_enemy_ground_point(Vector2(10, 10), radius, host.current_map_id).is_equal_approx(Vector2(10, 10)), "projection helper does not acquire new polygon ejection semantics")
	host.current_map_id = 777
	check(host.hc_m30_stable_enemy_ground_point(outside, radius, 777).is_equal_approx(outside), "non-Bich unchanged")
	host.free()
	print("M30_R2_SAFE_PROJECTION_%s checks=%d failures=%d contract=pre_R2_centre_trigger" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
