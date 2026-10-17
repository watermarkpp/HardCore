extends Node

const OriginalGameData := preload("res://tests/framework/helpers/multicore_original_game_data_oracle_20261014.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const DropRules := preload("res://scripts/item_drop_instance_rules.gd")
const Profession := preload("res://scripts/profession_rules.gd")
const Queries := preload("res://scripts/gameplay/content/content_query_core.gd")
const Catalogs := preload("res://scripts/gameplay/content/published_static_catalogs.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const BASELINE_CASES := "68ec03066872b1d106f213a9b14e8a89c272d37507fef7567f4b70dd6ffb0585"
const BASELINE_QUERIES := "a098928ba8ac6abcda4cb9d22bdb3b661bce898e685ce67de720a996df76dafd"
const BASELINE_RULES := "50338736e20bf0a4cddd88035973e3693367cc77278ffa998dde4a339b3efc3e"
var proof := Proof.new()
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok: failures.append(label)

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

static func query_cases(source: Object) -> Array:
	var cases: Array = [["is_loaded", []], ["get_bich_quests", []],
		["dpv2_source_slot_gate", []], ["is_dpv2_direct_baseline_loaded", []]]
	for record: Dictionary in source.item_catalog:
		var identity: String = source.item_entity_id(record)
		if identity.is_empty(): continue
		for method: String in ["get_item_record", "get_item_rules_record", "get_item_price_record", "get_item_shop_price", "get_entity_record", "item_entity_id", "skill_book_skill_id"]:
			cases.append([method, [identity]])
		cases.append(["get_item", [str(record.get("name", ""))]])
	for skill: Dictionary in source.skills:
		cases.append(["get_skill", [str(skill.get("skill_id", "")), int(skill.get("skillLevel", 0))]])
		cases.append(["skill_book_entity_id", ["hc.skill." + str(skill.get("skill_id", ""))]])
	for profession: String in ["战士", "法师", "道士", "hc.profession.warrior", "unknown"]:
		cases.append(["get_profession_skills", [profession]])
	for id: Variant in source._monsters_by_id:
		cases.append(["canonical_monster_classification", [int(id)]])
		cases.append(["dpv2_ground_slot_limit_for_monster", [int(id)]])
		cases.append(["get_entity_record", ["hc.monster.%06d" % int(id)]])
	for id: Variant in source._maps_by_id:
		cases.append(["get_entity_record", ["hc.map.%06d" % int(id)]])
	for map_name: String in source._maps_by_name:
		cases.append(["get_map", [map_name]])
	for red_name: bool in [false,true]:
		for method: String in ["service_home_map_id","service_home_runtime_map_id","service_home_point"]:
			cases.append([method,[red_name]])
	for map_id: int in [-1,0,910001,913203]: cases.append(["service_runtime_map_id",[map_id]])
	for key: String in ["HomeMap","RedHomeMap","HomeX","HomeY","missing_source_setting"]:
		cases.append(["service_setup_value",[key,-17]])
	for quest_id: String in source._bich_quests_by_id:
		cases.append(["get_bich_quest", [quest_id]])
	for stock_key: String in source.merchant_catalog.get("merchants", {}):
		cases.append(["merchant_context", [stock_key]])
		cases.append(["merchant_stock", [stock_key]])
		var merchant: Dictionary = source.merchant_catalog.merchants[stock_key]
		cases.append(["merchant_context_by_id", [str(merchant.get("merchantId", ""))]])
	for id: Variant in source._dpv2_direct_item_by_id:
		cases.append(["dpv2_direct_item_identity", [int(id)]])
		cases.append(["dpv2_direct_resolve_slot_reward", [{"canonical_item_id": int(id)}]])
	for level in range(1, 71): cases.append(["service_exp_to_next_level", [level]])
	for invalid: Variant in [-1, 0, 1.5, "1", true, {}, []]:
		cases.append(["canonical_monster_id", [invalid]])
		cases.append(["dpv2_direct_item_identity", [invalid]])
	for invalid: Variant in ["hc.item.999999", {"item_id": 80.5}, {"item_id": 80, "itemId": 81}, {"service_index": 2147483646}]:
		cases.append(["get_item_record", [invalid]])
		cases.append(["get_item_price_record", [invalid]])
	cases.append(["dpv2_direct_resolve_slot_reward", [{"gold_amount": 42}]])
	cases.append(["dpv2_direct_resolve_slot_reward", [{"gold_amount": 42, "canonical_item_id": 80}]])
	return cases

static func query_results(source: Object, cases: Array) -> Array:
	var results: Array = []
	for query: Array in cases:
		results.append(source.callv(query[0], query[1]))
	return results

static func rule_results() -> Array:
	var results: Array = []
	for id: int in [80, 140, 232, 218, 219, 220, 920032]:
		var record: Dictionary = GameData.get_item_record({"item_id": id})
		var instance: Dictionary = DropRules.create_instance(record, "v115-content-baseline:%d" % id)
		results.append([id, instance, DropRules.validate_instance(instance, record), GameData.validate_item_drop_instance(instance)])
	for profession: String in ["战士", "法师", "道士"]:
		for level: int in [1, 22, 60, 80]: results.append([profession, level, Profession.stats_for_level(profession, level)])
	return results

static func digest(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()

static func phase(label: String) -> void:
	print("CONTENT_PHASE %s tick_ms=%d" % [label, Time.get_ticks_msec()])

static func foreign_owner_probe(core: RefCounted) -> Dictionary:
	# This pure original helper would return 42 without its entry guard. It
	# demonstrates rejection without deliberately dereferencing a foreign Node.
	return {"query_rejected": core._dpv2_json_integer(42) == -1}

static func thread_probe(snapshot: Dictionary, cases: Array, entered: Semaphore, proceed: Semaphore) -> Dictionary:
	var token: Dictionary = snapshot.catalog_lease
	var accepted := Catalogs.enter_reader(token)
	entered.post()
	proceed.wait()
	if not accepted: return {"entered": false}
	phase("S_factory_rejections_begin")
	var invalid: Dictionary = snapshot.duplicate()
	invalid.fields = {"object": RefCounted.new()}
	var rejects_object := Queries.from_snapshot(invalid) == null
	var cyclic: Dictionary = {}
	cyclic["self"] = cyclic
	invalid.fields = cyclic
	var rejects_cycle := Queries.from_snapshot(invalid) == null
	cyclic.clear()
	invalid.fields = {}
	var rejects_incomplete := Queries.from_snapshot(invalid) == null
	invalid = snapshot.duplicate()
	invalid.fields_sha256 = "tampered"
	var rejects_hash := Queries.from_snapshot(invalid) == null
	invalid = snapshot.duplicate()
	invalid.catalog_lease = token.duplicate()
	invalid.catalog_lease.generation += 1
	var rejects_stale := Queries.from_snapshot(invalid) == null
	phase("S_factory_rejections_end")
	var port := Queries.create_content_port(snapshot)
	phase("S_factory_constructed")
	if port == null:
		Catalogs.leave_reader(token)
		return {"entered": true, "created": false}
	var core: Variant = port._source
	var output := {"entered": true, "created": true, "owner_thread": OS.get_thread_caller_id(),
		"non_node": not core is Node, "revision": core.source_revision,
		"rejects_object": rejects_object, "rejects_cycle": rejects_cycle,
		"rejects_incomplete": rejects_incomplete, "rejects_hash": rejects_hash,
		"rejects_stale": rejects_stale,
		"query_sha256": digest(query_results(core, cases))}
	phase("S_queries_done")
	var values: Array = []
	for id: int in [80, 140, 232, 218, 219, 220, 920032]:
		var record: Dictionary = port.get_item_record({"item_id": id})
		var instance: Dictionary = port.rules.get("item_instances").create_instance(record, "v115-content-baseline:%d" % id)
		values.append([id, instance, port.rules.get("item_instances").validate_instance(instance, record), port.validate_item_drop_instance(instance)])
	for profession: String in ["战士", "法师", "道士"]:
		for level: int in [1, 22, 60, 80]:
			values.append([profession, level, port.rules.get("professions").stats_for_level(profession, level)])
	output.rule_sha256 = digest(values)
	var before: int = core._ui_l1_price_maintenance_count
	core._price_by_name.clear()
	output.rebuilt_price = port.get_item_price_record("hc.item.000080")
	output.maintenance_delta = int(core._ui_l1_price_maintenance_count) - before
	output.main_field_not_visible = port.get_bich_quest("owner_local_probe").is_empty()
	output.growth_path = port.profession_growth_source_path
	output.diagnostics = core.diagnostics()
	# Exercise a live core after its S reader lease is relinquished. The
	# original unguarded implementation reads and writes here, so this is a
	# behavioral rejection witness rather than a source-text assertion.
	var saved_hits: int = core._ui_l1_price_fast_hits
	output.reader_left_for_rejection = Catalogs.leave_reader(token)
	output.expired_reader_query_rejected = core._dpv2_json_integer(42) == -1
	output.expired_field_read_rejected = core._state.read_field("_ui_l1_price_fast_hits") == null
	core._state.write_field("_ui_l1_price_fast_hits", saved_hits + 17)
	core._ui_l1_price_fast_hits = saved_hits + 31
	output.expired_property_read_rejected = core._ui_l1_price_fast_hits == 0
	output.reader_reentered = Catalogs.enter_reader(token)
	output.expired_writes_rejected = core._ui_l1_price_fast_hits == saved_hits
	# Core lifetime ends on its S owner before the read lease is left.
	core = null
	port = null
	output.left = Catalogs.leave_reader(token)
	return output

func graph_checks() -> void:
	var numeric := Graph.capture({1: {"name": "first"}, "1": [2, 3], 2.5: "float key"})
	check(numeric.success and numeric.value.has(1) and numeric.value.has("1") and numeric.value[2.5] == "float key", "value graph preserves numeric and string index keys")
	var cyclic: Array = []
	cyclic.append(cyclic)
	check(not Graph.capture(cyclic).success, "value graph rejects a cycle")
	cyclic.clear()
	var node := Node.new()
	check(not Graph.capture({"node": node}).success, "value graph rejects Node")
	node.free()
	check(not Graph.capture({"resource": Resource.new()}).success, "value graph rejects Resource")
	check(not Graph.capture({"callback": Callable(self, "graph_checks")}).success, "value graph rejects Callable")
	var shared := {"same": [1, 2]}
	var copied := Graph.capture({"a": shared, "b": shared})
	check(copied.success and is_same(copied.value.a, copied.value.b) and not is_same(shared, copied.value.a), "publication owns a distinct graph and preserves shared index records")
	check(copied.value.is_read_only() and copied.value.a.is_read_only() and copied.value.a.same.is_read_only(), "publication recursively freezes arrays and dictionaries")
	var empty_dictionary: Dictionary = {}
	var empty_array: Array = []
	var mutable := Graph.capture({"a": empty_dictionary, "b": empty_dictionary,
		"c": empty_array, "d": empty_array}, false)
	mutable.value.a.owner = "S"
	mutable.value.c.append("S")
	check(mutable.value.b.get("owner") == "S" and mutable.value.d == ["S"] and empty_dictionary.is_empty() and empty_array.is_empty(), "owned graph preserves empty container aliases without sharing source state")

func legacy_mutation_checks() -> void:
	var saved: Dictionary = {}
	for key: String in ["_price_by_name", "_price_by_item_id", "_price_by_service_index", "equipment_price_candidates", "_bich_quests_by_id"]:
		saved[key] = GameData.get(key)
	GameData._bich_quests_by_id = {"live": {"owner": "replacement"}}
	check(GameData.get_bich_quest("live").get("owner") == "replacement", "legacy adapter observes a field dictionary replacement immediately")
	GameData._bich_quests_by_id.live.owner = "in-place"
	check(GameData.content_query_core().get_bich_quest("live").owner == "in-place", "legacy adapter observes in-place field edits immediately")
	for key: String in ["_price_by_name", "_price_by_item_id", "_price_by_service_index"]:
		GameData.set(key, (saved[key] as Dictionary).duplicate(true))
	var before: int = GameData._ui_l1_price_maintenance_count
	for index in 100: GameData.get_item_price_record("hc.item.000080")
	check(GameData._ui_l1_price_maintenance_count == before, "100 resolved price queries perform zero index maintenance")
	GameData._price_by_name.clear()
	GameData.get_item_price_record("hc.item.000080")
	check(GameData._ui_l1_price_maintenance_count == before + 1, "legacy cleared index executes the original rebuild at the same call")
	before = GameData._ui_l1_price_maintenance_count
	GameData.get_item_price_record({"service_index": 2147483646})
	check(GameData._ui_l1_price_maintenance_count == before + 1, "missing high priority identity still runs original maintenance")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/equipment_price_candidates_v1.json"))
	for index in 2:
		var candidate: Dictionary = source.records[index]
		var id: int = [140, 232][index]
		GameData._price_by_item_id.erase(id)
		GameData._price_by_name.erase(candidate.name)
		GameData.equipment_price_candidates = {"records": [candidate]}
		var resolved: Dictionary = GameData.get_item_price_record("hc.item.%06d" % id)
		check(resolved.get("base_price") == candidate.price, "same-size overlay replacement remains discoverable for item %d" % id)
	for key: String in saved: GameData.set(key, saved[key])

func _run() -> void:
	check(GameData.ensure_loaded(), "original production catalogs loaded")
	var oracle := OriginalGameData.new()
	check(oracle.ensure_loaded(), "preserved original GameData loads the same current production inputs")
	var oracle_cases := query_cases(oracle)
	var cases := query_cases(GameData)
	var oracle_query_digest := digest(query_results(oracle, cases))
	var oracle_metadata := {"source_sha256":FileAccess.get_sha256("res://tests/framework/helpers/multicore_original_game_data_oracle_20261014.gd"),
		"query_cases":cases.size(),"cases_sha256":digest(cases),"query_result_sha256":oracle_query_digest,
		"historical_cases_sha256":BASELINE_CASES,"historical_query_sha256":BASELINE_QUERIES,"historical_rule_sha256":BASELINE_RULES}
	print("CONTENT_CURRENT_INPUT_ORACLE ",JSON.stringify(oracle_metadata))
	oracle.free()
	var values := query_results(GameData, cases)
	var rules := rule_results()
	var baseline := {"query_cases": cases.size(), "cases_sha256": digest(cases),
		"query_result_sha256": digest(values), "rule_result_sha256": digest(rules),
		"game_data_sha256": FileAccess.get_sha256("res://scripts/game_data.gd"),
		"item_count": GameData.item_catalog.size(), "skill_rows": GameData.skills.size(),
		"monster_count": GameData._monsters_by_id.size(), "rule_results": rules}
	var directory := "res://outputs/v115_multicore/content_query"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join("ORIGINAL_QUERY_BASELINE.json")
	if not FileAccess.file_exists(path):
		var output := FileAccess.open(path, FileAccess.WRITE)
		if output != null:
			output.store_string(JSON.stringify(baseline, "  ", true, true))
			output.close()
	print("CONTENT_ORIGINAL_CENSUS ", JSON.stringify(baseline.merged({"rule_results": "saved_in_owned_evidence"}, true)))
	check(cases.size() > 1000 and values.size() == cases.size(), "real catalog query census has nonzero complete coverage")
	check(GameData.has_method("content_query_core"), "GameData delegates its production queries to one non Node core")
	check(GameData.has_method("publish_content_snapshot"), "simulation receives an independently published content graph")
	check(digest(cases) == digest(oracle_cases) and cases.size() == oracle_cases.size() and cases.size() >= 7388, "all original cases match the preserved source on current production inputs")
	check(digest(values) == oracle_query_digest, "all current legacy queries equal preserved original source on current inputs")
	var current_rule_digest := digest(rules)
	var foreign_worker := Thread.new()
	var main_core: RefCounted = GameData.content_query_core()
	check(foreign_worker.start(foreign_owner_probe.bind(main_core)) == OK, "owner rejection probe uses a real foreign Thread")
	var foreign_result: Dictionary = foreign_worker.wait_to_finish()
	check(foreign_result.get("query_rejected", false), "foreign Thread cannot execute a main-owned query helper")
	check(main_core._dpv2_json_integer(42) == 42, "owner helper retains its original numeric result")
	var native_capture: Dictionary = Graph.capture({"owned": []}, false)
	check(native_capture.success and native_capture.get("memo_entries", -1) == 2, "content graph dispatch selects the native identity-memo implementation")
	graph_checks()
	phase("M_graph_checks_done")
	legacy_mutation_checks()
	phase("M_mutations_done")
	var lease := Catalogs.acquire()
	phase("M_catalogs_published")
	check(not lease.is_empty(), "fixed catalogs publish one validated immutable lease")
	if not lease.is_empty():
		var document_before: Dictionary = Catalogs.Entities.document()
		check(document_before.is_read_only() and Catalogs.Skills.document().is_read_only(), "identity and skill publications are read only")
		check(not Catalogs.Entities.publish(document_before), "active lease rejects identity publication")
		check(not Catalogs.Skills.reload_data().get("valid", true), "active lease rejects skill reload")
		Catalogs.Rank.clear_cache_for_tests()
		Catalogs.Taoist.clear_cache_for_tests()
		Catalogs.Entities._document = {}
		check(Catalogs.Entities.document() == document_before and not Catalogs.Rank._policy.is_empty() and not Catalogs.Taoist._rules_cache.is_empty(), "active lease rejects reset and direct cache replacement")
		var snapshot: Dictionary = GameData.publish_content_snapshot(lease)
		phase("M_snapshot_published")
		check(not snapshot.is_empty() and snapshot.database_revision == GameData.database_revision, "published query fields bind the same database revision")
		if not snapshot.is_empty():
			var saved_quests: Dictionary = GameData._bich_quests_by_id
			GameData._bich_quests_by_id = saved_quests.duplicate(true)
			GameData._bich_quests_by_id.owner_local_probe = {"owner": "M only"}
			var before: Dictionary = GameData.content_query_core().diagnostics()
			var worker := Thread.new()
			var entered := Semaphore.new()
			var proceed := Semaphore.new()
			# Semaphores are test-harness coordination, never content graph fields.
			check(worker.start(thread_probe.bind(snapshot, Graph.capture(cases).value, entered, proceed)) == OK, "real Godot Thread starts with value-only content input")
			entered.wait()
			check(Gate.reader_count() == 1 and not Catalogs.release_after_host_quiescence(lease), "main cannot release a catalog while the real S reader is active")
			check(Queries.from_snapshot(snapshot) == null, "main cannot construct a simulation query core using an S-only lease")
			proceed.post()
			var result: Dictionary = worker.wait_to_finish()
			check(result.get("entered", false) and result.get("created", false) and result.get("non_node", false), "S creates its own non Node query and rules owner")
			check(result.get("owner_thread") != OS.get_main_thread_id() and result.get("left", false), "real S owner enters and leaves its catalog read lease")
			check(result.get("rejects_object", false) and result.get("rejects_cycle", false), "S factory rejects objects and cycles before serialization")
			check(result.get("rejects_incomplete", false) and result.get("rejects_hash", false) and result.get("rejects_stale", false), "S factory rejects missing fields tampered hashes and stale publication tokens")
			check(result.get("query_sha256") == oracle_query_digest, "all current S queries equal preserved original source on current inputs")
			check(result.get("rule_sha256") == current_rule_digest, "real S create validate and profession calculations equal original production source")
			check(result.get("maintenance_delta") == 1 and result.get("rebuilt_price", {}).get("base_price") == 50, "S rebuilds its own price indexes at the original maintenance boundary")
			check(result.get("main_field_not_visible", false) and GameData.content_query_core().diagnostics() == before, "S fields and diagnostics are independent of main state mutations")
			check(result.get("growth_path") == GameData.profession_growth_source_path, "S professions use the exact published ContentLayers source path")
			check(result.get("reader_left_for_rejection", false) and result.get("reader_reentered", false), "lease rejection probe leaves and reacquires the same current publication")
			check(result.get("expired_reader_query_rejected", false), "a released reader cannot run even a pure original query helper")
			check(result.get("expired_field_read_rejected", false) and result.get("expired_property_read_rejected", false), "released reader field and typed property reads fail closed")
			check(result.get("expired_writes_rejected", false), "released reader cannot change owner fields through store or property writes")
			GameData._bich_quests_by_id = saved_quests
		check(Catalogs.release_after_host_quiescence(lease), "isolated no-world test releases after its only reader Thread joined")
		check(Catalogs.Skills.reload_data().get("valid", false), "quiescent main can reload formal skill catalogs again")
		check(Catalogs.Entities.publish(document_before), "quiescent main can republish the validated formal identity catalog")
	proof.write_receipt("multicore_content_query_20261014", proof.records.size(), failures.size())
	print("MULTICORE_CONTENT_QUERY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", proof.records.size(), failures])
	get_tree().quit(0 if failures.is_empty() else 1)
