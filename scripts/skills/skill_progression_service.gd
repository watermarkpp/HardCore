class_name SkillProgressionService
extends RefCounted

const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")

const STATE_CONTRACT_ID := "skills.progression.cn_mir2_176.v1"

var _progress: Dictionary = {}


func learn(skill_name_or_id: String, player_level: int) -> Dictionary:
	var skill_id := SkillDataLoaderScript.stable_skill_id(skill_name_or_id)
	var rank_zero := SkillDataLoaderScript.rank_record(skill_id, 0)
	if rank_zero.is_empty():
		return {"accepted": false, "reason": "unknown_skill", "skill_id": skill_id}
	if _progress.has(skill_id):
		return {"accepted": false, "reason": "already_learned", "skill_id": skill_id}
	if player_level < int(rank_zero.get("player_level_required", 1)):
		return {"accepted": false, "reason": "player_level", "skill_id": skill_id}
	_progress[skill_id] = {"rank": 0, "current_proficiency": 0}
	return {"accepted": true, "reason": "", "skill_id": skill_id, "rank": 0}


func is_learned(skill_name_or_id: String) -> bool:
	return _progress.has(SkillDataLoaderScript.stable_skill_id(skill_name_or_id))


func state(skill_name_or_id: String) -> Dictionary:
	var skill_id := SkillDataLoaderScript.stable_skill_id(skill_name_or_id)
	return _progress.get(skill_id, {}).duplicate(true)


func apply_proficiency_event(
	skill_name_or_id: String,
	event_id: String,
	player_level: int,
	rng: RefCounted
) -> Dictionary:
	var skill_id := SkillDataLoaderScript.stable_skill_id(skill_name_or_id)
	if not _progress.has(skill_id):
		return _event_result(false, "skill_not_learned", skill_id, 0, false)
	var definition := SkillDataLoaderScript.skill(skill_id)
	var trigger: Dictionary = definition.get("proficiency_trigger", {})
	if event_id.is_empty() or event_id != str(trigger.get("event", "")):
		return _event_result(false, "ineligible_event", skill_id, 0, false)
	if not rng.has_method("training_gain"):
		return _event_result(false, "rng_required", skill_id, 0, false)
	var entry: Dictionary = _progress[skill_id]
	var rank := clampi(int(entry.get("rank", 0)), 0, 3)
	if rank >= 3:
		return _event_result(true, "terminal_rank", skill_id, 0, false)
	var gain := int(rng.call("training_gain"))
	if gain < 1 or gain > 3:
		return _event_result(false, "invalid_rng_gain", skill_id, 0, false)
	entry["current_proficiency"] = maxi(0, int(entry.get("current_proficiency", 0))) + gain
	var next_rank_data := SkillDataLoaderScript.rank_record(skill_id, rank + 1)
	var required_level := int(next_rank_data.get("player_level_required", 1))
	var required_proficiency := int(next_rank_data.get("proficiency_required_to_reach_rank", 0))
	var ranked_up := player_level >= required_level and int(entry.current_proficiency) >= required_proficiency
	if ranked_up:
		entry["rank"] = rank + 1
		entry["current_proficiency"] = 0
	_progress[skill_id] = entry
	var result := _event_result(true, "", skill_id, gain, ranked_up)
	result["rank"] = int(entry.rank)
	result["current_proficiency"] = int(entry.current_proficiency)
	result["required_player_level"] = required_level
	result["required_proficiency"] = required_proficiency
	return result


func load_snapshot(value: Variant) -> Dictionary:
	_progress.clear()
	var source: Dictionary = {}
	var migrated_legacy := false
	if value is Dictionary and str(value.get("contract_id", "")) == STATE_CONTRACT_ID:
		source = value.get("skills", {})
	elif value is Dictionary:
		source = value
		migrated_legacy = true
	var rejected: Array[String] = []
	for raw_key: Variant in source:
		var skill_id := SkillDataLoaderScript.stable_skill_id(str(raw_key))
		if skill_id.is_empty():
			rejected.append(str(raw_key))
			continue
		var raw_entry: Variant = source[raw_key]
		var rank := 0
		var proficiency := 0
		if raw_entry is Dictionary:
			rank = clampi(int(raw_entry.get("rank", 0)), 0, 3)
			proficiency = maxi(0, int(raw_entry.get("current_proficiency", 0)))
		else:
			rank = clampi(int(raw_entry), 0, 3)
		_progress[skill_id] = {
			"rank": rank,
			"current_proficiency": 0 if migrated_legacy else proficiency,
		}
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


func _event_result(accepted: bool, reason: String, skill_id: String, gain: int, ranked_up: bool) -> Dictionary:
	return {
		"accepted": accepted,
		"reason": reason,
		"skill_id": skill_id,
		"gain": gain,
		"ranked_up": ranked_up,
	}
