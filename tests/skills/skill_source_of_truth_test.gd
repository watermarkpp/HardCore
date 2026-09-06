extends Node

const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const LegacySkillAdapterScript := preload("res://scripts/skills/legacy_skill_adapter.gd")


func _ready() -> void:
	var validation := SkillDataLoaderScript.reload_data()
	assert(validation.valid, "SOT validation failed: %s" % [validation.errors])
	assert(validation.skill_count == 33)
	assert(validation.unique_skill_ids == 33)
	assert(validation.class_counts == {"warrior": 6, "wizard": 14, "taoist": 13})
	assert(SkillDataLoaderScript.skill_ids().size() == 33)
	assert(SkillDataLoaderScript.legacy_records().size() == 132)
	assert(LegacySkillAdapterScript.records().size() == 132)
	assert(LegacySkillAdapterScript.profession_skills("战士").size() == 6)
	assert(LegacySkillAdapterScript.profession_skills("wizard").size() == 14)
	assert(LegacySkillAdapterScript.profession_skills("道士").size() == 13)
	var fireball := SkillDataLoaderScript.skill("火球术")
	assert(fireball.skill_id == "wizard.fireball")
	assert(SkillDataLoaderScript.stable_skill_id("FireBall") == "wizard.fireball")
	assert(SkillDataLoaderScript.rank_record("wizard.fireball", 3).mp_cost == 9)
	var integrity := SkillDataLoaderScript.validate_package_integrity()
	assert(integrity.valid, "Package integrity failed: %s" % [integrity.errors])
	assert(integrity.checked_files == 10)
	assert(integrity.runtime_sot_sha256 == SkillDataLoaderScript.SOURCE_OF_TRUTH_SHA256)
	var identity := SkillDataLoaderScript.source_identity()
	assert(identity.authority == "user_authoritative_override")
	assert(identity.sot_sha256 == SkillDataLoaderScript.SOURCE_OF_TRUTH_SHA256)
	assert(SkillDataLoaderScript.runtime_status_allowed("historical_verified"))
	assert(SkillDataLoaderScript.runtime_status_allowed("source_formula_reference"))
	assert(SkillDataLoaderScript.runtime_status_allowed("project_canonical"))
	for forbidden_status: String in [
		"needs_regression_verification",
		"selected_service_candidate",
		"project_adapter_C_candidate",
		"legacy_project_baseline",
		"rejected_version_mismatch",
		"unverified",
	]:
		assert(not SkillDataLoaderScript.runtime_status_allowed(forbidden_status))
	var test_manifest := SkillDataLoaderScript.package_test_manifest()
	assert(test_manifest.global_tests.size() == 19)
	assert(bool(test_manifest.get("project_overlay_valid", false)))
	assert(test_manifest.get("project_overlay", {}).get("entry_count", 0) == 2)
	assert(test_manifest.skill_tests.size() == 152)
	print("SKILL_SOURCE_OF_TRUTH_PASS: package hashes, 33/6-14-13, four ranks, aliases, legacy 132 adapter")
	get_tree().quit()
