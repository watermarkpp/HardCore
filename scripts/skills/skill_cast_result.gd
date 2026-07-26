class_name SkillCastResult
extends RefCounted

const CONTRACT_ID := "skills.cast_result.v1"


static func failure(skill_id: String, reason: String) -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"accepted": false,
		"effect_success": false,
		"skill_id": skill_id,
		"reason": reason,
		"resource_commit": false,
		"proficiency_event": "",
		"effects": [],
	}


static func success(skill_id: String, plan: Dictionary) -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"accepted": true,
		"effect_success": bool(plan.get("effect_success", true)),
		"skill_id": skill_id,
		"reason": "",
		"resource_commit": bool(plan.get("resource_commit", true)),
		"proficiency_event": str(plan.get("proficiency_event", "")),
		"effects": plan.get("effects", []).duplicate(true),
		"runtime_family": str(plan.get("runtime_family", "")),
		"timing": plan.get("timing", {}).duplicate(true),
		"geometry": plan.get("geometry", {}).duplicate(true),
		"target": plan.get("target", {}).duplicate(true),
		"resource": plan.get("resource", {}).duplicate(true),
		"mechanics": plan.get("mechanics", {}).duplicate(true),
	}
