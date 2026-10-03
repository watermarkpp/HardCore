extends RefCounted

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const MAX_STATES_PER_TARGET := 16
const SKILL_FIELDS := ["geometry.maximum_range_gu", "geometry.radius_grid_steps",
	"timing.body_cast_ms", "timing.total_action_lock_ms", "timing.cooldown_ms",
	"timing.effect_resolve_ms_from_cast_start", "mp_cost_by_rank.0", "mp_cost_by_rank.1",
	"mp_cost_by_rank.2", "mp_cost_by_rank.3"]

static func build() -> Dictionary:
	var declared := preload("res://scripts/features/compilation/feature_resource_registry.gd").declarations()
	var ids: Array = []
	for id: String in Loader.skill_ids():
		ids.append(Loader.entity_skill_id(id))
	return Graph.capture({"core_api_version":1,
		"stat_keys":["accuracy","agility","attack_min","attack_max","magic_min","magic_max",
			"tao_min","tao_max","max_hp","max_mp"], "skill_ids":ids,
		"capabilities":["stats.contribute","skills.modify","combat.post_hit","effects.periodic","actor.capabilities","items.transact"],
		"handler_ids":["hc.ignite.v1"], "resource_paths":declared.records.keys(),
		"skill_fields":SKILL_FIELDS, "tag_keys":["hc.numeric","hc.periodic","hc.sight"],
		"actor_capability_ids":["hc.can_see_stealth","hc.immune.periodic"],
		"max_commands_per_event":32,"max_states_per_target":MAX_STATES_PER_TARGET,"max_sources":64}).value
