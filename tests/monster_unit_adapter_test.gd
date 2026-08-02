extends Node

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const MonsterUnitAdapterScript := preload("res://scripts/monster_unit_adapter.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const CONTRACT_PATH := "res://assets/data/monster_runtime_unit_contract_v1.json"


func _ready() -> void:
	_verify_contract_and_legacy_scalar_boundary()
	_verify_frozen_footprint_round_trip()
	_verify_projection_adapter_is_read_only()
	print("MONSTER_UNIT_ADAPTER_PASS contract=%s" % MonsterUnitAdapterScript.CONTRACT_ID)
	get_tree().quit(0)


func _verify_contract_and_legacy_scalar_boundary() -> void:
	var file := FileAccess.open(CONTRACT_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(parsed is Dictionary, "monster unit contract is not valid JSON")
	assert(parsed.get("contractId", "") == MonsterUnitAdapterScript.CONTRACT_ID)
	var authority: Dictionary = parsed.get("authority", {})
	assert(authority.get("sourcePolicyId", "") == "MIR-SOURCE-PRIORITY-1")
	assert(authority.get("sourceLane", "") == "combat_units")
	assert(authority.get("sourceTier", "") == "primary")
	assert(authority.get("distribution", "") == "project.hardcore.combat_unit_contract.v1")
	assert(str(authority.get("approvedGroundUnitContractSha256", "")).length() == 64)
	for legacy_source: Dictionary in authority.get("legacyDataSources", []):
		assert(legacy_source.get("role", "") == "read_only_legacy_values")
		assert(str(legacy_source.get("sha256", "")).length() == 64)
	assert(is_equal_approx(MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(384.0), 12.0))
	assert(is_equal_approx(MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(512.0), 16.0))
	assert(is_equal_approx(MonsterUnitAdapterScript.gu_to_legacy_screen_scalar_px(4.84375), 155.0))
	assert(parsed.get("schemaVersion", 0) == 2)
	var coordinate_references: Array = parsed.get("coordinateReferences", [])
	assert(coordinate_references.any(func(entry: Dictionary) -> bool:
		return entry.get("contractId", "") == "monster.safe_zone.relative_ground_reference.v1"
	))
	var render_boundaries: Array = parsed.get("renderBoundaries", [])
	assert(render_boundaries.any(func(entry: Dictionary) -> bool:
		return entry.get("contractId", "") == "monster.visual.resource_residency.screen_px.v1"
	))
	assert(render_boundaries.any(func(entry: Dictionary) -> bool:
		return entry.get("contractId", "") == "monster.boss.warning.ground_projection.v1"
	))
	var aliases: Array = parsed.get("compatibilityAliases", [])
	assert(aliases.size() == 1 and aliases[0].get("field", "") == "collision_radius")
	assert(int(aliases[0].get("monsterRuntimeReads", -1)) == 0)


func _verify_frozen_footprint_round_trip() -> void:
	for radius_px: float in [10.0, 12.0, 15.0, 16.0, 18.0, 20.0, 24.0, 28.0]:
		var combat_radius_gu := (
			MonsterUnitAdapterScript.footprint_radius_px_to_combat_radius_gu(radius_px)
		)
		assert(is_equal_approx(
			combat_radius_gu,
			radius_px / (32.0 * sqrt(2.0)),
		))
		assert(is_equal_approx(
			MonsterUnitAdapterScript.combat_radius_gu_to_footprint_radius_px(combat_radius_gu),
			radius_px,
		))
		assert(is_equal_approx(
			WorldSpatialRulesScript.actor_screen_radius_px_from_combat_radius_gu(combat_radius_gu),
			radius_px,
		))
		for frozen_vertex_px: Vector2 in WorldSpatialRulesScript.actor_footprint_polygon(radius_px, 32):
			var vertex_ground_gu := (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(frozen_vertex_px)
			)
			assert(
				absf(vertex_ground_gu.length() - combat_radius_gu) <= 0.00001,
				"frozen ellipse vertex is not one GU circle: r_px=%.3f vertex=%s" % [
					radius_px, frozen_vertex_px,
				],
			)
			assert(
				GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(vertex_ground_gu).is_equal_approx(
					frozen_vertex_px
				),
				"frozen footprint pixel vertex changed after GU round trip",
			)


func _verify_projection_adapter_is_read_only() -> void:
	var legacy := {
		"runtimeProjection": {
			"moveSpeed": 48.0,
			"attackRange": 155.0,
			"aggroRadius": 384.0,
		},
	}
	var before := JSON.stringify(legacy)
	var formal := MonsterUnitAdapterScript.runtime_projection_gu(legacy, 0.0, 0.0, 0.0)
	assert(is_equal_approx(float(formal.move_speed_gu_per_sec), 1.5))
	assert(is_equal_approx(float(formal.attack_range_gu), 4.84375))
	assert(is_equal_approx(float(formal.aggro_radius_gu), 12.0))
	assert(
		formal.keys().all(func(key: Variant) -> bool: return str(key).ends_with("_gu") or str(key).ends_with("_gu_per_sec")),
		"formal runtime projection leaked an untyped field",
	)
	assert(JSON.stringify(legacy) == before, "legacy source profile was rewritten")

	var relocation_legacy := {"radiusCells": 4}
	var relocation_before := JSON.stringify(relocation_legacy)
	assert(is_equal_approx(
		MonsterUnitAdapterScript.relocation_radius_gu(relocation_legacy, 0.0),
		4.0,
	))
	assert(JSON.stringify(relocation_legacy) == relocation_before, "legacy relocation profile was rewritten")
	assert(is_equal_approx(
		MonsterUnitAdapterScript.relocation_radius_gu({"radius_gu": 5.5}, 0.0),
		5.5,
	))
