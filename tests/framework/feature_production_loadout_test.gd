extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")
var proof := Proof.new()
var errors: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.learned_skills = {"雷电术":0}
	var sword := GameData.get_item_record({"item_id":85})
	check(not sword.is_empty() and int(sword.get("itemId", -1)) == 85, "formal item authority supplies exact ID 85")
	if sword.is_empty():
		_finish()
		return
	PlayerState.equipment["hc.slot.weapon"] = PlayerState._make_item_instance(str(sword.name), sword, 5302, false)
	PlayerState.recalculate_stats(false)
	check(PlayerState.feature_errors.is_empty(), "production content/loadout validates")
	check(ContentLayers.feature_configuration().enabled_modules.is_empty(), "all new modules default disabled")
	check(PlayerState.feature_bundle().sources.is_empty(), "default disabled loadout has no sources")
	var accuracy := int(PlayerState.computed_stats.accuracy)
	var original := Loader.skill("wizard.lightning")
	var plain := PlayerState.effective_skill_definition("wizard.lightning")
	check(plain == original, "empty extension preserves the exact old definition")
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", true), "formal module activation succeeds")
	check(PlayerState.feature_errors.is_empty(), "activation recompiles via actual PlayerState signal consumer")
	var bundle := PlayerState.feature_bundle()
	check(bundle.sources.size() == 3 and int(bundle.tags.get("hc.numeric", 0)) == 3, "item, skill and rule grants have distinct stable handles")
	check(int(PlayerState.computed_stats.accuracy) == accuracy + 4, "old base calculator plus two explicit contributions applies once")
	var effective := PlayerState.effective_skill_definition("wizard.lightning")
	check(float(effective.geometry.maximum_range_gu) == float(original.geometry.maximum_range_gu) + 1.0,
		"effective geometry leaf differs by exactly the declared amount")
	check(int(effective.mp_cost_by_rank[0]) == int(original.mp_cost_by_rank[0]) + 1, "effective resource leaf differs by the same module")
	check(effective.is_read_only() and effective.geometry.is_read_only(), "effective nested definition is immutable")
	var count: int = PlayerState._feature_loadout.compile_count
	PlayerState._damage_equipment_durability_raw("hc.slot.weapon", 1)
	PlayerState.recalculate_stats(false)
	check(PlayerState._feature_loadout.compile_count == count, "pure durability wear never recompiles qualification")
	PlayerState._damage_equipment_durability_raw("hc.slot.weapon", 2147483647)
	PlayerState.recalculate_stats(false)
	check(PlayerState._feature_loadout.compile_count == count + 1, "crossing broken boundary recompiles exactly once")
	check(PlayerState.feature_bundle().sources.size() == 2 and int(PlayerState.feature_bundle().tags["hc.numeric"]) == 2,
		"broken equipment revokes only that source and leaves learned skill and rule")
	check(bundle.sources.size() == 3, "old accepted immutable source snapshot remains unchanged")
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", false), "disable module through actual content entry")
	check(PlayerState.feature_bundle().sources.is_empty(), "deactivation withdraws every module source")
	check(PlayerState.effective_skill_definition("wizard.lightning") == original, "deactivation restores exact canonical skill")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_production_loadout_test", checks, errors.size()):
		errors.append("receipt failed")
	print(("FRAMEWORK_FEATURE_PRODUCTION_LOADOUT_PASS" if errors.is_empty() else "FRAMEWORK_FEATURE_PRODUCTION_LOADOUT_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
