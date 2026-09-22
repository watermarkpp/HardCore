extends Node

const FORMAL_RUNTIME_FILES := [
	"res://scripts/game_root.gd",
	"res://scripts/player.gd",
	"res://scripts/enemy.gd",
	"res://scripts/skill_projectile.gd",
	"res://scripts/ground_effect.gd",
	"res://scripts/summon_actor.gd",
	"res://scripts/caster_skill_runtime.gd",
	"res://scripts/caster_skill_visual_effect.gd",
	"res://scripts/profession_rules.gd",
	"res://scripts/skills/combat_direction_space.gd",
	"res://scripts/skills/caster_spell_geometry.gd",
	"res://scripts/skills/warrior_melee_geometry.gd",
	"res://scripts/skills/spell_target_lock_policy.gd",
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd",
	"res://scripts/world_spatial_rules.gd",
	"res://scripts/loot_pickup.gd",
]

const GLOBALLY_FORBIDDEN_TOKENS := [
	".collision_radius\n",
	"var collision_radius:",
	"@export var move_speed :=",
	"maximum_range_tiles",
	"length_tiles",
	"width_tiles",
	"WorldSpatialRulesScript.environment_blocks_actor(",
	"WorldSpatialRules.environment_blocks_actor(",
	"WorldSpatialRulesScript.actor_footprint_polygon(",
	"WorldSpatialRules.actor_footprint_polygon(",
	"MapEditorRuntimeBridgeScript.tile_to_world(",
	"MapEditorRuntimeBridgeScript.world_to_tile(",
	"MapEditorRuntimeBridgeScript.cell_to_world(",
]

const GLOBALLY_FORBIDDEN_AMBIGUOUS_UNIT_STEMS := [
	"origin_world",
	"direction_world",
	"geometry_world",
]

const FILE_SPECIFIC_FORBIDDEN := {
	"res://scripts/game_root.gd": [
		"\"area_radius\":",
		"_canonical_world_to_fractional_tile",
		"_canonical_fractional_tile_to_world",
	],
	"res://scripts/caster_skill_runtime.gd": [
		"\"range\":",
		"\"area_radius\":",
		"area_radius_cells",
		"plan.get(\"range\"",
		"plan.get(\"cell_size\"",
	],
	# ProfessionRules is the versioned one-way adapter for the historical
	# profession-growth payload. Its dynamic contract tests prove that these
	# legacy source keys never escape into the formal runtime profile, so the
	# static audit deliberately checks the consumers instead of banning the
	# adapter's input vocabulary.
	"res://scripts/skills/combat_direction_space.gd": [
		"world_delta_to_fractional_tile_delta",
		"fractional_tile_delta_to_world_delta",
		"projected_world_direction",
		"\"source_world_delta\"",
		"\"fractional_tile_delta\"",
	],
	"res://scripts/skills/caster_spell_geometry.gd": [
		"continuous_line_world_points",
	],
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd": [
		"\"runtime_home_position\":",
		"\"map_center_world\":",
		"\"position\":",
		"static func home_position()",
		"static func portal_position(",
	],
}


func _ready() -> void:
	for stem: String in GLOBALLY_FORBIDDEN_AMBIGUOUS_UNIT_STEMS:
		assert(_contains_ambiguous_unit_stem(stem, stem))
		assert(not _contains_ambiguous_unit_stem("%s_px" % stem, stem))
		assert(not _contains_ambiguous_unit_stem("target_actor_%s_px" % stem, stem))
		assert(_contains_ambiguous_unit_stem("%s_px_extra" % stem, stem))
	for path: String in FORMAL_RUNTIME_FILES:
		assert(FileAccess.file_exists(path), "missing formal runtime source: %s" % path)
		var source := FileAccess.get_file_as_string(path)
		assert(not source.is_empty(), "empty formal runtime source: %s" % path)
		for token: String in GLOBALLY_FORBIDDEN_TOKENS:
			assert(
				not source.contains(token),
				"formal runtime still contains forbidden unit token %s in %s" % [token, path]
			)
		for stem: String in GLOBALLY_FORBIDDEN_AMBIGUOUS_UNIT_STEMS:
			assert(
				not _contains_ambiguous_unit_stem(source, stem),
				"formal runtime still contains ambiguous unit stem %s in %s"
				% [stem, path]
			)
		for token: String in FILE_SPECIFIC_FORBIDDEN.get(path, []):
			assert(
				not source.contains(token),
				"formal runtime still contains ambiguous field/API %s in %s" % [token, path]
			)
	print("COMBAT_UNIT_RUNTIME_STATIC_AUDIT_PASS: formal runtime exposes GU/GS/PX units and legacy names remain adapter-only")
	get_tree().quit(0)


func _contains_ambiguous_unit_stem(source: String, stem: String) -> bool:
	var matcher := RegEx.new()
	var compile_error := matcher.compile(
		"%s(?!_px(?:[^A-Za-z0-9_]|$))" % stem
	)
	assert(compile_error == OK, "invalid static unit-gate regex for %s" % stem)
	return matcher.search(source) != null
