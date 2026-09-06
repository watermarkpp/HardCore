class_name WarriorMeleeGeometry
extends RefCounted

const CombatDirectionSpaceScript := preload(
	"res://scripts/skills/combat_direction_space.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

## Canonical warrior melee geometry. Every value is expressed in logical map
## tiles after the actor/enemy footpoints have been converted to fractional
## canonical tile coordinates. Screen pixels are deliberately not accepted.

const CONTRACT_ID := "gameplay.warrior.melee_geometry.ground_gu.v2"
const WILD_RUSH_CONTRACT_ID := "gameplay.warrior.wild_rush.atomic_ground_gu.v2"
const TARGET_COUNT_POLICY_ID := "gameplay.warrior.melee_target_count.v1"
const DIRECTION_SPACE_CONTRACT_ID := CombatDirectionSpaceScript.CONTRACT_ID
const FOOTPRINT_INTERSECTION_CONTRACT_ID := (
	"gameplay.warrior.melee_footprint_intersection.ground_gu_sat.v2"
)
const THRUST_CONTINUOUS_DAMAGE_AXIS_CONTRACT_ID := (
	"gameplay.warrior.thrust.damage_axis.snapped_visual_8dir_snapshot.v1"
)
## User-authorized formal design (2026-08-09): when the locked target is valid,
## inside the attack skill's legal melee range and not blocked by terrain, the
## release axis is the continuous Ground GU direction from the player release
## footpoint to the locked target release footpoint. The old snapped 8-dir
## damage-axis contract above is retained only for unmigrated callers/tests and
## must never be presented as this behavior.
const TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID := (
	"gameplay.warrior.melee.target_aligned_continuous_release.v1"
)
const TARGET_ALIGNED_RELEASE_FOOTPRINT_CONTRACT_ID := (
	"gameplay.warrior.target_aligned_release_footprint.shared_snapshot.v1"
)
## User-authorized HardCore override (2026-09-06): every ordinary melee
## attack is a fixed 2 GU single-target release.  Fire Sword inherits the
## same 2 GU contact range; these are total reaches, so a second range-bonus
## pass is forbidden.  The release snapshot below remains the sole runtime
## geometry truth for both modes.
const NORMAL_FIRE_FIXED_REACH_CONTRACT_ID := (
	"gameplay.warrior.normal_fire.fixed_2gu.v1"
)
const RELEASE_FOOTPRINT_CONTRACT_ID := (
	"gameplay.warrior.release_footprint.shared_snapshot.v1"
)
const TARGET_FOOTPRINT_CONTRACT_ID := (
	WorldSpatialRulesScript.ACTOR_GROUND_FOOTPRINT_CONTRACT_ID
)
const UNLIMITED_TARGETS := -1

const SKILL_NORMAL := "normal"
const SKILL_FIRE := "fire"
const SKILL_HALF_MOON := "half_moon"
const SKILL_THRUST := "thrust"

const BASE_REACH_GU := {
	SKILL_NORMAL: 2.0,
	SKILL_FIRE: 2.0,
	## User-authorized HardCore override: Half Moon is a 2 GU fan.
	SKILL_HALF_MOON: 2.0,
	## User-authorized HardCore override: Thrusting is a fixed 3 GU line.
	SKILL_THRUST: 3.0,
}
const RANGE_BONUS_CAP_GU := {
	## Ordinary and Fire Sword ranges are explicit total reaches, not bases
	## that can be extended by a second range calculation.
	SKILL_NORMAL: 0.0,
	SKILL_FIRE: 0.0,
	## The explicit 2 GU/3 GU skill lengths are total reaches, not bases
	## extended by a second range calculation.
	SKILL_HALF_MOON: 0.0,
	SKILL_THRUST: 0.0,
}
const MAXIMUM_TARGETS := {
	SKILL_NORMAL: 1,
	SKILL_FIRE: 1,
	SKILL_HALF_MOON: UNLIMITED_TARGETS,
	SKILL_THRUST: UNLIMITED_TARGETS,
}

const THRUST_PRIMARY_REACH_GU := 1.5
const THRUST_TOTAL_REACH_GU := 3.0
const THRUST_WIDTH_GU := 1.0
const THRUST_SECONDARY_IGNORE_AC := true
## Short straight-line footprint shared by normal/fire target-aligned releases.
## Width covers the locked target combat radius (<= 0.5 GU) so the locked
## target remains formally covered while the band stays a narrow line.
const TARGET_ALIGNED_NORMAL_WIDTH_GU := 1.0
const TARGET_ALIGNED_LINE_WIDTH_GU := 1.0
## User-authorized HardCore override: Half Moon's release snapshot is a
## symmetric 120-degree fan centered on the continuous GU release axis. The
## legacy relative codes remain stable for primary/left/right consumers; code 2
## (the old +90-degree fourth sector) is no longer inside the canonical fan.
const TARGET_ALIGNED_HALF_MOON_ARC_CENTER_OFFSET_RADIANS := 0.0
const TARGET_ALIGNED_HALF_MOON_HALF_ANGLE_RADIANS := PI / 3.0
const HALF_MOON_RELATIVE_DIRECTION_OFFSETS: Array[int] = [7, 0, 1]
const HALF_MOON_SIDE_SECTOR_CENTER_RADIANS := (PI / 8.0 + PI / 3.0) * 0.5
const HALF_MOON_SIDE_SECTOR_HALF_ANGLE_RADIANS := (PI / 3.0 - PI / 8.0) * 0.5
const WILD_RUSH_TARGET_REACH_GU := 1.5
const WILD_RUSH_PUSH_DISTANCE_GU := 3.0
const WILD_RUSH_MAXIMUM_GRID_STEPS := 3
const EPSILON := 0.0001

# Versioned aliases for integration code pending GU field migration.
const BASE_REACH_TILES := BASE_REACH_GU
const RANGE_BONUS_CAP_TILES := RANGE_BONUS_CAP_GU
const THRUST_PRIMARY_REACH_TILES := THRUST_PRIMARY_REACH_GU
const THRUST_WIDTH_TILES := THRUST_WIDTH_GU
const WILD_RUSH_TARGET_REACH_TILES := WILD_RUSH_TARGET_REACH_GU
const WILD_RUSH_PUSH_DISTANCE_TILES := WILD_RUSH_MAXIMUM_GRID_STEPS

# ArtSpec/screen-facing order: S, SW, W, NW, N, NE, E, SE. The values are
# steps in canonical map-tile coordinates, not screen-space vectors.
const FACING_TILE_STEPS: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
]


