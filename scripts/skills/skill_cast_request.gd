class_name SkillCastRequest
extends RefCounted

const CONTRACT_ID := "skills.cast_request.v1"


static func create(
	skill_id: String,
	rank: int,
	caster_level: int,
	origin_tile := Vector2i.ZERO,
	facing := Vector2i.DOWN,
	target_context := {},
	resource_context := {},
	seed_value := 0
) -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"skill_id": skill_id,
		"rank": clampi(rank, 0, 3),
		"caster_level": maxi(1, caster_level),
		"origin_tile": origin_tile,
		"facing": facing,
		"target_context": target_context.duplicate(true),
		"resource_context": resource_context.duplicate(true),
		"seed": seed_value,
		"client_claimed_damage": null,
		"client_claimed_success": null,
	}


static func validate(request: Variant) -> Dictionary:
	if not request is Dictionary:
		return {"valid": false, "reason": "request_not_dictionary"}
	if str(request.get("contract_id", "")) != CONTRACT_ID:
		return {"valid": false, "reason": "request_contract"}
	if str(request.get("skill_id", "")).is_empty():
		return {"valid": false, "reason": "skill_id"}
	if int(request.get("rank", -1)) < 0 or int(request.get("rank", -1)) > 3:
		return {"valid": false, "reason": "rank"}
	return {"valid": true, "reason": ""}
