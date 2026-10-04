extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Provider := preload("res://scripts/features/adapters/contribution_provider.gd")
const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const REGISTRY := "res://assets/data/features/validation/source_composition_registry.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.profession = "法师"; PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}
	PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog(REGISTRY), "actual catalog registers the default-off affix mechanism")
	var base: Dictionary = {}
	for index in range(256):
		var candidate := Drop.create_instance(GameData.get_item_record({"item_id":85}), "affix-admission:"+str(index))
		for modifier: Dictionary in candidate.get("modifiers", []):
			if modifier.stat == "magic_max" and modifier.op == "add" and float(modifier.value)>0:
				base = candidate; break
		if not base.is_empty(): break
	check(not base.is_empty() and GameData.validate_item_drop_instance(base), "real drop generator supplies the complete validated immutable affix payload")
	if base.is_empty(): _finish(); return
	PlayerState.equipment = {"hc.slot.weapon":base}
	PlayerState.recalculate_stats(false)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true)
		and PlayerState.feature_bundle().sources.size()==1, "valid original affix grants exactly one source through actual atomic publication")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false), "normal source can be withdrawn before invalid candidate probes")
	var missing_contract := base.duplicate(true); missing_contract.erase("drop_instance_contract_id")
	_probe(missing_contract, "missing_drop_contract")
	var duplicate := missing_contract.duplicate(true)
	duplicate.modifiers = [{"stat":"magic_max","op":"add","value":1},{"stat":"magic_max","op":"add","value":1}]
	_probe(duplicate, "duplicate_forged_modifiers")
	var forged := missing_contract.duplicate(true)
	forged.modifiers = [{"stat":"magic_max","op":"add","value":1000}]
	_probe(forged, "forged_modifier_value")
	var wrong_identity := missing_contract.duplicate(true); wrong_identity.instance_id = "affix-admission:forged"
	_probe(wrong_identity, "wrong_persistent_instance")
	var missing_identity := missing_contract.duplicate(true); missing_identity.erase("instance_id")
	_probe(missing_identity, "missing_persistent_instance")
	# Compatibility authorizes old equipment use, never new affix provenance.
	var legacy := base.duplicate(true)
	for field: String in ["drop_instance_contract_id","drop_rules_contract_id","drop_key_digest","drop_affix","modifiers","instance_id"]:
		legacy.erase(field)
	PlayerState.equipment = {"hc.slot.weapon":legacy}; PlayerState.recalculate_stats(false)
	check(Codec.decode_wire(legacy).status==Codec.KNOWN_VALID and PlayerState._feature_item_eligible(legacy),
		"ordinary historical non-affix gear retains its existing compatibility")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true) and PlayerState.feature_bundle().sources.is_empty(),
		"compatible plain historical gear enables the module without fabricating affix sources")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false), "plain historical gear can withdraw the module normally")
	PlayerState.equipment = {"hc.slot.weapon":base}; PlayerState.recalculate_stats(false)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true) and PlayerState.feature_bundle().sources.size()==1,
		"valid original source remains available after every failed candidate")
	PlayerState.equipment = {}; PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog(), "owned fixture restores original default-off configuration")
	_finish()

func _probe(instance: Dictionary, label: String) -> void:
	check(not GameData.validate_item_drop_instance(instance) and PlayerState._feature_item_eligible(instance)
		and Codec.decode_wire(instance).status==Codec.KNOWN_VALID, label+": exact legacy ingress reaches the new source boundary")
	var configuration := ContentLayers.feature_configuration()
	var collected: Variant = Provider.collect(configuration.bindings, ["hc.ignite"], {"hc.slot.weapon":instance},
		PlayerState.active_profile_id, GameData.get_item_record, PlayerState._feature_item_eligible, PlayerState.is_skill_learned)
	check(collected is Dictionary and collected.get("success")==false and collected.get("sources") is Array
		and collected.sources.is_empty(), label+": source boundary returns a typed rejection without granting provenance")
	print("AFFIX_ADMISSION_PROBE="+JSON.stringify({"case":label,"typed_result":collected is Dictionary,
		"source_count":collected.get("sources",[]).size() if collected is Dictionary else -1}))
	if not collected is Dictionary or not collected.has("success"): return # Original script error is retained by the native runner.
	PlayerState.equipment = {"hc.slot.weapon":instance}; PlayerState.recalculate_stats(false)
	var before := ContentLayers.feature_configuration()
	var bundle := PlayerState.feature_bundle()
	var stats := PlayerState.computed_stats.duplicate(true)
	var count: int = PlayerState._feature_loadout.compile_count
	check(not ContentLayers.set_feature_module_enabled("hc.ignite",true), label+": actual publication rejects the whole invalid source candidate")
	var after := ContentLayers.feature_configuration()
	check(is_same(after.catalog,before.catalog) and after.enabled_modules==before.enabled_modules
		and is_same(PlayerState.feature_bundle(),bundle) and PlayerState.computed_stats==stats
		and PlayerState._feature_loadout.compile_count==count, label+": rejected candidate preserves the complete old publication")
	ContentLayers.set_feature_module_enabled("hc.ignite",false)

func _finish() -> void:
	if not proof.write_receipt("feature_affix_admission_test",checks,failures.size()): failures.append("receipt")
	print(("FRAMEWORK_FEATURE_AFFIX_ADMISSION_PASS" if failures.is_empty() else "FRAMEWORK_FEATURE_AFFIX_ADMISSION_FAIL")
		+" checks="+str(checks)+" failures="+str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