static func reach_tiles(mode: String, range_bonus_tiles := 0.0) -> float:
	return reach_gu(mode, range_bonus_tiles)


static func reach_gu(mode: String, range_bonus_gu := 0.0) -> float:
	var base := float(BASE_REACH_GU.get(mode, BASE_REACH_GU[SKILL_NORMAL]))
	var bonus_cap := float(RANGE_BONUS_CAP_GU.get(mode, 0.0))
	return base + clampf(float(range_bonus_gu), 0.0, bonus_cap)


static func reach_contract_id(mode: String) -> String:
	if mode == SKILL_NORMAL or mode == SKILL_FIRE:
		return NORMAL_FIRE_FIXED_REACH_CONTRACT_ID
	return CONTRACT_ID


static func maximum_targets(mode: String) -> int:
	return int(MAXIMUM_TARGETS.get(mode, 1))


static func has_finite_target_limit(mode: String) -> bool:
	return maximum_targets(mode) != UNLIMITED_TARGETS


static func target_count_policy(mode: String) -> Dictionary:
	var limit := maximum_targets(mode)
	return {
		"contract_id": TARGET_COUNT_POLICY_ID,
		"mode": mode,
		"maximum_targets": limit,
		"unlimited_within_geometry": limit == UNLIMITED_TARGETS,
	}


static func facing_tile_step(direction_index: int) -> Vector2i:
	return CombatDirectionSpaceScript.canonical_grid_step(direction_index)


static func canonical_ground_direction_gu(direction_index: int) -> Vector2:
	return CombatDirectionSpaceScript.canonical_ground_direction_gu(
		direction_index
	)


static func chebyshev_distance(origin: Vector2, target: Vector2) -> float:
	## Deprecated name retained while integration migrates. Result is Euclidean GU.
	return GroundUnitSpaceScript.distance_gu(origin, target)


static func is_single_target_in_reach(
	origin: Vector2,
	target: Vector2,
	mode: String,
	range_bonus_tiles := 0.0
) -> bool:
	return (
		GroundUnitSpaceScript.is_within_range_gu(
			origin,
			target,
			reach_gu(mode, range_bonus_tiles)
		)
		and GroundUnitSpaceScript.distance_gu(origin, target) > EPSILON
	)


static func is_single_target_in_reach_gu(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	mode: String,
	range_bonus_gu := 0.0
) -> bool:
	return is_single_target_in_reach(
		origin_ground_gu, target_ground_gu, mode, range_bonus_gu
	)


static func line_coordinates(delta: Vector2, direction_index: int) -> Vector2:
	var forward := Vector2(facing_tile_step(direction_index))
	forward = forward.normalized()
	var side := Vector2(forward.y, -forward.x)
	return Vector2(delta.dot(forward), delta.dot(side))


static func line_coordinates_gu(
	delta_ground_gu: Vector2,
	direction_index: int
) -> Vector2:
	return line_coordinates(delta_ground_gu, direction_index)


static func thrust_slot(
	origin: Vector2,
	target: Vector2,
	direction_index: int,
	range_bonus_tiles := 0.0
) -> int:
	var coordinates := line_coordinates(target - origin, direction_index)
	if coordinates.x <= EPSILON:
		return 0
	if absf(coordinates.y) > THRUST_WIDTH_GU * 0.5 + EPSILON:
		return 0
	if coordinates.x > reach_tiles(SKILL_THRUST, range_bonus_tiles) + EPSILON:
		return 0
	return 1 if coordinates.x <= THRUST_PRIMARY_REACH_GU + EPSILON else 2


static func thrust_slot_gu(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	direction_index: int,
	range_bonus_gu := 0.0
) -> int:
	return thrust_slot(
		origin_ground_gu, target_ground_gu, direction_index, range_bonus_gu
	)


static func thrust_slot_ignores_ac(slot: int) -> bool:
	return THRUST_SECONDARY_IGNORE_AC and slot == 2


static func target_footprint_polygon_ground_gu(
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float
) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for offset_ground_gu: Vector2 in (
		WorldSpatialRulesScript.actor_footprint_ground_polygon_gu(
			target_combat_radius_gu
		)
	):
		polygon.append(target_center_ground_gu + offset_ground_gu)
	return polygon


static func attack_region_polygons(
	origin: Vector2,
	direction_index: int,
	mode: String,
	range_bonus_tiles := 0.0
) -> Array[PackedVector2Array]:
	var resolved_mode := mode if mode in BASE_REACH_GU else SKILL_NORMAL
	var result: Array[PackedVector2Array] = []
	if resolved_mode == SKILL_THRUST:
		result.append(_thrust_region_polygon(
			origin,
			direction_index,
			0.0,
			reach_tiles(SKILL_THRUST, range_bonus_tiles)
		))
		return result
	if resolved_mode == SKILL_HALF_MOON:
		## One arc polygon is the canonical 120-degree footprint. Do not rebuild
		## the old four-cell fan here: release snapshots and broadphase consumers
		## must agree at the exact angular boundary.
		result.append(_direction_sector_polygon_for_direction_ground_gu(
			origin,
			canonical_ground_direction_gu(direction_index),
			reach_tiles(SKILL_HALF_MOON, range_bonus_tiles),
			TARGET_ALIGNED_HALF_MOON_HALF_ANGLE_RADIANS,
		))
		return result
	result.append(direction_sector_polygon(
		origin,
		direction_index,
		reach_tiles(resolved_mode, range_bonus_tiles)
	))
	return result


static func attack_region_polygons_ground_gu(
	origin_ground_gu: Vector2,
	direction_index: int,
	mode: String,
	range_bonus_gu := 0.0
) -> Array[PackedVector2Array]:
	return attack_region_polygons(
		origin_ground_gu, direction_index, mode, range_bonus_gu
	)


