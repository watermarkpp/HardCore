extends Node

# Actual GameRoot read-only seam vs its frozen pre-R2 formula. No _ready/world.
const Game := preload("res://scripts/game_root.gd")
const Rules := preload("res://scripts/world_spatial_rules.gd")
const Reference := preload("res://tests/m30_r4_r2/fixture_geometry.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("M30_R2_SAFE " + label)

func _ready() -> void:
	var host := Game.new()
	host.current_map_id = Game.BICH_RUNTIME_MAP_ID
	host._zone_generation = 1
	var raw: Array = [{"shape": "circle", "center_ground_gu": Vector2(10, 10), "radius_gu": 1.0}]
	host._safe_zone_context = Rules.compile_safe_zone_context(host.current_map_id, 1, 1, raw)
	host._active_safe_zones = host._safe_zone_context["zones"]
	check(host._safe_zone_context_is_valid(), "compiled fixture must be valid")
	var radius := 0.4
	var inside_padding := Vector2(11.2, 10)
	check(not Rules.point_inside_safe_zones_ground_gu(inside_padding, host._active_safe_zones), "centre is outside: old preflight accepted")
	var projected: Vector2 = host.hc_m30_stable_enemy_ground_point(inside_padding, radius, host.current_map_id)
	check(projected.is_finite() and not projected.is_equal_approx(inside_padding), "body padding still requires relocation")
	check(projected.is_equal_approx(Reference.stable_reference(host, inside_padding, radius)), "exact pre-R2 projection preserved")
	for d: int in range(8):
		var point := Vector2(10, 10) + Vector2.from_angle(TAU * d / 8.0) * 2.0
		check(host.hc_m30_stable_enemy_ground_point(point, radius, host.current_map_id).is_equal_approx(point), "clear point unchanged direction %d" % d)
	check(not host.hc_m30_stable_enemy_ground_point(inside_padding, radius, host.current_map_id + 1).is_finite(), "wrong-map owner fails closed")
	check(not host.hc_m30_stable_enemy_ground_point(Vector2.INF, radius, host.current_map_id).is_finite(), "nonfinite point rejected")
	check(not host.hc_m30_stable_enemy_ground_point(inside_padding, -1.0, host.current_map_id).is_finite(), "negative radius rejected")
	host.current_map_id = 777
	check(host.hc_m30_stable_enemy_ground_point(inside_padding, radius, 777).is_equal_approx(inside_padding), "non-Bich policy unchanged")
	host.free()
	print("M30_R2_SAFE_PROJECTION_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
