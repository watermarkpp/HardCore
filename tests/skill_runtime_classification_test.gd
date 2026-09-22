extends Node

const Policy := preload("res://scripts/skills/skill_runtime_classification.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const WizardRuntime := preload("res://scripts/skills/runtimes/wizard_skill_runtime.gd")
const TaoistRuntime := preload("res://scripts/skills/runtimes/taoist_skill_runtime.gd")
const SkillRngScript := preload("res://scripts/skills/skill_rng.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_exact_source_coverage_and_context_consumers()
	_test_real_action_boundaries()
	_test_unknown_ids_and_read_isolation()
	print("SKILL_RUNTIME_CLASSIFICATION_PASS")
	get_tree().quit(0)


func _test_exact_source_coverage_and_context_consumers() -> void:
	var source_ids := Loader.skill_ids()
	var policy_ids := Policy.skill_ids()
	assert(source_ids.size() == 33, "formal SOT must expose the accepted 33 skills")
	assert(policy_ids.size() == source_ids.size(), "classification has missing or extra IDs")
	var class_counts := {"warrior": 0, "wizard": 0, "taoist": 0}
	var hostile_context_count := 0
	var push_probe_count := 0
	for skill_id: String in source_ids:
		assert(policy_ids.has(skill_id), "SOT skill has no exact classification: " + skill_id)
		var definition := Loader.skill(skill_id)
		var profile := Policy.profile(skill_id)
		assert(not profile.is_empty(), "profile must exist for each formal stable ID")
		assert(profile.get("skill_id", "") == skill_id)
		assert(profile.get("domain", "") in ["physical", "spell"])
		for field: String in ["delivery", "target_shape", "target_semantics", "lifetime_owner"]:
			assert(not str(profile.get(field, "")).is_empty(), "missing " + field + ": " + skill_id)
		var profession := str(definition.get("class", ""))
		assert(class_counts.has(profession))
		class_counts[profession] = int(class_counts[profession]) + 1
		var mechanics: Dictionary = definition.get("mechanics", {})
		var family := str(mechanics.get("runtime_family", ""))
		# These SOT families correspond to the two actual context.targets
		# consumers, not to every hostile spell or every area-shaped skill.
		var expects_hostile_targets := family in [
			"area_push_no_damage", "monster_boundary_control",
		]
		var expects_push_probe := family == "area_push_no_damage"
		assert(
			Policy.needs_hostile_context_targets(skill_id) == expects_hostile_targets,
			"hostile context must follow the actual control consumer: " + skill_id,
		)
		assert(Policy.needs_push_path_probe(skill_id) == expects_push_probe)
		hostile_context_count += int(Policy.needs_hostile_context_targets(skill_id))
		push_probe_count += int(Policy.needs_push_path_probe(skill_id))
		if family == "passive_stat_modifier":
			assert(mechanics.get("stat", "") == "accuracy")
			assert(profile.get("domain", "") == "physical")
			assert(profile.get("delivery", "") == "passive")
		if family == "single_projectile_damage":
			assert(definition.get("geometry", {}).get("shape", "") == "projectile")
			assert(definition.get("target", {}).get("mode", "") == "hostile_single")
			assert(profile.get("domain", "") == "spell")
			assert(profile.get("delivery", "") == "projectile")
			assert(profile.get("target_shape", "") == "single")
		if str(mechanics.get("damage_type", "")) == "physical":
			assert(profile.get("domain", "") == "physical")
		if str(mechanics.get("defence_type", "")) == "MAC":
			assert(profile.get("domain", "") == "spell")
	for skill_id: String in policy_ids:
		assert(source_ids.has(skill_id), "classification contains an invented ID: " + skill_id)
	assert(class_counts == {"warrior": 6, "wizard": 14, "taoist": 13})
	assert(hostile_context_count == 2, "only push and boundary control consume hostile arrays")
	assert(push_probe_count == 1, "boundary control must not inherit repulsion path probes")


func _test_real_action_boundaries() -> void:
	# Exercise real profession runtimes with real primary definitions. The
	# classification cannot turn a visual strategy into a damage delivery.
	var lightning := _wizard_effect("wizard.lightning")
	assert(lightning.get("type", "") == "targeted_sky_strike")
	assert(not bool(lightning.get("horizontal_projectile", true)))
	assert(Policy.profile("wizard.lightning").get("delivery", "") == "direct")
	assert(Policy.profile("wizard.lightning").get("target_shape", "") == "single")
	var great_fireball := _wizard_effect("wizard.great_fireball")
	assert(great_fireball.get("type", "") == "projectile_damage")
	assert(Policy.profile("wizard.great_fireball").get("target_shape", "") == "single")
	var hellfire := _wizard_effect("wizard.hellfire")
	assert(hellfire.get("type", "") == "line_damage")
	assert(not bool(hellfire.get("channeled", true)))
	assert(Policy.profile("wizard.hellfire").get("delivery", "") == "direct")
	assert(Policy.profile("wizard.hellfire").get("target_shape", "") == "line")
	var laser := _wizard_effect("wizard.laser")
	assert(laser.get("type", "") == "piercing_line_damage")
	assert(Policy.profile("wizard.laser").get("delivery", "") == "direct")
	var fire_wall := _wizard_effect("wizard.fire_wall")
	assert(fire_wall.get("type", "") == "persistent_ground_damage")
	assert(int(fire_wall.get("tick_interval_ms", 0)) > 0)
	assert(Policy.profile("wizard.fire_wall").get("delivery", "") == "persistent_ground")
	assert(Policy.profile("wizard.fire_wall").get("lifetime_owner", "") == "FireWallFieldController")
	var spiritual := Loader.skill("taoist.spiritual_warfare")
	assert(spiritual.get("mechanics", {}).get("affects", []).has("physical_melee_hit_checks"))
	assert(Policy.profile("taoist.spiritual_warfare").get("domain", "") == "physical")
	assert(Policy.profile("warrior.wild_rush").get("target_semantics", "") == "hostile_control")
	assert(Policy.profile("warrior.fire_sword").get("delivery", "") == "melee_charge")

	var healing_definition := Loader.skill("taoist.mass_healing")
	assert(bool(healing_definition.get("mechanics", {}).get("must_use_dedicated_heal_pipeline", false)))
	var healing_request := {
		"skill_id": "taoist.mass_healing",
		"rank": 1,
		"caster_level": 35,
		"target_context": {
			"primary_stat_roll": 20,
			"caster_ground_position_gu": Vector2.ZERO,
			"friendly_candidates": [{
				"instance_id": 101,
				"is_self": true,
				"current_hp": 50,
				"max_hp": 100,
				"ground_position_gu": Vector2.ZERO,
				"level": 35,
				"actor_kind": "self",
			}],
		},
	}
	var heal_plan := TaoistRuntime.execute(healing_definition, healing_request, SkillRngScript.new(42))
	var heal_effects: Array = heal_plan.get("effects", [])
	assert(heal_effects.size() == 1)
	assert(heal_effects[0].get("type", "") == "dedicated_area_heal")
	assert(heal_effects[0].get("target_instance_ids", []).has(101))
	assert(Policy.profile("taoist.mass_healing").get("target_semantics", "") == "friendly_heal")
	assert(not Policy.needs_hostile_context_targets("taoist.mass_healing"))


func _wizard_effect(skill_id: String) -> Dictionary:
	var request := {
		"skill_id": skill_id,
		"rank": 1,
		"caster_level": 35,
		"target_context": {"primary_stat_roll": 20, "target_is_undead": false},
	}
	var plan := WizardRuntime.execute(Loader.skill(skill_id), request, SkillRngScript.new(42))
	var effects: Array = plan.get("effects", [])
	assert(effects.size() == 1, "expected one real gameplay action: " + skill_id)
	return effects[0]


func _test_unknown_ids_and_read_isolation() -> void:
	for unknown: String in ["", "雷电术", "wizard.unknown", "lightning", "wizard.lightning.extra", " Wizard.lightning"]:
		assert(Policy.profile(unknown).is_empty(), "unknown or alias must not infer a profile")
		assert(not Policy.needs_hostile_context_targets(unknown))
		assert(not Policy.needs_push_path_probe(unknown))
	var local_copy := Policy.profile("wizard.repulsion_ring")
	local_copy["context_targets"] = "none"
	local_copy["domain"] = "physical"
	assert(Policy.needs_hostile_context_targets("wizard.repulsion_ring"))
	assert(Policy.needs_push_path_probe("wizard.repulsion_ring"))
	assert(Policy.profile("wizard.repulsion_ring").get("domain", "") == "spell")
