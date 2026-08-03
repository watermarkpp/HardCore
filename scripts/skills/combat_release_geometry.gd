class_name CombatReleaseGeometry
extends RefCounted

const CombatDirectionSpaceScript := preload(
	"res://scripts/skills/combat_direction_space.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

## Stable profession-level contract for resolving combat geometry at the
## actual hit/projectile release frame. Input acceptance may remember a target
## identity, but world positions are deliberately sampled only at release.

const CONTRACT_ID := "gameplay.professions.combat_release_geometry.live_footpoint_gu.v2"
const MELEE_RELEASE_FACING_POLICY_ID := (
	"gameplay.warrior.melee_release_facing.canonical_tile_8dir.v2"
)
const WILD_RUSH_RELEASE_TARGET_POLICY_ID := (
	"gameplay.warrior.wild_rush.original_locked_target_release.v1"
)
const TARGET_CENTERED_SPATIAL_RELEASE_POLICY_ID := (
	"gameplay.wizard.target_centered_spatial.release_live_footpoint.v1"
)
const LIVE_LOCKED_TARGET_AXIS_CONTRACT_ID := (
	"gameplay.professions.combat_release.live_locked_target_axis_gu.v1"
)
const TARGET_CENTERED_SPATIAL_SKILL_IDS := {
	"wizard.exploding_flame": true,
	"wizard.fire_wall": true,
	"wizard.ice_storm": true,
}
const CONTINUOUS_AIM_LINE_SKILL_IDS := {
	"wizard.hellfire": true,
	"wizard.laser": true,
}
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


static func tracks_locked_target_for_skill(
	stable_skill_id: String,
	target_mode: String
) -> bool:
	# Wild Rush is spatially a direction skill, but its direction and corridor
	# are derived from the one eligible monster chosen before the body action.
	# Preserve only that original instance through the release frame. The three
	# canonical target-centred spatial spells are also bound to the selected
	# monster identity, but never to an input-time coordinate snapshot: resolve()
	# receives the monster's live manually-authored footpoint at release. This
	# keeps their ground geometry spatial while preventing a delayed cast from
	# silently degrading to the caster's facing point.
	return (
		stable_skill_id == "warrior.wild_rush"
		or TARGET_CENTERED_SPATIAL_SKILL_IDS.has(stable_skill_id)
		or CONTINUOUS_AIM_LINE_SKILL_IDS.has(stable_skill_id)
		or tracks_locked_target(target_mode)
	)


static func target_centered_spatial_policy_id(stable_skill_id: String) -> String:
	if TARGET_CENTERED_SPATIAL_SKILL_IDS.has(stable_skill_id):
		return TARGET_CENTERED_SPATIAL_RELEASE_POLICY_ID
	return ""


static func resolve(
	actor_position_at_release: Vector2,
	input_direction: Vector2,
	locked_target_instance_id := 0,
	locked_target_position_at_release := Vector2.ZERO,
	locked_target_valid_at_release := false,
	track_locked_target := true,
	release_facing_policy := FACING_POLICY_LIVE_LOCKED_TARGET
) -> Dictionary:
	var input_direction_ground_gu := _normalized_input_ground_direction(input_direction)
	var release_direction_ground_gu := input_direction_ground_gu
	var effective_facing_policy := release_facing_policy
	if effective_facing_policy not in [
		FACING_POLICY_LIVE_LOCKED_TARGET,
		FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION,
	]:
		effective_facing_policy = FACING_POLICY_LIVE_LOCKED_TARGET
	var direction_resolution: Dictionary = {}
	if effective_facing_policy == FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION:
		# Preserve the input-facing snapshot for the whole action. The screen PX
		# vector is converted to GU before quantization and then projected back to
		# the matching screen/visual direction.
		direction_resolution = CombatDirectionSpaceScript.resolve_screen_delta_px(
			input_direction
		)
		release_direction_ground_gu = direction_resolution.get(
			"canonical_ground_direction_gu", input_direction_ground_gu
		)
	var had_locked_target := track_locked_target and locked_target_instance_id > 0
	var valid_original_target := had_locked_target and locked_target_valid_at_release
	var origin_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			actor_position_at_release
		)
	)
	var locked_target_ground_gu_at_release := Vector2.ZERO
	var live_locked_target_delta_ground_gu := Vector2.ZERO
	var live_locked_target_direction_ground_gu := Vector2.ZERO
	var live_locked_target_direction_index := -1
	if valid_original_target:
		# Preserve the established release direction's single linear conversion.
		# Converting two large absolute screen positions separately and subtracting
		# introduced avoidable floating cancellation at some 16-way line angles.
		live_locked_target_delta_ground_gu = (
			GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
				locked_target_position_at_release - actor_position_at_release
			)
		)
		locked_target_ground_gu_at_release = (
			origin_ground_gu + live_locked_target_delta_ground_gu
		)
		if (
			live_locked_target_delta_ground_gu.length_squared()
			> EPSILON * EPSILON
		):
			live_locked_target_direction_ground_gu = (
				live_locked_target_delta_ground_gu.normalized()
			)
			live_locked_target_direction_index = (
				CombatDirectionSpaceScript.direction_index_for_ground_delta_gu(
					live_locked_target_direction_ground_gu
				)
			)
	if (
		valid_original_target
		and effective_facing_policy == FACING_POLICY_LIVE_LOCKED_TARGET
	):
		if not live_locked_target_direction_ground_gu.is_zero_approx():
			release_direction_ground_gu = live_locked_target_direction_ground_gu
	var release_direction_screen_px := (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			release_direction_ground_gu
		).normalized()
	)
	return {
		"contract_id": CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"policy": (
			POLICY_LOCKED_SINGLE_TARGET
			if had_locked_target
			else POLICY_INPUT_DIRECTION
		),
		"origin_screen_px": actor_position_at_release,
		"origin_ground_gu": origin_ground_gu,
		"direction_ground_gu": release_direction_ground_gu,
		"direction_screen_px": release_direction_screen_px,
		"release_facing_policy": effective_facing_policy,
		"release_facing_policy_id": (
			MELEE_RELEASE_FACING_POLICY_ID
			if effective_facing_policy == FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
			else ""
		),
		"direction_locked_for_action": (
			effective_facing_policy == FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
		),
		"direction_space_contract_id": str(
			direction_resolution.get("contract_id", "")
		),
		"direction_index": int(direction_resolution.get("direction_index", -1)),
		"visual_direction_index": int(
			direction_resolution.get("visual_direction_index", -1)
		),
		"direction_source_screen_delta_px": direction_resolution.get(
			"source_screen_delta_px", Vector2.ZERO
		),
		"direction_source_ground_delta_gu": direction_resolution.get(
			"ground_delta_gu", Vector2.ZERO
		),
		"direction_canonical_grid_step": direction_resolution.get(
			"canonical_grid_step", Vector2i.ZERO
		),
		"refresh_actor_footpoint_at_release": true,
		"refresh_locked_target_footpoint_at_release": valid_original_target,
		"live_locked_target_axis_contract_id": LIVE_LOCKED_TARGET_AXIS_CONTRACT_ID,
		"locked_target_ground_gu_at_release": locked_target_ground_gu_at_release,
		"live_locked_target_delta_ground_gu": live_locked_target_delta_ground_gu,
		"live_locked_target_direction_ground_gu": (
			live_locked_target_direction_ground_gu
		),
		"live_locked_target_direction_index": live_locked_target_direction_index,
		"locked_target_instance_id": locked_target_instance_id if had_locked_target else 0,
		"locked_target_valid_at_release": valid_original_target,
		"allow_target_retarget": not had_locked_target,
		"allow_directional_scan": not had_locked_target,
	}


static func _normalized_input_ground_direction(input_direction_screen_px: Vector2) -> Vector2:
	var ground_direction := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		input_direction_screen_px
	)
	if ground_direction.length_squared() <= EPSILON * EPSILON:
		return Vector2(1.0, 1.0).normalized()
	return ground_direction.normalized()


static func candidate_allowed(release_geometry: Dictionary, candidate_instance_id: int) -> bool:
	var locked_id := int(release_geometry.get("locked_target_instance_id", 0))
	if locked_id > 0:
		return (
			bool(release_geometry.get("locked_target_valid_at_release", false))
			and candidate_instance_id == locked_id
		)
	return bool(release_geometry.get("allow_directional_scan", true))
