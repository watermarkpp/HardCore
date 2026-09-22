extends Node

const GAME_ROOT_PATH := "res://scripts/game_root.gd"

const FORMAL_TARGET_RESOLVERS: Array[String] = [
	"_apply_canonical_spell_damage",
	"_canonical_spell_geometry_targets",
	"_damage_enemies",
	"_physical_primary_targets",
	"_thrust_secondary_targets",
	"_half_moon_secondary_targets",
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := FileAccess.get_file_as_string(GAME_ROOT_PATH)
	assert(not source.is_empty(), "game_root source must be readable")
	assert(
		source.contains("SkillFootprintQueryPlanScript")
		and source.contains("_aoe_query_enemy_candidates_aabb")
		and source.contains("_aoe_query_enemy_candidates_segment"),
		"R3X-2 broadphase plan/query helpers are required",
	)
	assert(
		source.contains("aoe_query_plan_invalid_or_spatial_index_unavailable"),
		"mapped gameplay must fail closed when the spatial plan is unavailable",
	)
	var fallback_body := _function_body(
		source,
		"_aoe_reference_fallback_allowed",
	)
	assert(
		not fallback_body.contains("PlayerState.test_mode")
		and source.contains("set_aoe_reference_fallback_for_test")
		and source.contains("_aoe_reference_fallback_test_enabled"),
		"legacy group fallback must require an explicit audit/test flag",
	)
	for resolver_name: String in FORMAL_TARGET_RESOLVERS:
		var body := _function_body(source, resolver_name)
		assert(not body.is_empty(), "missing formal resolver: %s" % resolver_name)
		assert(
			not body.contains('get_nodes_in_group("enemies")'),
			"formal resolver still performs an enemy group scan: %s" % resolver_name,
		)
		assert(
			not body.contains("validate_for_consumer")
			and not body.contains("target_aligned_release_plan_intersects_target_footprint_ground_gu"),
			"formal resolver must not revalidate every candidate: %s" % resolver_name,
		)
		assert(
			body.contains("_aoe_query_enemy_candidates_aabb")
			or body.contains("_aoe_query_enemy_candidates_segment")
			or resolver_name == "_damage_enemies",
			"formal resolver must use the shared broadphase: %s" % resolver_name,
		)
	assert(
		source.contains("_aoe_insert_by_distance")
		and source.contains("_aoe_insert_by_instance_id")
		and source.contains('"cell_sequence"'),
		"line/cell ordering must remain explicit and deterministic",
	)
	print(
		"MONSTER_CORE_LOOP_STRUCTURAL_GATE_PASS resolvers=%d group_fallback=explicit"
		% FORMAL_TARGET_RESOLVERS.size()
	)
	get_tree().quit(0)


func _function_body(source: String, function_name: String) -> String:
	var start := source.find("func %s" % function_name)
	if start < 0:
		return ""
	var body_start := source.find("\n", start)
	if body_start < 0:
		return ""
	var next_function := source.find("\nfunc ", body_start + 1)
	if next_function < 0:
		next_function = source.length()
	return source.substr(body_start + 1, next_function - body_start - 1)
