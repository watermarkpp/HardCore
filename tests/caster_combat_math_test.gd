extends Node


func _ready() -> void:
	assert(WizardCombatMath.classic_get_power(8, 2, 0) == 4)
	assert(WizardCombatMath.classic_get_power(8, 2, 3) == 10)
	assert(WizardCombatMath.damage("wizard.fireball", 100, 0) == 104)
	assert(WizardCombatMath.damage("wizard.fireball", 100, 3) == 110)
	assert(WizardCombatMath.damage_with_rolls("wizard.lightning", 100, 3, 14, 11, false) == 125)
	assert(WizardCombatMath.damage_with_rolls("wizard.lightning", 100, 3, 14, 11, true) == 188)
	assert(WizardCombatMath.damage_with_rolls("wizard.hell_lightning", 100, 3, 20, 4, false) == 12)
	assert(WizardCombatMath.fire_wall_duration(3, 30) == 28.0)
	assert(WizardCombatMath.shield_power(3, 30) == 45)
	assert(WizardCombatMath.teleport_succeeds(3, 9) and not WizardCombatMath.teleport_succeeds(3, 10))
	assert(WizardCombatMath.repulsion_push_cells(3, 1) == 4)
	assert(WizardCombatMath.repulsion_succeeds(3, 30, 28, 16) and not WizardCombatMath.repulsion_succeeds(3, 30, 28, 17))
	assert(WizardCombatMath.holy_word_succeeds(3, 40, 35, 40, true))
	assert(not WizardCombatMath.holy_word_succeeds(3, 40, 35, 0, false))

	assert(TaoistCombatMath.healing("taoist.healing", 100, 3) == 214)
	assert(TaoistCombatMath.damage("taoist.soul_fire_talisman", 100, 3) == 120)
	var green_poison := TaoistCombatMath.poison_power(3, 30, true)
	assert(green_poison == 100 and TaoistCombatMath.poison_duration(3, green_poison) == 5)
	assert(TaoistCombatMath.status_duration("taoist.invisibility", 3, 20) == 90)
	assert(TaoistCombatMath.buff_power("taoist.defense", 3, 20) == 260)
	assert(TaoistCombatMath.revelation_duration(3, 20) == 70)
	assert(TaoistCombatMath.revelation_succeeds(0, 3) and not TaoistCombatMath.revelation_succeeds(0, 4))

	var skeleton := TaoistCombatMath.summon_profile("taoist.summon_skeleton", 3, 35, 30)
	var divine_beast := TaoistCombatMath.summon_profile("taoist.summon_divine_beast", 3, 35, 30)
	assert(skeleton.attack_type == "physical" and divine_beast.attack_type == "fire")
	assert(skeleton.summon_level == 3 and skeleton.summon_exp_level == 3 and skeleton.summon_count == 1)
	assert(skeleton.amulet_cost == 1 and divine_beast.amulet_cost == 5)
	assert(divine_beast.max_hp > skeleton.max_hp and divine_beast.attack_range > skeleton.attack_range)
	assert(skeleton.lifetime_seconds == 864000.0 and divine_beast.lifetime_seconds == 864000.0)
	assert(skeleton.reject_when_owner_has_slave and divine_beast.recall_existing_on_create_failure)

	for skill_id: String in ProfessionRules.SKILL_CATALOG:
		if skill_id.begins_with("wizard."):
			var profile := WizardCombatMath.profile_overrides(skill_id, 3)
			assert(not profile.is_empty() and profile.formula_id.ends_with("classic_magic_pas.v2"))
		elif skill_id.begins_with("taoist."):
			var profile := TaoistCombatMath.profile_overrides(skill_id, 3)
			assert(not profile.is_empty() and profile.formula_id.ends_with("classic_magic_pas.v2"))
	print("CASTER_COMBAT_MATH_PASS: 27 caster skills use Magic.pas formula contracts")
	get_tree().quit(0)
