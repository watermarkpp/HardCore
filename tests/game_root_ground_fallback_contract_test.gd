extends Node

const GameRootScript := preload("res://scripts/game_root.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	var game := GameRootScript.new()
	# No published runtime uses this id, which exercises the compatibility path
	# without attaching GameRoot and starting the scene lifecycle.
	game.current_map_id = 2147483000
	for sample_ground_gu: Vector2 in [
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.DOWN,
		Vector2(2.0, -3.0),
		Vector2(-4.75, 8.125),
	]:
		var screen_position_px: Vector2 = game._canonical_ground_gu_to_screen_px(
			sample_ground_gu
		)
		assert(screen_position_px.is_equal_approx(
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				sample_ground_gu
			)
		))
		assert(game._canonical_screen_px_to_ground_gu(
			screen_position_px
		).is_equal_approx(sample_ground_gu))
	for direction_index: int in range(32):
		var delta_ground_gu := Vector2.from_angle(
			TAU * float(direction_index) / 32.0
		) * 8.0
		var delta_screen_px: Vector2 = game._canonical_ground_gu_to_screen_px(
			delta_ground_gu
		)
		assert(is_equal_approx(
			game._canonical_screen_px_to_ground_gu(delta_screen_px).length(),
			8.0
		))
	for distance_gu: float in game.SAFE_RING_TELEPORT_DISTANCES_GU:
		for direction_index: int in range(8):
			var direction_ground := Vector2.from_angle(
				TAU * float(direction_index) / 8.0
			)
			var motion_screen_px := (
				GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
					direction_ground * distance_gu
				)
			)
			assert(is_equal_approx(
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					motion_screen_px
				).length(),
				distance_gu
			))
	assert(game._canonical_grid_cell_to_screen_px(Vector2i(2, -3)) == Vector2(160.0, -16.0))
	game.free()
	print("GAME_ROOT_GROUND_FALLBACK_PASS: no-runtime 64x32 projection is symmetric")
	get_tree().quit(0)
