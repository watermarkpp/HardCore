extends Node

const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	var pickup_screen_position_px := Vector2(137.0, -91.0)
	for direction_index: int in range(32):
		var direction_ground_gu := Vector2.from_angle(
			TAU * float(direction_index) / 32.0
		)
		var inside_screen_position_px := (
			pickup_screen_position_px
			+ GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu
				* (LootPickupScript.COLLECTION_RADIUS_GU - 0.0001)
			)
		)
		var outside_screen_position_px := (
			pickup_screen_position_px
			+ GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu
				* (LootPickupScript.COLLECTION_RADIUS_GU + 0.0001)
			)
		)
		assert(LootPickupScript.target_is_within_collection_range_screen_px(
			pickup_screen_position_px,
			inside_screen_position_px
		))
		assert(not LootPickupScript.target_is_within_collection_range_screen_px(
			pickup_screen_position_px,
			outside_screen_position_px
		))
	print("LOOT_PICKUP_GROUND_UNIT_PASS: 32 directions use one 0.75 GU radius")
	get_tree().quit(0)
