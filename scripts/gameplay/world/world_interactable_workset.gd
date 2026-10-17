extends RefCounted
const ProfessionRules := preload("res://scripts/profession_rules.gd")

static func workset_skill_order(
	priority_candidates: Array,
	max_skills := 7
) -> Array[String]:
	var ordered: Array[String] = []
	var seen: Dictionary = {}
	if max_skills <= 0:
		return ordered
	for raw_skill: Variant in priority_candidates:
		var skill_id := ProfessionRules.skill_id(str(raw_skill))
		if skill_id.is_empty() or seen.has(skill_id):
			continue
		seen[skill_id] = true
		ordered.append(skill_id)
		if ordered.size() >= max_skills:
			break
	return ordered
