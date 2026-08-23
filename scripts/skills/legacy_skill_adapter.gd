class_name LegacySkillAdapter
extends RefCounted

const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)

## Compatibility-only view for existing UI/GameData consumers. Runtime skill
## membership, progression, MP and mechanics remain owned by SkillDataLoader.
## The queried rank goes through the unified resolver so this view never
## truncates an effective rank; legacy_records() only contains base ranks
## 0..3, so higher ranks simply return no legacy record (source-view
## limitation, not a runtime effective-rank clamp).

static func records() -> Array:
	return SkillDataLoaderScript.legacy_records()


static func get_skill(skill_name_or_id: String, rank := 0) -> Dictionary:
	var stable_id := SkillDataLoaderScript.stable_skill_id(skill_name_or_id)
	var safe_rank := SkillRankResolverScript.safe_effective_rank(rank)
	for record: Variant in records():
		if (
			record is Dictionary
			and str(record.get("skill_id", "")) == stable_id
			and int(record.get("skillLevel", -1)) == safe_rank
		):
			return record.duplicate(true)
	return {}


static func profession_skills(profession_name_or_id: String) -> Array:
	var profession_id: String = {
		"战士": "warrior", "warrior": "warrior",
		"法师": "wizard", "wizard": "wizard",
		"道士": "taoist", "taoist": "taoist",
	}.get(profession_name_or_id, "")
	var result: Array = []
	for skill_id: String in SkillDataLoaderScript.skill_ids():
		var definition := SkillDataLoaderScript.skill(skill_id)
		if str(definition.get("class", "")) == profession_id:
			result.append(get_skill(skill_id, 0))
	return result
