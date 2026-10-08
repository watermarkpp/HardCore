extends Node

const ProgressionScript := preload("res://scripts/skills/skill_progression_service.gd")


func _ready() -> void:
	var progression: SkillProgressionService = ProgressionScript.new()
	var baseline: Dictionary = progression.snapshot()
	var learned := progression.learn("hc.skill.equipment.ring_teleport", 50)
	assert(not bool(learned.get("accepted", false)))
	assert(str(learned.get("reason", "")) == "equipment_granted_skill")
	assert(progression.snapshot() == baseline, "grant learn changed progression")
	var forged_snapshot := {
		"contract_id": ProgressionScript.STATE_CONTRACT_ID,
		"skills": {"hc.skill.equipment.ring_teleport": {"base_rank": 3}},
	}
	var loaded := progression.load_snapshot(forged_snapshot)
	assert(not bool(loaded.get("success", false)))
	assert(progression.snapshot() == baseline, "forged grant snapshot changed progression")
	print("EQUIPMENT_GRANTED_SKILL_PROGRESSION_REJECTION_PASS learn=false load=false snapshot_unchanged=true")
	get_tree().quit(0)
