class_name SkillCastRequest
extends RefCounted

const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)

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
		## Effective rank = base rank + equipment bonus. No gameplay cap; only
		## the policy's technical anti-abuse sanity cap applies.
		"rank": SkillRankResolverScript.safe_effective_rank(rank),
		"caster_level": maxi(1, caster_level),
		"origin_tile": origin_tile,
		"facing": facing,
		"target_context": _copy_target_context_preserving_snapshot(target_context),
		"resource_context": resource_context.duplicate(true),
		"seed": seed_value,
		"client_claimed_damage": null,
		"client_claimed_success": null,
	}


static func _copy_target_context_preserving_snapshot(
	target_context: Dictionary
) -> Dictionary:
	## Target/resource context is request-owned and normally deep-copied.  A
	## formal release snapshot is different: an already immutable snapshot is
	## the single identity shared by the release and its query plan.  Preserve
	## that exact dictionary reference. Mutable/non-dictionary values stay on
	## the deep-copy path; all snapshots still require strict validation.
	var snapshot: Variant = target_context.get("skill_footprint_snapshot", null)
	if snapshot is Dictionary and (snapshot as Dictionary).is_read_only():
		var context_without_snapshot: Dictionary = target_context.duplicate(false)
		context_without_snapshot.erase("skill_footprint_snapshot")
		var copied_context: Dictionary = context_without_snapshot.duplicate(true)
		copied_context["skill_footprint_snapshot"] = snapshot
		return copied_context
	return target_context.duplicate(true)


static func validate(request: Variant) -> Dictionary:
	if not request is Dictionary:
		return {"valid": false, "reason": "request_not_dictionary"}
	if str(request.get("contract_id", "")) != CONTRACT_ID:
		return {"valid": false, "reason": "request_contract"}
	if str(request.get("skill_id", "")).is_empty():
		return {"valid": false, "reason": "skill_id"}
	var request_rank := int(request.get("rank", -1))
	if (
		request_rank < 0
		or request_rank > SkillRankResolverScript.technical_effective_rank_cap()
	):
		return {"valid": false, "reason": "rank"}
	return {"valid": true, "reason": ""}
