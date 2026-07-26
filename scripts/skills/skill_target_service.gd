class_name SkillTargetService
extends RefCounted


static func validate(definition: Dictionary, target_context: Dictionary) -> Dictionary:
	var target: Dictionary = definition.get("target", {})
	var mode := str(target.get("mode", ""))
	var requires_target := mode not in [
		"self_stat", "self", "self_summon", "self_next_melee_charge",
		"caster_surrounding_area", "surrounding_units",
	]
	if requires_target and not bool(target_context.get("has_target", false)):
		return {"valid": false, "reason": "target_required", "target": target}
	if bool(target.get("requires_line_of_sight", false)) and not bool(target_context.get("line_of_sight", false)):
		return {"valid": false, "reason": "line_of_sight", "target": target}
	var relation := str(target.get("relation", ""))
	if relation.contains("hostile") and bool(target_context.get("friendly", false)):
		return {"valid": false, "reason": "hostile_target_required", "target": target}
	if relation.contains("friendly") and bool(target_context.get("hostile", false)):
		return {"valid": false, "reason": "friendly_target_required", "target": target}
	return {"valid": true, "reason": "", "target": target.duplicate(true)}
