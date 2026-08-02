class_name CombatUnitLegacyAdapter
extends RefCounted

## Versioned bridge from the primary classic server/client timing rules into
## combat.unit.gu_gs_px.v1.  No untyped legacy value may leave this class.

const CONTRACT_ID := "combat.unit.legacy_primary_source_adapter.v1"
const COMBAT_UNIT_CONTRACT_ID := "combat.unit.gu_gs_px.v1"
const LEGACY_SKILL_SPATIAL_ADAPTER_CONTRACT_ID := (
	"combat.unit.legacy_primary_skill_spatial_to_gu_once.v1"
)
const LEGACY_SKILL_GEOMETRY_SOURCE_EVIDENCE := {
	"lane": "skills",
	"source_tier": "primary",
	"distribution": "project_formal_contract",
	"path": "assets/data/vanilla_176/skills_source_of_truth_v1.json",
	"sha256": "883359E2CF191A196F749653067F2030130FC11FD59A033A89EE557CAB7607E2",
	"source_contract_id": "skills.mir2_176.vanilla_33.v1.0.1",
	"adapter_semantics": "legacy_primary_numeric_semantics_as_gu_once",
	"topology_semantics": "legacy_declared_grid_topology_as_gs_once",
	"fallback_used": false,
}
const LEGACY_SKILL_SPATIAL_FIELD_MAP := {
	"geometry": {
		"maximum_range_tiles": "maximum_range_gu",
		"range_tiles": "reach_gu",
		"length_tiles": "effect_length_gu",
		"maximum_reach_tiles": "maximum_reach_gu",
		"endpoint_tolerance_tiles": "endpoint_tolerance_gu",
		"primary_segment_reach_tiles": "primary_segment_reach_gu",
		"range_bonus_cap_tiles": "range_bonus_cap_gu",
		"base_reach_tiles": "base_reach_gu",
		"start_distance_tiles": "start_distance_gu",
		"fixed_push_distance_tiles": "fixed_push_distance_gu",
		"target_reach_tiles": "target_reach_gu",
		"runtime_melee_reach_tiles": "runtime_melee_reach_gu",
		"height_tiles": "height_grid_steps",
		"radius_tiles": "radius_grid_steps",
		"search_radius_tiles": "search_radius_grid_steps",
	},
	"mechanics": {
		"fixed_push_distance_tiles": "fixed_push_distance_gu",
	},
}

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


static func adapt_primary_skill_definition_once_to_gu(
	legacy_primary_definition: Dictionary
) -> Dictionary:
	## This is the only boundary allowed to read the historical primary skill
	## spatial field names. Approved gameplay distances become GU while declared
	## cell topology becomes GS; both are renamed once without numeric scaling.
	var definition_gu := legacy_primary_definition.duplicate(true)
	var result := {
		"contract_id": LEGACY_SKILL_SPATIAL_ADAPTER_CONTRACT_ID,
		"unit_contract_id": COMBAT_UNIT_CONTRACT_ID,
		"source_contract_id": str(
			LEGACY_SKILL_GEOMETRY_SOURCE_EVIDENCE.source_contract_id
		),
		"adapter_semantics": str(
			LEGACY_SKILL_GEOMETRY_SOURCE_EVIDENCE.adapter_semantics
		),
		"topology_semantics": str(
			LEGACY_SKILL_GEOMETRY_SOURCE_EVIDENCE.topology_semantics
		),
		"valid": true,
		"consumed_legacy_fields": [],
		"errors": [],
		"definition_gu": definition_gu,
	}
	for section_name: String in LEGACY_SKILL_SPATIAL_FIELD_MAP:
		var section: Dictionary = definition_gu.get(section_name, {})
		if section.is_empty():
			continue
		var field_map: Dictionary = LEGACY_SKILL_SPATIAL_FIELD_MAP[section_name]
		for legacy_field: String in field_map:
			if not section.has(legacy_field):
				continue
			var qualified_field := "%s.%s" % [section_name, legacy_field]
			result.consumed_legacy_fields.append(qualified_field)
			var raw_value: Variant = section[legacy_field]
			section.erase(legacy_field)
			if not (raw_value is int or raw_value is float):
				result.valid = false
				result.errors.append("%s:not_numeric" % qualified_field)
				continue
			section[str(field_map[legacy_field])] = float(raw_value)
		if section_name == "geometry" and section.has("width_tiles"):
			var width_value: Variant = section["width_tiles"]
			section.erase("width_tiles")
			result.consumed_legacy_fields.append("geometry.width_tiles")
			if not (width_value is int or width_value is float):
				result.valid = false
				result.errors.append("geometry.width_tiles:not_numeric")
			else:
				var formal_width_field := (
					"effect_width_gu"
					if str(section.get("shape", "")) == "line"
					else "width_grid_steps"
				)
				section[formal_width_field] = float(width_value)
		if section_name == "geometry" and section.has("footprint_tiles"):
			var footprint_description: Variant = section["footprint_tiles"]
			section.erase("footprint_tiles")
			result.consumed_legacy_fields.append("geometry.footprint_tiles")
			section["footprint_grid_steps_description"] = footprint_description
		definition_gu[section_name] = section
	return result
