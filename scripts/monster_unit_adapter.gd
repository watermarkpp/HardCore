class_name MonsterUnitAdapter
extends RefCounted


const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

## Versioned, read-only boundary from the historical monster projection fields
## into COMBAT-UNIT-V1 ground units. Legacy source dictionaries are never
## rewritten by this adapter.

const CONTRACT_ID := "monster.runtime.units.gu.v1"
const LEGACY_PROJECTION_ID := "monster.runtime_projection.screen_scalar_px.v1"
const LEGACY_SCREEN_SCALAR_PX_PER_GU := 32.0


static func legacy_screen_scalar_px_to_gu(value_px: float) -> float:
	return value_px / LEGACY_SCREEN_SCALAR_PX_PER_GU


static func gu_to_legacy_screen_scalar_px(value_gu: float) -> float:
	return value_gu * LEGACY_SCREEN_SCALAR_PX_PER_GU


static func footprint_radius_px_to_combat_radius_gu(radius_px: float) -> float:
	# The frozen physics footprint is the screen ellipse (r, r/2). Under the
	# inverse 64x32 projection every boundary point has ground length
	# r / (32*sqrt(2)); this is not the legacy scalar r/32 conversion.
	return WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(radius_px)


static func combat_radius_gu_to_footprint_radius_px(radius_gu: float) -> float:
	return WorldSpatialRulesScript.actor_screen_radius_px_from_combat_radius_gu(radius_gu)


static func runtime_projection_gu(
	profile: Dictionary,
	default_move_speed_gu_per_sec: float,
	default_attack_range_gu: float,
	default_aggro_radius_gu: float
) -> Dictionary:
	var projection: Dictionary = profile.get("runtimeProjection", {})
	return {
		"move_speed_gu_per_sec": _formal_or_legacy_scalar_gu(
			projection,
			"move_speed_gu_per_sec",
			"moveSpeed",
			default_move_speed_gu_per_sec,
		),
		"attack_range_gu": _formal_or_legacy_scalar_gu(
			projection,
			"attack_range_gu",
			"attackRange",
			default_attack_range_gu,
		),
		"aggro_radius_gu": _formal_or_legacy_scalar_gu(
			projection,
			"aggro_radius_gu",
			"aggroRadius",
			default_aggro_radius_gu,
		),
	}


static func collision_radius_gu(profile: Dictionary, default_radius_px: float) -> float:
	if profile.has("combat_radius_gu"):
		return maxf(0.0, float(profile.get("combat_radius_gu", 0.0)))
	return footprint_radius_px_to_combat_radius_gu(
		float(profile.get("collisionRadius", default_radius_px))
	)


static func range_gu(
	record: Dictionary,
	formal_key: String,
	legacy_px_key: String,
	default_gu: float
) -> float:
	return _formal_or_legacy_scalar_gu(
		record,
		formal_key,
		legacy_px_key,
		default_gu,
	)


static func relocation_radius_gu(record: Dictionary, default_radius_gu: float) -> float:
	if record.has("radius_gu"):
		return maxf(0.0, float(record.get("radius_gu", default_radius_gu)))
	if record.has("radiusCells"):
		# Historical project data labels this as a cell radius. One coordinate-axis
		# neighbor is 1 GU; the formal relocation radius is Euclidean, so the value
		# is converted once here and never exposed as an untyped/GS runtime field.
		return (
			maxf(0.0, float(record.get("radiusCells", 0.0)))
			* GroundUnitSpaceScript.AXIS_NEIGHBOR_COST_GU
		)
	return maxf(0.0, default_radius_gu)


static func _formal_or_legacy_scalar_gu(
	record: Dictionary,
	formal_key: String,
	legacy_px_key: String,
	default_gu: float
) -> float:
	if record.has(formal_key):
		return maxf(0.0, float(record.get(formal_key, default_gu)))
	if record.has(legacy_px_key):
		return maxf(
			0.0,
			legacy_screen_scalar_px_to_gu(float(record.get(legacy_px_key, 0.0))),
		)
	return maxf(0.0, default_gu)
