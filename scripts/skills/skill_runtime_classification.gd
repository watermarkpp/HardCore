class_name SkillRuntimeClassification
extends RefCounted

## Exact-ID classification of existing production consumers. This policy owns
## no nodes, clocks, damage, geometry, target selection, resources or RNG.
## Gameplay numbers and exact footprints remain in the primary SOT/plan.
## `target_shape` is a category, never a replacement for canonical geometry.
## `lifetime_owner` identifies gameplay/state ownership, not visual lifetime.
## Direct line spells resolve at release even when their visuals travel or loop.
##
## Only context_targets drives the generic hostile-array preparation policy.
## It does not describe scalar target_context fields or friendly candidates;
## those retain their own production consumers and must not be removed.
## Callers must reject an empty profile before interpreting the boolean helpers.
## No display-name, prefix, suffix, profession or unknown-ID inference is allowed.

const CONTRACT_ID := "skills.runtime.classification.v1"

## The two non-none entries come from WizardSkillRuntime._resolve_repulsion
## and TaoistSkillRuntime._resolve_entrapment, the actual context.targets
## consumers. Only repulsion consumes each candidate's path_blocked field.
const _PROFILES := {
	"warrior.basic_swordsmanship": {
		"domain": "physical",
		"delivery": "passive",
		"target_shape": "none",
		"target_semantics": "physical_accuracy_modifier",
		"lifetime_owner": "GameRoot._on_player_attack",
		"context_targets": "none"
	},
	"warrior.slaying_swordsmanship": {
		"domain": "physical",
		"delivery": "melee_modifier",
		"target_shape": "melee_front",
		"target_semantics": "physical_melee_modifier",
		"lifetime_owner": "GameRoot._on_player_attack",
		"context_targets": "none"
	},
	"warrior.thrusting": {
		"domain": "physical",
		"delivery": "melee",
		"target_shape": "line",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "GameRoot._execute_canonical_melee",
		"context_targets": "none"
	},
	"warrior.half_moon": {
		"domain": "physical",
		"delivery": "melee",
		"target_shape": "arc",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "GameRoot._execute_canonical_melee",
		"context_targets": "none"
	},
	"warrior.wild_rush": {
		"domain": "physical",
		"delivery": "direct",
		"target_shape": "line",
		"target_semantics": "hostile_control",
		"lifetime_owner": "GameRoot._apply_wild_rush_displacement",
		"context_targets": "none"
	},
	"warrior.fire_sword": {
		"domain": "physical",
		"delivery": "melee_charge",
		"target_shape": "single",
		"target_semantics": "self_physical_charge",
		"lifetime_owner": "GameRoot._canonical_fire_charge_expires_ms",
		"context_targets": "none"
	},
	"wizard.fireball": {
		"domain": "spell",
		"delivery": "projectile",
		"target_shape": "single",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "SkillProjectile",
		"context_targets": "none"
	},
	"wizard.repulsion_ring": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "ring",
		"target_semantics": "hostile_control",
		"lifetime_owner": "GameRoot._apply_canonical_effects_from_plan",
		"context_targets": "adjacent_push"
	},
	"wizard.temptation_light": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "single",
		"target_semantics": "hostile_control_or_tame",
		"lifetime_owner": "EnemyActor",
		"context_targets": "none"
	},
	"wizard.hellfire": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "line",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "GameRoot._apply_canonical_spell_damage",
		"context_targets": "none"
	},
	"wizard.lightning": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "single",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "GameRoot._apply_canonical_spell_damage",
		"context_targets": "none"
	},
	"wizard.great_fireball": {
		"domain": "spell",
		"delivery": "projectile",
		"target_shape": "single",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "SkillProjectile",
		"context_targets": "none"
	},
	"wizard.teleport": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "self",
		"target_semantics": "self_teleport",
		"lifetime_owner": "GameRoot._apply_canonical_effects_from_plan",
		"context_targets": "none"
	},
	"wizard.exploding_flame": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "area",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "GameRoot._apply_canonical_spell_damage",
		"context_targets": "none"
	},
	"wizard.fire_wall": {
		"domain": "spell",
		"delivery": "persistent_ground",
		"target_shape": "area",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "FireWallFieldController",
		"context_targets": "none"
	},
	"wizard.laser": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "line",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "GameRoot._apply_canonical_spell_damage",
		"context_targets": "none"
	},
	"wizard.hell_lightning": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "ring",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "GameRoot._apply_canonical_spell_damage",
		"context_targets": "none"
	},
	"wizard.magic_shield": {
		"domain": "spell",
		"delivery": "actor_status",
		"target_shape": "self",
		"target_semantics": "self_buff",
		"lifetime_owner": "PlayerCharacter.shield_time",
		"context_targets": "none"
	},
	"wizard.holy_word": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "single",
		"target_semantics": "hostile_instant_kill",
		"lifetime_owner": "GameRoot._apply_canonical_effects_from_plan",
		"context_targets": "none"
	},
	"wizard.ice_storm": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "area",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "GameRoot._apply_canonical_spell_damage",
		"context_targets": "none"
	},
	"taoist.healing": {
		"domain": "spell",
		"delivery": "actor_status",
		"target_shape": "single",
		"target_semantics": "friendly_heal",
		"lifetime_owner": "GameRoot._ongoing_heals",
		"context_targets": "none"
	},
	"taoist.spiritual_warfare": {
		"domain": "physical",
		"delivery": "passive",
		"target_shape": "none",
		"target_semantics": "physical_accuracy_modifier",
		"lifetime_owner": "GameRoot._on_player_attack",
		"context_targets": "none"
	},
	"taoist.poison": {
		"domain": "spell",
		"delivery": "actor_status",
		"target_shape": "single",
		"target_semantics": "hostile_debuff",
		"lifetime_owner": "EnemyActor",
		"context_targets": "none"
	},
	"taoist.soul_fire_talisman": {
		"domain": "spell",
		"delivery": "projectile",
		"target_shape": "single",
		"target_semantics": "hostile_damage",
		"lifetime_owner": "SkillProjectile",
		"context_targets": "none"
	},
	"taoist.summon_skeleton": {
		"domain": "spell",
		"delivery": "summon",
		"target_shape": "adjacent_spawn",
		"target_semantics": "main_pet",
		"lifetime_owner": "SummonActor",
		"context_targets": "none"
	},
	"taoist.invisibility": {
		"domain": "spell",
		"delivery": "actor_status",
		"target_shape": "self",
		"target_semantics": "self_buff",
		"lifetime_owner": "PlayerCharacter.stealth_time",
		"context_targets": "none"
	},
	"taoist.mass_invisibility": {
		"domain": "spell",
		"delivery": "actor_status",
		"target_shape": "area",
		"target_semantics": "friendly_buff",
		"lifetime_owner": "PlayerCharacter/SummonActor",
		"context_targets": "none"
	},
	"taoist.magic_defense": {
		"domain": "spell",
		"delivery": "actor_status",
		"target_shape": "area",
		"target_semantics": "friendly_buff",
		"lifetime_owner": "PlayerCharacter/SummonActor",
		"context_targets": "none"
	},
	"taoist.defense": {
		"domain": "spell",
		"delivery": "actor_status",
		"target_shape": "area",
		"target_semantics": "friendly_buff",
		"lifetime_owner": "PlayerCharacter/SummonActor",
		"context_targets": "none"
	},
	"taoist.revelation": {
		"domain": "spell",
		"delivery": "direct",
		"target_shape": "single",
		"target_semantics": "target_information",
		"lifetime_owner": "GameHUD.show_message",
		"context_targets": "none"
	},
	"taoist.entrapment": {
		"domain": "spell",
		"delivery": "actor_status",
		"target_shape": "boundary",
		"target_semantics": "hostile_control",
		"lifetime_owner": "EnemyActor/EntrapmentBoundaryController",
		"context_targets": "boundary_control"
	},
	"taoist.mass_healing": {
		"domain": "spell",
		"delivery": "actor_status",
		"target_shape": "area",
		"target_semantics": "friendly_heal",
		"lifetime_owner": "GameRoot._ongoing_heals",
		"context_targets": "none"
	},
	"taoist.summon_divine_beast": {
		"domain": "spell",
		"delivery": "summon",
		"target_shape": "adjacent_spawn",
		"target_semantics": "main_pet",
		"lifetime_owner": "SummonActor",
		"context_targets": "none"
	}
}


static func skill_ids() -> PackedStringArray:
	var result := PackedStringArray(_PROFILES.keys())
	result.sort()
	return result


static func profile(skill_id: String) -> Dictionary:
	if not _PROFILES.has(skill_id):
		return {}
	var stored: Dictionary = _PROFILES[skill_id]
	var result := stored.duplicate(true)
	result["skill_id"] = skill_id
	return result


static func needs_hostile_context_targets(skill_id: String) -> bool:
	var stored: Dictionary = _PROFILES.get(skill_id, {})
	return str(stored.get("context_targets", "none")) in [
		"adjacent_push", "boundary_control",
	]


static func needs_push_path_probe(skill_id: String) -> bool:
	var stored: Dictionary = _PROFILES.get(skill_id, {})
	return str(stored.get("context_targets", "none")) == "adjacent_push"