static func footprint_intersects_mode_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	direction_index: int,
	mode: String,
	range_bonus_gu := 0.0
) -> bool:
	var target_polygon := target_footprint_polygon_ground_gu(
		target_center_ground_gu,
		target_combat_radius_gu
	)
	for attack_polygon: PackedVector2Array in attack_region_polygons_ground_gu(
		origin_ground_gu,
		direction_index,
		mode,
		range_bonus_gu
	):
		if convex_polygons_intersect_inclusive(attack_polygon, target_polygon):
			return true
	return false


static func footprint_intersects_direction_sector_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	direction_index: int,
	reach_gu: float
) -> bool:
	return _footprint_intersects_direction_ground_sector_gu(
		origin_ground_gu,
		target_center_ground_gu,
		target_combat_radius_gu,
		canonical_ground_direction_gu(direction_index),
		reach_gu,
		PI / 8.0,
	)


static func _footprint_intersects_direction_ground_sector_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	direction_ground_gu: Vector2,
	reach_gu: float,
	half_angle_radians: float,
) -> bool:
	return convex_polygons_intersect_inclusive(
		_direction_sector_polygon_for_direction_ground_gu(
			origin_ground_gu,
			direction_ground_gu,
			reach_gu,
			half_angle_radians,
		),
		target_footprint_polygon_ground_gu(
			target_center_ground_gu,
			target_combat_radius_gu
		)
	)


static func half_moon_footprint_relative_sector_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	attack_direction_index: int,
	range_bonus_gu := 0.0
) -> int:
	if maxf(0.0, target_combat_radius_gu) <= EPSILON:
		return _half_moon_point_relative_sector_gu(
			origin_ground_gu,
			target_center_ground_gu,
			attack_direction_index,
			range_bonus_gu,
		)
	var effective_reach_gu := reach_gu(SKILL_HALF_MOON, range_bonus_gu)
	# Primary damage remains the facing sector. If an ellipse straddles the
	# primary/secondary boundary, primary wins deterministically and the caller
	# must not add the same target to a secondary list.
	if _footprint_intersects_direction_ground_sector_gu(
		origin_ground_gu,
		target_center_ground_gu,
		target_combat_radius_gu,
		canonical_ground_direction_gu(attack_direction_index),
		effective_reach_gu,
		PI / 8.0,
	):
		return 0
	var attack_axis := canonical_ground_direction_gu(attack_direction_index)
	if _footprint_intersects_direction_ground_sector_gu(
		origin_ground_gu,
		target_center_ground_gu,
		target_combat_radius_gu,
		attack_axis.rotated(-HALF_MOON_SIDE_SECTOR_CENTER_RADIANS),
		effective_reach_gu,
		HALF_MOON_SIDE_SECTOR_HALF_ANGLE_RADIANS,
	):
		return 7
	if _footprint_intersects_direction_ground_sector_gu(
		origin_ground_gu,
		target_center_ground_gu,
		target_combat_radius_gu,
		attack_axis.rotated(HALF_MOON_SIDE_SECTOR_CENTER_RADIANS),
		effective_reach_gu,
		HALF_MOON_SIDE_SECTOR_HALF_ANGLE_RADIANS,
	):
		return 1
	return -1


static func _half_moon_point_relative_sector_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	attack_direction_index: int,
	range_bonus_gu := 0.0
) -> int:
	## A point candidate has no area polygon. Keep its classification in the
	## same continuous angular contract instead of asking SAT to intersect four
	## coincident vertices, which is undefined for a zero-radius footprint.
	if not is_single_target_in_reach(
		origin_ground_gu,
		target_center_ground_gu,
		SKILL_HALF_MOON,
		range_bonus_gu,
	):
		return -1
	var delta := target_center_ground_gu - origin_ground_gu
	var attack_axis := canonical_ground_direction_gu(attack_direction_index)
	var angular_delta := wrapf(
		delta.angle() - attack_axis.angle(),
		-PI,
		PI,
	)
	if absf(angular_delta) <= PI / 8.0 + EPSILON:
		return 0
	if (
		angular_delta >= -TARGET_ALIGNED_HALF_MOON_HALF_ANGLE_RADIANS - EPSILON
		and angular_delta < 0.0
	):
		return 7
	if (
		angular_delta <= TARGET_ALIGNED_HALF_MOON_HALF_ANGLE_RADIANS + EPSILON
		and angular_delta > 0.0
	):
		return 1
	return -1


static func thrust_footprint_slot_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	direction_index: int,
	range_bonus_gu := 0.0
) -> int:
	return thrust_footprint_slot_for_direction_ground_gu(
		origin_ground_gu,
		target_center_ground_gu,
		target_combat_radius_gu,
		canonical_ground_direction_gu(direction_index),
		range_bonus_gu
	)


static func attack_release_footprint_snapshot_ground_gu(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	direction_index: int,
	mode: String,
	range_bonus_gu := 0.0,
	coordinate_context := {}
) -> Dictionary:
	var resolved_direction_index := posmod(direction_index, 8)
	var direction_ground_gu := canonical_ground_direction_gu(
		resolved_direction_index
	)
	match mode:
		SKILL_THRUST:
			return SkillFootprintSnapshotScript.create_directed_rectangle(
				skill_id,
				release_id,
				origin_ground_gu,
				direction_ground_gu,
				reach_gu(SKILL_THRUST, range_bonus_gu),
				THRUST_WIDTH_GU,
				0.0,
				0.0,
				0.0,
				"",
				coordinate_context
			)
		SKILL_HALF_MOON:
			# The project override is a symmetric 120-degree sector centered
			# on the canonical visual facing axis. This snapshot is the sole
			# release footprint consumed by candidate and damage validation.
			return SkillFootprintSnapshotScript.create_sector_arc(
				skill_id,
				release_id,
				origin_ground_gu,
				direction_ground_gu.rotated(
					TARGET_ALIGNED_HALF_MOON_ARC_CENTER_OFFSET_RADIANS
				),
				reach_gu(SKILL_HALF_MOON, range_bonus_gu),
				TARGET_ALIGNED_HALF_MOON_HALF_ANGLE_RADIANS,
				96,
				coordinate_context
			)
		SKILL_NORMAL, SKILL_FIRE:
			return SkillFootprintSnapshotScript.create_sector_arc(
				skill_id,
				release_id,
				origin_ground_gu,
				direction_ground_gu,
				reach_gu(mode, range_bonus_gu),
				PI / 8.0,
				24,
				coordinate_context
			)
	return {}


