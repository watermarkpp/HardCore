extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Progression := preload("res://scripts/skills/skill_progression_service.gd")
const Rng := preload("res://scripts/skills/skill_rng.gd")
const Formula := preload("res://scripts/skills/formulas/mir2_skill_formula.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	var service := Progression.new()
	assert(service.learn("wizard.fireball", 7).accepted)
	assert(service.state("火球术") == {"rank": 0, "current_proficiency": 0})
	var wrong := service.apply_proficiency_event("wizard.fireball", "invalid", 40, Rng.new(1))
	assert(not wrong.accepted and wrong.gain == 0)
	var rng := Rng.new(42)
	for index in range(3000):
		var result := service.apply_proficiency_event(
			"wizard.fireball",
			"valid_projectile_cast_created",
			40,
			rng
		)
		assert(result.accepted)
		assert(result.gain >= 1 and result.gain <= 3)
		if result.ranked_up:
			assert(result.current_proficiency == 0)
		if result.rank == 3:
			break
	assert(service.state("wizard.fireball").rank == 3)
	var snapshot := service.snapshot()
	assert(snapshot.contract_id == Progression.STATE_CONTRACT_ID)
	var restored := Progression.new()
	assert(restored.load_snapshot(snapshot).loaded_count == 1)
	assert(restored.state("wizard.fireball").rank == 3)
	var migrated := Progression.new()
	var migration := migrated.load_snapshot({"火球术": 2, "未知技能": 3})
	assert(migration.migrated_legacy and migration.loaded_count == 1)
	assert(migration.rejected == ["未知技能"])
	assert(migrated.state("wizard.fireball") == {"rank": 2, "current_proficiency": 0})
	var formula_rng := Rng.new(7)
	assert(Formula.get_power(formula_rng, 3, 8) == 8)
	assert(Formula.get_power13(formula_rng, 3, 30) == 30)
	for index in range(20):
		var gain := Rng.new(index).training_gain()
		assert(gain >= 1 and gain <= 3)
	print("SKILL_PROGRESSION_SERVICE_PASS: per-rank proficiency, 1-3 RNG, reset, terminal rank, legacy migration")
	get_tree().quit()
