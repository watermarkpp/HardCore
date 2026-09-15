extends Node

## Combat authority static gate (GPT audit R1-P0 close-out).
## Locks the production combat candidate/delivery authority contract:
##   1. GroundSkillEffect must not scan the enemies group and must not call
##      take_damage directly (candidates: RuntimeCombatSpatialIndex,
##      delivery: injected runtime_tick_adapter only).
##   2. FireWallFieldController must not scan the enemies group and must not
##      call take_damage directly (delivery: runtime_tick_callback only).
##   3. The fire wall runtime must keep the explicit fail-closed cap policy
##      (evict_oldest only via configured data, never implicit).
## If a future change needs to touch these invariants, it must do so through
## a reviewed contract change, not by silently reintroducing the old paths.

const _GROUND_EFFECT_SOURCE := "res://scripts/ground_effect.gd"
const _CONTROLLER_SOURCE := "res://scripts/fire_wall_field_controller.gd"
const _GAME_ROOT_SOURCE := "res://scripts/game_root.gd"
const _QUERY_SERVICE_SOURCE := (
	"res://scripts/layers/runtime/combat_target_query_service.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ground_effect_source := _read(_GROUND_EFFECT_SOURCE)
	assert(
		not ground_effect_source.contains('get_nodes_in_group("enemies")'),
		"GroundSkillEffect must not scan the enemies group (R1-P0 item 3)"
	)
	assert(
		not ground_effect_source.contains("take_damage("),
		"GroundSkillEffect must not deliver damage via take_damage "
		+ "(R1-P0 item 5)"
	)
	assert(
		ground_effect_source.contains(
			"_combat_spatial_index.query_aabb_candidates("
		),
		"GroundSkillEffect self-managed tick must use the shared spatial index"
	)
	var controller_source := _read(_CONTROLLER_SOURCE)
	assert(
		not controller_source.contains('get_nodes_in_group("enemies")'),
		"FireWallFieldController must not scan the enemies group"
	)
	assert(
		not controller_source.contains("take_damage("),
		"FireWallFieldController must not deliver damage via take_damage"
	)
	var game_root_source := _read(_GAME_ROOT_SOURCE)
	assert(
		game_root_source.contains("FIRE_WALL_CAP_POLICY_REJECT_NEW"),
		"fire wall cap policy must stay explicit and fail-closed"
	)
	assert(
		game_root_source.contains("_fire_wall_registry_key("),
		"fire wall registry key must stay source-aware"
	)
	# R1-B: every special-geometry broadphase enters the shared service with
	# an envelope-only aabb descriptor; the per-skill canonical gates stay the
	# exact authority. Direct index node queries survive only in the two
	# sanctioned non-delivery mechanic/probe sites.
	for func_name: String in [
		"_target_spatial_query_aabb_into",
		"_target_spatial_query_segment_into",
		"_aoe_query_enemy_candidates_aabb",
		"_aoe_query_enemy_candidates_segment",
	]:
		var body := _function_source(game_root_source, func_name)
		assert(
			body.contains("_service_candidates_envelope_into("),
			"%s must route through CombatTargetQueryService" % func_name
		)
		assert(
			not body.contains("query_enemy_nodes_aabb_into")
			and not body.contains("query_enemy_nodes_segment_into"),
			"%s must not query the spatial index directly" % func_name
		)
	assert(
		game_root_source.contains("func _target_query_service("),
		"game_root must keep the shared target-query service accessor"
	)
	assert(
		_function_source(
			game_root_source, "_enforce_bich_safe_zone"
		).contains("query_enemy_nodes_aabb_into"),
		"safe-zone enforcement stays a sanctioned direct index consumer"
	)
	assert(
		_function_source(
			game_root_source, "_hc_m30_landing_clear"
		).contains("query_enemy_nodes_segment_unsorted_into"),
		"the M30 landing probe stays a sanctioned direct index consumer"
	)
	# R1-B: the GameRoot ability-id combat enumerations are frozen. Adding an
	# ability-id combat branch requires a reviewed contract change, never a
	# silent enum growth.
	var frozen_enums := {
		"CANONICAL_WIZARD_GEOMETRY_SKILLS": [
			"wizard.hellfire", "wizard.hell_lightning", "wizard.laser",
		],
		"CONTINUOUS_WIZARD_LINE_SKILLS": [
			"wizard.hellfire", "wizard.laser",
		],
		"GROUND_EXACT_SKILL_IDS": [
			"wizard.repulsion_ring", "wizard.exploding_flame",
			"wizard.fire_wall", "wizard.hell_lightning",
			"wizard.ice_storm", "taoist.mass_invisibility",
			"taoist.magic_defense", "taoist.defense",
			"taoist.entrapment", "taoist.mass_healing",
		],
		"TARGET_FOOTPRINT_SKILL_IDS": [
			"wizard.lightning", "wizard.temptation_light",
			"wizard.holy_word", "taoist.healing", "taoist.poison",
			"taoist.revelation",
		],
		"ATTACHED_STATE_SKILL_IDS": [
			"wizard.magic_shield", "taoist.invisibility",
		],
	}
	for enum_name: String in frozen_enums:
		var expected: Array = frozen_enums[enum_name]
		var actual := _const_skill_ids(game_root_source, enum_name)
		assert(
			actual.size() == expected.size(),
			"%s changed size: ability-id combat branches are frozen" % (
				enum_name
			)
		)
		for skill_id: String in expected:
			assert(
				actual.has(skill_id),
				"%s lost %s; ability-id combat branches are frozen" % [
					enum_name, skill_id
				]
			)
	var query_service_source := _read(_QUERY_SERVICE_SOURCE)
	assert(
		not query_service_source.contains("get_nodes_in_group("),
		"CombatTargetQueryService must never scan scene-tree groups"
	)
	assert(
		not query_service_source.contains("take_damage("),
		"CombatTargetQueryService must never deliver damage"
	)
	print("COMBAT_AUTHORITY_STATIC_GATE_PASS")
	get_tree().quit(0)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "cannot read source for static gate: %s" % path)
	return file.get_as_text()


func _function_source(source: String, func_name: String) -> String:
	var start := source.find("func %s(" % func_name)
	assert(start >= 0, "static gate cannot find func %s" % func_name)
	var next := source.find("\nfunc ", start + 1)
	var end := next if next >= 0 else source.length()
	return source.substr(start, end - start)


func _const_skill_ids(source: String, const_name: String) -> Array[String]:
	var start := source.find("const %s" % const_name)
	assert(start >= 0, "static gate cannot find const %s" % const_name)
	var open := -1
	var close_char := ""
	for candidate: String in ["[", "{"]:
		var at := source.find(candidate, start)
		if at >= 0 and (open < 0 or at < open):
			open = at
			close_char = "]" if candidate == "[" else "}"
	assert(open >= 0 and close_char != "", "malformed const %s" % const_name)
	var close := source.find(close_char, open)
	assert(close > open, "malformed const %s" % const_name)
	var regex := RegEx.new()
	regex.compile("\"([a-z_.]+)\"")
	var ids: Array[String] = []
	for match: RegExMatch in regex.search_all(
		source.substr(open, close - open)
	):
		ids.append(match.get_string(1))
	return ids