static func wild_rush_release_footprint_snapshot_ground_gu(
	release_id: String,
	segment_start_ground_gu: Vector2,
	segment_end_ground_gu: Vector2,
	caster_combat_radius_gu: float,
	coordinate_context := {}
) -> Dictionary:
	return SkillFootprintSnapshotScript.create_swept_capsule_path(
		"warrior.wild_rush",
		release_id,
		segment_start_ground_gu,
		segment_end_ground_gu,
		maxf(0.0, caster_combat_radius_gu),
		SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS,
		"",
		-1,
		coordinate_context
	)


static func release_snapshot_intersects_target_footprint_ground_gu(
	skill_footprint_snapshot: Dictionary,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float
) -> bool:
	return (
		SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			skill_footprint_snapshot,
			target_center_ground_gu,
			target_combat_radius_gu
		)
	)


static func thrust_damage_axis_plan_ground_gu(
	visual_direction_index: int,
	release_geometry: Dictionary,
	coordinate_context := {}
) -> Dictionary:
	var resolved_visual_direction_index := posmod(visual_direction_index, 8)
	var canonical_direction_ground_gu := canonical_ground_direction_gu(
		resolved_visual_direction_index
	)
	var live_direction_index := int(
		release_geometry.get("live_locked_target_direction_index", -1)
	)
	var origin_ground_gu: Vector2 = release_geometry.get(
		"origin_ground_gu", Vector2.ZERO
	)
	var release_id := str(release_geometry.get(
		"release_id", "unbound_release"
	))
	var skill_footprint_snapshot := (
		attack_release_footprint_snapshot_ground_gu(
			"warrior.thrusting",
			release_id,
			origin_ground_gu,
			resolved_visual_direction_index,
			SKILL_THRUST,
			0.0,
			coordinate_context
		)
	)
	return {
		"contract_id": THRUST_CONTINUOUS_DAMAGE_AXIS_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"visual_direction_index": resolved_visual_direction_index,
		"canonical_visual_direction_ground_gu": canonical_direction_ground_gu,
		"damage_direction_ground_gu": canonical_direction_ground_gu,
		"damage_axis_source": "canonical_visual_direction_snapped",
		"uses_live_locked_target_axis": false,
		"fallback_reason": "continuous_target_axis_rejected_by_visual_contract",
		"live_locked_target_direction_index": live_direction_index,
		"effect_length_gu": reach_gu(SKILL_THRUST),
		"effect_width_gu": THRUST_WIDTH_GU,
		"primary_segment_end_gu": THRUST_PRIMARY_REACH_GU,
		"release_id": release_id,
		"skill_footprint_snapshot": skill_footprint_snapshot,
	}


## ---------------------------------------------------------------------------
## Target-aligned continuous release contract (v1)
## ---------------------------------------------------------------------------
## INTEGRATION_HOOK: game_root._on_player_attack / _execute_canonical_melee
## must route through target_aligned_melee_release_plan_ground_gu() whenever a
## locked target is valid at release. The old snapped thrust plan is retained
## for unmigrated callers only.

static func target_aligned_continuous_axis_gu(
	release_geometry: Dictionary
) -> Dictionary:
	var locked_target_valid := bool(release_geometry.get(
		"locked_target_valid_at_release", false
	))
	var locked_target_instance_id := int(release_geometry.get(
		"locked_target_instance_id", 0
	))
	var raw_axis_ground_gu: Variant = release_geometry.get(
		"live_locked_target_direction_ground_gu", Vector2.ZERO
	)
	var axis_ground_gu := (
		(raw_axis_ground_gu as Vector2)
		if raw_axis_ground_gu is Vector2
		else Vector2.ZERO
	)
	var invalid_lock_reason := (
		"invalid_target" if not locked_target_valid else "missing_lock"
	)
	if not locked_target_valid or locked_target_instance_id <= 0:
		return {
			"valid": false,
			"reason": invalid_lock_reason,
			"axis_ground_gu": Vector2.ZERO,
			"origin_ground_gu": release_geometry.get(
				"origin_ground_gu", Vector2.ZERO
			),
			"locked_target_ground_gu_at_release": release_geometry.get(
				"locked_target_ground_gu_at_release", Vector2.ZERO
			),
			"locked_target_instance_id": locked_target_instance_id,
		}
	if axis_ground_gu.length_squared() <= EPSILON * EPSILON:
		return {
			"valid": false,
			"reason": "zero_axis",
			"axis_ground_gu": Vector2.ZERO,
			"origin_ground_gu": release_geometry.get(
				"origin_ground_gu", Vector2.ZERO
			),
			"locked_target_ground_gu_at_release": release_geometry.get(
				"locked_target_ground_gu_at_release", Vector2.ZERO
			),
			"locked_target_instance_id": locked_target_instance_id,
		}
	return {
		"valid": true,
		"reason": "",
		"axis_ground_gu": axis_ground_gu.normalized(),
		"origin_ground_gu": release_geometry.get(
			"origin_ground_gu", Vector2.ZERO
		),
		"locked_target_ground_gu_at_release": release_geometry.get(
			"locked_target_ground_gu_at_release", Vector2.ZERO
		),
		"locked_target_instance_id": locked_target_instance_id,
	}


