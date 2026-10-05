extends "res://tests/framework/natural_effect_lifecycle_cold_test.gd"

const MANA_SUPPLY_ID := "hc.service_item.000663"

func _scenario() -> String:
	return "natural_sustained_chain" if periodic_children else "natural_sustained_resource"

func _run() -> void:
	check(not PlayerState.test_mode,"independent cold uses real persistence")
	var path := "res://outputs/test_logs/framework/"+_scenario()+"_expected.json"
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	check(expected is Dictionary,"successful current live producer supplied its two-round expectation")
	if not expected is Dictionary: _finish(); return
	check(Gate.accepts(expected,_scenario()+"_test"),"cold binds this invocation runner-confirmed complete PASS producer")
	if not failures.is_empty(): _finish(); return
	check(expected.source_content_sha256 == OS.get_environment("HARDCORE_R3_CONTENT_SHA256") and expected.producer_run_id != OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"same source and independent cold run identity")
	check(int(expected.completed_rounds)==2 and int(expected.fixture_deaths)==60,"handoff explicitly owns two complete thirty-target rounds")
	check(str(expected.get("mana_supply_id", "")) == MANA_SUPPLY_ID
		and int(expected.get("mana_supply_seed_count", -1)) == 20
		and int(expected.get("mana_supply_remaining_count", -1))
			== int(expected.get("mana_supply_initial_count", -1)) + 20
			- int(expected.get("mana_supply_successful_uses", -1))
		and str(expected.get("mana_supply_quick_slot", "")) == MANA_SUPPLY_ID,
		"same-source producer declared exact legal supply input, consumption and binding")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"actual independent startup upgrade")
	check(PlayerState.select_character(expected.profile_id),"exact producer profile loads")
	check(PlayerState.experience == int(expected.experience),"both complete cohorts and incidental canonical rewards survive once without duplicate credit")
	check(PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID) == int(expected.get("mana_supply_remaining_count", -1))
		and PlayerState.quick_item_slots[0] == MANA_SUPPLY_ID,
		"independent cold restore retains the absolute potion remainder and formal quick-slot identity")
	check(PlayerState._world_clock_generation == expected.generation,"saved generation marker is retained; separate nonempty-generation coverage remains authoritative")
	check(PlayerState._json_persistence.pending_count()==0 and PlayerState._world_json_persistence.pending_count()==0,"both production writer queues drain")
	_finish()

func _finish() -> void:
	var written := proof.write_receipt(_scenario()+"_cold_test",checks,failures.size())
	print("NATURAL_SUSTAINED_COLD_",("PASS" if written and failures.is_empty() else "FAIL")," checks=",checks," failures=",failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
