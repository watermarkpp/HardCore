class_name SkillVisibilityPolicy
extends RefCounted

## Single source of truth for hiding skills from the visible/usable game
## skill system without removing their stable ID, data or code (old saves and
## quick-slot bindings keep referencing the ID and stay loadable).
##
## Contract: skills.skill_visibility_policy.v1
## Currently hidden: taoist.revelation (kept for save/shortcut compatibility).

const CONTRACT_ID := "skills.skill_visibility_policy.v1"

const HIDDEN_SKILL_IDS := {
	"taoist.revelation": true,
}


static func is_skill_visible(skill_name_or_id: String) -> bool:
	return not HIDDEN_SKILL_IDS.has(skill_name_or_id)


static func is_skill_castable(skill_name_or_id: String) -> bool:
	return not HIDDEN_SKILL_IDS.has(skill_name_or_id)
