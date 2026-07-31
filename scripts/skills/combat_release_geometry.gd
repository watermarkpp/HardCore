class_name CombatReleaseGeometry
extends RefCounted

## Stable profession-level contract for resolving combat geometry at the
## actual hit/projectile release frame. Input acceptance may remember a target
## identity, but world positions are deliberately sampled only at release.

const CONTRACT_ID := "gameplay.professions.combat_release_geometry.live_footpoint.v1"
const MELEE_RELEASE_FACING_POLICY_ID := "gameplay.warrior.melee_release_facing.locked_input_8dir.v1"
const POLICY_LOCKED_SINGLE_TARGET := "locked_single_target"
const POLICY_INPUT_DIRECTION := "input_direction"
const FACING_POLICY_LIVE_LOCKED_TARGET := "live_locked_target_direction"
const FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION := "locked_input_eight_direction"
const EPSILON := 0.0001


static func tracks_locked_target(target_mode: String) -> bool:
	# Single-target direct hits and projectiles keep the originally selected
	# target. Direction, target-area and self-area skills remain spatial casts;
	# they must never become homing attacks merely because a target was present.
	return target_mode == "single"


static func resolve(
	actor_position_at_release: Vector2,
	input_direction: Vector2,
	locked_target_instance_id := 0,
	locked_target_position_at_release := Vector2.ZERO,
	locked_target_valid_at_release := false,
	track_locked_target := true,
	release_facing_policy := FACING_POLICY_LIVE_LOCKED_TARGET
) -> Dictionary:
	var normalized_input := _normalized_input_direction(input_direction)
	var effective_facing_policy := release_facing_policy
	if effective_facing_policy not in [
		FACING_POLICY_LIVE_LOCKED_TARGET,
		FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION,
	]:
		effective_facing_policy = FACING_POLICY_LIVE_LOCKED_TARGET
	if effective_facing_policy == FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION:
		normalized_input = _quantized_eight_direction(normalized_input)
	var had_locked_target := track_locked_target and locked_target_instance_id > 0
	var valid_original_target := had_locked_target and locked_target_valid_at_release
	var release_direction := normalized_input
	if (
		valid_original_target
		and effective_facing_policy == FACING_POLICY_LIVE_LOCKED_TARGET
	):
		var live_delta := locked_target_position_at_release - actor_position_at_release
		if live_delta.length_squared() > EPSILON * EPSILON:
			release_direction = live_delta.normalized()
	return {
		"contract_id": CONTRACT_ID,
		"policy": (
			POLICY_LOCKED_SINGLE_TARGET
			if had_locked_target
			else POLICY_INPUT_DIRECTION
		),
		"origin_world": actor_position_at_release,
		"direction_world": release_direction,
		"release_facing_policy": effective_facing_policy,
		"release_facing_policy_id": (
			MELEE_RELEASE_FACING_POLICY_ID
			if effective_facing_policy == FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
			else ""
		),
		"direction_locked_for_action": (
			effective_facing_policy == FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
		),
		"refresh_actor_footpoint_at_release": true,
		"refresh_locked_target_footpoint_at_release": valid_original_target,
		"locked_target_instance_id": locked_target_instance_id if had_locked_target else 0,
		"locked_target_valid_at_release": valid_original_target,
		"allow_target_retarget": not had_locked_target,
		"allow_directional_scan": not had_locked_target,
	}


static func _normalized_input_direction(input_direction: Vector2) -> Vector2:
	if input_direction.length_squared() <= EPSILON * EPSILON:
		return Vector2.DOWN
	return input_direction.normalized()


static func _quantized_eight_direction(input_direction: Vector2) -> Vector2:
	var direction_index := wrapi(
		int(round((input_direction.angle() - PI / 2.0) / (TAU / 8.0))),
		0,
		8
	)
	var locked_angle := PI / 2.0 + float(direction_index) * TAU / 8.0
	return Vector2(cos(locked_angle), sin(locked_angle)).normalized()


static func candidate_allowed(release_geometry: Dictionary, candidate_instance_id: int) -> bool:
	var locked_id := int(release_geometry.get("locked_target_instance_id", 0))
	if locked_id > 0:
		return (
			bool(release_geometry.get("locked_target_valid_at_release", false))
			and candidate_instance_id == locked_id
		)
	return bool(release_geometry.get("allow_directional_scan", true))