static func target_aligned_melee_release_plan_ground_gu(
	release_geometry: Dictionary,
	mode: String,
	coordinate_context: Dictionary,
	range_bonus_gu := 0.0,
	terrain_blocked := false
) -> Dictionary:
	## Builds the single canonical target-aligned release snapshot. Eligibility
	## requires: locked target valid at release, non-zero live continuous axis,
	## locked target inside the skill's legal reach and no terrain block.
	## Ineligible releases return a plan with target_axis_eligible=false and a
	## null snapshot so every consumer fails closed; upper-layer whiff/fail
	## strategy stays untouched and no legacy snapped plan is substituted.
	var resolved_mode := mode if mode in BASE_REACH_GU else SKILL_NORMAL
	var origin_ground_gu: Variant = release_geometry.get(
		"origin_ground_gu", Vector2.INF
	)
	if (
		not origin_ground_gu is Vector2
		or not _vector2_is_finite(origin_ground_gu as Vector2)
	):
		return _target_aligned_ineligible_plan(
			release_geometry, resolved_mode, "missing_origin"
		)
	if not bool(release_geometry.get("locked_target_valid_at_release", false)):
		return _target_aligned_ineligible_plan(
			release_geometry, resolved_mode, "invalid_target"
		)
	var locked_target_ground_gu := (
		release_geometry.get(
			"locked_target_ground_gu_at_release", Vector2.ZERO
		) as Vector2
	)
	if (
		origin_ground_gu as Vector2
	).distance_squared_to(locked_target_ground_gu) <= EPSILON * EPSILON:
		return _target_aligned_ineligible_plan(
			release_geometry, resolved_mode, "same_footpoint"
		)
	var axis_result := target_aligned_continuous_axis_gu(release_geometry)
	if not bool(axis_result.get("valid", false)):
		return _target_aligned_ineligible_plan(
			release_geometry,
			resolved_mode,
			str(axis_result.get("reason", "invalid_target"))
		)
	if terrain_blocked:
		return _target_aligned_ineligible_plan(
			release_geometry, resolved_mode, "terrain_blocked"
		)
	var continuous_axis_ground_gu := (
		axis_result.get("axis_ground_gu", Vector2.ZERO) as Vector2
	)
	var release_id := str(release_geometry.get(
		"release_id", "unbound_target_aligned_release"
	))
	var skill_id := _target_aligned_skill_id(resolved_mode)
	var snapshot := target_aligned_release_snapshot_ground_gu(
		skill_id,
		release_id,
		origin_ground_gu as Vector2,
		continuous_axis_ground_gu,
		resolved_mode,
		range_bonus_gu,
		coordinate_context
	)
	var locked_target_combat_radius_gu := maxf(
		0.0,
		float(release_geometry.get(
			"locked_target_combat_radius_gu_at_release", 0.0
		))
	)
	# Eligibility consumes the exact same snapshot and the target's complete
	# combat footprint as damage and presentation. A centre-only distance gate
	# would reject large monsters whose body still intersects the release band.
	if not release_snapshot_intersects_target_footprint_ground_gu(
		snapshot,
		locked_target_ground_gu,
		locked_target_combat_radius_gu
	):
		return _target_aligned_ineligible_plan(
			release_geometry, resolved_mode, "out_of_range"
		)
	var visual_direction_index := (
		CombatDirectionSpaceScript.direction_index_for_ground_delta_gu(
			continuous_axis_ground_gu
		)
	)
	var plan := {
		"contract_id": TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID,
		"footprint_contract_id": TARGET_ALIGNED_RELEASE_FOOTPRINT_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"mode": resolved_mode,
		"skill_id": skill_id,
		"release_id": release_id,
		"origin_ground_gu": origin_ground_gu as Vector2,
		"continuous_axis_ground_gu": continuous_axis_ground_gu,
		"locked_target_ground_gu_at_release": locked_target_ground_gu,
		"locked_target_instance_id": int(
			axis_result.get("locked_target_instance_id", 0)
		),
		"locked_target_combat_radius_gu_at_release": (
			locked_target_combat_radius_gu
		),
		"target_axis_eligible": true,
		"ineligible_reason": "",
		"visual_direction_index": visual_direction_index,
		"visual_direction_contract_id": DIRECTION_SPACE_CONTRACT_ID,
		"range_bonus_gu": range_bonus_gu,
		"terrain_blocked": false,
		"skill_footprint_snapshot": snapshot,
	}
	plan.make_read_only()
	return plan


static func target_aligned_release_snapshot_ground_gu(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	continuous_axis_ground_gu: Vector2,
	mode: String,
	range_bonus_gu := 0.0,
	coordinate_context := {}
) -> Dictionary:
	match mode:
		SKILL_THRUST:
			return SkillFootprintSnapshotScript.create_directed_rectangle(
				skill_id,
				release_id,
				origin_ground_gu,
				continuous_axis_ground_gu,
				reach_gu(SKILL_THRUST, range_bonus_gu),
				TARGET_ALIGNED_LINE_WIDTH_GU,
				0.0,
				0.0,
				0.0,
				"",
				coordinate_context
			)
		SKILL_HALF_MOON:
			return SkillFootprintSnapshotScript.create_sector_arc(
				skill_id,
				release_id,
				origin_ground_gu,
				continuous_axis_ground_gu.rotated(
					TARGET_ALIGNED_HALF_MOON_ARC_CENTER_OFFSET_RADIANS
				),
				reach_gu(SKILL_HALF_MOON, range_bonus_gu),
				TARGET_ALIGNED_HALF_MOON_HALF_ANGLE_RADIANS,
				96,
				coordinate_context
			)
		SKILL_NORMAL, SKILL_FIRE:
			return SkillFootprintSnapshotScript.create_directed_rectangle(
				skill_id,
				release_id,
				origin_ground_gu,
				continuous_axis_ground_gu,
				reach_gu(mode, range_bonus_gu),
				TARGET_ALIGNED_NORMAL_WIDTH_GU,
				0.0,
				0.0,
				0.0,
				"",
				coordinate_context
			)
	return {}


static func target_aligned_release_plan_intersects_target_footprint_ground_gu(
	plan: Dictionary,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	coordinate_context: Dictionary
) -> bool:
	## Candidate gate that consumes the plan's exact release snapshot. A plan
	## without target_axis_eligible or without a strict-valid snapshot always
	## fails closed; no second attack range is ever computed here.
	if not bool(plan.get("target_axis_eligible", false)):
		return false
	var raw_snapshot: Variant = plan.get("skill_footprint_snapshot")
	if not raw_snapshot is Dictionary:
		return false
	var snapshot := raw_snapshot as Dictionary
	if not bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		coordinate_context,
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false)):
		return false
	return release_snapshot_intersects_target_footprint_ground_gu(
		snapshot,
		target_center_ground_gu,
		target_combat_radius_gu
	)


