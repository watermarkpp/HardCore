extends Node

const Fixtures := preload(
	"res://tests/helpers/combat_absolute_ground_fixtures.gd"
)
const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

const EPSILON := 0.0001


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks := 0
	for size: Vector2i in [
		Fixtures.DESIGN_256,
		Fixtures.DESIGN_300x200,
	]:
		var center := Fixtures.map_center(size)
		for abs_pos: Vector2 in [
			Vector2(130.0, 130.0),
			Vector2(42.0, 67.0),
			Vector2(4.0, 9.0),
		]:
			var screen: Vector2 = Mapper.ground_position_gu_to_screen_position_px(
				abs_pos,
				size
			)
			var canonical_inv: Vector2 = (
				Mapper.screen_position_px_to_ground_position_gu(screen, size)
			)
			var raw_inv: Vector2 = (
				GroundUnit.screen_delta_px_to_ground_delta_gu(screen)
			)
			assert(
				canonical_inv.distance_to(abs_pos) <= EPSILON,
				"canonical map-aware inverse must return the absolute ground GU"
			)
			if center.length() > EPSILON:
				assert(
					raw_inv.distance_to(abs_pos) > 0.5,
					"raw screen-delta inverse must NOT equal absolute position on a non-zero-center map"
				)
			var roundtrip: Vector2 = Mapper.ground_position_gu_to_screen_position_px(
				canonical_inv,
				size
			)
			assert(
				roundtrip.distance_to(screen) <= EPSILON,
				"ground->screen->ground roundtrip must be identity"
			)
			checks += 1
	assert(
		Fixtures.screen_to_ground(Fixtures.DESIGN_256).call(
			Vector2(0.0, 80.0)
		).distance_to(Vector2(130.0, 130.0)) <= EPSILON,
		"fixture screen_to_ground(0,80) must be (130,130) on 256x256"
	)
	assert(
		Fixtures.ground_to_screen(Fixtures.DESIGN_256).call(
			Vector2(130.0, 130.0)
		).distance_to(Vector2(0.0, 80.0)) <= EPSILON,
		"fixture ground_to_screen(130,130) must be (0,80) on 256x256"
	)
	checks += 2
	print("COMBAT_ABSOLUTE_GROUND_ROUNDTRIP_PASS checks=%d" % checks)
	get_tree().quit(0)
