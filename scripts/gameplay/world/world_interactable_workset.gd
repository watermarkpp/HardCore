extends RefCounted
const ProfessionCore := preload("res://scripts/gameplay/profile/rules/professions_core.gd")

static func workset_skill_order(
	priority_candidates: Array,
	profession: RefCounted,
	max_skills := 7
) -> Array[String]:
	assert(profession != null and profession.get_script() == ProfessionCore and profession.get("_owner_thread_id") == OS.get_thread_caller_id())
	var ordered: Array[String] = []
	var seen: Dictionary = {}
	if max_skills <= 0:
		return ordered
	for raw_skill: Variant in priority_candidates:
		var skill_id: String = profession.skill_id(str(raw_skill))
		if skill_id.is_empty() or seen.has(skill_id):
			continue
		seen[skill_id] = true
		ordered.append(skill_id)
		if ordered.size() >= max_skills:
			break
	return ordered
