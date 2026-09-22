extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Progression := preload("res://scripts/skills/skill_progression_service.gd")
const Rng := preload("res://scripts/skills/skill_rng.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	var service := Progression.new()

	# Level requirement blocks the first book.
	var low := service.learn("wizard.fireball", 1)
	assert(not low.accepted and low.outcome == "level_requirement")
	assert(not service.is_learned("wizard.fireball"))

	# First book learns at base rank 1.
	var first := service.learn("wizard.fireball", 40)
	assert(first.accepted and first.outcome == "learned" and first.base_rank == 1)
	assert(service.state("火球术") == {"base_rank": 1, "rank": 1})

	# Same-name books upgrade 1 -> 2 -> 3.
	for expected: int in [2, 3]:
		var upgrade := service.learn("wizard.fireball", 40)
		assert(
			upgrade.accepted
			and upgrade.outcome == "upgraded"
			and upgrade.base_rank == expected
		)

	# Terminal rank rejects further books without consuming anything.
	var terminal := service.learn("wizard.fireball", 40)
	assert(not terminal.accepted and terminal.outcome == "max")
	assert(terminal.base_rank == 3 and service.state("wizard.fireball").base_rank == 3)

	# Level requirement also blocks an upgrade.
	var new_service := Progression.new()
	new_service.load_snapshot({"wizard.fireball": 1})
	var blocked_upgrade := new_service.learn("wizard.fireball", 1)
	assert(
		not blocked_upgrade.accepted
		and blocked_upgrade.outcome == "level_requirement"
		and blocked_upgrade.base_rank == 1
	)

	# Proficiency is disabled: no-op rejection, no mutation, no persistence.
	var noop := service.apply_proficiency_event(
		"wizard.fireball",
		"valid_projectile_cast_created",
		40,
		Rng.new(1)
	)
	assert(not noop.accepted and noop.gain == 0)
	assert(noop.reason == "proficiency_disabled")
	assert(service.state("wizard.fireball").base_rank == 3)
	assert(not service.snapshot().skills["wizard.fireball"].has("current_proficiency"))

	# v2 snapshot roundtrip persists base_rank and never persists proficiency.
	var snapshot := service.snapshot()
	assert(snapshot.contract_id == Progression.STATE_CONTRACT_ID)
	var restored := Progression.new()
	assert(restored.load_snapshot(snapshot).loaded_count == 1)
	assert(restored.state("wizard.fireball").base_rank == 3)
	assert(not restored.snapshot().skills["wizard.fireball"].has("current_proficiency"))

	# v1 -> v2 load keeps rank as base_rank and discards proficiency; v1 is
	# canonical (stable IDs), so no legacy Chinese-name sync is flagged.
	var migrated := Progression.new()
	var migration := migrated.load_snapshot({
		"contract_id": "skills.progression.cn_mir2_176.v1",
		"skills": {
			"wizard.fireball": {"rank": 2, "current_proficiency": 321},
		},
	})
	assert(not migration.migrated_legacy and migration.loaded_count == 1)
	assert(migrated.state("wizard.fireball").base_rank == 2)
	assert(not migrated.snapshot().skills["wizard.fireball"].has("current_proficiency"))

	# Bare legacy dictionary (Chinese names + int ranks) still migrates.
	var bare := Progression.new()
	var bare_migration := bare.load_snapshot({"火球术": 2, "未知技能": 3})
	assert(bare_migration.migrated_legacy and bare_migration.loaded_count == 1)
	assert(bare_migration.rejected == ["未知技能"])
	assert(bare.state("wizard.fireball") == {"base_rank": 2, "rank": 2})

	# Base-rank boundary: persisted base ranks clamp to the 0..3 contract.
	var bounds := Progression.new()
	bounds.load_snapshot({"wizard.fireball": 4, "wizard.lightning": -5})
	assert(bounds.state("wizard.fireball").base_rank == 3)
	assert(bounds.state("wizard.lightning").base_rank == 0)

	# Equipment can never enable an unlearned skill; once learned, ordinary
	# high effective ranks pass through without a gameplay cap.
	var equipped := Progression.new()
	assert(equipped.effective_rank("wizard.fireball", 1000) == 0)
	assert(equipped.learn("wizard.fireball", 40).accepted)
	assert(equipped.effective_rank("wizard.fireball", 1000) == 1001)
	assert(equipped.effective_rank("wizard.fireball", -3) == 1)

	print(
		"SKILL_PROGRESSION_SERVICE_PASS: book 1->2->3, max reject, "
		+ "level gates, v1->v2 migration, proficiency disabled, "
		+ "equipment-on-unlearned rejected"
	)
	get_tree().quit()
