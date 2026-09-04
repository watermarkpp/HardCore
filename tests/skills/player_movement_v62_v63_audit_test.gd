extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const UnitAdapter := preload("res://scripts/skills/combat_unit_legacy_adapter.gd")

const V62_SCREEN_SPEED_PX_PER_SEC := 190.0


func _ready() -> void:
	var legacy_ground_speeds_gu_per_sec: Array[float] = []
	for direction_index: int in range(8):
		var screen_direction_px := Vector2.DOWN.rotated(
			TAU * float(direction_index) / 8.0
		).normalized()
		legacy_ground_speeds_gu_per_sec.append(
			GroundUnit.screen_delta_px_to_ground_delta_gu(
				screen_direction_px * V62_SCREEN_SPEED_PX_PER_SEC
			).length()
		)
	assert(absf(legacy_ground_speeds_gu_per_sec.min() - 4.1984465) < 0.0001)
	assert(absf(legacy_ground_speeds_gu_per_sec.max() - 8.3968930) < 0.0001)
	assert(
		legacy_ground_speeds_gu_per_sec.max()
		/ legacy_ground_speeds_gu_per_sec.min() > 1.999
	)
	assert(UnitAdapter.PLAYER_MOVE_SOURCE_EVIDENCE.source_tier == "primary")
	assert(UnitAdapter.PRIMARY_PLAYER_RUN_STEP_DISTANCE_GU == 2.0)
	assert(UnitAdapter.PRIMARY_PLAYER_RUN_INTERVAL_SECONDS == 0.600)
	assert(is_equal_approx(UnitAdapter.PLAYER_MOVE_SPEED_GU_PER_SEC, 10.0 / 3.0))
	for direction_index: int in range(32):
		var ground_direction_gu := Vector2.from_angle(
			TAU * float(direction_index) / 32.0
		)
		var screen_velocity_px_per_sec := (
			GroundUnit.desired_screen_velocity_px_per_sec(
				ground_direction_gu,
				UnitAdapter.PLAYER_MOVE_SPEED_GU_PER_SEC
			)
		)
		assert(is_equal_approx(
			GroundUnit.screen_delta_px_to_ground_delta_gu(
				screen_velocity_px_per_sec
			).length(),
			UnitAdapter.PLAYER_MOVE_SPEED_GU_PER_SEC
		))
	print(
		"PLAYER_MOVEMENT_V62_V63_AUDIT_PASS: v62 190 PX/s varied "
		+ "4.1984..8.3969 GU/s; v63 primary 2 GU/600 ms is 3.3333 GU/s in 32 directions"
	)
	get_tree().quit(0)