static func target_aligned_thrust_slot_for_plan_gu(
	plan: Dictionary,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	coordinate_context: Dictionary,
	range_bonus_gu := 0.0
) -> int:
	## Same-snapshot slot classification for the continuous thrust release.
	## Primary segment (slot 1) is 0..1.5 GU, secondary (slot 2) is
	## 1.5..reach GU; width remains 1 GU.
	if not bool(plan.get("target_axis_eligible", false)):
		return 0
	var raw_snapshot: Variant = plan.get("skill_footprint_snapshot")
	if not raw_snapshot is Dictionary:
		return 0
	var snapshot := raw_snapshot as Dictionary
	if not bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		coordinate_context,
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false)):
		return 0
	var target_polygon := target_footprint_polygon_ground_gu(
		target_center_ground_gu,
		target_combat_radius_gu
	)
	if not SkillFootprintSnapshotScript.intersects_target_polygon_ground_gu(
		snapshot,
		target_polygon
	):
		return 0
	return thrust_footprint_slot_for_direction_ground_gu(
		snapshot.get("origin_ground_gu", Vector2.ZERO) as Vector2,
		target_center_ground_gu,
		target_combat_radius_gu,
		snapshot.get("direction_ground_gu", Vector2.ZERO) as Vector2,
		range_bonus_gu
	)


static func target_aligned_half_moon_relative_sector_for_plan_gu(
	plan: Dictionary,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	coordinate_context: Dictionary,
	range_bonus_gu := 0.0
) -> int:
	## Same-snapshot sector classification for the continuous half-moon fan.
	## Return codes preserve the primary/left/right mapping: 0 = primary sector
	## centered on the continuous axis (+/-22.5 deg), 7 = the negative-angle
	## side band, 1 = the positive-angle side band. The bands end at +/-60 deg,
	## exactly matching the 120-degree release snapshot. A body straddling the
	## primary boundary wins primary deterministically.
	if not bool(plan.get("target_axis_eligible", false)):
		return -1
	var raw_snapshot: Variant = plan.get("skill_footprint_snapshot")
	if not raw_snapshot is Dictionary:
		return -1
	var snapshot := raw_snapshot as Dictionary
	if not bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		coordinate_context,
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false)):
		return -1
	var target_polygon := target_footprint_polygon_ground_gu(
		target_center_ground_gu,
		target_combat_radius_gu
	)
	if not SkillFootprintSnapshotScript.intersects_target_polygon_ground_gu(
		snapshot,
		target_polygon
	):
		return -1
	var origin_ground_gu := (
		plan.get("origin_ground_gu", Vector2.ZERO) as Vector2
	)
	var continuous_axis_ground_gu := (
		plan.get("continuous_axis_ground_gu", Vector2.ZERO) as Vector2
	)
	var effective_reach_gu := reach_gu(SKILL_HALF_MOON, range_bonus_gu)
	if footprint_intersects_continuous_direction_sector_gu(
		origin_ground_gu,
		target_center_ground_gu,
		target_combat_radius_gu,
		continuous_axis_ground_gu,
		effective_reach_gu
	):
		return 0
	if _footprint_intersects_direction_ground_sector_gu(
		origin_ground_gu,
		target_center_ground_gu,
		target_combat_radius_gu,
		continuous_axis_ground_gu.rotated(-HALF_MOON_SIDE_SECTOR_CENTER_RADIANS),
		effective_reach_gu,
		HALF_MOON_SIDE_SECTOR_HALF_ANGLE_RADIANS,
	):
		return 7
	if _footprint_intersects_direction_ground_sector_gu(
		origin_ground_gu,
		target_center_ground_gu,
		target_combat_radius_gu,
		continuous_axis_ground_gu.rotated(HALF_MOON_SIDE_SECTOR_CENTER_RADIANS),
		effective_reach_gu,
		HALF_MOON_SIDE_SECTOR_HALF_ANGLE_RADIANS,
	):
		return 1
	return -1


static func footprint_intersects_continuous_direction_sector_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	direction_ground_gu: Vector2,
	effective_reach_gu: float
) -> bool:
	return convex_polygons_intersect_inclusive(
		_direction_sector_polygon_for_direction_ground_gu(
			origin_ground_gu,
			direction_ground_gu,
			effective_reach_gu
		),
		target_footprint_polygon_ground_gu(
			target_center_ground_gu,
			target_combat_radius_gu
		)
	)


static func _target_aligned_skill_id(mode: String) -> String:
	match mode:
		SKILL_THRUST:
			return "warrior.thrusting"
		SKILL_HALF_MOON:
			return "warrior.half_moon"
		SKILL_FIRE:
			return "warrior.fire_sword"
		_:
			return "warrior.normal_attack"


static func _target_aligned_ineligible_plan(
	release_geometry: Dictionary,
	mode: String,
	reason: String
) -> Dictionary:
	var visual_direction_index := int(release_geometry.get(
		"direction_index", -1
	))
	if visual_direction_index < 0 or visual_direction_index >= 8:
		var axis_ground_gu: Vector2 = release_geometry.get(
			"live_locked_target_direction_ground_gu", Vector2.ZERO
		)
		visual_direction_index = (
			CombatDirectionSpaceScript.direction_index_for_ground_delta_gu(
				axis_ground_gu
			)
			if axis_ground_gu.length_squared() > EPSILON * EPSILON
			else 0
		)
	return {
		"contract_id": TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID,
		"footprint_contract_id": TARGET_ALIGNED_RELEASE_FOOTPRINT_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"mode": mode,
		"skill_id": _target_aligned_skill_id(mode),
		"release_id": str(release_geometry.get(
			"release_id", "unbound_target_aligned_release"
		)),
		"origin_ground_gu": release_geometry.get(
			"origin_ground_gu", Vector2.ZERO
		),
		"continuous_axis_ground_gu": release_geometry.get(
			"live_locked_target_direction_ground_gu", Vector2.ZERO
		),
		"locked_target_ground_gu_at_release": release_geometry.get(
			"locked_target_ground_gu_at_release", Vector2.ZERO
		),
		"locked_target_instance_id": int(release_geometry.get(
			"locked_target_instance_id", 0
		)),
		"locked_target_combat_radius_gu_at_release": maxf(
			0.0,
			float(release_geometry.get(
				"locked_target_combat_radius_gu_at_release", 0.0
			))
		),
		"target_axis_eligible": false,
		"ineligible_reason": reason,
		"visual_direction_index": visual_direction_index,
		"visual_direction_contract_id": DIRECTION_SPACE_CONTRACT_ID,
		"range_bonus_gu": 0.0,
		"terrain_blocked": reason == "terrain_blocked",
		"skill_footprint_snapshot": null,
	}


