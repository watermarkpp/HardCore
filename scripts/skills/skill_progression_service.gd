class_name SkillProgressionService
extends RefCounted

const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)

## HardCore skill-growth contract v2: base ranks are learned/upgraded with
## skill books (first book = 1, third book = 3), and effective cast rank = base_rank +
## equipment bonus. Proficiency is fully removed: it is never produced,
## upgraded, persisted or converted. v1 snapshots still load (rank kept as
## base_rank, current_proficiency discarded).
const STATE_CONTRACT_ID := "skills.progression.hardcore.v2"
const LEGACY_STATE_CONTRACT_ID := "skills.progression.cn_mir2_176.v1"

var _progress: Dictionary = {}


func learn(skill_name_or_id: String, player_level: int) -> Dictionary:
	var skill_id := SkillDataLoaderScript.stable_skill_id(skill_name_or_id)
	var rank_zero := SkillDataLoaderScript.rank_record(skill_id, 0)
	if rank_zero.is_empty():
		return _learn_result(false, "unknown_skill", skill_id, 0, 0, "")
	var current_rank := int(_progress.get(skill_id, {}).get("base_rank", -1))
	if current_rank < 0:
		var required_level := int(rank_zero.get("player_level_required", 1))
		if player_level < required_level:
			return _learn_result(
				false,
				"player_level",
				skill_id,
				0,
				required_level,
				"level_requirement"
			)
		_set_base_rank(skill_id, 1)
		return _learn_result(true, "", skill_id, 1, required_level, "learned")
	if current_rank >= 3:
		return _learn_result(
			false,
			"max_rank",
			skill_id,
			3,
			int(rank_zero.get("player_level_required", 1)),
			"max"
		)
	var next_rank := current_rank + 1
	var next_rank_data := SkillDataLoaderScript.rank_record(skill_id, next_rank)
	if next_rank_data.is_empty():
		return _learn_result(
			false,
			"rank_data_missing",
			skill_id,
			current_rank,
			0,
			""
		)
	var required_level := int(next_rank_data.get("player_level_required", 1))
	if player_level < required_level:
		return _learn_result(
			false,
			"player_level",
			skill_id,
			current_rank,
			required_level,
			"level_requirement"
		)
	_set_base_rank(skill_id, next_rank)
	return _learn_result(
		true,
		"",
		skill_id,
		next_rank,
		required_level,
		"upgraded"
	)


func effective_rank(skill_name_or_id: String, equipment_bonus := 0) -> int:
	var skill_id := SkillDataLoaderScript.stable_skill_id(skill_name_or_id)
	if not _progress.has(skill_id):
		## Equipment can never enable an unlearned skill.
		return 0
	var base_rank := int(_progress[skill_id].get("base_rank", 0))
	var bonus := maxi(0, int(equipment_bonus))
	return SkillRankResolverScript.safe_effective_rank(base_rank + bonus)


func is_learned(skill_name_or_id: String) -> bool:
	return _progress.has(SkillDataLoaderScript.stable_skill_id(skill_name_or_id))


func state(skill_name_or_id: String) -> Dictionary:
	var skill_id := SkillDataLoaderScript.stable_skill_id(skill_name_or_id)
	return _progress.get(skill_id, {}).duplicate(true)


## Compatibility no-op for pre-v2 callers: proficiency is disabled and can
## never grow, upgrade or persist. Returns a clear rejection so callers never
## consume resources for a proficiency gain.
func apply_proficiency_event(
	skill_name_or_id: String,
	_event_id: String,
	_player_level: int,
	_rng: RefCounted
) -> Dictionary:
	var skill_id := SkillDataLoaderScript.stable_skill_id(skill_name_or_id)
	if not _progress.has(skill_id):
		return _no_op_result(skill_id, "skill_not_learned")
	return _no_op_result(skill_id, "proficiency_disabled")


func load_snapshot(value: Variant) -> Dictionary:
	_progress.clear()
	var source: Dictionary = {}
	var migrated_legacy := false
	if value is Dictionary:
		var contract_id := str(value.get("contract_id", ""))
		if contract_id == STATE_CONTRACT_ID:
			source = value.get("skills", {})
		elif contract_id == LEGACY_STATE_CONTRACT_ID:
			source = value.get("skills", {})
			## v1 snapshots are already canonical (stable skill IDs): keep
			## base_rank and discard proficiency, but do NOT flag legacy sync
			## that would repopulate the Chinese-name dictionary.
			migrated_legacy = false
		else:
			source = value
			migrated_legacy = true
	var rejected: Array[String] = []
	for raw_key: Variant in source:
		var skill_id := SkillDataLoaderScript.stable_skill_id(str(raw_key))
		if skill_id.is_empty():
			rejected.append(str(raw_key))
			continue
		var raw_entry: Variant = source[raw_key]
		var base_rank := 0
		if raw_entry is Dictionary:
			base_rank = clampi(
				int(raw_entry.get("base_rank", raw_entry.get("rank", 0))),
				0,
				3
			)
		else:
			base_rank = clampi(int(raw_entry), 0, 3)
		_set_base_rank(skill_id, base_rank)
	return {
		"loaded_count": _progress.size(),
		"rejected": rejected,
		"migrated_legacy": migrated_legacy,
	}


func snapshot() -> Dictionary:
	return {
		"contract_id": STATE_CONTRACT_ID,
		"skills": _progress.duplicate(true),
	}


func _set_base_rank(skill_id: String, base_rank: int) -> void:
	_progress[skill_id] = {
		"base_rank": base_rank,
		## Legacy compatibility alias kept for unmodified pre-v2 readers
		## (e.g. PlayerState effective_skill_level); never carries proficiency.
		"rank": base_rank,
	}


func _learn_result(
	accepted: bool,
	reason: String,
	skill_id: String,
	base_rank: int,
	required_level: int,
	outcome: String
) -> Dictionary:
	return {
		"accepted": accepted,
		"reason": reason,
		"outcome": outcome,
		"skill_id": skill_id,
		"base_rank": base_rank,
		"rank": base_rank,
		"required_level": required_level,
	}


func _no_op_result(skill_id: String, reason: String) -> Dictionary:
	var base_rank := int(_progress.get(skill_id, {}).get("base_rank", 0))
	return {
		"accepted": false,
		"reason": reason,
		"outcome": "proficiency_disabled",
		"skill_id": skill_id,
		"gain": 0,
		"ranked_up": false,
		"base_rank": base_rank,
		"rank": base_rank,
	}
