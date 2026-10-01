extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Progression := preload("res://scripts/skills/skill_progression_service.gd")
var proof := Proof.new()
var errors: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		errors.append(label)

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.learned_skills = {"雷电术":2}
	check(PlayerState.learned_skills == {"hc.skill.wizard.lightning":2}, "legacy name converts once to canonical runtime ID")
	check(PlayerState.learned_skills.is_read_only(), "skill identity projection cannot become a second mutable authority")
	check(PlayerState.is_skill_learned("wizard.lightning"), "stable ID query works immediately after import without repair scan")
	var previous: Dictionary = PlayerState.learned_skills
	PlayerState.learned_skills = {"unknown.skill":1}
	check(PlayerState.learned_skills == previous, "invalid identity import preserves prior runtime skills")
	var identity_errors: Variant = PlayerState.get("skill_identity_errors")
	check(identity_errors is Array and not identity_errors.is_empty(), "unknown identity is explicitly reported")
	var service := Progression.new()
	service.load_snapshot({"wizard.fireball":2})
	var before: Dictionary = service.snapshot()
	var rejected := service.load_snapshot({"contract_id":Progression.STATE_CONTRACT_ID,"skills":{"雷电术":{"base_rank":2}}})
	check(not bool(rejected.get("success", true)) and service.snapshot() == before, "canonical schema refuses Chinese-name identity atomically")
	rejected = service.load_snapshot({"雷电术":1,"wizard.lightning":3})
	check(not bool(rejected.get("success", true)) and service.snapshot() == before, "duplicate alias to same canonical ID refuses conflicting records")
	rejected = service.load_snapshot({"雷电术":1,"未知技能":3})
	check(not bool(rejected.get("success", true)) and service.snapshot() == before, "unknown legacy identity cannot disappear during partial migration")
	var imported := service.load_snapshot({"雷电术":2})
	check(bool(imported.get("success", false)) and service.snapshot().skills.has("hc.skill.wizard.lightning")
		and not service.snapshot().skills.has("雷电术"), "explicit legacy boundary produces canonical progression")
	if not proof.write_receipt("skill_identity_authority_test", checks, errors.size()):
		errors.append("receipt failed")
	print(("FRAMEWORK_SKILL_IDENTITY_AUTHORITY_PASS" if errors.is_empty() else "FRAMEWORK_SKILL_IDENTITY_AUTHORITY_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