static func _direction_sector_polygon_for_direction_ground_gu(
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	effective_reach_gu: float,
	half_angle_radians := PI / 8.0,
) -> PackedVector2Array:
	## Continuous-direction analogue of direction_sector_polygon(). The default
	## is the ordinary 45-degree sector; callers may provide the exact half-angle
	## for a canonical arc/sub-sector while staying in GU space.
	var safe_reach_gu := maxf(0.0, effective_reach_gu)
	var safe_half_angle_radians := clampf(
		float(half_angle_radians),
		0.0,
		PI * 0.5,
	)
	var center_angle_radians := direction_ground_gu.angle()
	var polygon := PackedVector2Array([origin_ground_gu])
	const ARC_SEGMENTS := 24
	for index: int in range(ARC_SEGMENTS + 1):
		var weight := float(index) / float(ARC_SEGMENTS)
		var angle_radians := lerpf(
			center_angle_radians - safe_half_angle_radians,
			center_angle_radians + safe_half_angle_radians,
			weight
		)
		polygon.append(
			origin_ground_gu + Vector2.from_angle(angle_radians) * safe_reach_gu
		)
	return polygon


static func _vector2_is_finite(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func thrust_footprint_slot_for_axis_plan_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	damage_axis_plan: Dictionary,
	range_bonus_gu := 0.0,
	coordinate_context := {}
) -> int:
	if (
		str(damage_axis_plan.get("contract_id", ""))
		!= THRUST_CONTINUOUS_DAMAGE_AXIS_CONTRACT_ID
	):
		return 0
	var damage_direction_ground_gu: Vector2 = damage_axis_plan.get(
		"damage_direction_ground_gu", Vector2.ZERO
	)
	if damage_direction_ground_gu.length_squared() <= EPSILON * EPSILON:
		return 0
	var target_polygon_ground_gu := target_footprint_polygon_ground_gu(
		target_center_ground_gu,
		target_combat_radius_gu
	)
	var raw_snapshot: Variant = damage_axis_plan.get(
		"skill_footprint_snapshot", {}
	)
	var effective_snapshot: Dictionary = {}
	if (
		raw_snapshot is Dictionary
		and bool(SkillFootprintSnapshotScript.validate_for_consumer(
			raw_snapshot,
			coordinate_context,
			SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
		).get("valid", false))
		and (raw_snapshot.get("origin_ground_gu", Vector2.ZERO) as Vector2)
		.is_equal_approx(origin_ground_gu)
		and is_zero_approx(range_bonus_gu)
	):
		effective_snapshot = raw_snapshot
	else:
		effective_snapshot = (
			SkillFootprintSnapshotScript.create_directed_rectangle(
				"warrior.thrusting",
				str(damage_axis_plan.get("release_id", "unbound_release")),
				origin_ground_gu,
				damage_direction_ground_gu,
				reach_gu(SKILL_THRUST, range_bonus_gu),
				THRUST_WIDTH_GU,
				0.0,
				0.0,
				0.0,
				"",
				coordinate_context
			)
		)
	if not SkillFootprintSnapshotScript.intersects_target_polygon_ground_gu(
		effective_snapshot,
		target_polygon_ground_gu
	):
		return 0
	return thrust_footprint_slot_for_direction_ground_gu(
		origin_ground_gu,
		target_center_ground_gu,
		target_combat_radius_gu,
		damage_direction_ground_gu,
		range_bonus_gu
	)


static func thrust_footprint_slot_for_direction_ground_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	damage_direction_ground_gu: Vector2,
	range_bonus_gu := 0.0
) -> int:
	if damage_direction_ground_gu.length_squared() <= EPSILON * EPSILON:
		return 0
	var normalized_damage_direction_ground_gu := (
		damage_direction_ground_gu.normalized()
	)
	var target_polygon := target_footprint_polygon_ground_gu(
		target_center_ground_gu,
		target_combat_radius_gu
	)
	# Test the primary segment first. A body straddling the 1.5-tile boundary is
	# assigned once to slot 1, so integration cannot apply both damage bands.
	if convex_polygons_intersect_inclusive(
		_thrust_region_polygon_for_direction_ground_gu(
			origin_ground_gu,
			normalized_damage_direction_ground_gu,
			0.0,
			THRUST_PRIMARY_REACH_GU
		),
		target_polygon
	):
		return 1
	if convex_polygons_intersect_inclusive(
		_thrust_region_polygon_for_direction_ground_gu(
			origin_ground_gu,
			normalized_damage_direction_ground_gu,
			THRUST_PRIMARY_REACH_GU,
			reach_gu(SKILL_THRUST, range_bonus_gu)
		),
		target_polygon
	):
		return 2
	return 0


static func convex_polygons_intersect_inclusive(
	first: PackedVector2Array,
	second: PackedVector2Array
) -> bool:
	## Deterministic convex SAT. Boundary contact is an intersection; EPSILON is
	## scaled by the tested axis length so the tolerance remains in tile units.
	if first.size() < 3 or second.size() < 3:
		return false
	for polygon: PackedVector2Array in [first, second]:
		for index in range(polygon.size()):
			var edge := polygon[(index + 1) % polygon.size()] - polygon[index]
			if edge.length_squared() <= EPSILON * EPSILON:
				continue
			var axis := Vector2(-edge.y, edge.x)
			var first_projection := _project_polygon(first, axis)
			var second_projection := _project_polygon(second, axis)
			var projection_epsilon := EPSILON * axis.length()
			if (
				first_projection.y < second_projection.x - projection_epsilon
				or second_projection.y < first_projection.x - projection_epsilon
			):
				return false
	return true


