extends Node

const ItemDropInstanceRulesScript := preload("res://scripts/item_drop_instance_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded())
	var rules := ItemDropInstanceRulesScript.configuration_snapshot()
	assert(str(rules.get("contract_id", "")) == ItemDropInstanceRulesScript.INSTANCE_RULES_CONTRACT_ID)
	assert(bool(rules.get("enabled", false)))
	assert(int(rules.affix_roll.numerator) == 1 and int(rules.affix_roll.denominator) == 20)
	assert(int(rules.affix_roll.increment) == 1)
	assert(str(rules.provenance.classification) == "project_gameplay_default_not_original_value")

	var catalog := GameData.get_item_record({"item_id": 80})
	assert(str(catalog.get("kind", "")) == "equipment" and str(catalog.get("name", "")) == "木剑")
	var identity := _identity_record(catalog)
	var affixed: Dictionary = {}
	var ordinary: Dictionary = {}
	for index in range(1000):
		# Frozen v1 generator remains a compatibility oracle after the v2 rollout.
		var created := identity.duplicate(true)
		created["item_instance"] = ItemDropInstanceRulesScript.create_legacy_instance(catalog, "rules:%d" % index)
		assert(str(created.get("identity_status", "")) == "resolved", str(created))
		var instance: Dictionary = created.get("item_instance", {})
		assert(ItemDropInstanceRulesScript.validate_instance(instance, catalog))
		if ItemDropInstanceRulesScript.is_affixed_instance(instance, catalog) and affixed.is_empty():
			affixed = created
		elif not ItemDropInstanceRulesScript.is_affixed_instance(instance, catalog) and ordinary.is_empty():
			ordinary = created
		if not affixed.is_empty() and not ordinary.is_empty():
			break
	assert(not affixed.is_empty() and not ordinary.is_empty(), "deterministic 5 percent sample did not cover both outcomes")

	var stable_key := "rules:stable"
	var first := PlayerState.create_drop_item_instance(identity, stable_key)
	var second := PlayerState.create_drop_item_instance(identity, stable_key)
	assert(first == second, "same stable drop key rerolled or changed identity")
	assert(str(first.item_instance.instance_id).begins_with("drop:v1:80:"))
	assert((ordinary.item_instance.modifiers as Array).is_empty())
	assert((affixed.item_instance.modifiers as Array).size() == 1)
	_test_v1_history_is_independent_from_rollout_controls(affixed.item_instance, catalog)
	_test_permanent_max_durability_loss_is_valid(ordinary.item_instance, catalog)

	var probe_expected := RandomNumberGenerator.new()
	probe_expected.seed = 8675309
	var expected_first := probe_expected.randi()
	var expected_second := probe_expected.randi()
	var probe_actual := RandomNumberGenerator.new()
	probe_actual.seed = 8675309
	assert(probe_actual.randi() == expected_first)
	PlayerState.create_drop_item_instance(identity, "rules:rng-isolation")
	assert(probe_actual.randi() == expected_second, "drop instance generation consumed an unrelated RNG")

	var forged: Dictionary = affixed.item_instance.duplicate(true)
	forged["random_stats"] = {"attack_max": 999}
	assert(not ItemDropInstanceRulesScript.validate_instance(forged, catalog))
	forged = affixed.item_instance.duplicate(true)
	forged.modifiers[0]["value"] = 999
	assert(not ItemDropInstanceRulesScript.validate_instance(forged, catalog))
	forged = affixed.item_instance.duplicate(true)
	forged["item_id"] = 81
	assert(not ItemDropInstanceRulesScript.validate_instance(forged, catalog))
	var non_master_equipment := {
		"itemId": 9999998,
		"name": "non-master-equipment-fixture",
		"kind": "equipment",
		"category": "圣物",
		"maxDurability": 1,
	}
	var non_master_instance := ItemDropInstanceRulesScript.create_instance(
		non_master_equipment,
		"rules:non-master",
	)
	assert(not non_master_instance.is_empty())
	assert(ItemDropInstanceRulesScript.validate_instance(non_master_instance, non_master_equipment))
	assert(not ItemDropInstanceRulesScript.is_affixed_instance(non_master_instance, non_master_equipment),
		"equipment outside the primary attribute table received a W7 affix")
	_test_catalog_modifier_preservation(catalog, affixed.item_instance)

	var potion_catalog := GameData.get_item_record({"item_id": 910013})
	var potion_identity := _identity_record(potion_catalog)
	assert(PlayerState.create_drop_item_instance(potion_identity, "rules:potion") == potion_identity,
		"non-equipment identity was mutated")
	var invalid := PlayerState.create_drop_item_instance(identity, "")
	assert(str(invalid.get("identity_status", "")) == "invalid_instance")
	assert(str(invalid.get("item_instance_error", "")) == "instance_generation_failed")
	assert(not invalid.has("item_instance"))
	print("ITEM_DROP_INSTANCE_RULES_TEST_PASS")
	get_tree().quit(0)


func _test_v1_history_is_independent_from_rollout_controls(
	instance: Dictionary,
	catalog: Dictionary,
) -> void:
	var original_rules: Dictionary = ItemDropInstanceRulesScript._rules_cache.duplicate(true)
	ItemDropInstanceRulesScript._rules_cache["enabled"] = false
	ItemDropInstanceRulesScript._rules_cache["affix_roll"]["numerator"] = 0
	ItemDropInstanceRulesScript._rules_cache["affix_roll"]["denominator"] = 100
	assert(ItemDropInstanceRulesScript.validate_instance(instance, catalog),
		"rollout controls invalidated an existing item.drop.affix.v1 record")
	ItemDropInstanceRulesScript._rules_cache = original_rules


func _test_permanent_max_durability_loss_is_valid(
	instance: Dictionary,
	catalog: Dictionary,
) -> void:
	var damaged := instance.duplicate(true)
	var reduced_max_raw := maxi(
		1,
		int(damaged.max_durability_raw) - ItemDropInstanceRulesScript.DURABILITY_RAW_UNITS_PER_DISPLAY,
	)
	damaged["max_durability_raw"] = reduced_max_raw
	damaged["durability_raw"] = mini(reduced_max_raw, maxi(0, reduced_max_raw - 250))
	damaged["max_durability"] = int(ceil(
		float(damaged.max_durability_raw)
		/ ItemDropInstanceRulesScript.DURABILITY_RAW_UNITS_PER_DISPLAY
	))
	damaged["durability"] = (
		0 if int(damaged.durability_raw) == 0
		else int(ceil(
			float(damaged.durability_raw)
			/ ItemDropInstanceRulesScript.DURABILITY_RAW_UNITS_PER_DISPLAY
		))
	)
	assert(ItemDropInstanceRulesScript.validate_instance(damaged, catalog),
		"legal permanent max-durability loss was rejected")


func _test_catalog_modifier_preservation(catalog: Dictionary, affixed_instance: Dictionary) -> void:
	var item_id := int(catalog.get("itemId", -1))
	var item_name := str(catalog.get("name", ""))
	var original_by_id: Dictionary = GameData._catalog_by_item_id[item_id].duplicate(true)
	var original_by_name: Dictionary = GameData._items_by_name[item_name].duplicate(true)
	var no_catalog_modifier := original_by_id.duplicate(true)
	no_catalog_modifier.erase("modifiers")
	GameData._catalog_by_item_id[item_id] = no_catalog_modifier
	GameData._items_by_name[item_name] = no_catalog_modifier
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.equipment["武器"] = affixed_instance.duplicate(true)
	PlayerState.recalculate_stats(false)
	var affix_only_attack_max := float(PlayerState.computed_stats.attack_max)

	var array_catalog := no_catalog_modifier.duplicate(true)
	array_catalog["modifiers"] = [{"stat": "attack_max", "op": "add", "value": 2}]
	GameData._catalog_by_item_id[item_id] = array_catalog
	GameData._items_by_name[item_name] = array_catalog
	PlayerState.recalculate_stats(false)
	assert(float(PlayerState.computed_stats.attack_max) == affix_only_attack_max + 2.0,
		"catalog Array modifier was lost or the instance modifier was applied twice")

	var dictionary_catalog := no_catalog_modifier.duplicate(true)
	dictionary_catalog["modifiers"] = {"criticalChance": 0.25}
	GameData._catalog_by_item_id[item_id] = dictionary_catalog
	GameData._items_by_name[item_name] = dictionary_catalog
	PlayerState.recalculate_stats(false)
	assert(float(PlayerState.computed_stats.attack_max) == affix_only_attack_max)
	assert(is_equal_approx(float(PlayerState.computed_stats.critical_chance), 0.25),
		"catalog legacy Dictionary modifier was lost")
	GameData._catalog_by_item_id[item_id] = original_by_id
	GameData._items_by_name[item_name] = original_by_name


func _identity_record(catalog: Dictionary) -> Dictionary:
	var item_id := int(catalog.get("itemId", -1))
	var item_name := str(catalog.get("name", ""))
	return {
		"item_id": item_id,
		"canonical_item_id": item_id,
		"canonical_name": item_name,
		"source_item_id": item_id,
		"source_canonical_item_id": item_id,
		"source_canonical_name": item_name,
		"item_name": item_name,
		"name": item_name,
		"output_item_id": item_id,
		"output_record": catalog.duplicate(true),
		"identity_status": "resolved",
	}
