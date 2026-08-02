class_name CombatUnitLegacyAdapter
extends RefCounted

## Versioned bridge from the primary classic server/client timing rules into
## combat.unit.gu_gs_px.v1.  No untyped legacy value may leave this class.

const CONTRACT_ID := "combat.unit.legacy_primary_source_adapter.v1"

const PLAYER_MOVE_SOURCE_EVIDENCE := {
	"lane": "server_rules+client_rules",
	"source_tier": "primary",
	"distribution": "original_gameofmir",
	"server_path": "M2Server/GameConfig.pas",
	"server_sha256": "237E4916F88F72F7076A9128A4AB53B02AC9E2F9337EDF06B30A7075358DA190",
	"client_path": "MirClient/ClMain.pas",
	"client_sha256": "C0928322DE261CC600384F0B278F14EA8B44034C7E900CC5AA3AEA0C05F7775B",
	"records": ["RunIntervalTime=600", "CM_RUN advances two grid coordinates"],
	"adapter_rule": "2 GU / 0.600 seconds",
}
const PROJECTILE_SOURCE_EVIDENCE := {
	"lane": "client_rules",
	"source_tier": "primary",
	"distribution": "original_gameofmir",
	"client_path": "MirClient/magiceff.pas",
	"client_sha256": "66606A4E495790F83E8A6FCE3809EC54963882FF0B55CA390D1442B4E4699F3C",
	"record": "tracked projectile 500 screen-axis coefficient / 700 milliseconds",
	"primary_gu_scalar_query": "missing",
	"adapter_rule": "canonical S projection 32 PX/GU, applied once",
}
const PROJECTILE_RADIUS_SOURCE_EVIDENCE := {
	"lane": "client_rules+combat_units",
	"source_tier": "primary_then_approved_legacy_adapter",
	"primary_ground_collision_radius_query": "missing",
	"legacy_runtime_radius_px": 24.0,
	"adapter_rule": "area-equivalent sqrt(64*32) PX/GU",
}
const SUMMON_SPATIAL_SOURCE_EVIDENCE := {
	"lane": "server_rules+combat_units",
	"source_tier": "primary_then_approved_legacy_adapter",
	"server_distribution": "original_gameofmir",
	"server_sources": [
		{
			"path": "M2Server/LocalDB.pas",
			"sha256": "09210446AB8E2D55D98968015846A34F6786EAF42826B54FB30C4C8426F100AE",
		},
		{
			"path": "M2Server/Magic.pas",
			"sha256": "BC8981DD4283B34CE35E21FAA2A69520231B475C4300303181E0C66CC2C453BF",
		},
	],
	"server_records": [
		"M2Server/LocalDB.pas monster WALK_SPD is an interval, not PX/s",
		"M2Server/Magic.pas created slaves inherit monster movement rules",
	],
	"primary_continuous_gu_per_sec_query": "missing",
	"primary_summon_aggro_attack_leash_gu_query": "missing",
	"legacy_baseline": "TaoistCombatMath summon profile unsuffixed screen scalars",
	"adapter_rule": "area-equivalent sqrt(64*32) PX/GU, applied once",
}

# server_rules primary evidence:
# dev_art_sources/reference/original_gameofmir/M2Server/GameConfig.pas
# SHA-256 237E4916F88F72F7076A9128A4AB53B02AC9E2F9337EDF06B30A7075358DA190
# lines 1040-1041: RunIntervalTime=600ms, WalkIntervalTime=600ms.
# MirClient/ClMain.pas shows CM_RUN advances two grid coordinates per accepted
# run action.  HardCore's continuous movement is the run-equivalent lane, so
# the formal scalar speed is 2 GU / 0.6 s. Direction is normalized in GU by
# GroundUnitSpace; classic diagonal GS length is deliberately not preserved.
const PRIMARY_PLAYER_RUN_STEP_DISTANCE_GU := 2.0
const PRIMARY_PLAYER_RUN_INTERVAL_SECONDS := 0.600
const PLAYER_MOVE_SPEED_GU_PER_SEC := (
	PRIMARY_PLAYER_RUN_STEP_DISTANCE_GU
	/ PRIMARY_PLAYER_RUN_INTERVAL_SECONDS
)

# client_rules primary evidence:
# dev_art_sources/reference/original_gameofmir/MirClient/magiceff.pas
# SHA-256 66606A4E495790F83E8A6FCE3809EC54963882FF0B55CA390D1442B4E4699F3C
# The tracked projectile constructs a 500 screen-axis coefficient and advances
# it with /700 milliseconds. The source has no GU scalar, so this explicit
# adapter uses the canonical S projection (32 PX per GU) exactly once. Runtime
# projectile code receives only the resulting GU/s value.
const PRIMARY_TRACKED_PROJECTILE_AXIS_PX_PER_SEC := 500.0 / 0.700
const CANONICAL_SOUTH_AXIS_PX_PER_GU := 32.0
const PROJECTILE_SPEED_GU_PER_SEC := (
	PRIMARY_TRACKED_PROJECTILE_AXIS_PX_PER_SEC
	/ CANONICAL_SOUTH_AXIS_PX_PER_GU
)

# The old production setup supplied a 24 PX circular projectile contact radius.
# Primary server/client sources do not define a ground-plane collision radius,
# so preserve that value through the formal 64x32 area-equivalent footprint
# adapter instead of interpreting 24 as GU.
const LEGACY_PROJECTILE_HIT_RADIUS_PX := 24.0
const ISO_AREA_EQUIVALENT_PX_PER_GU := sqrt(64.0 * 32.0)
const PROJECTILE_RADIUS_GU := (
	LEGACY_PROJECTILE_HIT_RADIUS_PX
	/ ISO_AREA_EQUIVALENT_PX_PER_GU
)


static func legacy_screen_distance_px_to_gu(
	distance_px: float
) -> float:
	## Compatibility-only S-axis conversion for old call sites. New callers must
	## provide max_travel_distance_gu directly.
	return maxf(0.0, distance_px) / CANONICAL_SOUTH_AXIS_PX_PER_GU


static func legacy_isometric_screen_scalar_px_to_gu(value_px: float) -> float:
	## For old directionless radii/speeds only. The area-equivalent scale avoids
	## choosing one isometric screen axis as the hidden gameplay direction.
	return maxf(0.0, value_px) / ISO_AREA_EQUIVALENT_PX_PER_GU