static func _thrust_region_polygon(
	origin: Vector2,
	direction_index: int,
	start_forward: float,
	end_forward: float
) -> PackedVector2Array:
	var forward := Vector2(facing_tile_step(direction_index)).normalized()
	return _thrust_region_polygon_for_direction_ground_gu(
		origin,
		forward,
		start_forward,
		end_forward
	)


static func _thrust_region_polygon_for_direction_ground_gu(
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	start_forward_gu: float,
	end_forward_gu: float
) -> PackedVector2Array:
	if direction_ground_gu.length_squared() <= EPSILON * EPSILON:
		return PackedVector2Array()
	var forward := direction_ground_gu.normalized()
	var side := Vector2(forward.y, -forward.x)
	var half_width := THRUST_WIDTH_GU * 0.5
	return PackedVector2Array([
		origin_ground_gu + forward * start_forward_gu - side * half_width,
		origin_ground_gu + forward * end_forward_gu - side * half_width,
		origin_ground_gu + forward * end_forward_gu + side * half_width,
		origin_ground_gu + forward * start_forward_gu + side * half_width,
	])


static func direction_sector_polygon(
	origin: Vector2,
	direction_index: int,
	reach: float
) -> PackedVector2Array:
	# Convex approximation of the exact Euclidean GU sector. Twenty-four arc
	# samples keep SAT deterministic while guaranteeing every direction has the
	# same formal radius; endpoints include the ±22.5° boundaries.
	var safe_reach_gu := maxf(0.0, reach)
	var center_angle := Vector2(facing_tile_step(direction_index)).angle()
	var polygon := PackedVector2Array([origin])
	const ARC_SEGMENTS := 24
	for index: int in range(ARC_SEGMENTS + 1):
		var weight := float(index) / float(ARC_SEGMENTS)
		var angle := lerpf(
			center_angle - PI / 8.0,
			center_angle + PI / 8.0,
			weight
		)
		polygon.append(origin + Vector2.from_angle(angle) * safe_reach_gu)
	return polygon


static func _clip_polygon_to_half_plane(
	polygon: PackedVector2Array,
	normal: Vector2,
	plane_origin: Vector2
) -> PackedVector2Array:
	var result := PackedVector2Array()
	if polygon.is_empty():
		return result
	for index in range(polygon.size()):
		var current := polygon[index]
		var previous := polygon[posmod(index - 1, polygon.size())]
		var current_distance := normal.dot(current - plane_origin)
		var previous_distance := normal.dot(previous - plane_origin)
		var current_inside := current_distance >= -EPSILON
		var previous_inside := previous_distance >= -EPSILON
		if current_inside != previous_inside:
			var denominator := previous_distance - current_distance
			if absf(denominator) > EPSILON * EPSILON:
				var weight := clampf(previous_distance / denominator, 0.0, 1.0)
				result.append(previous.lerp(current, weight))
		if current_inside:
			result.append(current)
	return result


static func _project_polygon(polygon: PackedVector2Array, axis: Vector2) -> Vector2:
	var minimum := polygon[0].dot(axis)
	var maximum := minimum
	for index in range(1, polygon.size()):
		var projection := polygon[index].dot(axis)
		minimum = minf(minimum, projection)
		maximum = maxf(maximum, projection)
	return Vector2(minimum, maximum)


static func direction_index_for_ground_delta_gu(delta_ground_gu: Vector2) -> int:
	return CombatDirectionSpaceScript.direction_index_for_ground_delta_gu(
		delta_ground_gu
	)


static func half_moon_relative_sector(attack_direction_index: int, target_direction_index: int) -> int:
	return posmod(target_direction_index - attack_direction_index, 8)


static func is_in_half_moon_arc(
	origin: Vector2,
	target: Vector2,
	attack_direction_index: int,
	range_bonus_tiles := 0.0
) -> bool:
	if not is_single_target_in_reach(origin, target, SKILL_HALF_MOON, range_bonus_tiles):
		return false
	var delta := target - origin
	if delta.length_squared() <= EPSILON * EPSILON:
		return false
	var attack_axis := canonical_ground_direction_gu(attack_direction_index)
	var angular_delta := wrapf(
		delta.angle() - attack_axis.angle(),
		-PI,
		PI,
	)
	return absf(angular_delta) <= TARGET_ALIGNED_HALF_MOON_HALF_ANGLE_RADIANS + EPSILON


static func is_in_half_moon_arc_gu(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	attack_direction_index: int,
	range_bonus_gu := 0.0
) -> bool:
	return is_in_half_moon_arc(
		origin_ground_gu,
		target_ground_gu,
		attack_direction_index,
		range_bonus_gu
	)


static func fire_can_begin(has_valid_target_in_reach: bool) -> bool:
	return has_valid_target_in_reach


static func fire_consumes_charge(resolution: String) -> bool:
	# A legal physical hit attempt consumes the charge whether it lands or MISSes.
	# Input rejection and pre-hit cancellation never consume it.
	return resolution in ["hit", "miss"]


static func wild_rush_target_is_adjacent(origin: Vector2, target: Vector2) -> bool:
	var distance := GroundUnitSpaceScript.distance_gu(origin, target)
	return (
		distance > EPSILON
		and GroundUnitSpaceScript.is_within_range_gu(
			origin,
			target,
			WILD_RUSH_TARGET_REACH_GU
		)
	)


static func wild_rush_direction_ground_gu(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2
) -> Vector2:
	return GroundUnitSpaceScript.normalized_ground_direction(
		origin_ground_gu,
		target_ground_gu
	)


static func wild_rush_direction_step(origin: Vector2, target: Vector2) -> Vector2i:
	return facing_tile_step(direction_index_for_ground_delta_gu(target - origin))


static func wild_rush_resolved_distance(
	static_clear_distance_tiles: int,
	dynamic_blocker_in_corridor: bool
) -> int:
	# Another monster anywhere in the complete three-tile corridor cancels the
	# whole displacement. Static geometry instead truncates the coupled movement
	# at the final valid tile before the obstacle.
	if dynamic_blocker_in_corridor:
		return 0
	return clampi(
		static_clear_distance_tiles,
		0,
		WILD_RUSH_MAXIMUM_GRID_STEPS
	)
