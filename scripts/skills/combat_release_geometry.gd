class_name CombatReleaseGeometry
extends RefCounted

## Stable profession-level contract for resolving combat geometry at the
## actual hit/projectile release frame. Input acceptance may remember a target
## identity, but world positions are deliberately sampled only at release.

const CONTRACT_ID := "gameplay.professions.combat_release_geometry.live_footpoint.v1"
const POLICY_LOCKED_SINGLE_TARGET := "locked_single_target"
const POLICY_INPUT_DIRECTION := "input_direction"
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
	track_locked_target := true
) -> Dictionary:
	var normalized_input := input_direction.normalized()
	if normalized_input.length_squared() <= EPSILON * EPSILON:
		normalized_input = Vector2.DOWN
	var had_locked_target := track_locked_target and locked_target_instance_id > 0
	var valid_original_target := had_locked_target and locked_target_valid_at_release
	var release_direction := normalized_input
	if valid_original_target:
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
		"locked_target_instance_id": locked_target_instance_id if had_locked_target else 0,
		"locked_target_valid_at_release": valid_original_target,
		"allow_target_retarget": not had_locked_target,
		"allow_directional_scan": not had_locked_target,
	}


static func candidate_allowed(release_geometry: Dictionary, candidate_instance_id: int) -> bool:
	var locked_id := int(release_geometry.get("locked_target_instance_id", 0))
	if locked_id > 0:
		return (
			bool(release_geometry.get("locked_target_valid_at_release", false))
			and candidate_instance_id == locked_id
		)
	return bool(release_geometry.get("allow_directional_scan", true))
