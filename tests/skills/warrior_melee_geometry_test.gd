extends Node

const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")


func _ready() -> void:
	assert(Geometry.CONTRACT_ID == "gameplay.warrior.melee_geometry.ground_gu.v2")
	assert(is_equal_approx(Geometry.reach_tiles("normal"), 1.5))
	assert(is_equal_approx(Geometry.reach_tiles("fire"), 1.5))
	assert(is_equal_approx(Geometry.reach_tiles("half_moon"), 1.5))
	assert(is_equal_approx(Geometry.reach_tiles("thrust"), 2.5))
	assert(is_equal_approx(Geometry.reach_tiles("half_moon", 99.0), 2.0))
	assert(is_equal_approx(Geometry.reach_tiles("thrust", 99.0), 3.5))
	assert(Geometry.maximum_targets("normal") == 1)
	assert(Geometry.maximum_targets("fire") == 1)
	assert(Geometry.maximum_targets("half_moon") == Geometry.UNLIMITED_TARGETS)
	assert(Geometry.maximum_targets("thrust") == Geometry.UNLIMITED_TARGETS)
	assert(Geometry.has_finite_target_limit("normal"))
	assert(Geometry.has_finite_target_limit("fire"))
	assert(not Geometry.has_finite_target_limit("half_moon"))
	assert(not Geometry.has_finite_target_limit("thrust"))
	for unlimited_mode: String in ["thrust", "half_moon"]:
		var policy := Geometry.target_count_policy(unlimited_mode)
		assert(policy.contract_id == "gameplay.warrior.melee_target_count.v1")
		assert(policy.maximum_targets == Geometry.UNLIMITED_TARGETS)
		assert(policy.unlimited_within_geometry)
	for single_mode: String in ["normal", "fire"]:
		var policy := Geometry.target_count_policy(single_mode)
		assert(policy.maximum_targets == 1)
		assert(not policy.unlimited_within_geometry)

	# S faces ground direction normalize(1, 1); formal lengths are Euclidean GU.
	assert(Geometry.facing_tile_step(0) == Vector2i(1, 1))
	var south_gu := Vector2(1.0, 1.0).normalized()
	assert(Geometry.thrust_slot(Vector2.ZERO, south_gu * 1.5, 0) == 1)
	assert(Geometry.thrust_slot(Vector2.ZERO, south_gu * 2.5, 0) == 2)
	assert(Geometry.thrust_slot(Vector2.ZERO, south_gu * 2.5002, 0) == 0)
	assert(Geometry.thrust_slot(Vector2.ZERO, Vector2(2.0, 0.9), 0) == 0)
	# Target count never alters the accepted line/arc. Multiple targets can
	# occupy the same valid segment or sector; callers must enumerate them all.
	for same_segment_target: Vector2 in [south_gu, south_gu * 1.2, south_gu * 1.4]:
		assert(Geometry.thrust_slot(Vector2.ZERO, same_segment_target, 0) == 1)
	# Fractional tile positions are quantized in canonical tile space. World
	# projection happens only after direction selection.
	assert(Geometry.direction_index_for_ground_delta_gu(Vector2(1.0, 0.5)) == 0)
	assert(Geometry.direction_index_for_ground_delta_gu(Vector2(0.5, 1.0)) == 0)

	# Facing N (index 4) sweeps NW,N,NE,E: relative offsets 7,0,1,2.
	for allowed_direction: int in [3, 4, 5, 6]:
		var target := Vector2(Geometry.facing_tile_step(allowed_direction)).normalized() * 1.5
		assert(Geometry.is_in_half_moon_arc(Vector2.ZERO, target, 4))
	for rejected_direction: int in [0, 1, 2, 7]:
		var target := Vector2(Geometry.facing_tile_step(rejected_direction))
		assert(not Geometry.is_in_half_moon_arc(Vector2.ZERO, target, 4))
	assert(not Geometry.is_in_half_moon_arc(Vector2.ZERO, Vector2(-1.5002, -1.5002), 4))
	for same_sector_distance: float in [0.25, 0.5, 0.75, 1.0, 1.25, 1.5]:
		assert(Geometry.is_in_half_moon_arc(
			Vector2.ZERO,
			Vector2(Geometry.facing_tile_step(4)).normalized() * same_sector_distance,
			4
		))

	assert(not Geometry.fire_can_begin(false))
	assert(Geometry.fire_can_begin(true))
	assert(Geometry.fire_consumes_charge("hit"))
	assert(Geometry.fire_consumes_charge("miss"))
	assert(not Geometry.fire_consumes_charge("invalid_target"))
	assert(not Geometry.fire_consumes_charge("cancelled_before_hit_test"))

	assert(
		ReleaseGeometry.CONTRACT_ID
		== "gameplay.professions.combat_release_geometry.live_footpoint_gu.v2"
	)
	assert(ReleaseGeometry.tracks_locked_target("single"))
	for spatial_mode: String in ["direction", "target_area", "self", "self_area"]:
		assert(not ReleaseGeometry.tracks_locked_target(spatial_mode))
	var moving_target := ReleaseGeometry.resolve(
		Vector2(4.0, 5.0),
		Vector2.RIGHT,
		77,
		Vector2(1.0, 9.0),
		true,
		true,
		ReleaseGeometry.FACING_POLICY_LIVE_LOCKED_TARGET
	)
	assert(moving_target.origin_screen_px == Vector2(4.0, 5.0))
	assert(moving_target.direction_screen_px.is_equal_approx(Vector2(-3.0, 4.0).normalized()))
	for legacy_key: String in [
		"origin_world",
		"direction_world",
		"direction_source_world_delta",
		"direction_source_fractional_tile_delta",
	]:
		assert(not moving_target.has(legacy_key))
	assert(moving_target.locked_target_instance_id == 77)
	assert(not moving_target.allow_target_retarget and not moving_target.allow_directional_scan)
	assert(ReleaseGeometry.candidate_allowed(moving_target, 77))
	assert(not ReleaseGeometry.candidate_allowed(moving_target, 88))
	var locked_melee_facing := ReleaseGeometry.resolve(
		Vector2(4.0, 5.0),
		Vector2.RIGHT,
		77,
		Vector2(1.0, 9.0),
		true,
		true,
		ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
	)
	assert(locked_melee_facing.origin_screen_px == Vector2(4.0, 5.0))
	assert(locked_melee_facing.direction_screen_px.is_equal_approx(Vector2.RIGHT))
	assert(locked_melee_facing.locked_target_valid_at_release)
	assert(locked_melee_facing.refresh_actor_footpoint_at_release)
	assert(locked_melee_facing.refresh_locked_target_footpoint_at_release)
	assert(locked_melee_facing.direction_locked_for_action)
	assert(
		locked_melee_facing.release_facing_policy_id
		== ReleaseGeometry.MELEE_RELEASE_FACING_POLICY_ID
	)
	assert(ReleaseGeometry.candidate_allowed(locked_melee_facing, 77))
	var vanished_target := ReleaseGeometry.resolve(
		Vector2(4.0, 5.0), Vector2.RIGHT, 77, Vector2.ZERO, false, true
	)
	assert(not vanished_target.locked_target_valid_at_release)
	assert(vanished_target.direction_screen_px == Vector2.RIGHT)
	assert(not vanished_target.allow_target_retarget)
	assert(not ReleaseGeometry.candidate_allowed(vanished_target, 77))
	assert(not ReleaseGeometry.candidate_allowed(vanished_target, 88))
	var directional_area := ReleaseGeometry.resolve(
		Vector2(4.0, 5.0), Vector2.RIGHT, 77, Vector2(4.0, 20.0), true, false
	)
	assert(directional_area.direction_screen_px == Vector2.RIGHT)
	assert(directional_area.locked_target_instance_id == 0)
	assert(directional_area.allow_directional_scan)
	assert(ReleaseGeometry.candidate_allowed(directional_area, 88))

	# Live hit-frame coordinates retain the existing fractional-tile reach
	# contract: a moved target outside the real range must remain a clean miss.
	for mode: String in ["normal", "fire", "half_moon", "thrust"]:
		var just_outside := Geometry.reach_tiles(mode) + 0.001
		assert(not Geometry.is_single_target_in_reach(
			Vector2.ZERO, Vector2(just_outside, 0.0), mode
		))
	print("WARRIOR_MELEE_GEOMETRY_PASS: Euclidean GU, capped bonuses, arc/lane and fire MISS policy")
	get_tree().quit()
