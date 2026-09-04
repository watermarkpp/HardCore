extends Node

const LegacyAdapter := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)
const PlayerCharacterScript := preload("res://scripts/player.gd")
const SkillDataLoader := preload("res://scripts/skills/skill_data_loader.gd")


func _ready() -> void:
	_test_primary_skill_geometry_is_adapted_to_gu_once()
	_test_invalid_geometry_is_rejected()
	_test_runtime_loader_exposes_only_formal_spatial_units()
	_test_player_release_signal_uses_formal_screen_keys_only()
	print("COMBAT_UNIT_LEGACY_SKILL_GEOMETRY_ADAPTER_PASS")
	get_tree().quit(0)


func _test_primary_skill_geometry_is_adapted_to_gu_once() -> void:
	var legacy_source := {
		"skill_id": "test.spatial_adapter",
		"geometry": {
			"maximum_range_tiles": 12.0,
			"length_tiles": 5,
			"width_tiles": 1.0,
			"radius_tiles": 2,
			"shape": "line",
		},
		"mechanics": {"fixed_push_distance_tiles": 3},
	}
	var original := legacy_source.duplicate(true)
	var adapted := LegacyAdapter.adapt_primary_skill_definition_once_to_gu(
		legacy_source
	)
	assert(adapted.valid)
	assert(
		adapted.contract_id
		== LegacyAdapter.LEGACY_SKILL_SPATIAL_ADAPTER_CONTRACT_ID
	)
	assert(adapted.unit_contract_id == "combat.unit.gu_gs_px.v1")
	assert(
		adapted.adapter_semantics
		== "legacy_primary_numeric_semantics_as_gu_once"
	)
	assert(
		adapted.topology_semantics
		== "legacy_declared_grid_topology_as_gs_once"
	)
	var geometry_gu: Dictionary = adapted.definition_gu.geometry
	var mechanics_gu: Dictionary = adapted.definition_gu.mechanics
	assert(is_equal_approx(float(geometry_gu.maximum_range_gu), 12.0))
	assert(is_equal_approx(float(geometry_gu.effect_length_gu), 5.0))
	assert(is_equal_approx(float(geometry_gu.effect_width_gu), 1.0))
	assert(is_equal_approx(float(geometry_gu.radius_grid_steps), 2.0))
	assert(is_equal_approx(float(mechanics_gu.fixed_push_distance_gu), 3.0))
	assert(not geometry_gu.has("maximum_range_tiles"))
	assert(not geometry_gu.has("length_tiles"))
	assert(not geometry_gu.has("width_tiles"))
	assert(not geometry_gu.has("radius_tiles"))
	assert(not mechanics_gu.has("fixed_push_distance_tiles"))
	assert(adapted.consumed_legacy_fields.has("geometry.maximum_range_tiles"))
	assert(adapted.consumed_legacy_fields.has("geometry.length_tiles"))
	assert(adapted.consumed_legacy_fields.has("geometry.width_tiles"))
	assert(adapted.consumed_legacy_fields.has("geometry.radius_tiles"))
	assert(adapted.consumed_legacy_fields.has("mechanics.fixed_push_distance_tiles"))
	assert(legacy_source == original)


func _test_invalid_geometry_is_rejected() -> void:
	var adapted := LegacyAdapter.adapt_primary_skill_definition_once_to_gu({
		"geometry": {"length_tiles": "five"},
	})
	assert(not adapted.valid)
	assert(not adapted.definition_gu.geometry.has("effect_length_gu"))
	assert(adapted.errors.has("geometry.length_tiles:not_numeric"))


func _test_runtime_loader_exposes_only_formal_spatial_units() -> void:
	var hellfire := SkillDataLoader.skill("wizard.hellfire")
	assert(is_equal_approx(float(hellfire.geometry.effect_length_gu), 5.0))
	assert(is_equal_approx(float(hellfire.geometry.effect_width_gu), 1.0))
	var exploding := SkillDataLoader.skill("wizard.exploding_flame")
	assert(exploding.geometry.width_grid_steps == 3.0)
	assert(exploding.geometry.height_grid_steps == 3.0)
	var rush := SkillDataLoader.skill("warrior.wild_rush")
	assert(is_equal_approx(float(rush.mechanics.fixed_push_distance_gu), 3.0))
	for skill_id: String in SkillDataLoader.skill_ids():
		var definition := SkillDataLoader.skill(skill_id)
		for section_name: String in ["geometry", "mechanics"]:
			for field_name: String in definition.get(section_name, {}):
				assert(
					not field_name.ends_with("_tiles"),
					"runtime leaked unitless field %s.%s from %s"
					% [section_name, field_name, skill_id]
				)


func _test_player_release_signal_uses_formal_screen_keys_only() -> void:
	var payload := PlayerCharacterScript.combat_release_signal_payload({
		"origin_screen_px": Vector2(11.0, 22.0),
		"direction_screen_px": Vector2(3.0, 4.0),
		"origin_world": Vector2(999.0, 999.0),
		"direction_world": Vector2(-999.0, -999.0),
	})
	assert(payload.origin_screen_px == Vector2(11.0, 22.0))
	assert(payload.direction_screen_px == Vector2(3.0, 4.0))
	assert(not payload.has("origin_world"))
	assert(not payload.has("direction_world"))
