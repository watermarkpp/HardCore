extends Node

const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")


func _ready() -> void:
	assert(Geometry.CONTRACT_ID == "gameplay.warrior.melee_geometry.fractional_tile.v1")
	assert(is_equal_approx(Geometry.reach_tiles("normal"), 1.5))
	assert(is_equal_approx(Geometry.reach_tiles("fire"), 1.5))
	assert(is_equal_approx(Geometry.reach_tiles("half_moon"), 1.5))
	assert(is_equal_approx(Geometry.reach_tiles("thrust"), 2.5))
	assert(is_equal_approx(Geometry.reach_tiles("half_moon", 99.0), 2.0))
	assert(is_equal_approx(Geometry.reach_tiles("thrust", 99.0), 3.5))
	assert(Geometry.maximum_targets("normal") == 1)
	assert(Geometry.maximum_targets("fire") == 1)
	assert(Geometry.maximum_targets("half_moon") == 4)
	assert(Geometry.maximum_targets("thrust") == 2)

	# S faces tile step (1, 1); the first 1.5 tiles are primary and the
	# endpoint-tolerance segment through 2.5 tiles is the second target slot.
	assert(Geometry.facing_tile_step(0) == Vector2i(1, 1))
	assert(Geometry.thrust_slot(Vector2.ZERO, Vector2(1.5, 1.5), 0) == 1)
	assert(Geometry.thrust_slot(Vector2.ZERO, Vector2(2.5, 2.5), 0) == 2)
	assert(Geometry.thrust_slot(Vector2.ZERO, Vector2(2.5002, 2.5002), 0) == 0)
	assert(Geometry.thrust_slot(Vector2.ZERO, Vector2(2.0, 0.9), 0) == 0)
	# Fractional tile positions must quantize exactly like the sprite-facing
	# system after the 64x32 isometric projection, not in unprojected tile space.
	assert(Geometry.direction_index_for_tile_delta(Vector2(1.0, 0.5)) == 7)
	assert(Geometry.direction_index_for_tile_delta(Vector2(0.5, 1.0)) == 1)

	# Facing N (index 4) sweeps NW,N,NE,E: relative offsets 7,0,1,2.
	for allowed_direction: int in [3, 4, 5, 6]:
		var target := Vector2(Geometry.facing_tile_step(allowed_direction)) * 1.5
		assert(Geometry.is_in_half_moon_arc(Vector2.ZERO, target, 4))
	for rejected_direction: int in [0, 1, 2, 7]:
		var target := Vector2(Geometry.facing_tile_step(rejected_direction))
		assert(not Geometry.is_in_half_moon_arc(Vector2.ZERO, target, 4))
	assert(not Geometry.is_in_half_moon_arc(Vector2.ZERO, Vector2(-1.5002, -1.5002), 4))

	assert(not Geometry.fire_can_begin(false))
	assert(Geometry.fire_can_begin(true))
	assert(Geometry.fire_consumes_charge("hit"))
	assert(Geometry.fire_consumes_charge("miss"))
	assert(not Geometry.fire_consumes_charge("invalid_target"))
	assert(not Geometry.fire_consumes_charge("cancelled_before_hit_test"))
	print("WARRIOR_MELEE_GEOMETRY_PASS: fractional tiles, capped bonuses, arc/lane and fire MISS policy")
	get_tree().quit()
